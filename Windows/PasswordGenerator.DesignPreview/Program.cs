using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Automation;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using PasswordGenerator.App;
using PasswordGenerator.Core;

namespace PasswordGenerator.DesignPreview;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var options = args.Select((value, index) => (value, index)).Where(pair => pair.value.StartsWith("--", StringComparison.Ordinal))
            .ToDictionary(pair => pair.value[2..], pair => pair.index + 1 < args.Length ? args[pair.index + 1] : "", StringComparer.Ordinal);
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        LoadTheme(application);
        var exitCode = 0;
        if (options.TryGetValue("matrix", out var matrixDirectory))
        {
            var scenes = 0; var failed = new List<string>();
            foreach (var size in new[] { (1060, 840), (1440, 1000), (1920, 840) })
            foreach (var language in new[] { "de", "en" })
            foreach (var mode in Enum.GetValues<GeneratorMode>())
            foreach (var state in new[] { ("Collecting", "false"), ("Ready", "false"), ("Generated", "false"), ("Generated", "true") })
            {
                var name = $"{language}-{mode}-{state.Item1}-{size.Item1}x{size.Item2}-{state.Item2}";
                var scene = new Dictionary<string, string> { ["width"] = size.Item1.ToString(CultureInfo.InvariantCulture), ["height"] = size.Item2.ToString(CultureInfo.InvariantCulture),
                    ["language"] = language, ["mode"] = mode.ToString(), ["phase"] = state.Item1, ["visible"] = state.Item2,
                    ["full"] = "true", ["output"] = Path.Combine(matrixDirectory, name + ".png"), ["check-controls"] = "true" };
                if (Render(scene) != 0) failed.Add(name);
                scenes++;
            }
            var report = new { SceneCount = scenes, PublicFixtureOnly = true, NativeWindowsCreated = 0, FailedScenes = failed };
            Directory.CreateDirectory(matrixDirectory);
            File.WriteAllText(Path.Combine(matrixDirectory, "matrix.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine(JsonSerializer.Serialize(report)); exitCode = failed.Count == 0 ? 0 : 2;
        }
        else exitCode = Render(options);
        application.Shutdown(); return exitCode;
    }

    private static int Render(Dictionary<string, string> options)
    {
        string Option(string key, string fallback) => options.GetValueOrDefault(key, fallback);
        var width = double.Parse(Option("width", "1060"), CultureInfo.InvariantCulture);
        var height = double.Parse(Option("height", "840"), CultureInfo.InvariantCulture);
        var output = Path.GetFullPath(Option("output", "Windows/artifacts/design-preview.png"));
        AppModel.PreviewLanguage = Option("language", "de");
        AppModel.PreviewMode = Enum.Parse<GeneratorMode>(Option("mode", "Bip39"), true);
        AppModel.PreviewPhase = Enum.Parse<AppModel.GenerationPhase>(Option("phase", "Ready"), true);
        AppModel.PreviewVisible = Option("visible", "false") == "true";
        AppModel.PreviewLength = options.TryGetValue("length", out var length) ? int.Parse(length, CultureInfo.InvariantCulture) : null;
        var window = new MainWindow { Width = width, Height = height };
        // This development process never shows a window and never creates a native HWND.
        // Thus SourceInitialized/capture guards are never entered, while the exact production visual tree is reused.
        var content = (FrameworkElement)window.Content;
        window.Content = null;
        ApplyPreviewLayout(window, width, height);
        var frame = new Border { Background = window.Background, Child = content, Width = width, Height = height };
        frame.Measure(new Size(width, height)); frame.Arrange(new Rect(0, 0, width, height)); frame.UpdateLayout();
        var page = (StackPanel)Field(window, "page");
        if (Option("full", "false") == "true")
        {
            var pageTop = page.TransformToAncestor(frame).Transform(new Point()).Y;
            var totalHeight = Math.Ceiling(page.ActualHeight * ((ScaleTransform)page.LayoutTransform).ScaleY + pageTop + page.Margin.Bottom);
            frame.Height = totalHeight; frame.Measure(new Size(width, totalHeight)); frame.Arrange(new Rect(0, 0, width, totalHeight)); frame.UpdateLayout();
        }
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(frame.ActualWidth), (int)Math.Ceiling(frame.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(frame);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        using (var file = File.Create(output)) encoder.Save(file);
        var geometry = Inspect(content);
        var controlChecks = VerifyControls(content, geometry.failures);
        if (Option("check-controls", "false") == "true") controlChecks += VerifyMainWindow(window, frame, geometry.failures);
        var nativeWindowCreated = PresentationSource.FromVisual(window) != null || (nint)Field(window, "hwnd") != 0;
        if (nativeWindowCreated) geometry.failures.Add("Preview unexpectedly created a native window.");
        var report = new { output, width = frame.ActualWidth, height = frame.ActualHeight, language = AppModel.PreviewLanguage,
            mode = AppModel.PreviewMode.ToString(), phase = AppModel.PreviewPhase.ToString(), publicFixtureOnly = true,
            nativeWindowCreated, geometry.textBlocks, geometry.buttons, controlChecks, checks = geometry.failures };
        File.WriteAllText(Path.ChangeExtension(output, ".json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine(JsonSerializer.Serialize(report));
        ((System.Windows.Threading.DispatcherTimer)Field(window, "refreshTimer")).Stop();
        ((AppModel)Field(window, "model")).Dispose();
        return geometry.failures.Count == 0 ? 0 : 2;
    }

    private static object Field(MainWindow window, string name) => typeof(MainWindow).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(window)!;

    private static void ApplyPreviewLayout(MainWindow window, double width, double height)
    {
        var layout = typeof(MainWindow).GetMethod("ApplyLayout", BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("The production ApplyLayout method is missing.");
        layout.Invoke(window, [width, height]);
    }

    private static void LoadTheme(Application application)
    {
        var dictionary = (ResourceDictionary)Application.LoadComponent(new Uri("/PasswordGenerator.DesignPreview;component/Themes/Controls.xaml", UriKind.Relative));
        application.Resources.MergedDictionaries.Add(dictionary);
    }

    private static (List<string> failures, int textBlocks, int buttons) Inspect(DependencyObject root)
    {
        var failures = new List<string>();
        int textBlocks = 0, buttons = 0;
        void Walk(DependencyObject node)
        {
            if (node is UIElement collapsed && collapsed.Visibility != Visibility.Visible) return;
            if (node is FrameworkElement element && element.ActualWidth > 0 && element.ActualHeight > 0)
            {
                if (element is TextBlock or Button or TextBox or Slider && root is FrameworkElement viewport)
                {
                    var bounds = element.TransformToAncestor(viewport).TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));
                    if (bounds.Left < -2 || bounds.Right > viewport.ActualWidth + 2)
                        failures.Add($"Horizontal overflow: {element.GetType().Name}, bounds {bounds.Left:F1}..{bounds.Right:F1}, viewport {viewport.ActualWidth:F1}.");
                }
                if (element is Button button && button.Content is string label && !string.IsNullOrEmpty(label))
                {
                    buttons++;
                    var text = new FormattedText(label, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                        new Typeface(button.FontFamily, button.FontStyle, button.FontWeight, button.FontStretch), button.FontSize, Brushes.White, 1);
                    if (button.ActualWidth > 0 && text.Width > button.ActualWidth - button.Padding.Left - button.Padding.Right + 2)
                        failures.Add($"Button label clipped: {label}, text {text.Width:F1}, available {button.ActualWidth - button.Padding.Left - button.Padding.Right:F1}");
                }
                if (element is TextBlock textBlock && !string.IsNullOrEmpty(textBlock.Text) && textBlock.ActualWidth > 0 && textBlock.TextTrimming == TextTrimming.None)
                {
                    textBlocks++;
                    var text = new FormattedText(textBlock.Text, CultureInfo.CurrentUICulture, textBlock.FlowDirection,
                        new Typeface(textBlock.FontFamily, textBlock.FontStyle, textBlock.FontWeight, textBlock.FontStretch), textBlock.FontSize, Brushes.White, 1);
                    var runOffset = 0;
                    foreach (var inline in textBlock.Inlines)
                    {
                        if (inline is Run run && run.Text.Length > 0 && runOffset + run.Text.Length <= textBlock.Text.Length)
                        {
                            text.SetFontSize(run.FontSize, runOffset, run.Text.Length);
                            text.SetFontTypeface(new Typeface(run.FontFamily, run.FontStyle, run.FontWeight, run.FontStretch), runOffset, run.Text.Length);
                            runOffset += run.Text.Length;
                        }
                    }
                    if (textBlock.TextWrapping == TextWrapping.NoWrap && text.Width > textBlock.ActualWidth + 2)
                        failures.Add($"Text clipped: {textBlock.Text}, text {text.Width:F1}, available {textBlock.ActualWidth:F1}");
                    if (textBlock.TextWrapping != TextWrapping.NoWrap)
                    {
                        text.MaxTextWidth = Math.Max(1, textBlock.ActualWidth - textBlock.Padding.Left - textBlock.Padding.Right);
                        if (text.Height > textBlock.ActualHeight - textBlock.Padding.Top - textBlock.Padding.Bottom + 2)
                            failures.Add($"Text height clipped: {textBlock.Text}, text {text.Height:F1}, available {textBlock.ActualHeight - textBlock.Padding.Top - textBlock.Padding.Bottom:F1}");
                    }
                }
            }
            for (var index = 0; index < VisualTreeHelper.GetChildrenCount(node); index++) Walk(VisualTreeHelper.GetChild(node, index));
        }
        Walk(root);
        if (textBlocks < 20 || buttons < 10) failures.Add($"Preview tree unexpectedly empty: {textBlocks} text blocks, {buttons} buttons.");
        return (failures, textBlocks, buttons);
    }

    private static int VerifyControls(DependencyObject root, List<string> failures)
    {
        var sliders = new List<Slider>();
        void Collect(DependencyObject node)
        {
            if (node is Slider slider) sliders.Add(slider);
            for (var index = 0; index < VisualTreeHelper.GetChildrenCount(node); index++) Collect(VisualTreeHelper.GetChild(node, index));
        }
        Collect(root);
        var assertions = 0;
        foreach (var slider in sliders)
        {
            if (slider.Template.FindName("PART_Track", slider) is not Track track) { failures.Add("Slider has no PART_Track."); continue; }
            assertions++;
            if (track.Minimum != slider.Minimum || track.Maximum != slider.Maximum || track.Value != slider.Value)
                failures.Add($"Slider track bindings are inconsistent: track {track.Minimum}/{track.Value}/{track.Maximum}, slider {slider.Minimum}/{slider.Value}/{slider.Maximum}.");
            if (slider.IsEnabled && slider.Value < slider.Maximum)
            {
                var original = slider.Value;
                Slider.IncreaseLarge.Execute(null, slider);
                assertions++;
                if (slider.Value <= original || slider.Value > slider.Maximum) failures.Add("Slider IncreaseLarge does not update its value within bounds.");
                Slider.DecreaseLarge.Execute(null, slider);
                assertions++;
                if (slider.Value >= Math.Min(original + slider.LargeChange, slider.Maximum) || slider.Value < slider.Minimum)
                    failures.Add("Slider DecreaseLarge does not update its value within bounds.");
                slider.Value = original;
            }
        }
        return assertions;
    }

    private static int VerifyMainWindow(MainWindow window, FrameworkElement frame, List<string> failures)
    {
        var model = (AppModel)Field(window, "model");
        var originalMode = model.Mode; var originalLength = model.Length; var originalCase = model.UppercaseHex;
        var assertions = 0;
        IEnumerable<DependencyObject> Descendants(DependencyObject node)
        {
            yield return node;
            for (var index = 0; index < VisualTreeHelper.GetChildrenCount(node); index++)
                foreach (var child in Descendants(VisualTreeHelper.GetChild(node, index))) yield return child;
        }
        void Click(string id)
        {
            frame.UpdateLayout();
            var button = Descendants(frame).OfType<Button>().FirstOrDefault(item => AutomationProperties.GetAutomationId(item) == id);
            if (button == null) { failures.Add("Missing control: " + id); return; }
            button.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); frame.UpdateLayout(); assertions++;
        }
        if (model.Phase != AppModel.GenerationPhase.Generated)
        {
            Click("Mode_Bip39"); Click("Length_12"); assertions++;
            if (model.Length != 12) failures.Add("BIP39 length button did not select 12 words.");
            for (var iteration = 0; iteration < 5; iteration++) { Click("Length_24"); Click("Length_12"); }
            var legends = (System.Collections.ICollection)Field(window, "legendGrids"); assertions++;
            if (legends.Count != 1) failures.Add($"Length changes retained inactive legend grids ({legends.Count}).");
            Click("Mode_Pin"); assertions++;
            if (model.Mode != GeneratorMode.Pin) failures.Add("Mode picker did not select PIN.");
            var slider = (Slider)Field(window, "lengthSlider"); var initial = slider.Value;
            Slider.IncreaseSmall.Execute(null, slider); frame.UpdateLayout(); assertions++;
            if (model.Length != (int)initial + 1) failures.Add("PIN slider keyboard increment did not update the model length.");
            Slider.DecreaseSmall.Execute(null, slider); frame.UpdateLayout(); assertions++;
            if (model.Length != (int)initial) failures.Add("PIN slider keyboard decrement did not restore the model length.");
            Click("Mode_Hex");
        }
        if (model.Mode == GeneratorMode.Hex)
        {
            var phase = model.Phase; var visible = model.Visible; var length = model.Length;
            Click("UppercaseHex"); assertions++;
            if (!model.UppercaseHex || model.Length != length || model.Phase != phase || model.Visible != visible) failures.Add("Uppercase picker altered generation state or failed to change case.");
            Click("LowercaseHex"); assertions++;
            if (model.UppercaseHex || model.Length != length || model.Phase != phase || model.Visible != visible) failures.Add("Lowercase picker altered generation state or failed to change case.");
        }
        if (model.Phase != AppModel.GenerationPhase.Generated) { model.SetMode(originalMode); model.SetLength(originalLength); }
        model.UppercaseHex = originalCase; frame.UpdateLayout();
        return assertions;
    }
}
