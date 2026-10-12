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
using System.Windows.Shell;
using System.Windows.Threading;
using PasswordGenerator.Core;

namespace PasswordGenerator.App;

/// <summary>Native Windows adaptation of the 2.3.6 SwiftUI window.</summary>
public sealed class MainWindow : Window
{
    private static readonly Brush Teal = Brush("#3BE0C4"), Secondary = Brush("#A8B2C1"), Muted = Brush("#8995A8"), Amber = Brush("#FFB84D");
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
        Background = Brush("#060B12"); Foreground = Brushes.White; FontFamily = new("Segoe UI"); FontSize = 14;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.CanResize;
        WindowChrome.SetWindowChrome(this, new WindowChrome { CaptionHeight = 0, ResizeBorderThickness = new(6), GlassFrameThickness = new(0), CornerRadius = new(0), UseAeroCaptionButtons = false });
        Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/PasswordGenerator.ico"));
        page.LayoutTransform = scaleTransform;
        scroller.Content = page;
        Content = scroller;
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
    private static TextBlock Text(string text, double size = 14, Brush? color = null, FontWeight? weight = null) => new() { Text = text, FontSize = size, Foreground = color ?? Brushes.White, FontWeight = weight ?? FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center };
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
    private Border Card(string step, string title, string subtitle, UIElement content)
    {
        var stack = Vertical();
        var heading = new DockPanel { Margin = new(0, 0, 0, 18) };
        var number = Surface(Text(step, 14, Teal, FontWeights.Bold), "#102B2C", 8, new(9, 6, 9, 6));
        number.Margin = new(0, 0, 13, 0); number.VerticalAlignment = VerticalAlignment.Top;
        DockPanel.SetDock(number, Dock.Left); heading.Children.Add(number);
        var titles = Vertical(); titles.Children.Add(Text(title, 18, weight: FontWeights.Bold));
        titles.Children.Add(Text(subtitle, color: Secondary)); heading.Children.Add(titles);
        stack.Children.Add(heading); stack.Children.Add(content);
        var card = Surface(stack); card.Margin = new(0, 0, 0, 20); return card;
    }

    private void BuildPage()
    {
        building = true;
        lengthInput = null; lengthSlider = null; bipLengthButtons.Clear();
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
        var windowButtons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        windowButtons.Children.Add(Button("−", () => WindowState = WindowState.Minimized, "MinimizeWindow"));
        windowButtons.Children.Add(Button("□", () => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized, "MaximizeWindow"));
        windowButtons.Children.Add(Button("×", Close, "CloseWindow"));
        DockPanel.SetDock(windowButtons, Dock.Right); header.Children.Add(windowButtons);
        var language = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(14, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center };
        foreach (var code in new[] { "en", "de" })
        {
            var languageButton = Button(code.ToUpperInvariant(), () => model.SetLanguage(code), "Language_" + code);
            if (model.Language == code) languageButton.Background = Brush("#123936");
            language.Children.Add(languageButton);
        }
        AutomationProperties.SetName(language, Tr("Sprache", "Language")); DockPanel.SetDock(language, Dock.Right); header.Children.Add(language);
        var logo = new Image { Source = new BitmapImage(new Uri("pack://application:,,,/Assets/PasswordGeneratorLogo.png")), Width = 58, Height = 58, Margin = new(0, 0, 16, 0) };
        DockPanel.SetDock(logo, Dock.Left); header.Children.Add(logo);
        var brand = Vertical(); brand.Children.Add(Text(Title, 29, weight: FontWeights.Bold));
        brand.Children.Add(Text(Tr("Seedphrasen, Wortpasswörter, ASCII, PINs und Hex. Lokal auf deinem PC.", "Seed phrases, word passwords, ASCII, PINs, and hex. Locally on your PC."), color: Secondary));
        brand.MouseLeftButtonDown += (_, e) => { if (e.ClickCount == 2) WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; else DragMove(); };
        header.Children.Add(brand); return header;
    }
    private UIElement SecurityStrip()
    {
        var grid = new UniformGrid { Columns = 2, Margin = new(0, 0, 0, 14) };
        AddBadge("◆", "Windows CSPRNG", "BCryptGenRandom / .NET", grid);
        AddBadge("↗", Tr("Mauspool", "Mouse pool"), Tr("4.096 Bewegungen", "4,096 movements"), grid);
        AddBadge("⇄", "Fisher–Yates", Tr("Alle 6 s und vor Generierung", "Every 6 sec and before generation"), grid);
        runtimeText = AddBadge("✓", Tr("Laufzeitschutz", "Runtime protection"), "", grid);
        return grid;
    }
    private static TextBlock AddBadge(string icon, string title, string detail, Panel parent)
    {
        var dock = new DockPanel(); var symbol = Text(icon, 20, Teal, FontWeights.Bold); symbol.Margin = new(0, 0, 12, 0); DockPanel.SetDock(symbol, Dock.Left); dock.Children.Add(symbol);
        var labels = Vertical(); labels.Children.Add(Text(title, weight: FontWeights.Bold)); var description = Text(detail, color: Muted); labels.Children.Add(description); dock.Children.Add(labels);
        var surface = Surface(dock, "#131A23", 14, new(12, 10, 12, 10)); surface.Margin = new(0, 0, 6, 6); parent.Children.Add(surface); return description;
    }
    private Border ConfigurationCard()
    {
        var contents = Vertical(); var controls = Vertical(); configurationControls = controls;
        var modes = new UniformGrid { Columns = 5, Margin = new(0, 0, 0, 16) };
        foreach (var mode in Enum.GetValues<GeneratorMode>())
        {
            var button = Button(ModeTitle(mode), () => model.SetMode(mode), "Mode_" + mode);
            button.Margin = new(0, 0, 5, 0); if (model.Mode == mode) button.Background = Brush("#123936"); modes.Children.Add(button);
        }
        controls.Children.Add(modes);
        if (model.Mode == GeneratorMode.Bip39)
        {
            var counts = new UniformGrid { Columns = 5 };
            foreach (var count in new[] { 12, 15, 18, 21, 24 })
            {
                var button = Button(Tr($"{count} Wörter", $"{count} words"), () => model.SetLength(count), "Length_" + count);
                bipLengthButtons[count] = button;
                button.Margin = new(0, 0, 5, 0); if (model.Length == count) button.Background = Brush("#123936"); counts.Children.Add(button);
            }
            controls.Children.Add(counts);
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
            var decrease = Button("−", () => model.SetLength(Math.Clamp(model.Length - 1, range.Min, range.Max)), "DecreaseLength"); DockPanel.SetDock(decrease, Dock.Left); row.Children.Add(decrease);
            var increase = Button("+", () => model.SetLength(Math.Clamp(model.Length + 1, range.Min, range.Max)), "IncreaseLength"); increase.Margin = new(3, 0, 12, 0); DockPanel.SetDock(increase, Dock.Left); row.Children.Add(increase);
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
            exportRow.Children.Add(Text(Tr("Leer = ohne Trennzeichen", "Empty = no separator"), color: Secondary)); contents.Children.Add(exportRow);
            if (model.Mode == GeneratorMode.Bip39) { var note = Text(Tr("Für den Wallet-Import Leerzeichen verwenden. Ohne Trennzeichen gehen Wortgrenzen verloren. Das Trennzeichen ändert nur den kopierten Text.", "Use spaces for wallet import. Without a separator, word boundaries are lost. The separator changes only the copied text."), color: Secondary); note.Margin = new(0, 7, 0, 0); contents.Children.Add(note); }
        }
        else if (model.Mode == GeneratorMode.Hex)
        {
            var hex = new CheckBox { Content = Tr("Großbuchstaben (A bis F)", "Uppercase (A to F)"), IsChecked = model.UppercaseHex, Margin = new(0, 15, 0, 7) };
            AutomationProperties.SetAutomationId(hex, "UppercaseHex");
            hex.Checked += (_, _) => { model.UppercaseHex = true; RenderSecret(); }; hex.Unchecked += (_, _) => { model.UppercaseHex = false; RenderSecret(); };
            contents.Children.Add(hex); contents.Children.Add(Text(Tr("Gilt für Anzeige und Kopieren. Ein Wechsel erzeugt keinen neuen Schlüssel und verändert seine Entropie nicht.", "Applies to display and copying. Switching case does not generate a new key or change its entropy."), color: Secondary));
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
        confirmContent.Children.Add(Text(Tr("PC offline · keine Aufnahme, Bildschirmfreigabe oder Fernwartung · vertrauenswürdiges System", "PC offline · no recording, screen sharing, or remote support · trusted system"), color: Secondary));
        confirmation = new CheckBox { Content = confirmContent, IsChecked = model.Confirmed, Margin = new(0, 18, 0, 18), ToolTip = Tr("Wird bei App-Wechsel, Minimierung, Ruhezustand oder Sitzungswechsel zurückgesetzt.", "Resets when switching apps, minimizing, sleeping, or changing sessions.") };
        AutomationProperties.SetAutomationId(confirmation, "SecureEnvironmentConfirmation"); confirmation.Checked += (_, _) => { model.Confirmed = true; UpdateCounters(); }; confirmation.Unchecked += (_, _) => { model.Confirmed = false; UpdateCounters(); }; contents.Children.Add(confirmation);
        var actions = new DockPanel(); generateButton = Button(Tr("✦ Passwort erzeugen", "✦ Generate password"), model.Generate, "GeneratePassword"); generateButton.Padding = new(25, 14, 25, 14); generateButton.Background = new LinearGradientBrush((Color)ColorConverter.ConvertFromString("#29BFA9"), (Color)ColorConverter.ConvertFromString("#3F7AF2"), 0); DockPanel.SetDock(generateButton, Dock.Right); actions.Children.Add(generateButton);
        shuffleText = Text("", color: Muted); shuffleText.FontFamily = new("Consolas"); actions.Children.Add(shuffleText); contents.Children.Add(actions);
        var runtimeDetail = Text(model.Security.IsEnforced ? "" : Tr("Die Generierung erfordert gültige RSA-4096- und ML-DSA-87-Signaturen, Integritätsprüfung und eine Laufzeit ohne Debugger.", "Generation requires valid RSA-4096 and ML-DSA-87 signatures, integrity verification, and a runtime without a debugger."), color: Amber); runtimeDetail.Margin = new(0, 12, 0, 0); contents.Children.Add(runtimeDetail);
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
        }, "DiscardPassword"); discard.Foreground = Brush("#FF9E9E"); discard.Background = Brush("#23171E"); discard.Margin = new(12, 0, 0, 0); DockPanel.SetDock(discard, Dock.Right); footer.Children.Add(discard);
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
        var rating = Button(Rating(bits) + "  ⓘ", () => ShowEntropyInformation(bits), "EntropyInformation"); rating.Background = RatingBrush(bits); rating.MaxWidth = 380; DockPanel.SetDock(rating, Dock.Right); headline.Children.Add(rating);
        var value = Vertical(); value.Children.Add(Text(Tr("Nominelle Entropie", "Nominal entropy"), color: Secondary, weight: FontWeights.SemiBold));
        value.Children.Add(Text((bits?.ToString("N1", Culture) ?? "…") + Tr(" Bit", " bits") + (model.Mode == GeneratorMode.Bip39 && bits != null ? Tr(" · ohne Prüfsumme", " · excluding checksum") : ""), 27, weight: FontWeights.Bold)); headline.Children.Add(value); stack.Children.Add(headline);
        var estimates = Vertical(); estimates.Margin = new(0, 12, 0, 0);
        estimates.Children.Add(AttackRow(Tr("Exascale-Computer", "Exascale computer"), Tr("Vollsuche · 10^18 Prüfungen/s", "Full search · 10^18 checks/s"), bits, false));
        estimates.Children.Add(AttackRow(Tr("Petahertz-Quantencomputer", "Petahertz quantum computer"), Tr("Grover · 10^15 vollständige Iterationen/s", "Grover · 10^15 complete iterations/s"), bits, true));
        estimates.Children.Add(Text(Tr("Hypothetische Modelle, keine gemessenen Angriffszeiten.", "Hypothetical models, not measured attack times."), color: Secondary)); stack.Children.Add(Surface(estimates, "#0B1119", 11, new(12)));
        if (showLegend)
        {
            var legend = new UniformGrid { Columns = 2, Margin = new(0, 12, 0, 12) };
            foreach (var sample in new[] { 64.0, 128, 256, 1024 })
            {
                var item = Vertical(); item.Margin = new(0, 0, 8, 8); item.Children.Add(new Border { Height = 4, Background = RatingBrush(sample), Margin = new(0, 0, 0, 6) });
                item.Children.Add(Text(sample switch { 64 => Tr("< 128 Bit", "< 128 bits"), 128 => Tr("128 bis < 256 Bit", "128 to < 256 bits"), 256 => Tr("256 bis < 1.024 Bit", "256 to < 1,024 bits"), _ => Tr("≥ 1.024 Bit", "≥ 1,024 bits") }, weight: FontWeights.Bold)); item.Children.Add(Text(Rating(sample), color: Secondary)); legend.Children.Add(item);
            }
            stack.Children.Add(legend);
        }
        stack.Children.Add(Text(Tr("Nomineller Auswahlraum bei gleichverteilter Auswahl. Keine Messung der Zufallsquelle und keine Garantie für die Gesamtsicherheit.", "Nominal selection space with uniform sampling. No measurement of the random source and no guarantee of overall security."), color: Secondary));
        var surface = Surface(stack, "#111923", 16, new(16)); surface.Margin = new(0, 16, 0, 0); return surface;
    }
    private UIElement AttackRow(string title, string detail, double? bits, bool grover)
    {
        double? seconds = bits.HasValue ? (grover ? Math.Log10(Math.PI / 4) + bits.Value / 2 * Math.Log10(2) - 15 : bits.Value * Math.Log10(2) - 18) : null;
        var stack = Vertical(); stack.Margin = new(0, 0, 0, 12);
        var row = new DockPanel(); var duration = Text("≈ " + Duration(seconds), weight: FontWeights.Bold); DockPanel.SetDock(duration, Dock.Right); row.Children.Add(duration); row.Children.Add(Text(title, weight: FontWeights.SemiBold)); stack.Children.Add(row);
        stack.Children.Add(Text(detail + (!grover && bits.HasValue ? Tr(" · im Mittel ≈ ", " · on average ≈ ") + Duration(seconds + Math.Log10((1 + Math.Pow(2, -bits.Value)) / 2)) : ""), color: Secondary));
        const double budget = 3e71; var landauer = 1.380649e-23 * 2.7 * Math.Log(2); var energyThreshold = Math.Log2(budget / landauer);
        if (grover) energyThreshold = 2 * (energyThreshold - Math.Log2(Math.PI / 4));
        var years = seconds - Math.Log10(365.25 * 24 * 60 * 60);
        stack.Children.Add(Text(Tr("Landauer-Budget: ", "Landauer budget: ") + (bits == null ? "—" : bits > energyThreshold ? Tr("Suchaufwand > Budget", "search cost > budget") : Tr("Suchaufwand im Budget", "search cost within budget")) + "  ·  " + Tr("10^106-Jahre-Horizont: ", "10^106-year horizon: ") + (years == null ? "—" : years > 106 ? Tr("überschritten", "exceeded") : Tr("innerhalb", "within")), color: Secondary)); return stack;
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
    private static Brush RatingBrush(double? bits) => Brush(bits == null ? "#334356" : bits < 128 ? "#642B35" : bits < 256 ? "#665427" : bits < 1024 ? "#425A2A" : "#12472E");
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
                foreach (var pair in bipLengthButtons) pair.Value.Background = Brush(model.Length == pair.Key ? "#123936" : "#132033");
                entropyHost.Child = EntropyIndicator(model.Configuration?.EntropyBits, showLegend: true);
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
        var width = Math.Max(ActualWidth, 1060); var height = Math.Max(ActualHeight, 840);
        var scale = Math.Sqrt(width / 1060) * Math.Sqrt(height / 840);
        scaleTransform.ScaleX = scaleTransform.ScaleY = scale;
        page.Width = Math.Max(600, (width - 18) / scale - 60);
        page.Margin = new(30, 28, 30, 28);
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
