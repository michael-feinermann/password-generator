using System.Windows;

namespace PasswordGenerator.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try { MainWindow = new MainWindow(); MainWindow.Show(); }
        catch (Exception)
        {
            MessageBox.Show(LanguagePreferences.Load() == "de" ? "Die kryptografische Initialisierung ist fehlgeschlagen. Die App wird geschlossen." : "Cryptographic initialization failed. The application will close.", "Password Generator 2.3.6", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }
}
