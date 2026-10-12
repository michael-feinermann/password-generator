using System.IO;

namespace PasswordGenerator.App;

/// <summary>The language is the only application setting persisted to disk.</summary>
public static class LanguagePreferences
{
    private static readonly string FilePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Keep Vault", "Password Generator", "language.txt");
    public static string Load()
    {
        try { return File.Exists(FilePath) && File.ReadAllText(FilePath).Trim() == "de" ? "de" : "en"; }
        catch (IOException) { return "en"; }
        catch (UnauthorizedAccessException) { return "en"; }
    }
    public static void Save(string language)
    {
        try { Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!); File.WriteAllText(FilePath, language == "de" ? "de" : "en"); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
