using PasswordGenerator.Core;
using System.Windows.Threading;

namespace PasswordGenerator.App;

public sealed class AppModel : IDisposable
{
    public enum GenerationPhase { Collecting, Ready, Generated }
    public event Action? Changed;
    public event Action<string>? Error;
    private readonly PasswordGenerator.Core.PasswordGenerator generator;
    private EntropyPool? pool;
    private GeneratedPassword? secret;
    private readonly DispatcherTimer shuffleTimer;
    private readonly DispatcherTimer concealTimer;
    private readonly DispatcherTimer clipboardTimer;
    private ClipboardOwnership? clipboardSequence;
    private bool disposed;

    public string Language { get; private set; } = LanguagePreferences.Load();
    public GeneratorMode Mode { get; private set; } = GeneratorMode.Bip39;
    public int Length { get; private set; } = GeneratorMode.Bip39.DefaultLength();
    public string Bip39Separator { get; set; } = " ";
    public string EffSeparator { get; set; } = "-";
    public bool UppercaseHex { get; set; }
    public bool Confirmed { get; set; }
    public bool Visible { get; private set; }
    public bool ClipboardScheduled => clipboardSequence.HasValue;
    public GenerationPhase Phase { get; private set; }
    public RuntimeSecurityAssessment Security { get; private set; } = RuntimeSecurity.Check();
    public long EventCount { get; private set; }
    public long ShuffleCount => pool?.ShuffleCount ?? 0;
    public int ComponentCount => secret?.ComponentCount ?? 0;
    public WordListIntegrity Bip39Integrity => generator.Bip39.Integrity;
    public WordListIntegrity EffIntegrity => generator.Eff.Integrity;
    public GeneratorConfiguration? Configuration
    {
        get { var configuration = new GeneratorConfiguration(Mode, Length); try { configuration.Validate(); return configuration; } catch (ArgumentException) { return null; } }
    }
    public bool CanGenerate => !disposed && Phase == GenerationPhase.Ready && Configuration != null && pool != null && Confirmed && Security.IsEnforced;
    public string Separator { get => Mode == GeneratorMode.Bip39 ? Bip39Separator : EffSeparator; set { if (Mode == GeneratorMode.Bip39) Bip39Separator = value; else EffSeparator = value; } }
    public string Tr(string german, string english) => Language == "de" ? german : english;

    public AppModel()
    {
        CryptographicSelfTest.Run();
        generator = new();
        pool = new();
        shuffleTimer = Timer(TimeSpan.FromSeconds(6), () => { try { pool?.Shuffle(); Changed?.Invoke(); } catch (Exception) { FailRandom(); } });
        concealTimer = Timer(TimeSpan.FromSeconds(60), Conceal, start: false);
        clipboardTimer = Timer(TimeSpan.FromSeconds(45), ClearClipboard, start: false);
    }
    private static DispatcherTimer Timer(TimeSpan interval, Action action, bool start = true)
    {
        var timer = new DispatcherTimer { Interval = interval };
        timer.Tick += (_, _) => action();
        if (start) timer.Start();
        return timer;
    }
    public void SetLanguage(string language) { Language = language == "de" ? "de" : "en"; LanguagePreferences.Save(Language); Changed?.Invoke(); }
    public void SetMode(GeneratorMode mode) { if (Phase == GenerationPhase.Generated || Mode == mode) return; Mode = mode; Length = mode.DefaultLength(); Changed?.Invoke(); }
    public void SetLength(int length) { if (Phase == GenerationPhase.Generated || Length == length) return; Length = length; Changed?.Invoke(); }
    public void Record(MouseEntropyRecord sample)
    {
        if (disposed || pool == null) return;
        pool.Absorb(sample);
        if (EventCount < long.MaxValue) EventCount++;
        if (EventCount >= EntropyPool.RequiredMouseEventCount && Phase == GenerationPhase.Collecting) Phase = GenerationPhase.Ready;
    }
    public void Generate()
    {
        if (disposed || Phase != GenerationPhase.Ready || pool == null || Configuration is not { } config) return;
        if (!Confirmed) { Error?.Invoke(Tr("Bestätige die sichere Umgebung.", "Confirm a secure environment.")); return; }
        if (!VerifyRuntime(false)) return;
        try
        {
            // Disposal of stream state precedes publishing the secret to the UI.
            GeneratedPassword generated;
            using (var stream = pool.MakeStream()) generated = generator.Generate(config, stream.Bytes);
            // The core validates BIP39 components before owned result creation,
            // without exporting a joined plaintext phrase while concealed.
            secret = generated;
            Visible = false;
            Phase = GenerationPhase.Generated;
            Changed?.Invoke();
        }
        catch (Exception) { FailRandom(); }
    }
    public string DisplayText() => Visible && secret is { IsCleared: false } ? secret.ExportText(Separator, UppercaseHex) : "";
    public string[] DisplayWords() => Visible && secret is { IsCleared: false } ? secret.ExportText(" ", false).Split(' ') : [];
    public void Reveal()
    {
        if (disposed || Phase != GenerationPhase.Generated || secret is not { IsCleared: false }) return;
        if (!VerifyRuntime(true)) return;
        Visible = true;
        concealTimer.Stop(); concealTimer.Start();
        Changed?.Invoke();
    }
    public void Conceal() { concealTimer.Stop(); Visible = false; Changed?.Invoke(); }
    public void ContextChanged() { Confirmed = false; Conceal(); }
    public void Copy()
    {
        if (!Visible || disposed || secret is not { IsCleared: false }) return;
        if (!VerifyRuntime(true)) return;
        try
        {
            clipboardSequence = PrivateClipboard.Copy(secret.ExportText(Separator, UppercaseHex));
            clipboardTimer.Stop();
            if (clipboardSequence.HasValue) clipboardTimer.Start();
            else Error?.Invoke(Tr("Die Kopie konnte nicht für automatische Löschung überwacht werden. Kopiere erneut oder leere die Zwischenablage manuell.", "The copy could not be tracked for automatic cleanup. Copy again or clear the clipboard manually."));
            Changed?.Invoke();
        }
        catch (System.Runtime.InteropServices.ExternalException) { Error?.Invoke(Tr("Das Passwort konnte nicht in die Zwischenablage kopiert werden.", "The password could not be copied to the clipboard.")); }
    }
    private void ClearClipboard() { clipboardTimer.Stop(); PrivateClipboard.ClearIfUnchanged(clipboardSequence); clipboardSequence = null; Changed?.Invoke(); }
    public void Reset()
    {
        ClearSecret();
        pool?.Dispose(); pool = null;
        EventCount = 0; Confirmed = false; Phase = GenerationPhase.Collecting;
        if (!disposed) { try { pool = new(); } catch (Exception) { FailRandom(); } }
        Changed?.Invoke();
    }
    private void ClearSecret() { secret?.Clear(); secret?.Dispose(); secret = null; Conceal(); ClearClipboard(); }
    private bool VerifyRuntime(bool discard)
    {
        Security = RuntimeSecurity.Check();
        if (Security.IsEnforced) return true;
        if (discard) Reset();
        Error?.Invoke(Tr("Die Laufzeitprüfung ist fehlgeschlagen. Starte die signierte Installation ohne Debugger neu.", "Runtime verification failed. Restart the signed installation without a debugger.") + "\n\n" + Security.Details);
        Changed?.Invoke();
        return false;
    }
    private void FailRandom()
    {
        // Failure closes the entropy gate rather than retaining partially derived state.
        ClearSecret(); pool?.Dispose(); pool = null;
        EventCount = 0; Confirmed = false; Phase = GenerationPhase.Collecting;
        Error?.Invoke(Tr("Der Zufallspool oder eine kryptografische Prüfung ist fehlgeschlagen. Starte die App neu.", "The random pool or a cryptographic check failed. Restart the application."));
        Changed?.Invoke();
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        shuffleTimer.Stop(); concealTimer.Stop(); clipboardTimer.Stop();
        ClearSecret(); pool?.Dispose(); pool = null; Confirmed = false;
    }
}
