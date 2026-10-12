using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace PasswordGenerator.Signing;

internal static class Dpapi
{
    [StructLayout(LayoutKind.Sequential)] struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CryptProtectData(ref Blob input, string description, IntPtr entropy, IntPtr reserved,
        IntPtr prompt, uint flags, out Blob output);
    [DllImport("crypt32.dll", SetLastError = true)]
    static extern bool CryptUnprotectData(ref Blob input, IntPtr description, IntPtr entropy, IntPtr reserved,
        IntPtr prompt, uint flags, out Blob output);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);

    internal static unsafe byte[] Transform(byte[] data, bool encrypt)
    {
        fixed (byte* pointer = data)
        {
            var input = new Blob { Length = data.Length, Data = (IntPtr)pointer };
            Blob output;
            bool success = encrypt
                ? CryptProtectData(ref input, "Password Generator Windows release key", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output)
                : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output);
            if (!success) throw new Win32Exception(Marshal.GetLastWin32Error());
            try
            {
                byte[] bytes = new byte[output.Length];
                Marshal.Copy(output.Data, bytes, 0, bytes.Length);
                return bytes;
            }
            finally
            {
                CryptographicOperations.ZeroMemory(new Span<byte>((void*)output.Data, output.Length));
                LocalFree(output.Data);
            }
        }
    }
}
