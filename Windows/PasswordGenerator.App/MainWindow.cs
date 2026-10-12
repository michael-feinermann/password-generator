using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Media.Effects;
using System.Windows.Shell;
using System.Windows.Threading;
using PasswordGenerator.Core;

namespace PasswordGenerator.App;

/// <summary>Native Windows adaptation of the 2.3.6 SwiftUI window.</summary>
public sealed class MainWindow : Window
{
    private static readonly Brush Teal = Brush("#3BE0C4"), Secondary = Brush("#AFB1B5"), Muted = Brush("#979A9E"), Amber = Brush("#FFB84D");
    private readonly AppModel model = new();
    private readonly StackPanel page = new();
    private readonly ScrollViewer scroller = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly ScaleTransform scaleTransform = new(1, 1);
    private readonly DispatcherTimer refreshTimer;
    private TextBlock collectionText = null!, remainingText = null!, shuffleText = null!, runtimeText = null!, clipboardText = null!, revealHint = null!;
    private ProgressBar progress = null!;
    private Button generateButton = null!, revealButton = null!, copyButton = null!;
    private CheckBox confirmation = null!;
    private Border resultCard = null!;
    private StackPanel secretContent = null!;
    private FrameworkElement configurationControls = null!;
    private Border entropyHost = null!;
    private TextBox? lengthInput;
    private Slider? lengthSlider;
    private readonly Dictionary<int, Button> bipLengthButtons = [];
    private readonly List<TextBlock> materializedSecrets = [];
    private readonly List<UniformGrid> legendGrids = [];
    private UniformGrid securityGrid = null!;
    private string lastLanguage = "";
    private GeneratorMode lastMode = (GeneratorMode)(-1);
    private int lastLength = -1;
    private bool lastGenerated;
    private bool renderedVisible;
    private bool building;
    private Point? lastMousePoint;
    private HwndSource? source;
    private nint hwnd;

    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowDisplayAffinity(nint window, uint affinity);
    [DllImport("user32.dll")] private static extern short GetKeyState(int virtualKey);
    [DllImport("user32.dll")] private static extern int GetMessageTime();
    [DllImport("user32.dll")] private static extern bool GetClientRect(nint window, out NativeRect rectangle);
    [DllImport("wtsapi32.dll", SetLastError = true)] private static extern bool WTSRegisterSessionNotification(nint window, uint flags);
    [DllImport("wtsapi32.dll")] private static extern bool WTSUnRegisterSessionNotification(nint window);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }

    public MainWindow()
    {
        Title = "Password Generator 2.3.6";
        Width = MinWidth = 1060; Height = MinHeight = 840;
        Background = Brush("#060B12"); Foreground = Brushes.White; FontFamily = new("Segoe UI Variable, Segoe UI"); FontSize = 14;
        UseLayoutRounding = true; SnapsToDevicePixels = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.CanResize;
        WindowChrome.SetWindowChrome(this, new WindowChrome { CaptionHeight = 34, ResizeBorderThickness = new(6), GlassFrameThickness = new(0), CornerRadius = new(0), UseAeroCaptionButtons = false });
        Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/PasswordGenerator.ico"));
        page.LayoutTransform = scaleTransform;
        scroller.Content = page;
        var frame = new DockPanel();
        var titleBar = TitleBar(); DockPanel.SetDock(titleBar, Dock.Top); frame.Children.Add(titleBar);
        frame.Children.Add(scroller); Content = frame;
        model.Changed += Update;
        model.Error += message => MessageBox.Show(this, message, Tr("Aktion fehlgeschlagen", "Action failed"), MessageBoxButton.OK, MessageBoxImage.Error);
        SizeChanged += (_, _) => ResizeContent();
        Deactivated += (_, _) => { lastMousePoint = null; model.ContextChanged(); };
        StateChanged += (_, _) => { if (WindowState == WindowState.Minimized) model.ContextChanged(); };
        SourceInitialized += (_, _) => InitializeNativeWindow();
        Closing += (_, _) => { ClearMaterializedSecrets(); model.Dispose(); };
        Closed += (_, _) =>
        {
            refreshTimer?.Stop();
            source?.RemoveHook(WindowMessage);
            if (hwnd != 0) WTSUnRegisterSessionNotification(hwnd);
            ClearMaterializedSecrets();
            model.Dispose();
        };
        CommandBindings.Add(new CommandBinding(ApplicationCommands.Close, (_, _) => Close()));
        InputBindings.Add(new KeyBinding(new HideCommand(model), Key.H, ModifierKeys.Control | ModifierKeys.Shift));
        refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        refreshTimer.Tick += (_, _) => UpdateCounters();
        refreshTimer.Start();
        BuildPage();
    }

    private string Tr(string german, string english) => model.Tr(german, english);
    private CultureInfo Culture => CultureInfo.GetCultureInfo(model.Language == "de" ? "de-DE" : "en-US");
    private static Brush Brush(string hex) => (Brush)new BrushConverter().ConvertFromString(hex)!;
    private static TextBlock Text(string text, double size = 14, Brush? color = null, FontWeight? weight = null) => new() { Text = text, FontSize = size, Foreground = color ?? Brushes.White, FontWeight = weight ?? FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap };
    private static StackPanel Vertical(double gap = 0) => new() { Orientation = Orientation.Vertical, Margin = new(0, gap, 0, 0) };
    private static Button Button(string label, Action click, string id)
    {
        var button = new Button { Content = label };
        AutomationProperties.SetAutomationId(button, id);
        AutomationProperties.SetName(button, label);
        button.Click += (_, _) => click();
        return button;
    }
    private static Border Surface(UIElement child, string color = "#0E141D", double radius = 23, Thickness? padding = null) => new() { Background = Brush(color), BorderBrush = Brush("#232C38"), BorderThickness = new(1), CornerRadius = new(radius), Padding = padding ?? new(22), Child = child };
    private static Style Theme(string key) => (Style)Application.Current.FindResource(key);
    private static void SelectSegment(Button button, bool selected)
    {
        button.Style = Theme(selected ? "SelectedSegmentedButton" : "SegmentedButton");
        AutomationProperties.SetItemStatus(button, selected ? "Selected" : "");
    }
    private static Border SegmentTrack(Panel segments) => Surface(segments, "#131A23", 10, new(3));
    private static UIElement Symbol(string kind, double size = 16, Brush? color = null)
    {
        // Small vector symbols avoid font-dependent Unicode/emoji rendering.
        var data = kind switch
        {
            "lock" => "M5,10 L5,7 C5,0 15,0 15,7 L15,10 M3,10 L17,10 L17,20 L3,20 Z M10,14 L10,17",
            "cursor" => "M3,2 L3,18 L7,14 L11,21 L14,19 L10,13 L17,13 Z M16,2 L20,2 M18,5 L21,7",
            "shuffle" => "M1,5 L5,5 C9,5 11,17 15,17 L21,17 M17,13 L21,17 L17,21 M1,17 L5,17 C9,17 11,5 15,5 L21,5 M17,1 L21,5 L17,9",
            "shield" => "M11,1 L20,4 L20,11 C20,16 16,20 11,22 C6,20 2,16 2,11 L2,4 Z M6,11 L10,15 L16,8",
            "desktop" => "M1,2 L21,2 L21,16 L1,16 Z M11,16 L11,21 M6,21 L16,21",
            "atom" => "M2,11 C2,5 20,5 20,11 C20,17 2,17 2,11 M6,3 C11,0 20,16 15,19 C10,22 1,6 6,3 M15,3 C20,6 11,22 6,19 C1,16 10,0 15,3 M10,11 L12,11",
            "minimize" => "M3,11 L17,11",
            "maximize" => "M4,4 L16,4 L16,16 L4,16 Z",
            "close" => "M4,4 L16,16 M16,4 L4,16",
            "warning" => "M11,2 L22,21 L0,21 Z M11,8 L11,14 M11,17 L11,18",
            "half" => "M11,1 A10,10 0 1 1 11,21 A10,10 0 1 1 11,1 M11,1 L11,21 M3,7 L11,7 M1,11 L11,11 M3,15 L11,15",
            "bars" => "M2,20 L2,13 L6,13 L6,20 Z M9,20 L9,8 L13,8 L13,20 Z M16,20 L16,2 L20,2 L20,20 Z",
            "layers" => "M11,1 L22,6 L11,11 L0,6 Z M0,11 L11,16 L22,11 M0,16 L11,21 L22,16",
            _ => "M11,1 A10,10 0 1 1 11,21 A10,10 0 1 1 11,1 M11,9 L11,16 M11,5 L11,6"
        };
        return new Viewbox { Width = size, Height = size, Stretch = Stretch.Uniform, Child = new System.Windows.Shapes.Path { Data = Geometry.Parse(data), Stroke = color ?? Teal, StrokeThickness = 1.6, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round } };
    }
    private UIElement TitleBar()
    {
        var bar = new DockPanel { Height = 34, Background = Brush("#090F17"), LastChildFill = true };
        var controls = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var item in new[] { ("minimize", "MinimizeWindow", Tr("Minimieren", "Minimize"), (Action)(() => WindowState = WindowState.Minimized)), ("maximize", "MaximizeWindow", Tr("Maximieren / Wiederherstellen", "Maximize / restore"), (Action)(() => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized)), ("close", "CloseWindow", Tr("Schließen", "Close"), (Action)Close) })
        {
            var button = Button(item.Item3, item.Item4, item.Item2); button.Style = Theme(item.Item1 == "close" ? "CloseWindowButton" : "WindowControlButton");
            button.Content = Symbol(item.Item1, 12, Secondary); button.ToolTip = item.Item3;
            WindowChrome.SetIsHitTestVisibleInChrome(button, true); controls.Children.Add(button);
        }
        DockPanel.SetDock(controls, Dock.Right); bar.Children.Add(controls);
        var caption = Text(Title, 14, Muted); caption.Margin = new(16, 0, 0, 0); bar.Children.Add(caption);
        return bar;
    }
    private Border Card(string step, string title, string subtitle, UIElement content)
    {
        var stack = Vertical();
        var heading = new DockPanel { Margin = new(0, 0, 0, 18) };
        var stepText = Text(step, 14, Teal, FontWeights.Bold); stepText.FontFamily = new("Consolas");
        var number = Surface(stepText, "#12282E", 8, new(9, 6, 9, 6)); number.BorderThickness = new(0);
        number.Margin = new(0, 0, 13, 0); number.VerticalAlignment = VerticalAlignment.Top;
        DockPanel.SetDock(number, Dock.Left); heading.Children.Add(number);
        var titles = Vertical(); titles.Children.Add(Text(title, 18, weight: FontWeights.Bold));
        var description = Text(subtitle, color: Secondary); description.Margin = new(0, 3, 0, 0); titles.Children.Add(description); heading.Children.Add(titles);
        stack.Children.Add(heading); stack.Children.Add(content);
        var card = Surface(stack); card.Effect = new DropShadowEffect { Color = Colors.Black, Opacity = 0.16, BlurRadius = 24, ShadowDepth = 10, Direction = 270 }; card.Margin = new(0, 0, 0, 20); return card;
    }

    private void BuildPage()
    {
        building = true;
        lengthInput = null; lengthSlider = null; bipLengthButtons.Clear(); legendGrids.Clear();
        ClearMaterializedSecrets();
        page.Children.Clear();
        page.Children.Add(Header()); page.Children.Add(SecurityStrip());
        page.Children.Add(ConfigurationCard()); page.Children.Add(MouseCard());
        resultCard = ResultCard(); page.Children.Add(resultCard);
        page.Children.Add(Text(Tr("Die Entropieanzeige beschreibt den theoretischen Auswahlraum bei gleichverteilter Zufallsauswahl. Hashlängen und Mausereignisse werden nicht als zusätzliche Entropie gezählt. Nutze ein vertrauenswürdiges System. Seedphrasen gewähren Zugriff auf das zugehörige Wallet.", "The entropy display describes the theoretical selection space with uniform random sampling. Hash lengths and mouse events are not counted as additional entropy. Use a trusted system. Seed phrases grant access to the associated wallet."), color: Secondary));
        lastLanguage = model.Language; lastMode = model.Mode; lastLength = model.Length; lastGenerated = model.Phase == AppModel.GenerationPhase.Generated;
        building = false;
        ResizeContent(); Update();
    }
    private UIElement Header()
    {
        var header = new DockPanel { Margin = new(0, 0, 0, 20), LastChildFill = true };
        var language = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var code in new[] { "en", "de" })
        {
            var languageButton = Button(code.ToUpperInvariant(), () => model.SetLanguage(code), "Language_" + code);
            SelectSegment(languageButton, model.Language == code); languageButton.Padding = new(8, 6, 8, 6); languageButton.Margin = new(0, 0, code == "en" ? 3 : 0, 0);
            AutomationProperties.SetName(languageButton, code == "en" ? "English" : "Deutsch");
            language.Children.Add(languageButton);
        }
        AutomationProperties.SetName(language, Tr("Sprache", "Language")); var languageTrack = SegmentTrack(language); languageTrack.VerticalAlignment = VerticalAlignment.Center; languageTrack.Margin = new(16, 0, 0, 0); DockPanel.SetDock(languageTrack, Dock.Right); header.Children.Add(languageTrack);
        var logo = new Image { Source = new BitmapImage(new Uri("pack://application:,,,/Assets/PasswordGeneratorLogo.png")), Width = 58, Height = 58 };
        var logoTile = Surface(logo, "#10252D", 17, new(0)); logoTile.BorderThickness = new(0); logoTile.Margin = new(0, 0, 16, 0);
        DockPanel.SetDock(logoTile, Dock.Left); header.Children.Add(logoTile);
        var brand = Vertical(); brand.Children.Add(Text(Title, 29, weight: FontWeights.Bold));
        var subtitle = Text(Tr("Seedphrasen, Wortpasswörter, ASCII, PINs und Hex. Lokal auf deinem PC.", "Seed phrases, word passwords, ASCII, PINs, and hex. Locally on your PC."), color: Secondary); subtitle.Margin = new(0, 4, 0, 0); brand.Children.Add(subtitle);
        brand.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; else DragMove(); };
        header.Children.Add(brand); return header;
    }
    private UIElement SecurityStrip()
    {
        var grid = new UniformGrid { Columns = 2, Margin = new(-6, -6, -6, 14) }; securityGrid = grid;
        AddBadge("lock", "Windows CSPRNG", "BCryptGenRandom / .NET", grid);
        AddBadge("cursor", Tr("Mauspool", "Mouse pool"), Tr("4.096 Bewegungen", "4,096 movements"), grid);
        AddBadge("shuffle", "Fisher–Yates", Tr("Alle 6 s und vor Generierung", "Every 6 sec and before generation"), grid);
        runtimeText = AddBadge("shield", Tr("Laufzeitschutz", "Runtime protection"), "", grid);
        return grid;
    }
    private static TextBlock AddBadge(string icon, string title, string detail, Panel parent)
    {
        var dock = new DockPanel(); var symbol = Surface(Symbol(icon, 16), "#172C32", 8, new(0)); symbol.Width = symbol.Height = 28; symbol.BorderThickness = new(0); symbol.VerticalAlignment = VerticalAlignment.Center; symbol.Margin = new(0, 0, 10, 0); DockPanel.SetDock(symbol, Dock.Left); dock.Children.Add(symbol);
        var labels = Vertical(); labels.Children.Add(Text(title, weight: FontWeights.Bold)); var description = Text(detail, color: Muted); description.Margin = new(0, 1, 0, 0); labels.Children.Add(description); dock.Children.Add(labels);
        var surface = Surface(dock, "#131A23", 14, new(12, 10, 12, 10)); surface.Margin = new(6); parent.Children.Add(surface); return description;
    }
    private Border ConfigurationCard()
    {
        var contents = Vertical(); var controls = Vertical(); configurationControls = controls;
        var modes = new UniformGrid { Columns = 5 };
        foreach (var mode in Enum.GetValues<GeneratorMode>())
        {
            var button = Button(ModeTitle(mode), () => model.SetMode(mode), "Mode_" + mode);
            SelectSegment(button, model.Mode == mode); button.Margin = new(0, 0, mode == GeneratorMode.Hex ? 0 : 3, 0); modes.Children.Add(button);
        }
        var modeTrack = SegmentTrack(modes); modeTrack.Margin = new(0, 0, 0, 16); AutomationProperties.SetName(modeTrack, Tr("Passworttyp", "Password type")); controls.Children.Add(modeTrack);
        if (model.Mode == GeneratorMode.Bip39)
        {
            var counts = new UniformGrid { Columns = 5 };
            foreach (var count in new[] { 12, 15, 18, 21, 24 })
            {
                var button = Button(Tr($"{count} Wörter", $"{count} words"), () => model.SetLength(count), "Length_" + count);
                bipLengthButtons[count] = button;
                SelectSegment(button, model.Length == count); button.Margin = new(0, 0, count == 24 ? 0 : 3, 0); counts.Children.Add(button);
            }
            var countTrack = SegmentTrack(counts); AutomationProperties.SetName(countTrack, Tr("Wortanzahl", "Word count")); controls.Children.Add(countTrack);
        }
        else
        {
            var row = new DockPanel { Margin = new(0, 0, 0, 4) };
            var label = Text(model.Mode == GeneratorMode.Eff ? Tr("Wörter", "Words") : Tr("Zeichen", "Characters"), weight: FontWeights.SemiBold); label.Margin = new(0, 0, 14, 0); DockPanel.SetDock(label, Dock.Left); row.Children.Add(label);
            var length = new TextBox { Text = model.Length == 0 ? "" : model.Length.ToString(Culture), Width = 90, Margin = new(0, 0, 12, 0) };
            lengthInput = length;
            AutomationProperties.SetName(length, Tr("Länge direkt eingeben", "Enter length directly")); AutomationProperties.SetAutomationId(length, "LengthInput");
            length.TextChanged += (_, _) => { if (building) return; model.SetLength(int.TryParse(length.Text, NumberStyles.Integer, Culture, out var parsed) ? parsed : 0); };
            DockPanel.SetDock(length, Dock.Left); row.Children.Add(length);
            var range = model.Mode.LengthRange();
            var stepper = new StackPanel { Orientation = Orientation.Horizontal };
            var decrease = Button("−", () => model.SetLength(Math.Clamp(model.Length - 1, range.Min, range.Max)), "DecreaseLength"); SelectSegment(decrease, false); decrease.Width = 32; AutomationProperties.SetName(decrease, Tr("Länge verringern", "Decrease length")); stepper.Children.Add(decrease);
            var increase = Button("+", () => model.SetLength(Math.Clamp(model.Length + 1, range.Min, range.Max)), "IncreaseLength"); SelectSegment(increase, false); increase.Width = 32; AutomationProperties.SetName(increase, Tr("Länge erhöhen", "Increase length")); stepper.Children.Add(increase);
            var stepperTrack = SegmentTrack(stepper); stepperTrack.Margin = new(0, 0, 14, 0); DockPanel.SetDock(stepperTrack, Dock.Left); row.Children.Add(stepperTrack);
            var rangeLabel = Text($"{range.Min}…{range.Max}", color: Secondary); rangeLabel.Margin = new(12, 0, 0, 0); DockPanel.SetDock(rangeLabel, Dock.Right); row.Children.Add(rangeLabel);
            var slider = new Slider { Minimum = range.Min, Maximum = range.Max, Value = Math.Clamp(model.Length, range.Min, range.Max), TickFrequency = 1, IsSnapToTickEnabled = true, VerticalAlignment = VerticalAlignment.Center };
            lengthSlider = slider;
            AutomationProperties.SetName(slider, Tr("Länge", "Length")); AutomationProperties.SetAutomationId(slider, "LengthSlider");
            slider.ValueChanged += (_, _) => { if (!building) model.SetLength((int)slider.Value); };
            row.Children.Add(slider); controls.Children.Add(row);
        }
        contents.Children.Add(controls);
        entropyHost = new Border { Child = EntropyIndicator(model.Configuration?.EntropyBits, showLegend: true) };
        contents.Children.Add(entropyHost);
        if (model.Mode.UsesWords())
        {
            var exportRow = new DockPanel { Margin = new(0, 15, 0, 0) };
            var label = Text(Tr("Trennzeichen beim Kopieren", "Separator when copying"), weight: FontWeights.SemiBold); label.Margin = new(0, 0, 12, 0); DockPanel.SetDock(label, Dock.Left); exportRow.Children.Add(label);
            var separator = new TextBox { Text = model.Separator, Width = 180, FontFamily = new("Consolas"), Margin = new(0, 0, 12, 0) };
            AutomationProperties.SetName(separator, Tr("Trennzeichen beim Kopieren", "Separator when copying")); AutomationProperties.SetAutomationId(separator, "WordSeparator");
            separator.TextChanged += (_, _) => { model.Separator = separator.Text; };
            DockPanel.SetDock(separator, Dock.Left); exportRow.Children.Add(separator);
            var separatorHint = Text(model.Separator == " " ? Tr("Ein Leerzeichen", "One space") : Tr("Leer = ohne Trennzeichen", "Empty = no separator"), color: Secondary);
            separator.TextChanged += (_, _) => separatorHint.Text = separator.Text == " " ? Tr("Ein Leerzeichen", "One space") : Tr("Leer = ohne Trennzeichen", "Empty = no separator");
            exportRow.Children.Add(separatorHint); contents.Children.Add(exportRow);
            if (model.Mode == GeneratorMode.Bip39) { var note = Text(Tr("Für den Wallet-Import Leerzeichen verwenden. Ohne Trennzeichen gehen Wortgrenzen verloren. Das Trennzeichen ändert nur den kopierten Text.", "Use spaces for wallet import. Without a separator, word boundaries are lost. The separator changes only the copied text."), color: Secondary); note.Margin = new(0, 7, 0, 0); contents.Children.Add(note); }
        }
        else if (model.Mode == GeneratorMode.Hex)
        {
            var hexChoices = new UniformGrid { Columns = 2 };
            Button? lowercase = null, uppercase = null;
            void SetCase(bool value) { model.UppercaseHex = value; SelectSegment(lowercase!, !value); SelectSegment(uppercase!, value); RenderSecret(); }
            lowercase = Button(Tr("Kleinbuchstaben (a bis f)", "Lowercase (a to f)"), () => SetCase(false), "LowercaseHex");
            uppercase = Button(Tr("Großbuchstaben (A bis F)", "Uppercase (A to F)"), () => SetCase(true), "UppercaseHex");
            SelectSegment(lowercase, !model.UppercaseHex); SelectSegment(uppercase, model.UppercaseHex); lowercase.Margin = new(0, 0, 3, 0);
            hexChoices.Children.Add(lowercase); hexChoices.Children.Add(uppercase);
            var hexTrack = SegmentTrack(hexChoices); hexTrack.Margin = new(0, 15, 0, 7); AutomationProperties.SetName(hexTrack, Tr("Hex-Ausgabe", "Hex output")); contents.Children.Add(hexTrack);
            contents.Children.Add(Text(Tr("Gilt für Anzeige und Kopieren. Ein Wechsel erzeugt keinen neuen Schlüssel und verändert seine Entropie nicht.", "Applies to display and copying. Switching case does not generate a new key or change its entropy."), color: Secondary));
        }
        return Card("01", Tr("Typ und Länge wählen", "Choose type and length"), ModeDescription(), contents);
    }
    private Border MouseCard()
    {
        var contents = Vertical(); var status = new DockPanel();
        remainingText = Text("", color: Secondary); DockPanel.SetDock(remainingText, Dock.Right); status.Children.Add(remainingText);
        collectionText = Text("", weight: FontWeights.SemiBold); AutomationProperties.SetAutomationId(collectionText, "MouseEventCount"); status.Children.Add(collectionText); contents.Children.Add(status);
        progress = new ProgressBar { Minimum = 0, Maximum = EntropyPool.RequiredMouseEventCount, Margin = new(0, 15, 0, 15) }; AutomationProperties.SetName(progress, Tr("Mauspool füllen", "Fill mouse pool")); contents.Children.Add(progress);
        contents.Children.Add(Text(Tr("Der Pool hält die letzten 4.096 Bewegungen. Die Mausdaten erhalten keinen geschätzten Entropiewert.", "The pool retains the most recent 4,096 movements. Mouse data is not assigned an estimated entropy value."), color: Secondary));
        var confirmContent = Vertical(); confirmContent.Children.Add(Text(Tr("Sichere Umgebung bestätigen", "Confirm a secure environment"), weight: FontWeights.Bold));
        var confirmSubtitle = Text(Tr("PC offline · keine Aufnahme, Bildschirmfreigabe oder Fernwartung · vertrauenswürdiges System", "PC offline · no recording, screen sharing, or remote support · trusted system"), color: Secondary); confirmSubtitle.Margin = new(0, 4, 0, 0); confirmContent.Children.Add(confirmSubtitle);
        confirmation = new CheckBox { Content = confirmContent, IsChecked = model.Confirmed, Margin = new(0, 18, 0, 18), ToolTip = Tr("Wird bei App-Wechsel, Minimierung, Ruhezustand oder Sitzungswechsel zurückgesetzt.", "Resets when switching apps, minimizing, sleeping, or changing sessions.") };
        AutomationProperties.SetAutomationId(confirmation, "SecureEnvironmentConfirmation");
        AutomationProperties.SetName(confirmation, Tr("Sichere Umgebung bestätigen", "Confirm a secure environment"));
        AutomationProperties.SetHelpText(confirmation, Tr("Wird bei App-Wechsel, Minimierung, Ruhezustand oder Sitzungswechsel zurückgesetzt.", "Resets when switching apps, minimizing, sleeping, or changing sessions."));
        confirmation.Checked += (_, _) => { model.Confirmed = true; UpdateCounters(); }; confirmation.Unchecked += (_, _) => { model.Confirmed = false; UpdateCounters(); }; contents.Children.Add(confirmation);
        var actions = new DockPanel(); generateButton = Button(Tr("✦ Passwort erzeugen", "✦ Generate password"), model.Generate, "GeneratePassword"); generateButton.Style = Theme("PrimaryButton"); generateButton.Padding = new(20, 12, 20, 12); DockPanel.SetDock(generateButton, Dock.Right); actions.Children.Add(generateButton);
        shuffleText = Text("", color: Muted); shuffleText.FontFamily = new("Consolas"); actions.Children.Add(shuffleText); contents.Children.Add(actions);
        if (!model.Security.IsEnforced) { var runtimeDetail = Text(Tr("Die Generierung erfordert gültige RSA-4096- und ML-DSA-87-Signaturen, Integritätsprüfung und eine Laufzeit ohne Debugger.", "Generation requires valid RSA-4096 and ML-DSA-87 signatures, integrity verification, and a runtime without a debugger."), color: Amber); runtimeDetail.Margin = new(0, 12, 0, 0); contents.Children.Add(runtimeDetail); }
        return Card("02", Tr("Maus im ganzen Fenster bewegen", "Move the mouse anywhere in the window"), Tr("Alle Bewegungen und Ziehbewegungen fließen ein, auch über Schaltflächen und nach der Generierung.", "All movements and drags are included, also over controls and after generation."), contents);
    }
    private Border ResultCard()
    {
        var contents = Vertical(); contents.Children.Add(EntropyIndicator(model.Configuration?.EntropyBits, showLegend: false));
        var actions = new DockPanel { Margin = new(0, 16, 0, 12) };
        revealButton = Button("", () =>
        {
            if (model.Visible) { model.Conceal(); return; }
            if (MessageBox.Show(this, Tr("Beende vorher Bildschirmfreigaben, Aufnahmen und Fernwartung. Windows-Anzeigeschutz verhindert nicht jede Aufnahme. Die Anzeige wird nach ca. 60 Sekunden oder bei Deaktivierung wieder verdeckt.\n\nVorübergehend anzeigen?", "Stop screen sharing, recording, and remote support first. Windows display protection cannot prevent every capture. The display hides again after about 60 seconds or when the app deactivates.\n\nReveal temporarily?"), Tr("Geschützte Anzeige öffnen?", "Open protected display?"), MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) == MessageBoxResult.OK) model.Reveal();
        }, "RevealPassword"); DockPanel.SetDock(revealButton, Dock.Right); actions.Children.Add(revealButton);
        actions.Children.Add(Text(model.Mode == GeneratorMode.Bip39 ? Tr("✓ BIP39-Prüfsumme gültig", "✓ BIP39 checksum valid") : Tr("✓ Gleichverteilte Auswahl", "✓ Uniform selection"), color: Teal, weight: FontWeights.SemiBold)); contents.Children.Add(actions);
        revealHint = Text("", color: Secondary); revealHint.Margin = new(0, 0, 0, 12); contents.Children.Add(revealHint);
        secretContent = Vertical(); var secretScroll = new ScrollViewer { Content = secretContent, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Height = model.Mode.UsesWords() ? Math.Min((model.ComponentCount + 2) / 3, 7) * 52 : 240 };
        AutomationProperties.SetAutomationId(secretScroll, "ProtectedResult"); contents.Children.Add(secretScroll);
        var footer = new DockPanel { Margin = new(0, 16, 0, 16) };
        var discard = Button(Tr("Verwerfen", "Discard"), () =>
        {
            if (MessageBox.Show(this, Tr("Das Passwort wird nicht gespeichert und kann danach nicht wiederhergestellt werden. Für das nächste Passwort wird ein neuer Mauspool gesammelt.\n\nPasswort wirklich verwerfen?", "The password is not stored and cannot be recovered afterwards. A new mouse pool will be collected for the next password.\n\nDiscard this password?"), Tr("Passwort verwerfen?", "Discard password?"), MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.Cancel) == MessageBoxResult.OK) model.Reset();
        }, "DiscardPassword"); discard.Style = Theme("DangerButton"); discard.Margin = new(12, 0, 0, 0); DockPanel.SetDock(discard, Dock.Right); footer.Children.Add(discard);
        copyButton = Button(Tr("Kopieren · 45 s", "Copy · 45 sec"), model.Copy, "CopyPassword"); copyButton.Margin = new(12, 0, 0, 0); DockPanel.SetDock(copyButton, Dock.Right); footer.Children.Add(copyButton);
        clipboardText = Text("", color: Secondary); footer.Children.Add(clipboardText); contents.Children.Add(footer);
        var proof = Vertical(); proof.Children.Add(Text(RandomExplanation(), color: Secondary));
        foreach (var pair in new[] { ("BIP39", model.Bip39Integrity), ("EFF", model.EffIntegrity) })
        {
            foreach (var hash in new[] { ("SHA-256", pair.Item2.Sha256), ("SHA3-512", pair.Item2.Sha3_512), ("Skein-1024-1024", pair.Item2.Skein1024_1024) })
            {
                var hashHeading = Text(pair.Item1 + " " + hash.Item1, color: Teal, weight: FontWeights.Bold); hashHeading.Margin = new(0, 12, 0, 4); proof.Children.Add(hashHeading);
                var hashText = Text(hash.Item2, color: Secondary); hashText.FontFamily = new("Consolas"); proof.Children.Add(hashText);
            }
        }
        var details = new Expander { Header = Tr("Wortlisten und Zufallsverfahren", "Word lists and random generation"), Content = proof }; contents.Children.Add(details);
        return Card("03", Tr("Dein Passwort", "Your password"), ModeTitle(model.Mode), contents);
    }
    private UIElement EntropyIndicator(double? bits, bool showLegend)
    {
        var stack = Vertical(); var headline = new DockPanel();
        var rating = Button(Rating(bits), () => ShowEntropyInformation(bits), "EntropyInformation"); rating.Style = Theme("QuietButton"); rating.Background = RatingBrush(bits); rating.BorderBrush = RatingAccent(bits); rating.Foreground = RatingText(bits); rating.Padding = new(12, 10, 12, 10); rating.MaxWidth = 360; rating.Margin = new(18, 0, 0, 0);
        var ratingContent = new DockPanel(); var ratingSymbol = Symbol(RatingSymbol(bits), 16, RatingText(bits)); DockPanel.SetDock(ratingSymbol, Dock.Left); ratingContent.Children.Add(ratingSymbol);
        var info = Symbol("info", 17, RatingText(bits)); var infoSpace = new Border { Child = info, Margin = new(10, 0, 0, 0) }; DockPanel.SetDock(infoSpace, Dock.Right); ratingContent.Children.Add(infoSpace);
        var ratingTitle = Text(Rating(bits), color: RatingText(bits), weight: FontWeights.Bold); ratingTitle.Margin = new(8, 0, 0, 0); ratingContent.Children.Add(ratingTitle); rating.Content = ratingContent;
        DockPanel.SetDock(rating, Dock.Right); headline.Children.Add(rating);
        var value = Vertical(); value.Children.Add(Text(Tr("Nominelle Entropie", "Nominal entropy"), color: Secondary, weight: FontWeights.SemiBold));
        var entropyValue = Text("", 27, weight: FontWeights.Bold); entropyValue.Margin = new(0, 4, 0, 0);
        entropyValue.Inlines.Add(new System.Windows.Documents.Run(bits?.ToString("N1", Culture) ?? "…"));
        entropyValue.Inlines.Add(new System.Windows.Documents.Run(Tr("  Bit", "  bits")) { FontSize = 14, FontWeight = FontWeights.Medium, Foreground = Secondary });
        if (model.Mode == GeneratorMode.Bip39 && bits != null) entropyValue.Inlines.Add(new System.Windows.Documents.Run(Tr("  ohne Prüfsumme", "  excluding checksum")) { FontSize = 14, FontWeight = FontWeights.Normal, Foreground = Secondary });
        value.Children.Add(entropyValue); headline.Children.Add(value); stack.Children.Add(headline);
        var estimates = Vertical(); estimates.Margin = new(0, 12, 0, 0);
        estimates.Children.Add(AttackRow(Tr("Exascale-Computer", "Exascale computer"), Tr("Vollsuche · 10^18 Prüfungen/s", "Full search · 10^18 checks/s"), bits, false));
        estimates.Children.Add(new Border { Height = 1, Background = Brush("#232C38"), Margin = new(0, 10, 0, 10) });
        estimates.Children.Add(AttackRow(Tr("Petahertz-Quantencomputer", "Petahertz quantum computer"), Tr("Grover · 10^15 vollständige Iterationen/s", "Grover · 10^15 complete iterations/s"), bits, true));
        var modelNote = Text(Tr("Hypothetische Modelle, keine gemessenen Angriffszeiten.", "Hypothetical models, not measured attack times."), color: Secondary); modelNote.Margin = new(0, 10, 0, 0); estimates.Children.Add(modelNote);
        var estimateSurface = Surface(estimates, "#0B1119", 11, new(12)); estimateSurface.Margin = new(0, 12, 0, 0); estimateSurface.BorderThickness = new(0); estimates.Margin = new(0); stack.Children.Add(estimateSurface);
        if (showLegend)
        {
            var legend = new UniformGrid { Columns = 2, Margin = new(-7, 12, -7, 12) }; legendGrids.Add(legend);
            foreach (var sample in new[] { 64.0, 128, 256, 1024 })
            {
                var selected = Rating(bits) == Rating(sample);
                var item = Vertical(); item.Margin = new(7, 0, 7, 12); item.Children.Add(new Border { Height = 5, CornerRadius = new(3), Background = RatingAccent(sample), Opacity = selected ? 1 : 0.44, Margin = new(0, 0, 0, 7) });
                var entry = new DockPanel(); var glyph = new Border { Child = Symbol(RatingSymbol(sample), 15, RatingText(sample)), Margin = new(0, 3, 7, 0), VerticalAlignment = VerticalAlignment.Top }; DockPanel.SetDock(glyph, Dock.Left); entry.Children.Add(glyph);
                var labels = Vertical(); labels.Children.Add(Text(sample switch { 64 => Tr("< 128 Bit", "< 128 bits"), 128 => Tr("128 bis < 256 Bit", "128 to < 256 bits"), 256 => Tr("256 bis < 1.024 Bit", "256 to < 1,024 bits"), _ => Tr("≥ 1.024 Bit", "≥ 1,024 bits") }, color: selected ? Brushes.White : Secondary, weight: FontWeights.Bold));
                var level = Text(Rating(sample), color: Secondary); level.Margin = new(0, 2, 0, 0); labels.Children.Add(level); entry.Children.Add(labels); item.Children.Add(entry); legend.Children.Add(item);
            }
            stack.Children.Add(legend);
        }
        stack.Children.Add(Text(Tr("Nomineller Auswahlraum bei gleichverteilter Auswahl. Keine Messung der Zufallsquelle und keine Garantie für die Gesamtsicherheit.", "Nominal selection space with uniform sampling. No measurement of the random source and no guarantee of overall security."), color: Secondary));
        var surface = Surface(stack, "#111923", 16, new(16)); var accent = ((SolidColorBrush)RatingAccent(bits)).Color;
        surface.Background = new SolidColorBrush(Color.FromArgb(12, accent.R, accent.G, accent.B)); surface.BorderBrush = new SolidColorBrush(Color.FromArgb(71, accent.R, accent.G, accent.B));
        surface.Margin = new(0, 16, 0, 0); return surface;
    }
    private UIElement AttackRow(string title, string detail, double? bits, bool grover)
    {
        double? seconds = bits.HasValue ? (grover ? Math.Log10(Math.PI / 4) + bits.Value / 2 * Math.Log10(2) - 15 : bits.Value * Math.Log10(2) - 18) : null;
        var stack = Vertical();
        var row = new DockPanel(); var duration = Text("≈ " + Duration(seconds), weight: FontWeights.Bold); duration.Margin = new(10, 0, 0, 0); DockPanel.SetDock(duration, Dock.Right); row.Children.Add(duration);
        var icon = new Border { Child = Symbol(grover ? "atom" : "desktop", 15, Brushes.White), Margin = new(0, 0, 8, 0) }; DockPanel.SetDock(icon, Dock.Left); row.Children.Add(icon); row.Children.Add(Text(title, weight: FontWeights.SemiBold)); stack.Children.Add(row);
        var detailRow = new DockPanel { Margin = new(0, 5, 0, 0) };
        if (!grover && bits.HasValue) { var mean = Text(Tr("im Mittel ≈ ", "on average ≈ ") + Duration(seconds + Math.Log10((1 + Math.Pow(2, -bits.Value)) / 2)), color: Secondary); mean.Margin = new(12, 0, 0, 0); DockPanel.SetDock(mean, Dock.Right); detailRow.Children.Add(mean); }
        detailRow.Children.Add(Text(detail, color: Secondary)); stack.Children.Add(detailRow);
        const double budget = 3e71; var landauer = 1.380649e-23 * 2.7 * Math.Log(2); var energyThreshold = Math.Log2(budget / landauer);
        if (grover) energyThreshold = 2 * (energyThreshold - Math.Log2(Math.PI / 4));
        var years = seconds - Math.Log10(365.25 * 24 * 60 * 60);
        var status = new Grid { Margin = new(0, 5, 0, 0) }; status.ColumnDefinitions.Add(new()); status.ColumnDefinitions.Add(new());
        status.Children.Add(Text(Tr("Landauer-Budget: ", "Landauer budget: ") + (bits == null ? "—" : bits > energyThreshold ? Tr("Suchaufwand > Budget", "search cost > budget") : Tr("Suchaufwand im Budget", "search cost within budget")), color: bits > energyThreshold ? Teal : Secondary));
        var horizon = Text(Tr("10^106-Jahre-Horizont: ", "10^106-year horizon: ") + (years == null ? "—" : years > 106 ? Tr("überschritten", "exceeded") : Tr("innerhalb", "within")), color: years > 106 ? Teal : Secondary); horizon.HorizontalAlignment = HorizontalAlignment.Right; horizon.Margin = new(12, 0, 0, 0); Grid.SetColumn(horizon, 1); status.Children.Add(horizon); stack.Children.Add(status); return stack;
    }
    private string Duration(double? logarithm)
    {
        if (!logarithm.HasValue || !double.IsFinite(logarithm.Value)) return "—";
        var log = logarithm.Value; var unit = log < -9 ? (-12.0, "ps") : log < -6 ? (-9.0, "ns") : log < -3 ? (-6.0, "µs") : log < 0 ? (-3.0, "ms") : log < Math.Log10(60) ? (0.0, "s") : log < Math.Log10(3600) ? (Math.Log10(60), "min") : log < Math.Log10(86400) ? (Math.Log10(3600), "h") : log < Math.Log10(31557600) ? (Math.Log10(86400), Tr("Tage", "days")) : (Math.Log10(31557600), Tr("Jahre", "years"));
        var valueLog = log - unit.Item1;
        if (valueLog is >= -2 and < 6) return Math.Pow(10, valueLog).ToString("G3", Culture) + " " + unit.Item2;
        var exponent = Math.Floor(valueLog); var mantissa = Math.Pow(10, valueLog - exponent); if (mantissa >= 9.995) { mantissa = 1; exponent++; }
        return mantissa.ToString("G3", Culture) + " × 10^" + exponent.ToString("F0", CultureInfo.InvariantCulture) + " " + unit.Item2;
    }
    private string Rating(double? bits) => bits == null ? Tr("Noch keine Einordnung", "Not rated yet") : bits < 128 ? Tr("knackbar", "crackable") : bits < 256 ? Tr("nicht quantensicher", "not quantum-safe") : bits < 1024 ? Tr("praktisch nicht angreifbar", "practically unattackable") : Tr("thermodynamisch nicht angreifbar", "thermodynamically unattackable");
    private static Brush RatingBrush(double? bits) => Brush(bits == null ? "#131A23" : bits < 128 ? "#40171F" : bits < 256 ? "#403314" : bits < 1024 ? "#2B3D17" : "#12472E");
    private static Brush RatingAccent(double? bits) => Brush(bits == null ? "#7A8FA8" : bits < 128 ? "#F25769" : bits < 256 ? "#F7C247" : bits < 1024 ? "#B5ED75" : "#2E9E63");
    private static Brush RatingText(double? bits) => Brush(bits == null ? "#C7D1E0" : bits < 128 ? "#FFBAC4" : bits < 256 ? "#FFE094" : bits < 1024 ? "#D6FFAB" : "#D9FFE8");
    private static string RatingSymbol(double? bits) => bits == null ? "info" : bits < 128 ? "warning" : bits < 256 ? "half" : bits < 1024 ? "bars" : "layers";
    private void ShowEntropyInformation(double? bits)
    {
        var dialog = new Window { Owner = this, Title = Rating(bits), Width = 740, Height = 680, MinWidth = 520, MinHeight = 400, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = Background, Foreground = Foreground, FontFamily = FontFamily, FontSize = Math.Max(14, FontSize) };
        var content = Vertical(); content.Margin = new(24); content.Children.Add(Text(Rating(bits), 20, weight: FontWeights.Bold));
        content.Children.Add(Text(Tr("Diese Stufen beschreiben den nominellen Auswahlraum beim Erraten durch Brute-Force, keine Sicherheitsgarantie. Bei gleichverteilter Auswahl gilt N = 2^n. Die vollständige klassische Suche dauert N / 10^18 Sekunden, im Mittel ungefähr halb so lange. Die ideale Grover-Suche benötigt (π/4) × √N Iterationen, mit angenommenen 10^15 vollständigen Iterationen pro Sekunde. Reale Quantenhardware, KDF-Kosten und andere Angriffswege werden nicht bewertet.\n\nLandauer-Modell: 2,7 K, ein irreversibel gelöschtes Informationsbit je Prüfung oder Iteration, Energiebudget 3 × 10^71 J. Mindestenergie pro Löschung: kBT ln(2). Reversible Quantenrechnung erzwingt diese Löschannahme nicht. Das Überschreiten des Budgets schließt erfolgreiche Teilsuchen nicht aus.\n\n10^106 Jahre ist ein ausdrücklich angenommener kosmologischer Vergleichshorizont, kein nachgewiesener spätester Zeitpunkt für den Wärmetod des Universums. Temperatur, freie Energie und kosmologische Entwicklung bleiben Modellannahmen.\n\nEine KDF erzeugt keine fehlende Entropie. Passwortsuchraum und Schlüsselbreite beweisen nicht die Gesamtsicherheit einer Chiffre oder Kaskade.", "These levels describe the nominal selection space when guessing by brute force, not a security guarantee. With uniform selection, N = 2^n. Full classical search takes N / 10^18 seconds, with about half that on average. Ideal Grover search takes (π/4) × √N iterations at an assumed 10^15 complete iterations per second. Real quantum hardware, KDF costs, and other attack paths are not assessed.\n\nLandauer model: 2.7 K, one irreversibly erased information bit per check or iteration, energy budget 3 × 10^71 J. Minimum energy per erasure: kBT ln(2). Reversible quantum computation does not require this erasure assumption. Exceeding the budget does not exclude successful partial searches.\n\n10^106 years is an explicitly assumed cosmological comparison horizon, not a proven latest deadline for the universe's heat death. Temperature, free energy, and cosmological development remain model assumptions.\n\nA KDF cannot create missing entropy. Password search space and key width do not prove the overall security of a cipher or cascade."), color: Secondary));
        content.Children.Add(Button(Tr("Schließen", "Close"), dialog.Close, "CloseEntropyInformation"));
        dialog.Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; dialog.ShowDialog();
    }
    private string ModeTitle(GeneratorMode mode) => mode switch { GeneratorMode.Bip39 => "BIP39", GeneratorMode.Eff => "EFF", GeneratorMode.Ascii => "ASCII-94", GeneratorMode.Pin => "PIN", _ => "Hex" };
    private string ModeDescription() => model.Mode switch
    {
        GeneratorMode.Bip39 => Tr("Englische BIP39-Wortliste mit Prüfsumme: 12, 15, 18, 21 oder 24 Wörter.", "English BIP39 word list with checksum: 12, 15, 18, 21, or 24 words."),
        GeneratorMode.Eff => Tr("EFF Large Wordlist: 7.776 englische Wörter, 6 bis 128 Wörter pro Passwort.", "EFF Large Wordlist: 7,776 English words, 6 to 128 words per password."),
        GeneratorMode.Ascii => Tr("94 druckbare ASCII-Zeichen ohne Leerzeichen (! bis ~), 8 bis 256 Zeichen.", "94 printable ASCII characters without spaces (! through ~), 8 to 256 characters."),
        GeneratorMode.Pin => Tr("Ziffern 0 bis 9, 3 bis 512 Zeichen. Führende Nullen bleiben erhalten.", "Digits 0 through 9, 3 to 512 characters. Leading zeroes are preserved."),
        _ => Tr("Hexadezimale Zeichen 0 bis 9 und a bis f, 1 bis 512 Zeichen. Jedes Zeichen entspricht 4 Bit.", "Hexadecimal characters 0 through 9 and a through f, 1 to 512 characters. Each character represents 4 bits.")
    };
    private string RandomExplanation() => Tr("Vor jeder Generierung mischt Fisher–Yates 4.096 Mausereignisse mit kryptografischen Windows-Zufallsbytes. Skein-1024-1024 (128 Byte), SHA3-512 (64 Byte) und SHA-512 (64 Byte) werden verbunden. Ein XOR mit 256 frischen Windows-Zufallsbytes, eine Fisher–Yates-Mischung aller 2.048 Bits und ein zweites XOR mit separat angeforderten 256 frischen Zufallsbytes ergeben den Masterkey. Die Masken werden nicht wiederverwendet.\n\nDer Masterkey initialisiert Skein-1024-XOF, zweimal SHAKE256 und zweimal AES-256-CTR mit getrennten Schlüsseln und Big-Endian-Zählern ab null. Alle fünf Streams laufen bei Nachforderungen ohne Neustart weiter. Ihre Ausgaben werden per XOR verbunden und unmittelbar vor der gleichverteilten Zeichenauswahl mit weiteren frischen Windows-Zufallsbytes XOR-verknüpft. Die Mischung alle sechs Sekunden betrifft nur den Mauspool.\n\nBIP39- und EFF-Wortlisten werden gegen fest verankerte SHA-256-, SHA3-512- und Skein-1024-1024-Werte geprüft. Masterkey und Streamzustände werden vor Veröffentlichung bereinigt, eigene Passwort- und Poolpuffer beim Verwerfen oder Beenden überschrieben. Bereits für Anzeige oder Kopieren erzeugte .NET- und Betriebssystemkopien lassen sich nicht vollständig löschen; erzwungenes Beenden kann die Bereinigung verhindern.", "Before every generation, Fisher–Yates shuffles 4,096 mouse events with cryptographic Windows random bytes. Skein-1024-1024 (128 bytes), SHA3-512 (64 bytes), and SHA-512 (64 bytes) are concatenated. An XOR with 256 fresh Windows random bytes, a Fisher–Yates shuffle of all 2,048 bits, and another XOR with a separately requested 256 fresh random bytes produce the master key. Masks are never reused.\n\nThe master key initializes Skein-1024-XOF, two SHAKE256 streams, and two AES-256-CTR streams with separate keys and big-endian counters starting at zero. All five streams continue without restarting on further requests. Their outputs are XORed together and with fresh Windows random bytes immediately before uniform character selection. The six-second shuffle only affects the mouse pool.\n\nBIP39 and EFF word lists are verified against pinned SHA-256, SHA3-512, and Skein-1024-1024 values. Master key and stream states are cleared before publication; owned password and pool buffers are overwritten on discard or exit. .NET and operating-system copies created for display or copying cannot all be erased completely; forced termination can prevent cleanup.");

    private void Update()
    {
        if (building) return;
        if (lastLanguage != model.Language || lastMode != model.Mode || lastGenerated != (model.Phase == AppModel.GenerationPhase.Generated)) { BuildPage(); return; }
        if (lastLength != model.Length)
        {
            // Update the entropy card without replacing the text field or interrupting a slider drag.
            building = true;
            try
            {
                lastLength = model.Length;
                if (lengthInput != null && !lengthInput.IsKeyboardFocused) lengthInput.Text = model.Length == 0 ? "" : model.Length.ToString(Culture);
                if (lengthSlider != null) lengthSlider.Value = Math.Clamp(model.Length, lengthSlider.Minimum, lengthSlider.Maximum);
                foreach (var pair in bipLengthButtons) SelectSegment(pair.Value, model.Length == pair.Key);
                legendGrids.Clear();
                entropyHost.Child = EntropyIndicator(model.Configuration?.EntropyBits, showLegend: true);
                ApplyResponsiveColumns();
            }
            finally { building = false; }
        }
        resultCard.Visibility = model.Phase == AppModel.GenerationPhase.Generated ? Visibility.Visible : Visibility.Collapsed;
        configurationControls.IsEnabled = model.Phase != AppModel.GenerationPhase.Generated;
        confirmation.IsEnabled = model.Phase != AppModel.GenerationPhase.Generated;
        confirmation.IsChecked = model.Confirmed;
        UpdateCounters(); RenderSecret();
    }
    private void UpdateCounters()
    {
        if (building || collectionText == null) return;
        collectionText.Text = model.EventCount.ToString("N0", Culture) + Tr(" Bewegungen erfasst", " movements collected");
        var remaining = Math.Max(EntropyPool.RequiredMouseEventCount - model.EventCount, 0);
        remainingText.Text = remaining > 0 ? Tr("Noch ", "Remaining: ") + remaining.ToString("N0", Culture) : Tr("Pool gefüllt · Sammlung läuft weiter", "Pool filled · collection continues");
        remainingText.Foreground = remaining > 0 ? Secondary : Teal;
        progress.Value = Math.Min(model.EventCount, EntropyPool.RequiredMouseEventCount);
        shuffleText.Text = model.ShuffleCount.ToString("N0", Culture) + Tr(" Mischvorgänge", " shuffles");
        generateButton.IsEnabled = model.CanGenerate;
        generateButton.Content = model.Phase == AppModel.GenerationPhase.Generated ? Tr("Passwort erzeugt", "Password generated") : Tr("✦ Passwort erzeugen", "✦ Generate password");
        runtimeText.Text = model.Security.IsEnforced ? Tr("Signaturen · Integrität · kein Debugger", "Signatures · integrity · no debugger") : Tr("Generierung gesperrt", "Generation blocked");
        runtimeText.ToolTip = model.Security.Details;
    }
    private void RenderSecret()
    {
        if (building || secretContent == null) return;
        revealButton.Content = model.Visible ? Tr("Verdecken", "Hide") : Tr("Anzeigen", "Reveal");
        revealHint.Text = model.Visible ? Tr("Anzeige für ca. 60 Sekunden oder bis zur Deaktivierung.", "Shown for about 60 seconds or until deactivation.") : Tr("Das Ergebnis bleibt bis zur bestätigten Anzeige verdeckt.", "The result stays hidden until reveal is confirmed.");
        revealHint.Foreground = model.Visible ? Amber : Secondary; copyButton.IsEnabled = model.Visible;
        clipboardText.Text = model.ClipboardScheduled ? Tr("Löschung der Zwischenablage nach ca. 45 Sekunden vorgesehen.", "Clipboard clearing is scheduled after about 45 seconds.") : Tr("Cloud-Zwischenablage und Verlauf sind ausgeschlossen. Lokale Apps können die Kopie dennoch lesen.", "Cloud clipboard and history are excluded. Local apps may still read the copy.");
        if (renderedVisible == model.Visible && secretContent.Children.Count != 0 && model.Mode != GeneratorMode.Hex) return;
        ClearMaterializedSecrets(); secretContent.Children.Clear(); renderedVisible = model.Visible;
        if (model.Mode.UsesWords())
        {
            var words = model.DisplayWords(); var grid = new UniformGrid { Columns = 3 };
            for (var index = 0; index < model.ComponentCount; index++)
            {
                var word = Text(index < words.Length ? words[index] : "••••••••", 15, weight: FontWeights.SemiBold); word.FontFamily = new("Consolas");
                materializedSecrets.Add(word);
                var row = new DockPanel(); var number = Text((index + 1).ToString("D2", Culture), color: Teal); number.FontFamily = new("Consolas"); number.Margin = new(0, 0, 10, 0); DockPanel.SetDock(number, Dock.Left); row.Children.Add(number); row.Children.Add(word);
                var chip = Surface(row, "#111821", 10, new(11)); chip.Margin = new(0, 0, 9, 9); grid.Children.Add(chip);
            }
            Array.Clear(words); secretContent.Children.Add(grid);
        }
        else
        {
            var output = Text(model.Visible ? model.DisplayText() : "••••••••••••••••••••••••", 18, weight: FontWeights.SemiBold); output.FontFamily = new("Consolas"); output.Padding = new(16);
            materializedSecrets.Add(output); secretContent.Children.Add(Surface(output, "#111821", 12, new(0)));
        }
    }
    private void ClearMaterializedSecrets() { foreach (var text in materializedSecrets) text.Text = ""; materializedSecrets.Clear(); }
    private void ResizeContent()
    {
        ApplyLayout(Math.Max(ActualWidth, 1060), Math.Max(ActualHeight, 840));
    }
    private void ApplyLayout(double width, double height)
    {
        var scale = Math.Sqrt(width / 1060) * Math.Sqrt(height / 840);
        scaleTransform.ScaleX = scaleTransform.ScaleY = scale;
        page.Width = Math.Max(600, (width - 18) / scale - 60);
        page.Margin = new(30, 28, 30, 28);
        ApplyResponsiveColumns();
    }
    private void ApplyResponsiveColumns()
    {
        if (securityGrid != null) securityGrid.Columns = page.Width + 60 >= 1200 ? 4 : 2;
        foreach (var legend in legendGrids) legend.Columns = page.Width + 60 >= 1400 ? 4 : 2;
    }
    private void InitializeNativeWindow()
    {
        hwnd = new WindowInteropHelper(this).Handle; source = HwndSource.FromHwnd(hwnd); source?.AddHook(WindowMessage);
        // Best effort window capture exclusion. It is not a guarantee against all capture paths.
        _ = SetWindowDisplayAffinity(hwnd, 0x11);
        _ = WTSRegisterSessionNotification(hwnd, 0);
    }
    private nint WindowMessage(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == 0x200) // WM_MOUSEMOVE: the real local Windows event stream, including drags across WPF controls.
        {
            var bits = lParam.ToInt64(); var point = new Point((short)(bits & 0xffff), (short)((bits >> 16) & 0xffff));
            var previous = lastMousePoint; lastMousePoint = point;
            if (!GetClientRect(window, out var bounds) || point.X < bounds.Left || point.Y < bounds.Top || point.X >= bounds.Right || point.Y >= bounds.Bottom) { lastMousePoint = null; return 0; }
            if (previous == null || point == previous.Value) return 0;
            var pressed = (ulong)(wParam.ToInt64() & 0x73);
            var flags = (ulong)(wParam.ToInt64() & 0xc) | ((GetKeyState(0x12) & 0x8000) != 0 ? 0x10UL : 0);
            model.Record(new MouseEntropyRecord((ulong)(Stopwatch.GetTimestamp() * (1_000_000_000.0 / Stopwatch.Frequency)), unchecked((uint)GetMessageTime()) / 1000.0, point.X, point.Y, point.X - previous.Value.X, point.Y - previous.Value.Y, bounds.Right - bounds.Left, bounds.Bottom - bounds.Top, flags, pressed));
        }
        if (message is 0x218 or 0x2b1 or 0x7e || (message == 0x1c && wParam == 0)) model.ContextChanged(); // power, session, display, app activation
        return 0;
    }
    private sealed class HideCommand(AppModel model) : ICommand
    {
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => model.Conceal();
        public event EventHandler? CanExecuteChanged { add { } remove { } }
    }
}
