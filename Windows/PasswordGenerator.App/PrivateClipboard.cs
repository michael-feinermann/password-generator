using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace PasswordGenerator.App;

public readonly record struct ClipboardOwnership(uint Sequence, nint Owner);

/// <summary>Explicit local clipboard export with sequence-based conditional cleanup.</summary>
public static class PrivateClipboard
{
    [DllImport("user32.dll")] private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] private static extern nint GetClipboardOwner();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(nint owner);
    [DllImport("user32.dll")] private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetClipboardData(uint format, nint memory);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern uint RegisterClipboardFormat(string name);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern nint GlobalAlloc(uint flags, nuint bytes);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern nint GlobalLock(nint memory);
    [DllImport("kernel32.dll")] private static extern bool GlobalUnlock(nint memory);
    [DllImport("kernel32.dll")] private static extern nint GlobalFree(nint memory);

    public static ClipboardOwnership? Copy(string text)
    {
        var owner = Application.Current?.MainWindow is { } window ? new WindowInteropHelper(window).Handle : 0;
        if (!OpenClipboard(owner)) throw new ExternalException("Clipboard is busy.");
        char[]? characters = null;
        try
        {
            characters = new char[text.Length + 1];
            text.CopyTo(0, characters, 0, text.Length);
            if (!EmptyClipboard()) throw new ExternalException("Clipboard could not be prepared.");
            Put(13, characters.Length * 2, pointer => Marshal.Copy(characters, 0, pointer, characters.Length));
            foreach (var name in new[] { "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard", "ExcludeClipboardContentFromMonitorProcessing" })
            {
                var format = RegisterClipboardFormat(name);
                if (format == 0) throw new ExternalException("Clipboard privacy format could not be registered.");
                Put(format, 4, pointer => Marshal.WriteInt32(pointer, 0));
            }
        }
        catch { EmptyClipboard(); throw; }
        finally { if (characters != null) Array.Clear(characters); CloseClipboard(); }
        // Windows synthesizes ANSI/OEM/locale formats when committing Unicode text.
        // Reacquire the lock and bind the committed sequence to the original owner.
        if (!OpenClipboard(owner)) return null;
        try { return GetClipboardOwner() == owner ? new(GetClipboardSequenceNumber(), owner) : null; }
        finally { CloseClipboard(); }
    }

    private static void Put(uint format, int byteCount, Action<nint> write)
    {
        var memory = GlobalAlloc(2, (nuint)byteCount);
        if (memory == 0) throw new ExternalException("Clipboard allocation failed.");
        try
        {
            var pointer = GlobalLock(memory);
            if (pointer == 0) throw new ExternalException("Clipboard buffer could not be locked.");
            try { write(pointer); } finally { GlobalUnlock(memory); }
            if (SetClipboardData(format, memory) == 0) throw new ExternalException("Clipboard write failed.");
            memory = 0; // Windows owns the successfully transferred allocation.
        }
        finally
        {
            if (memory != 0)
            {
                var pointer = GlobalLock(memory);
                if (pointer != 0)
                {
                    try { for (var offset = 0; offset < byteCount; offset++) Marshal.WriteByte(pointer, offset, 0); }
                    finally { GlobalUnlock(memory); }
                }
                GlobalFree(memory);
            }
        }
    }

    public static void ClearIfUnchanged(ClipboardOwnership? expectedSequence)
    {
        if (!expectedSequence.HasValue || !OpenClipboard(0)) return;
        try { if (GetClipboardSequenceNumber() == expectedSequence.Value.Sequence && GetClipboardOwner() == expectedSequence.Value.Owner) EmptyClipboard(); }
        finally { CloseClipboard(); }
    }
}
