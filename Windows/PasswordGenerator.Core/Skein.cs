using System.Buffers.Binary;
using System.Numerics;

namespace PasswordGenerator.Core;

/// <summary>Skein 1.3 sequential unkeyed Skein-1024, ported from the v2.3.6 Swift core.</summary>
public static class Skein
{
    private const int Words = 16;
    private static readonly int[] Permutation = [0, 9, 2, 13, 6, 11, 4, 15, 10, 7, 12, 3, 14, 5, 8, 1];
    private static readonly int[,] Rotations = {
        {24,13,8,47,8,17,22,37}, {38,19,10,55,49,18,23,52},
        {33,4,51,13,34,41,59,17}, {5,20,48,41,47,28,16,25},
        {41,9,37,31,12,47,44,30}, {16,34,56,51,4,53,42,41},
        {31,44,47,46,19,42,44,25}, {9,48,35,52,23,31,37,20}
    };
    public static byte[] Hash1024(ReadOnlySpan<byte> bytes)
    {
        var chain = MessageChain(bytes, 1024);
        try { return OutputBlock(chain, 0); }
        finally { SecretMemory.Clear(chain); }
    }
    internal static ulong[] MessageChain(ReadOnlySpan<byte> bytes, ulong outputBitCount)
    {
        var chain = new ulong[Words];
        Span<byte> configuration = stackalloc byte[32];
        configuration.Clear();
        configuration[0] = 0x53; configuration[1] = 0x48; configuration[2] = 0x41; configuration[3] = 0x33;
        configuration[4] = 1;
        BinaryPrimitives.WriteUInt64LittleEndian(configuration[8..], outputBitCount);
        Ubi(configuration, 4, chain);
        Ubi(bytes, 48, chain);
        return chain;
    }
    internal static byte[] OutputBlock(ReadOnlySpan<ulong> chain, ulong counter)
    {
        Span<ulong> outputChain = stackalloc ulong[Words];
        chain.CopyTo(outputChain);
        Span<byte> counterBytes = stackalloc byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(counterBytes, counter);
        try
        {
            Ubi(counterBytes, 63, outputChain);
            var output = new byte[128];
            for (int i = 0; i < Words; i++) BinaryPrimitives.WriteUInt64LittleEndian(output.AsSpan(i * 8), outputChain[i]);
            return output;
        }
        finally { SecretMemory.Clear(outputChain); }
    }
    private static void Ubi(ReadOnlySpan<byte> bytes, ulong type, Span<ulong> chain)
    {
        Span<ulong> block = stackalloc ulong[Words];
        int offset = 0;
        try
        {
            do
            {
                block.Clear();
                int consumed = Math.Min(128, bytes.Length - offset);
                for (int i = 0; i < consumed; i++) block[i / 8] |= (ulong)bytes[offset + i] << ((i % 8) * 8);
                bool first = offset == 0;
                offset += consumed;
                ulong flags = type << 56;
                if (first) flags |= 1UL << 62;
                if (offset == bytes.Length) flags |= 1UL << 63;
                Compress(block, (ulong)offset, flags, chain);
            } while (offset < bytes.Length);
        }
        finally { SecretMemory.Clear(block); }
    }
    private static void Compress(ReadOnlySpan<ulong> block, ulong position, ulong flags, Span<ulong> chain)
    {
        Span<ulong> key = stackalloc ulong[17];
        Span<ulong> tweak = stackalloc ulong[3];
        Span<ulong> state = stackalloc ulong[16];
        Span<ulong> permuted = stackalloc ulong[16];
        key[16] = 0x1BD11BDAA9FC1A22;
        tweak[0] = position; tweak[1] = flags; tweak[2] = position ^ flags;
        block.CopyTo(state);
        for (int i = 0; i < Words; i++) { key[i] = chain[i]; key[16] ^= chain[i]; }
        try
        {
            unchecked
            {
                for (int round = 0; round < 80; round++)
                {
                    if (round % 4 == 0) InjectSubkey(round / 4, key, tweak, state);
                    for (int pair = 0; pair < 8; pair++)
                    {
                        int even = pair * 2, odd = even + 1;
                        state[even] += state[odd];
                        state[odd] = BitOperations.RotateLeft(state[odd], Rotations[round % 8, pair]) ^ state[even];
                    }
                    for (int i = 0; i < Words; i++) permuted[i] = state[Permutation[i]];
                    permuted.CopyTo(state);
                }
                InjectSubkey(20, key, tweak, state);
                for (int i = 0; i < Words; i++) chain[i] = state[i] ^ block[i];
            }
        }
        finally { SecretMemory.Clear(key); SecretMemory.Clear(tweak); SecretMemory.Clear(state); SecretMemory.Clear(permuted); }
    }
    private static void InjectSubkey(int subkey, ReadOnlySpan<ulong> key, ReadOnlySpan<ulong> tweak, Span<ulong> state)
    {
        unchecked
        {
            for (int i = 0; i < Words; i++) state[i] += key[(subkey + i) % 17];
            state[13] += tweak[subkey % 3]; state[14] += tweak[(subkey + 1) % 3]; state[15] += (ulong)subkey;
        }
    }
}

public sealed class Skein1024XofStream : IDisposable
{
    private readonly ulong[] chain;
    private byte[] block = [];
    private int position;
    private ulong nextBlockCounter, emittedByteCount;
    private bool cleared;
    public Skein1024XofStream(ReadOnlySpan<byte> bytes) => chain = Skein.MessageChain(bytes, ulong.MaxValue);
    public byte[] Read(int count)
    {
        ObjectDisposedException.ThrowIf(cleared, this);
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        if ((ulong)count > ulong.MaxValue / 8 - emittedByteCount) throw new InvalidOperationException("Skein-XOF output limit exceeded.");
        var output = new byte[count];
        int offset = 0;
        while (offset < count)
        {
            if (position == block.Length)
            {
                SecretMemory.Clear(block);
                block = Skein.OutputBlock(chain, nextBlockCounter++);
                position = 0;
            }
            int copied = Math.Min(block.Length - position, count - offset);
            block.AsSpan(position, copied).CopyTo(output.AsSpan(offset));
            System.Security.Cryptography.CryptographicOperations.ZeroMemory(block.AsSpan(position, copied));
            position += copied; offset += copied;
        }
        emittedByteCount += (ulong)count;
        return output;
    }
    public void Clear() => Dispose();
    public void Dispose()
    {
        if (cleared) return;
        SecretMemory.Clear(chain); SecretMemory.Clear(block);
        position = 0; nextBlockCounter = 0; emittedByteCount = 0; cleared = true;
        GC.SuppressFinalize(this);
    }
    ~Skein1024XofStream() => Dispose();
}
