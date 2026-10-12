using System.Security.Cryptography;
using System.Text;

namespace PasswordGenerator.Core;

public enum GeneratorMode { Bip39, Eff, Ascii, Pin, Hex }
public static class GeneratorModeExtensions
{
    public static (int Min, int Max) LengthRange(this GeneratorMode mode) => mode switch {
        GeneratorMode.Bip39 => (12, 24), GeneratorMode.Eff => (6, 128), GeneratorMode.Ascii => (8, 256), GeneratorMode.Pin => (3, 512), GeneratorMode.Hex => (1, 512), _ => throw new ArgumentOutOfRangeException(nameof(mode)) };
    public static int DefaultLength(this GeneratorMode mode) => mode switch { GeneratorMode.Bip39 => 24, GeneratorMode.Eff => 20, GeneratorMode.Ascii => 40, GeneratorMode.Pin => 6, GeneratorMode.Hex => 64, _ => throw new ArgumentOutOfRangeException(nameof(mode)) };
    public static IEnumerable<int> SupportedLengths(this GeneratorMode mode) => mode == GeneratorMode.Bip39 ? [12, 15, 18, 21, 24] : Enumerable.Range(mode.LengthRange().Min, mode.LengthRange().Max - mode.LengthRange().Min + 1);
    public static bool UsesWords(this GeneratorMode mode) => mode is GeneratorMode.Bip39 or GeneratorMode.Eff;
    public static int AlphabetSize(this GeneratorMode mode) => mode switch { GeneratorMode.Eff => Eff.WordCount, GeneratorMode.Ascii => 94, GeneratorMode.Pin => 10, GeneratorMode.Hex => 16, _ => throw new ArgumentOutOfRangeException(nameof(mode)) };
}
public sealed record GeneratorConfiguration(GeneratorMode Mode, int Length)
{
    public void Validate()
    {
        if (!Enum.IsDefined(Mode)) throw new ArgumentOutOfRangeException(nameof(Mode));
        var range = Mode.LengthRange();
        if (Length < range.Min || Length > range.Max || (Mode == GeneratorMode.Bip39 && Length % 3 != 0))
            throw new ArgumentOutOfRangeException(nameof(Length), $"Ungültige Länge für {Mode}: {Length}.");
    }
    /// <summary>Log2 of the uniformly sampled output space; this does not measure RNG entropy.</summary>
    public double EntropyBits
    {
        get
        {
            try { Validate(); } catch (ArgumentException) { return 0; }
            return Mode == GeneratorMode.Bip39 ? Bip39.EntropyByteCount(Length) * 8 : Length * Math.Log2(Mode.AlphabetSize());
        }
    }
    public NominalSecurityLevel NominalSecurityLevel => NominalSecurityLevelExtensions.FromBits(EntropyBits);
}

public sealed class GeneratedPassword : IDisposable
{
    private readonly SensitiveBytes storage;
    private readonly (int Offset, int Length)[] ranges;
    public double EntropyBits { get; }
    public GeneratorMode Mode { get; }
    public int ComponentCount => IsCleared ? 0 : ranges.Length;
    public bool IsCleared => storage.IsCleared;
    public NominalSecurityLevel NominalSecurityLevel => NominalSecurityLevelExtensions.FromBits(EntropyBits);
    public string Text => ExportText(Mode.UsesWords() ? " " : "");
    internal GeneratedPassword(IReadOnlyList<string> components, double entropyBits, GeneratorMode mode)
    {
        ranges = new (int, int)[components.Count];
        int count = 0;
        for (int i = 0; i < components.Count; i++) { int length = Encoding.UTF8.GetByteCount(components[i]); ranges[i] = (count, length); count += length; }
        storage = new SensitiveBytes(count);
        for (int i = 0; i < components.Count; i++) Encoding.UTF8.GetBytes(components[i], storage.Span.Slice(ranges[i].Offset, ranges[i].Length));
        EntropyBits = entropyBits; Mode = mode;
    }
    public string ExportText(string? wordSeparator = null, bool uppercaseHex = false)
    {
        if (IsCleared) return "";
        string separator = wordSeparator ?? (Mode == GeneratorMode.Bip39 ? " " : "-");
        int separatorLength = Mode.UsesWords() ? Encoding.UTF8.GetByteCount(separator) : 0;
        var output = new byte[storage.Span.Length + separatorLength * Math.Max(0, ranges.Length - 1)];
        try
        {
            int offset = 0;
            for (int i = 0; i < ranges.Length; i++)
            {
                if (Mode.UsesWords() && i > 0) offset += Encoding.UTF8.GetBytes(separator, output.AsSpan(offset));
                var range = ranges[i];
                storage.Span.Slice(range.Offset, range.Length).CopyTo(output.AsSpan(offset));
                if (Mode == GeneratorMode.Hex && uppercaseHex)
                    for (int b = offset; b < offset + range.Length; b++) if (output[b] is >= (byte)'a' and <= (byte)'f') output[b] -= 32;
                offset += range.Length;
            }
            return Encoding.UTF8.GetString(output);
        }
        finally { SecretMemory.Clear(output); }
    }
    public void Clear() => Dispose();
    public void Dispose() { storage.Dispose(); GC.SuppressFinalize(this); }
}

public sealed class PasswordGenerator
{
    public Bip39 Bip39 { get; } = new();
    public Eff Eff { get; } = new();
    public static readonly IReadOnlyList<string> AsciiAlphabet = Array.AsReadOnly(Enumerable.Range(33, 94).Select(i => ((char)i).ToString()).ToArray());
    public static readonly IReadOnlyList<string> PinAlphabet = Array.AsReadOnly("0123456789".Select(c => c.ToString()).ToArray());
    public static readonly IReadOnlyList<string> HexAlphabet = Array.AsReadOnly("0123456789abcdef".Select(c => c.ToString()).ToArray());
    public GeneratedPassword Generate(GeneratorConfiguration configuration, Func<int, byte[]> randomProvider)
    {
        ArgumentNullException.ThrowIfNull(configuration); ArgumentNullException.ThrowIfNull(randomProvider);
        configuration.Validate();
        string[] components;
        if (configuration.Mode == GeneratorMode.Bip39)
        {
            var entropy = SecureRandom.CheckedBytes(global::PasswordGenerator.Core.Bip39.EntropyByteCount(configuration.Length), randomProvider);
            try { components = Bip39.Mnemonic(entropy); } finally { SecretMemory.Clear(entropy); }
        }
        else
        {
            IReadOnlyList<string> alphabet = configuration.Mode switch { GeneratorMode.Eff => Eff.Words, GeneratorMode.Ascii => AsciiAlphabet, GeneratorMode.Pin => PinAlphabet, GeneratorMode.Hex => HexAlphabet, _ => throw new ArgumentOutOfRangeException(nameof(configuration)) };
            var indices = UniformIndices(configuration.Length, alphabet.Count, randomProvider);
            try { components = indices.Select(i => alphabet[i]).ToArray(); }
            finally { SecretMemory.Clear(indices); }
        }
        try
        {
            // Validate the selected shared word-list strings before creating the owned result.
            // No joined immutable secret phrase is exported merely to check its checksum.
            if (configuration.Mode == GeneratorMode.Bip39 && !Bip39.Validate(components))
                throw new CryptographicException("Die BIP-39-Prüfsumme ist ungültig.");
            return new GeneratedPassword(components, configuration.EntropyBits, configuration.Mode);
        }
        finally { Array.Clear(components); }
    }
    /// <summary>Rejects the incomplete final bucket; testable complete-domain invariant.</summary>
    public static int[] UniformIndices(int count, int upperBound, Func<int, byte[]> randomProvider)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        if (upperBound is <= 0 or > 65536) throw new ArgumentOutOfRangeException(nameof(upperBound));
        int width = upperBound <= 256 ? 1 : 2, range = width == 1 ? 256 : 65536, limit = range - range % upperBound;
        var result = new int[count];
        int filled = 0, consecutiveRejections = 0;
        try
        {
            while (filled < count)
            {
                var bytes = SecureRandom.CheckedBytes(checked((count - filled) * width), randomProvider);
                try
                {
                    for (int offset = 0; offset < bytes.Length; offset += width)
                    {
                        int candidate = width == 1 ? bytes[offset] : (bytes[offset] << 8) | bytes[offset + 1];
                        if (candidate >= limit)
                        {
                            if (++consecutiveRejections >= 1024) throw new CryptographicException("Die Zufallsquelle lieferte wiederholt ungeeignete Auswahlwerte.");
                            continue;
                        }
                        result[filled++] = candidate % upperBound; consecutiveRejections = 0;
                    }
                }
                finally { SecretMemory.Clear(bytes); }
            }
            return result;
        }
        catch { SecretMemory.Clear(result); throw; }
    }
}
