using System.Buffers.Binary;
using System.Security.Cryptography;

namespace PasswordGenerator.Core;

public readonly record struct MouseEntropyRecord(ulong UptimeNanoseconds, double EventTimestamp,
    double X, double Y, double DeltaX, double DeltaY, double CanvasWidth, double CanvasHeight,
    ulong ModifierFlags, ulong PressedMouseButtons);

/// <summary>Bounded mouse transcript. Access must be serialized by its UI owner.</summary>
public sealed class EntropyPool : IDisposable
{
    public const int Capacity = 4096, RequiredMouseEventCount = Capacity, RecordByteCount = 89;
    public int ShuffleCount { get; private set; }
    public ulong AbsorbedEventCount { get; private set; }
    public int EventCount { get; private set; }
    private readonly SensitiveBytes records = new(Capacity * RecordByteCount);
    private readonly int[] order = new int[Capacity];
    private int writeOffset;
    private bool cleared;
    private readonly Func<int, byte[]> randomProvider;
    public EntropyPool(Func<int, byte[]>? randomProvider = null)
    {
        this.randomProvider = randomProvider ?? SecureRandom.Bytes;
        Shuffle();
    }
    public void Absorb(MouseEntropyRecord record)
    {
        if (cleared) return;
        var bytes = records.Span.Slice(writeOffset * RecordByteCount, RecordByteCount);
        bytes[0] = 1;
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[1..], AbsorbedEventCount);
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[9..], record.UptimeNanoseconds);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[17..], record.EventTimestamp);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[25..], record.X);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[33..], record.Y);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[41..], record.DeltaX);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[49..], record.DeltaY);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[57..], record.CanvasWidth);
        BinaryPrimitives.WriteDoubleLittleEndian(bytes[65..], record.CanvasHeight);
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[73..], record.ModifierFlags);
        BinaryPrimitives.WriteUInt64LittleEndian(bytes[81..], record.PressedMouseButtons);
        if (EventCount < Capacity) { order[EventCount] = EventCount; EventCount++; }
        writeOffset = (writeOffset + 1) % Capacity;
        AbsorbedEventCount = unchecked(AbsorbedEventCount + 1);
    }
    public void Shuffle()
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        using var random = new PoolRandomReader(randomProvider);
        for (int i = EventCount - 1; i > 0; i--)
        {
            int selected = random.Uniform(i + 1);
            (order[i], order[selected]) = (order[selected], order[i]);
        }
        ShuffleCount = unchecked(ShuffleCount + 1);
    }
    public PasswordByteStream MakeStream()
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        if (EventCount < RequiredMouseEventCount) throw new InvalidOperationException($"Es wurden erst {EventCount} von {RequiredMouseEventCount} Mausbewegungen erfasst.");
        Shuffle();
        var serialized = new byte[EventCount * RecordByteCount];
        byte[]? skein = null, sha3 = null, sha512 = null, mask = null;
        using var master = new SensitiveBytes(256);
        try
        {
            for (int i = 0; i < EventCount; i++) records.Span.Slice(order[i] * RecordByteCount, RecordByteCount).CopyTo(serialized.AsSpan(i * RecordByteCount));
            skein = Skein.Hash1024(serialized); sha3 = SHA3_512.HashData(serialized); sha512 = SHA512.HashData(serialized);
            skein.CopyTo(master.Span); sha3.CopyTo(master.Span[128..]); sha512.CopyTo(master.Span[192..]);
            mask = SecureRandom.CheckedBytes(256, randomProvider);
            for (int i = 0; i < 256; i++) master.Span[i] ^= mask[i];
            SecretMemory.Clear(mask); mask = null;
            ShuffleDigestBits(master.Span, randomProvider);
            mask = SecureRandom.CheckedBytes(256, randomProvider);
            for (int i = 0; i < 256; i++) master.Span[i] ^= mask[i];
            return new PasswordByteStream(master.Span, randomProvider);
        }
        finally { SecretMemory.Clear(serialized); SecretMemory.Clear(skein); SecretMemory.Clear(sha3); SecretMemory.Clear(sha512); SecretMemory.Clear(mask); }
    }
    public static void ShuffleDigestBits(Span<byte> bytes, Func<int, byte[]> randomProvider)
    {
        if (bytes.Length != 256) throw new ArgumentException("Expected 256 master bytes.", nameof(bytes));
        using var random = new PoolRandomReader(randomProvider);
        for (int i = bytes.Length * 8 - 1; i > 0; i--)
        {
            int selected = random.Uniform(i + 1), firstByte = i / 8, secondByte = selected / 8;
            int difference = ((bytes[firstByte] >> (i % 8)) ^ (bytes[secondByte] >> (selected % 8))) & 1;
            bytes[firstByte] ^= (byte)(difference << (i % 8));
            bytes[secondByte] ^= (byte)(difference << (selected % 8));
        }
    }
    public void Clear() => Dispose();
    public void Dispose()
    {
        if (cleared) return;
        records.Dispose(); SecretMemory.Clear(order);
        writeOffset = 0; AbsorbedEventCount = 0; EventCount = 0; cleared = true;
        GC.SuppressFinalize(this);
    }
    ~EntropyPool() => Dispose();
}

public sealed class PasswordByteStream : IDisposable
{
    private readonly Skein1024XofStream skein;
    private readonly List<Shake256Stream> shakes = [];
    private readonly List<Aes256CtrStream> aes = [];
    private readonly Func<int, byte[]> randomProvider;
    private bool cleared;
    public PasswordByteStream(ReadOnlySpan<byte> master, Func<int, byte[]>? randomProvider = null)
    {
        if (master.Length != 256) throw new ArgumentException("Expected 256 master bytes.", nameof(master));
        this.randomProvider = randomProvider ?? SecureRandom.Bytes;
        skein = new Skein1024XofStream(master[..128]);
        try
        {
            for (int i = 128; i < 192; i += 32) shakes.Add(new Shake256Stream(master.Slice(i, 32)));
            for (int i = 192; i < 256; i += 32) aes.Add(new Aes256CtrStream(master.Slice(i, 32)));
        }
        catch { Dispose(); throw; }
    }
    public byte[] Bytes(int count)
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(count, SecureRandom.MaximumByteCount);
        byte[] result = skein.Read(count);
        byte[]? fragment = null;
        try
        {
            foreach (var stream in shakes)
            {
                fragment = stream.Read(count); Xor(result, fragment); SecretMemory.Clear(fragment); fragment = null;
            }
            foreach (var stream in aes)
            {
                fragment = stream.Read(count); Xor(result, fragment); SecretMemory.Clear(fragment); fragment = null;
            }
            fragment = SecureRandom.CheckedBytes(count, randomProvider); Xor(result, fragment);
            return result;
        }
        catch { SecretMemory.Clear(result); Dispose(); throw; }
        finally { SecretMemory.Clear(fragment); }
    }
    private static void Xor(Span<byte> output, ReadOnlySpan<byte> fragment) { for (int i = 0; i < output.Length; i++) output[i] ^= fragment[i]; }
    public void Clear() => Dispose();
    public void Dispose()
    {
        if (cleared) return;
        skein?.Dispose(); foreach (var shake in shakes) shake.Dispose(); foreach (var stream in aes) stream.Dispose();
        shakes.Clear(); aes.Clear(); cleared = true; GC.SuppressFinalize(this);
    }
    ~PasswordByteStream() => Dispose();
}

internal sealed class PoolRandomReader(Func<int, byte[]> provider) : IDisposable
{
    private byte[] buffer = [];
    private int offset;
    public int Uniform(int upperBound)
    {
        ulong bound = (ulong)upperBound, range = (ulong)uint.MaxValue + 1, limit = range - range % bound;
        for (int attempts = 0; attempts < 4096; attempts++)
        {
            if (offset + 4 > buffer.Length)
            {
                SecretMemory.Clear(buffer); buffer = SecureRandom.CheckedBytes(4096, provider); offset = 0;
            }
            ulong value = BinaryPrimitives.ReadUInt32LittleEndian(buffer.AsSpan(offset)); offset += 4;
            if (value < limit) return (int)(value % bound);
        }
        throw new CryptographicException("Die Zufallsquelle lieferte wiederholt ungeeignete Auswahlwerte.");
    }
    public void Dispose() { SecretMemory.Clear(buffer); offset = 0; }
}
