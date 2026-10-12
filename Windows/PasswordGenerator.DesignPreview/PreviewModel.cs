using PasswordGenerator.Core;

namespace PasswordGenerator.App;

/// <summary>Public, deterministic design fixture. Never initializes entropy, crypto, clipboard, or runtime guards.</summary>
public sealed class AppModel : IDisposable
{
    public enum GenerationPhase { Collecting, Ready, Generated }
    public sealed record RuntimeSecurityAssessment(bool IsEnforced, string Summary, string Details);
    public static string PreviewLanguage { get; set; } = "de";
    public static GeneratorMode PreviewMode { get; set; } = GeneratorMode.Bip39;
    public static GenerationPhase PreviewPhase { get; set; } = GenerationPhase.Ready;
    public static bool PreviewVisible { get; set; }
    public static int? PreviewLength { get; set; }

    public event Action? Changed;
    public event Action<string>? Error { add { } remove { } }
    public string Language { get; private set; } = PreviewLanguage;
    public GeneratorMode Mode { get; private set; } = PreviewMode;
    public int Length { get; private set; } = PreviewLength ?? PreviewMode.DefaultLength();
    public string Separator { get; set; } = PreviewMode == GeneratorMode.Bip39 ? " " : "-";
    public bool UppercaseHex { get; set; }
    public bool Confirmed { get; set; } = PreviewPhase != GenerationPhase.Collecting;
    public bool Visible { get; private set; } = PreviewVisible;
    public bool ClipboardScheduled { get; private set; }
    public GenerationPhase Phase { get; private set; } = PreviewPhase;
    public RuntimeSecurityAssessment Security { get; } = new(true, "Design fixture", "Public design fixture; no cryptography or security assessment is performed.");
    public long EventCount => Phase == GenerationPhase.Collecting ? 1513 : 4096;
    public long ShuffleCount => 7;
    public int ComponentCount => Mode.UsesWords() ? Length : 1;
    public WordListIntegrity Bip39Integrity => WordListIntegrity.Bip39Expected;
    public WordListIntegrity EffIntegrity => WordListIntegrity.EffExpected;
    public GeneratorConfiguration? Configuration
    {
        get { var configuration = new GeneratorConfiguration(Mode, Length); try { configuration.Validate(); return configuration; } catch (ArgumentException) { return null; } }
    }
    public bool CanGenerate => Phase == GenerationPhase.Ready && Confirmed && Configuration != null;

    public string Tr(string german, string english) => Language == "de" ? german : english;
    public void SetLanguage(string language) { Language = language; Changed?.Invoke(); }
    public void SetMode(GeneratorMode mode) { if (Phase == GenerationPhase.Generated || Mode == mode) return; Mode = mode; Length = mode.DefaultLength(); Changed?.Invoke(); }
    public void SetLength(int length) { if (Phase == GenerationPhase.Generated || Length == length) return; Length = length; Changed?.Invoke(); }
    public void Record(MouseEntropyRecord sample) { }
    public void Generate() { Phase = GenerationPhase.Generated; Visible = false; Changed?.Invoke(); }
    public string DisplayText() => Mode switch
    {
        GeneratorMode.Pin => new string('0', Length),
        GeneratorMode.Hex => string.Concat(Enumerable.Repeat(UppercaseHex ? "DEADBEEF" : "deadbeef", (Length + 7) / 8))[..Length],
        GeneratorMode.Ascii => string.Concat(Enumerable.Repeat("PUBLIC-DESIGN-FIXTURE!", (Length + 20) / 21))[..Length],
        _ => string.Join(Separator, DisplayWords())
    };
    public string[] DisplayWords() => Visible ? Enumerable.Range(0, Length).Select(i => new[] { "public", "design", "fixture", "only", "never", "use", "for", "wallet", "or", "real", "password", "storage" }[i % 12]).ToArray() : [];
    public void Reveal() { Visible = true; Changed?.Invoke(); }
    public void Conceal() { Visible = false; Changed?.Invoke(); }
    public void ContextChanged() { }
    public void Copy() { ClipboardScheduled = true; Changed?.Invoke(); }
    public void Reset() { Phase = GenerationPhase.Collecting; Visible = false; Changed?.Invoke(); }
    public void Dispose() { }
}
