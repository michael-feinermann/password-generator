namespace PasswordGenerator.App;

// The harness compiles model sources into its own executable. This shim is not
// referenced by, linked into, or shipped with PasswordGenerator.App.
public sealed record RuntimeSecurityAssessment(bool IsEnforced, string Summary, string Details);
public static class RuntimeSecurity
{
    public static bool Allowed { get; set; } = true;
    public static RuntimeSecurityAssessment Check() => new(Allowed, "Test assessment", "Test assessment");
}
