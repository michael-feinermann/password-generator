using System.Security.Cryptography;

namespace PasswordGenerator.Core;

/// <summary>Advancing AES-256 CTR with a 128-bit big endian counter and no wrap.</summary>
public sealed class Aes256CtrStream : IDisposable
{
    private readonly Aes aes;
    private readonly byte[] counter;
    private readonly byte[] block = new byte[16];
    private int blockOffset = 16;
    private bool counterExhausted, cleared;
    public Aes256CtrStream(ReadOnlySpan<byte> key) : this(key, new byte[16]) { }
    public Aes256CtrStream(ReadOnlySpan<byte> key, ReadOnlySpan<byte> initialCounter)
    {
        if (key.Length != 32) throw new ArgumentException("AES-256 benötigt genau 32 Schlüsselbytes.", nameof(key));
        if (initialCounter.Length != 16) throw new ArgumentException("AES-CTR benötigt genau 16 Zählerbytes.", nameof(initialCounter));
        counter = initialCounter.ToArray();
        aes = Aes.Create();
        byte[] copy = key.ToArray();
        try { aes.Key = copy; aes.Mode = CipherMode.ECB; aes.Padding = PaddingMode.None; }
        catch { Dispose(); throw; }
        finally { SecretMemory.Clear(copy); }
    }
    public byte[] Read(int count)
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(count, SecureRandom.MaximumByteCount);
        var result = new byte[count];
        try
        {
            int written = 0;
            while (written < count)
            {
                if (blockOffset == block.Length) Refill();
                int copied = Math.Min(count - written, block.Length - blockOffset);
                block.AsSpan(blockOffset, copied).CopyTo(result.AsSpan(written));
                CryptographicOperations.ZeroMemory(block.AsSpan(blockOffset, copied));
                written += copied; blockOffset += copied;
            }
            return result;
        }
        catch { SecretMemory.Clear(result); Dispose(); throw; }
    }
    private void Refill()
    {
        if (counterExhausted) throw new CryptographicException("Der AES-CTR-Zähler ist ausgeschöpft.");
        if (aes.EncryptEcb(counter, block, PaddingMode.None) != 16) throw new CryptographicException("AES block length mismatch.");
        blockOffset = 0;
        for (int i = counter.Length - 1; i >= 0; i--) { counter[i] = unchecked((byte)(counter[i] + 1)); if (counter[i] != 0) return; }
        counterExhausted = true;
    }
    public void Clear() => Dispose();
    public void Dispose()
    {
        if (cleared) return;
        aes?.Dispose(); SecretMemory.Clear(counter); SecretMemory.Clear(block);
        blockOffset = block.Length; counterExhausted = true; cleared = true;
        GC.SuppressFinalize(this);
    }
    ~Aes256CtrStream() => Dispose();
}

/// <summary>Native .NET SHAKE256 state; each read advances the same XOF.</summary>
public sealed class Shake256Stream : IDisposable
{
    private readonly Shake256 shake;
    private bool cleared;
    public Shake256Stream(ReadOnlySpan<byte> bytes) { shake = new Shake256(); shake.AppendData(bytes); }
    public byte[] Read(int count)
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        return count == 0 ? [] : shake.Read(count);
    }
    public void Clear() => Dispose();
    public void Dispose() { if (cleared) return; shake?.Dispose(); cleared = true; GC.SuppressFinalize(this); }
    ~Shake256Stream() => Dispose();
}
