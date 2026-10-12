using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace PasswordGenerator.Core;

/// <summary>One page-aligned allocation with best-effort page locking. Exported strings cannot be erased.</summary>
internal sealed unsafe class SensitiveBytes : IDisposable
{
    private readonly nint pointer;
    private readonly int count;
    private readonly nuint allocationSize;
    private readonly bool pagesLocked;
    public bool IsCleared { get; private set; }
    public Span<byte> Span => IsCleared ? throw new ObjectDisposedException(nameof(SensitiveBytes)) : new Span<byte>((void*)pointer, count);
    public SensitiveBytes(int count)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        this.count = count;
        int pageSize = Environment.SystemPageSize;
        allocationSize = checked((nuint)Math.Max(pageSize, ((long)count + pageSize - 1) / pageSize * pageSize));
        pointer = VirtualAlloc(0, allocationSize, 0x3000, 0x04);
        if (pointer == 0) throw new OutOfMemoryException("Secret allocation failed.");
        pagesLocked = VirtualLock(pointer, allocationSize);
    }
    public void Dispose()
    {
        if (IsCleared) return;
        if (pointer == 0) { IsCleared = true; return; }
        CryptographicOperations.ZeroMemory(new Span<byte>((void*)pointer, checked((int)allocationSize)));
        if (pagesLocked) VirtualUnlock(pointer, allocationSize);
        VirtualFree(pointer, 0, 0x8000);
        IsCleared = true;
        GC.SuppressFinalize(this);
    }
    ~SensitiveBytes() => Dispose();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern nint VirtualAlloc(nint address, nuint size, uint allocationType, uint protection);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool VirtualLock(nint address, nuint size);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool VirtualUnlock(nint address, nuint size);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool VirtualFree(nint address, nuint size, uint freeType);
}

internal static class SecretMemory
{
    public static void Clear(byte[]? bytes) { if (bytes is not null) CryptographicOperations.ZeroMemory(bytes); }
    public static void Clear(Span<ulong> words) => CryptographicOperations.ZeroMemory(MemoryMarshal.AsBytes(words));
    public static void Clear(Span<int> words) => CryptographicOperations.ZeroMemory(MemoryMarshal.AsBytes(words));
}

public static class SecureRandom
{
    public const int MaximumByteCount = 1_048_576;
    public static byte[] Bytes(int count)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(count, MaximumByteCount);
        var bytes = new byte[count];
        try { RandomNumberGenerator.Fill(bytes); return bytes; }
        catch { SecretMemory.Clear(bytes); throw; }
    }

    internal static byte[] CheckedBytes(int count, Func<int, byte[]> provider)
    {
        var bytes = provider(count);
        if (bytes is null || bytes.Length != count)
        {
            int actual = bytes?.Length ?? -1;
            SecretMemory.Clear(bytes);
            throw new CryptographicException($"Die Zufallsquelle lieferte {actual} statt {count} Byte.");
        }
        return bytes;
    }
}
