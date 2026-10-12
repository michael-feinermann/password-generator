using System.Diagnostics;
using System.Runtime.InteropServices;
using PasswordGenerator.Security;

namespace PasswordGenerator.App;

public sealed record RuntimeSecurityAssessment(bool IsEnforced, string Summary, string Details);

/// <summary>Fail-closed Windows integrity gate. This does not provide an App Sandbox.</summary>
public static class RuntimeSecurity
{
    [DllImport("kernel32.dll")] static extern bool IsDebuggerPresent();
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CheckRemoteDebuggerPresent(IntPtr process, out bool present);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern int WerSetFlags(uint flags);
    [DllImport("kernel32.dll")] static extern int WerGetFlags(IntPtr process, out uint flags);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetDefaultDllDirectories(uint flags);
    static readonly bool DllSearchRestricted = SetDefaultDllDirectories(0x1000); // application, system32, explicit user directories

    public static RuntimeSecurityAssessment Check()
    {
        try
        {
            if (!Environment.Is64BitProcess || !DllSearchRestricted)
                throw new InvalidOperationException("64-bit process and restricted DLL search are required.");
            if (Debugger.IsAttached || IsDebuggerPresent()
                || !CheckRemoteDebuggerPresent(GetCurrentProcess(), out bool remote) || remote)
                throw new InvalidOperationException("Debugger detected or debugger check unavailable.");
            if (WerSetFlags(1) != 0 || WerGetFlags(GetCurrentProcess(), out uint flags) != 0 || (flags & 1) == 0)
                throw new InvalidOperationException("Windows Error Reporting heap exclusion is unavailable.");
            var inventory = HybridIntegrity.VerifyDirectory(AppContext.BaseDirectory);
            return new(true, "RSA-4096 + ML-DSA-87 verified",
                $"Exact signed inventory: {inventory.Files.Length} files. Debugger checks passed; WER heap exclusion enabled; DLL search restricted. "
                + "Windows desktop process: no Apple App Sandbox equivalent. Administrator dumps and a compromised host cannot be prevented.");
        }
        catch (Exception error)
        {
            return new(false, "Generation blocked", "Windows integrity/runtime check failed: " + error.Message);
        }
    }
}
