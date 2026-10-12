using System.Security.Cryptography;
using System.Text;

namespace PasswordGenerator.Core;

public sealed record WordListIntegrity(string Sha256, string Sha3_512, string Skein1024_1024)
{
    public static readonly WordListIntegrity Bip39Expected = new(
        "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda",
        "862e1642f46f0e81d81fa48ad5a806a12a5578130ddf13c4c302aec44a03c710bc6574e965f9084b1918b4ce0a95dac282499e2cdcd8cf50e48f3851e2f32d32",
        "8f63cf649dc0938e25c164849d164cfef2f80ea256e290c27eda407bfb0bdffa1e9027d55eb2f193a799e5a61fa56334b4847ac7871c52079e84cf7f0eecad198ae6eb9b63cfb29ba8a9ecfb63a95ed7f30c0708e80ab25ceb95f0370a863800987fb98875ee0c9e0f6b1be1af7b31cbd9525410cd72e2ec380eae37f902fed4");
    public static readonly WordListIntegrity EffExpected = new(
        "addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e",
        "4573a7810c569805ab110b0ce5004d4697079afe2d74ba70daa9dd49bd0a60103c5bce9725db036bd1ebaf5813815a54f821e7d752b5ee6eb57bed4a7e58aa23",
        "29b0538e7e97f05e95827f8fad0377f90ac17ad2f940c67a9dffbab936f84ced030f719b165ada5c6ef3552a3284e607ec81eadba433530a308235cc4696aa014785464589e43d85175c1befa890306b8c774e42cf64936bd9d65048e6326180028b08ca45dbb5680927df40f09b4f30a20d036315fcfc06734098d4645385cb");
    public static WordListIntegrity Compute(ReadOnlySpan<byte> data) => new(
        Convert.ToHexStringLower(SHA256.HashData(data)), Convert.ToHexStringLower(SHA3_512.HashData(data)), Convert.ToHexStringLower(Skein.Hash1024(data)));
    internal static byte[] Resource(string name)
    {
        using var stream = typeof(WordListIntegrity).Assembly.GetManifestResourceStream($"PasswordGenerator.Core.Resources.{name}")
            ?? throw new InvalidOperationException($"Wortliste fehlt: {name}");
        using var bytes = new MemoryStream(); stream.CopyTo(bytes); return bytes.ToArray();
    }
    internal static string[] Rows(ReadOnlySpan<byte> data) => new UTF8Encoding(false, true).GetString(data).Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
}

public sealed class Bip39
{
    private readonly string[] words;
    private readonly Dictionary<string, int> indexByWord;
    public IReadOnlyList<string> Words { get; }
    public WordListIntegrity Integrity { get; }
    public Bip39() : this(WordListIntegrity.Resource("english.txt")) { }
    public Bip39(ReadOnlySpan<byte> verifiedWordListData)
    {
        Integrity = WordListIntegrity.Compute(verifiedWordListData);
        if (Integrity != WordListIntegrity.Bip39Expected) throw new CryptographicException("Die BIP-39-Wortliste hat den dreifachen Integritätstest nicht bestanden.");
        words = WordListIntegrity.Rows(verifiedWordListData);
        if (words.Length != 2048 || words.Distinct(StringComparer.Ordinal).Count() != 2048
            || !words.SequenceEqual(words.Order(StringComparer.Ordinal)) || words[0] != "abandon" || words[^1] != "zoo")
            throw new InvalidDataException("Die BIP-39-Wortliste ist ungültig.");
        Words = Array.AsReadOnly(words);
        indexByWord = words.Select((word, index) => (word, index)).ToDictionary(pair => pair.word, pair => pair.index, StringComparer.Ordinal);
    }
    public static int EntropyByteCount(int wordCount) => wordCount switch { 12 => 16, 15 => 20, 18 => 24, 21 => 28, 24 => 32, _ => throw new ArgumentOutOfRangeException(nameof(wordCount)) };
    public string[] Mnemonic(ReadOnlySpan<byte> entropy)
    {
        if (entropy.Length is not (16 or 20 or 24 or 28 or 32)) throw new ArgumentException("Ungültige Entropielänge.", nameof(entropy));
        int entropyBits = entropy.Length * 8, count = entropyBits / 32 * 3;
        byte[] checksum = SHA256.HashData(entropy);
        try
        {
            var result = new string[count];
            for (int wordOffset = 0; wordOffset < count; wordOffset++)
            {
                int index = 0;
                for (int bitOffset = 0; bitOffset < 11; bitOffset++)
                {
                    int sourceBit = wordOffset * 11 + bitOffset;
                    index = (index << 1) | (sourceBit < entropyBits ? Bit(entropy, sourceBit) : Bit(checksum, sourceBit - entropyBits));
                }
                result[wordOffset] = words[index];
            }
            return result;
        }
        finally { SecretMemory.Clear(checksum); }
    }
    public byte[] Entropy(IReadOnlyList<string> mnemonicWords)
    {
        int byteCount = EntropyByteCount(mnemonicWords.Count), entropyBits = byteCount * 8, checksumBits = entropyBits / 32;
        var allBits = new byte[mnemonicWords.Count * 11];
        var entropy = new byte[byteCount];
        byte[]? digest = null;
        try
        {
            for (int i = 0; i < mnemonicWords.Count; i++)
            {
                if (!indexByWord.TryGetValue(mnemonicWords[i], out int index)) throw new ArgumentException("Unbekanntes BIP-39-Wort.", nameof(mnemonicWords));
                for (int b = 0; b < 11; b++) allBits[i * 11 + b] = (byte)((index >> (10 - b)) & 1);
            }
            for (int i = 0; i < entropyBits; i++) entropy[i / 8] |= (byte)(allBits[i] << (7 - (i % 8)));
            digest = SHA256.HashData(entropy);
            for (int i = 0; i < checksumBits; i++) if (allBits[entropyBits + i] != Bit(digest, i)) throw new CryptographicException("Die BIP-39-Prüfsumme ist ungültig.");
            return entropy;
        }
        catch { SecretMemory.Clear(entropy); throw; }
        finally { SecretMemory.Clear(allBits); SecretMemory.Clear(digest); }
    }
    public bool Validate(IReadOnlyList<string> mnemonicWords)
    {
        byte[]? entropy = null;
        try { entropy = Entropy(mnemonicWords); return true; }
        catch (Exception exception) when (exception is ArgumentException or CryptographicException) { return false; }
        finally { SecretMemory.Clear(entropy); }
    }
    private static int Bit(ReadOnlySpan<byte> bytes, int index) => (bytes[index / 8] >> (7 - index % 8)) & 1;
}

public sealed class Eff
{
    public const int WordCount = 7776;
    public IReadOnlyList<string> Words { get; }
    public WordListIntegrity Integrity { get; }
    public Eff() : this(WordListIntegrity.Resource("eff_large_wordlist.txt")) { }
    public Eff(ReadOnlySpan<byte> verifiedWordListData)
    {
        Integrity = WordListIntegrity.Compute(verifiedWordListData);
        if (Integrity != WordListIntegrity.EffExpected) throw new CryptographicException("Die EFF-Wortliste hat den dreifachen Integritätstest nicht bestanden.");
        var rows = WordListIntegrity.Rows(verifiedWordListData);
        if (rows.Length != WordCount) throw new InvalidDataException("Die EFF-Wortliste ist ungültig.");
        var words = new string[WordCount];
        Span<char> label = stackalloc char[5];
        for (int i = 0; i < rows.Length; i++)
        {
            var fields = rows[i].Split('\t');
            int value = i;
            for (int d = 4; d >= 0; d--) { label[d] = (char)('1' + value % 6); value /= 6; }
            if (fields.Length != 2 || !fields[0].AsSpan().SequenceEqual(label) || fields[1].Length == 0 || fields[1].Any(char.IsWhiteSpace))
                throw new InvalidDataException("Die EFF-Wortliste ist ungültig.");
            words[i] = fields[1];
        }
        if (words.Distinct(StringComparer.Ordinal).Count() != WordCount || !words.SequenceEqual(words.Order(StringComparer.Ordinal)) || words[0] != "abacus" || words[^1] != "zoom")
            throw new InvalidDataException("Die EFF-Wortliste ist ungültig.");
        Words = Array.AsReadOnly(words);
    }
}
