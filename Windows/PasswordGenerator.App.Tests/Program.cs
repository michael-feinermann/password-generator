using PasswordGenerator.App;
using PasswordGenerator.Core;
using System.Diagnostics;
using System.Reflection;
using System.Windows;
using System.Windows.Threading;

internal static class Program
{
    private static int assertions;
    private static void Assert(bool condition, string name) { assertions++; if (!condition) throw new InvalidOperationException(name); }
    private static void SetSecret(AppModel model)
    {
        var dummy = new PasswordGenerator.Core.PasswordGenerator().Generate(new(GeneratorMode.Pin, 6), count => new byte[count]);
        typeof(AppModel).GetField("secret", BindingFlags.NonPublic | BindingFlags.Instance)!.SetValue(model, dummy);
        typeof(AppModel).GetProperty(nameof(AppModel.Phase))!.SetValue(model, AppModel.GenerationPhase.Generated);
    }
    private static DispatcherTimer ModelTimer(AppModel model, string name) => (DispatcherTimer)typeof(AppModel).GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(model)!;
    private static void PumpUntil(Func<bool> condition, TimeSpan timeout)
    {
        var frame = new DispatcherFrame(); var watch = Stopwatch.StartNew();
        var check = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
        check.Tick += (_, _) => { if (condition() || watch.Elapsed > timeout) { check.Stop(); frame.Continue = false; } };
        check.Start(); Dispatcher.PushFrame(frame);
        Assert(condition(), "Dispatcher timeout");
    }
    [STAThread]
    private static int Main()
    {
        var application = new Application();
        var window = new Window { Width = 20, Height = 20, ShowInTaskbar = false, WindowStyle = WindowStyle.None, Left = -10000, Top = -10000 };
        application.MainWindow = window; window.Show();
        var originalLanguage = LanguagePreferences.Load();
        try
        {
            using var model = new AppModel();
            model.Error += _ => { }; // UI presentation is tested separately.
            Assert(model.Mode == GeneratorMode.Bip39 && model.Length == 24, "Startup default");
            Assert(model.Phase == AppModel.GenerationPhase.Collecting && !model.Visible && model.DisplayText() == "" && model.ComponentCount == 0, "Startup empty and hidden");
            foreach (var pair in new[] { (GeneratorMode.Eff, 20), (GeneratorMode.Ascii, 40), (GeneratorMode.Pin, 6), (GeneratorMode.Hex, 64), (GeneratorMode.Bip39, 24) }) { model.SetMode(pair.Item1); Assert(model.Length == pair.Item2, "Mode default"); }
            model.SetMode(GeneratorMode.Ascii); model.SetLength(0); Assert(model.Configuration == null && !model.CanGenerate, "Invalid draft gated"); model.SetLength(40);
            for (var i = 0; i < 4095; i++) model.Record(new((ulong)i, i / 1000.0, i % 100, i % 80, 1, 1, 1060, 840, 0, 0));
            model.Confirmed = true;
            Assert(!model.CanGenerate && model.Phase == AppModel.GenerationPhase.Collecting, "4095 samples gated");
            model.Record(new(4096, 4.096, 10, 10, 1, 1, 1060, 840, 0, 0));
            Assert(model.CanGenerate && model.Phase == AppModel.GenerationPhase.Ready, "4096 samples gate");
            model.Confirmed = false; Assert(!model.CanGenerate, "Confirmation gate"); model.Confirmed = true;
            RuntimeSecurity.Allowed = false; model.Generate(); Assert(!model.CanGenerate && model.ComponentCount == 0, "Fresh runtime check gates generate"); RuntimeSecurity.Allowed = true;
            model.SetMode(GeneratorMode.Bip39); model.Confirmed = true; model.Generate(); Assert(model.Phase == AppModel.GenerationPhase.Generated && model.ComponentCount == 24 && !model.Visible && model.DisplayText() == "", "Complete model BIP39 generation remains concealed");
            model.Reset();
            model.SetMode(GeneratorMode.Pin); SetSecret(model);
            Assert(model.DisplayText() == "", "Dummy result initially hidden"); model.Copy(); Assert(!model.ClipboardScheduled, "Hidden copy gated");
            model.Reveal(); Assert(model.Visible && model.DisplayText() == "000000", "Reveal dummy result");
            Assert(ModelTimer(model, "concealTimer").Interval.TotalSeconds == 60, "Reveal timer60");
            Assert(ModelTimer(model, "clipboardTimer").Interval.TotalSeconds == 45, "Clipboard timer45");
            Assert(ModelTimer(model, "shuffleTimer").Interval.TotalSeconds == 6, "Pool timer6");
            model.Copy(); Assert(model.ClipboardScheduled && Clipboard.GetText() == "000000", "Explicit dummy copy");
            Assert(Clipboard.ContainsData("CanIncludeInClipboardHistory") && Clipboard.ContainsData("CanUploadToCloudClipboard") && Clipboard.ContainsData("ExcludeClipboardContentFromMonitorProcessing"), "Native clipboard exclusion formats");
            PrivateClipboard.Copy("PASSWORD-GENERATOR-TEST-UNRELATED"); model.Reset(); Assert(Clipboard.GetText() == "PASSWORD-GENERATOR-TEST-UNRELATED", "Cleanup preserves another clipboard write");
            SetSecret(model); model.Reveal(); model.Copy(); model.Reset(); Assert(!Clipboard.ContainsText(), "Own clipboard cleared on reset");
            SetSecret(model); model.Reveal(); model.Confirmed = true; model.ContextChanged(); Assert(!model.Visible && !model.Confirmed && model.DisplayText() == "", "Context hides and resets confirmation");
            model.Reveal(); RuntimeSecurity.Allowed = false; model.Copy(); Assert(model.Phase == AppModel.GenerationPhase.Collecting && model.ComponentCount == 0 && !model.Visible, "Runtime failure discards result before copy"); RuntimeSecurity.Allowed = true;
            model.Bip39Separator = ""; model.EffSeparator = "::"; model.UppercaseHex = true; model.Reset(); Assert(model.Bip39Separator == "" && model.EffSeparator == "::" && model.UppercaseHex, "Reset retains session export preferences");
            model.SetLanguage("de"); Assert(LanguagePreferences.Load() == "de", "Language persisted"); model.SetLanguage("invalid"); Assert(model.Language == "en", "Language fallback"); model.SetLanguage(originalLanguage);
            model.SetMode(GeneratorMode.Pin); SetSecret(model); model.Reveal(); model.Copy();
            var initialShuffles = model.ShuffleCount;
            Console.WriteLine("Model gates, native clipboard formats, conditional cleanup, context handling, and language checks passed. Waiting for real 45/60-second timers.");
            PumpUntil(() => !model.ClipboardScheduled, TimeSpan.FromSeconds(49)); Assert(!Clipboard.ContainsText(), "Actual45-second clipboard cleanup");
            PumpUntil(() => !model.Visible, TimeSpan.FromSeconds(18)); Assert(model.DisplayText() == "", "Actual60-second concealment");
            Assert(model.ShuffleCount >= initialShuffles + 9, "Actual periodic shuffles continue after generation");
            Console.WriteLine($"PASS AppModel: {assertions} assertions, including real 45-second clipboard and 60-second reveal timers.");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine("FAIL: " + error); return 1; }
        finally { LanguagePreferences.Save(originalLanguage); window.Close(); }
    }
}
