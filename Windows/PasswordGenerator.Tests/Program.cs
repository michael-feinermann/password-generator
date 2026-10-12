using System.Buffers.Binary;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using PasswordGenerator.Core;
using Generator = PasswordGenerator.Core.PasswordGenerator;

if (args.Length == 3 && args[0] == "--checksum")
{
    byte[] bytes = File.ReadAllBytes(args[2]);
    try
    {
        byte[] digest = args[1].ToUpperInvariant() switch {
            "SHA256" or "SHA-256" => SHA256.HashData(bytes), "SHA512" or "SHA-512" => SHA512.HashData(bytes),
            "SHA3-512" or "SHA3_512" => SHA3_512.HashData(bytes), "SKEIN-1024" or "SKEIN1024" or "SKEIN-1024-1024" => Skein.Hash1024(bytes),
            _ => throw new ArgumentException("Unsupported checksum algorithm.") };
        Console.WriteLine(Convert.ToHexStringLower(digest));
    }
    finally { CryptographicOperations.ZeroMemory(bytes); }
    return;
}
if (args.Length == 1 && args[0] == "--selftest") { CryptographicSelfTest.Run(); Console.WriteLine("Cryptographic self-test passed."); return; }

var tests = new CoreTests();
tests.Run();

internal sealed class CoreTests
{
    private int assertions, groups, failures;
    public void Run()
    {
        Test("Runtime cryptographic self-test and Windows RNG", CryptographicSelfTest.Run);
        Test("Independent SHA3-512 / SHAKE256 NIST vectors", NistVectors);
        Test("Independent Skein hash / advancing XOF reference vectors", SkeinVectors);
        Test("Independent AES-256-CTR vectors, partial blocks, carry, exhaustion", AesVectors);
        Test("BIP39 official English vectors and checksum failures", Bip39Vectors);
        Test("Bundled BIP39/EFF triple integrity and tamper rejection", WordListIntegrityTests);
        Test("All generator modes, limits, separators, case, leading zeroes", GeneratorTests);
        Test("Unbiased complete byte/two-byte domain sampling", SamplingTests);
        Test("Invalid input and broken random source fail closed", NegativeTests);
        Test("Independent complete pipeline, boundaries, overwritten shuffled pools", PipelineVectors);
        Test("Digest bit permutation intermediates and bit count preservation", BitShuffleTests);
        Test("Pool readiness, bounded transcript, disposal and zeroization", PoolAndMemoryTests);
        Test("Nominal levels and continuous attack-cost model boundaries", MetricsTests);
        Console.WriteLine(JsonSerializer.Serialize(new { status = failures == 0 ? "passed" : "failed", groups, assertions, failures,
            framework = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
            os = System.Runtime.InteropServices.RuntimeInformation.OSDescription }));
        if (failures != 0) Environment.ExitCode = 1;
    }
    private void Test(string name, Action action)
    {
        groups++;
        try { action(); Console.WriteLine($"PASS {name}"); }
        catch (Exception error) { failures++; Console.WriteLine($"FAIL {name}: {error}"); }
    }
    private void Check(bool value, string message = "Assertion failed") { assertions++; if (!value) throw new InvalidOperationException(message); }
    private void Equal<T>(T actual, T expected, string context = "") => Check(EqualityComparer<T>.Default.Equals(actual, expected), $"{context}: expected {expected}, got {actual}");
    private void Bytes(ReadOnlySpan<byte> actual, ReadOnlySpan<byte> expected, string context = "") => Check(actual.SequenceEqual(expected), $"{context}: bytes differ");
    private void Throws<T>(Action action) where T : Exception
    {
        assertions++;
        try { action(); } catch (T) { return; }
        throw new InvalidOperationException($"Expected {typeof(T).Name}");
    }
    private static JsonDocument Fixture(string name)
    {
        var assembly = Assembly.GetExecutingAssembly();
        string resource = assembly.GetManifestResourceNames().Single(n => n.EndsWith('.' + name, StringComparison.Ordinal));
        using var stream = assembly.GetManifestResourceStream(resource)!;
        return JsonDocument.Parse(stream);
    }
    private static byte[] Hex(JsonElement element, string property) => Convert.FromHexString(element.GetProperty(property).GetString()!);
    private static MouseEntropyRecord Record(int i) => new((ulong)(i + 1), i / 120.0, i % 127, i % 83, 1.2, -0.8, 800, 600, 0, 0);
    private void NistVectors()
    {
        using var sha3 = Fixture("sha3_nist_vectors.json");
        foreach (var vector in sha3.RootElement.EnumerateArray()) Bytes(SHA3_512.HashData(Hex(vector, "message")), Hex(vector, "output"), vector.GetProperty("label").GetString()!);
        using var shake = Fixture("shake_nist_vectors.json");
        foreach (var vector in shake.RootElement.EnumerateArray())
        {
            byte[] expected = Hex(vector, "output");
            using var stream = new Shake256Stream(Hex(vector, "message"));
            Bytes(stream.Read(0), []);
            byte[] actual = [.. stream.Read(Math.Min(1, expected.Length)), .. stream.Read(Math.Max(0, expected.Length - 1))];
            Bytes(actual, expected, vector.GetProperty("label").GetString()!);
        }
        byte[] input = Enumerable.Range(0, 513).Select(i => (byte)i).ToArray();
        byte[] full = Shake256.HashData(input, 4097);
        using var split = new Shake256Stream(input);
        var output = new List<byte>();
        foreach (int count in new[] { 0, 1, 134, 1, 1, 136, 1024, 2800 }) output.AddRange(split.Read(count));
        Bytes(output.ToArray(), full);
        split.Dispose(); Throws<ObjectDisposedException>(() => split.Read(0));
    }
    private void SkeinVectors()
    {
        using var hash = Fixture("skein1024_vectors.json");
        foreach (var vector in hash.RootElement.EnumerateArray()) Bytes(Skein.Hash1024(Hex(vector, "message")), Hex(vector, "output"), vector.GetProperty("label").GetString()!);
        using var xof = Fixture("skein1024_xof_vectors.json");
        foreach (var vector in xof.RootElement.EnumerateArray())
        {
            byte[] expected = Hex(vector, "output");
            using var stream = new Skein1024XofStream(Hex(vector, "message"));
            var actual = new List<byte>();
            foreach (int count in new[] { 0, 1, 126, 1, 1, 128, 127, expected.Length - 384 }) actual.AddRange(stream.Read(count));
            Bytes(actual.ToArray(), expected);
            stream.Dispose(); Throws<ObjectDisposedException>(() => stream.Read(0));
        }
        using var fixedLength = new Skein1024XofStream([]);
        Check(!fixedLength.Read(128).SequenceEqual(Skein.Hash1024([])), "XOF must use a different configuration from fixed-length hash");
    }
    private void AesVectors()
    {
        using var fixtures = Fixture("aes256ctr_vectors.json");
        foreach (var vector in fixtures.RootElement.EnumerateArray())
        {
            byte[] plaintext = Hex(vector, "plaintext"), ciphertext = Hex(vector, "ciphertext");
            using var stream = new Aes256CtrStream(Hex(vector, "key"), Hex(vector, "counter"));
            var output = new List<byte>();
            int offset = 0;
            foreach (int size in new[] { 0, 1, 14, 1, 1, 15, 17, 127, 128, 257 })
            {
                int count = Math.Min(size, plaintext.Length - offset);
                output.AddRange(stream.Read(count)); offset += count;
            }
            output.AddRange(stream.Read(plaintext.Length - offset));
            byte[] actual = output.ToArray();
            for (int i = 0; i < actual.Length; i++) actual[i] ^= plaintext[i];
            Bytes(actual, ciphertext, vector.GetProperty("name").GetString()!);
        }
        Throws<ArgumentException>(() => new Aes256CtrStream(new byte[31]));
        Throws<ArgumentException>(() => new Aes256CtrStream(new byte[33]));
        Throws<ArgumentException>(() => new Aes256CtrStream(new byte[32], new byte[15]));
        Throws<ArgumentException>(() => new Aes256CtrStream(new byte[32], []));
        using var exhausted = new Aes256CtrStream(new byte[32], Enumerable.Repeat((byte)255, 16).ToArray());
        Equal(exhausted.Read(1).Length, 1); Equal(exhausted.Read(15).Length, 15);
        Throws<CryptographicException>(() => exhausted.Read(1)); Throws<ObjectDisposedException>(() => exhausted.Read(0));
    }
    private void Bip39Vectors()
    {
        var bip39 = new Bip39();
        using var vectors = Fixture("trezor_english_vectors.json");
        foreach (var vector in vectors.RootElement.GetProperty("english").EnumerateArray())
        {
            byte[] entropy = Convert.FromHexString(vector[0].GetString()!);
            var mnemonic = bip39.Mnemonic(entropy);
            Equal(string.Join(' ', mnemonic), vector[1].GetString());
            Bytes(bip39.Entropy(mnemonic), entropy); Check(bip39.Validate(mnemonic));
        }
        foreach (int length in new[] { 0, 15, 17, 33 }) Throws<ArgumentException>(() => bip39.Mnemonic(new byte[length]));
        Check(!bip39.Validate(Enumerable.Repeat("abandon", 11).ToArray()));
        var invalid = Enumerable.Repeat("abandon", 12).ToArray();
        Check(!bip39.Validate(invalid)); invalid[0] = "invalid"; Check(!bip39.Validate(invalid));
        foreach (int length in new[] { 16, 20, 24, 28, 32 })
        {
            var entropy = Enumerable.Range(0, length).Select(i => (byte)(i * 7)).ToArray();
            Bytes(bip39.Entropy(bip39.Mnemonic(entropy)), entropy);
        }
    }
    private void WordListIntegrityTests()
    {
        var generator = new Generator();
        Equal(generator.Bip39.Integrity, WordListIntegrity.Bip39Expected); Equal(generator.Eff.Integrity, WordListIntegrity.EffExpected);
        Equal(generator.Bip39.Words.Count, 2048); Equal(generator.Eff.Words.Count, 7776);
        foreach (string name in new[] { "english.txt", "eff_large_wordlist.txt" })
        {
            using var stream = typeof(Bip39).Assembly.GetManifestResourceStream($"PasswordGenerator.Core.Resources.{name}")!;
            using var bytes = new MemoryStream(); stream.CopyTo(bytes); var data = bytes.ToArray();
            data[0] ^= 1;
            if (name == "english.txt") Throws<CryptographicException>(() => new Bip39(data)); else Throws<CryptographicException>(() => new Eff(data));
            if (name == "english.txt") Throws<CryptographicException>(() => new Bip39([])); else Throws<CryptographicException>(() => new Eff([]));
        }
    }
    private void GeneratorTests()
    {
        var generator = new Generator();
        foreach (var mode in Enum.GetValues<GeneratorMode>())
        {
            var range = mode.LengthRange();
            foreach (int length in mode == GeneratorMode.Bip39 ? mode.SupportedLengths() : new[] { range.Min, mode.DefaultLength(), range.Max })
            {
                using var result = generator.Generate(new(mode, length), count => new byte[count]);
                Equal(result.ComponentCount, length); Equal(result.Mode, mode);
                Equal(result.EntropyBits, new GeneratorConfiguration(mode, length).EntropyBits);
                if (mode.UsesWords())
                {
                    foreach (string separator in new[] { "", " ", "-", "::", "💡", "\t", "\n", "abandon" })
                        Equal(result.ExportText(separator), string.Join(separator, result.Text.Split(' ')));
                    Equal(result.ExportText(), result.ExportText(mode == GeneratorMode.Bip39 ? " " : "-"));
                }
                else { Equal(result.Text.Length, length); Equal(result.ExportText("ignore"), result.Text); }
                if (mode == GeneratorMode.Pin) Equal(result.Text, new string('0', length));
                result.Clear(); Equal(result.Text, ""); Equal(result.ComponentCount, 0); Check(result.IsCleared);
            }
        }
        foreach (int length in new[] { 1, 3, 63, 447, 448, 511, 512 })
        {
            using var result = generator.Generate(new(GeneratorMode.Hex, length), count => Enumerable.Range(0, count).Select(i => (byte)i).ToArray());
            Equal(result.Text.Length, length); Equal(result.Text[0], '0'); Equal(result.EntropyBits, (double)length * 4);
            Equal(result.ExportText(uppercaseHex: true), result.Text.ToUpperInvariant());
        }
        Equal(string.Concat(Generator.AsciiAlphabet), new string(Enumerable.Range(33, 94).Select(i => (char)i).ToArray()));
        Equal(string.Concat(Generator.PinAlphabet), "0123456789"); Equal(string.Concat(Generator.HexAlphabet), "0123456789abcdef");
    }
    private void SamplingTests()
    {
        foreach (int size in new[] { 10, 16, 94 })
        {
            bool supplied = false; int accepted = 256 - 256 % size;
            var indices = Generator.UniformIndices(256, size, count => { if (!supplied) { supplied = true; Equal(count, 256); return Enumerable.Range(0, 256).Select(i => (byte)i).ToArray(); } Equal(count, 256 - accepted); return new byte[count]; });
            var frequencies = new int[size];
            for (int i = 0; i < accepted; i++) frequencies[indices[i]]++;
            foreach (int frequency in frequencies) Equal(frequency, 256 / size);
        }
        bool suppliedEff = false;
        var effIndices = Generator.UniformIndices(65536, Eff.WordCount, count =>
        {
            if (suppliedEff) return new byte[count];
            suppliedEff = true; Equal(count, 131072);
            var bytes = new byte[count];
            for (int i = 0; i < 32768; i++) { BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(i * 4), (ushort)i); BinaryPrimitives.WriteUInt16BigEndian(bytes.AsSpan(i * 4 + 2), (ushort)(65535 - i)); }
            return bytes;
        });
        var counts = new int[Eff.WordCount];
        // Complete domain's accepted portion includes interleaved invalid values; count accepted from that first provider response.
        int acceptedEff = 65536 - 65536 % Eff.WordCount;
        for (int i = 0; i < acceptedEff; i++) counts[effIndices[i]]++;
        foreach (int frequency in counts) Equal(frequency, 8);
        Equal(Generator.UniformIndices(0, 1, _ => throw new InvalidOperationException()).Length, 0);
    }
    private void NegativeTests()
    {
        var generator = new Generator();
        foreach (var mode in Enum.GetValues<GeneratorMode>())
        {
            var range = mode.LengthRange();
            foreach (int length in new[] { -1, 0, range.Min - 1, range.Max + 1, int.MaxValue })
            {
                var configuration = new GeneratorConfiguration(mode, length);
                Equal(configuration.EntropyBits, 0.0);
                Throws<ArgumentOutOfRangeException>(() => generator.Generate(configuration, _ => throw new InvalidOperationException("invalid config touched RNG")));
            }
            foreach (int delta in new[] { -1, 1 }) Throws<CryptographicException>(() => generator.Generate(new(mode, mode.DefaultLength()), count => new byte[count + delta]));
            Throws<CryptographicException>(() => generator.Generate(new(mode, mode.DefaultLength()), _ => null!));
            Throws<IOException>(() => generator.Generate(new(mode, mode.DefaultLength()), _ => throw new IOException("provider failed")));
        }
        foreach (int invalid in new[] { 13, 14, 16, 17, 19, 20, 22, 23 }) Throws<ArgumentOutOfRangeException>(() => generator.Generate(new(GeneratorMode.Bip39, invalid), _ => throw new InvalidOperationException()));
        foreach (var mode in new[] { GeneratorMode.Eff, GeneratorMode.Ascii, GeneratorMode.Pin })
        {
            int calls = 0;
            using var result = generator.Generate(new(mode, mode.LengthRange().Min), count => Enumerable.Repeat(calls++ == 0 ? (byte)255 : (byte)0, count).ToArray());
            Equal(calls, 2); Equal(result.ComponentCount, mode.LengthRange().Min);
        }
        int supplied = 0;
        Throws<CryptographicException>(() => generator.Generate(new(GeneratorMode.Pin, 3), count => { supplied += count; return Enumerable.Repeat((byte)255, count).ToArray(); }));
        Check(supplied <= 1026);
        Throws<ArgumentOutOfRangeException>(() => SecureRandom.Bytes(-1)); Throws<ArgumentOutOfRangeException>(() => SecureRandom.Bytes(1048577)); Equal(SecureRandom.Bytes(0).Length, 0);
        using var broken = new PasswordByteStream(new byte[256], count => count == 32 ? new byte[31] : new byte[count]);
        Equal(broken.Bytes(16).Length, 16); Throws<CryptographicException>(() => broken.Bytes(32)); Throws<ObjectDisposedException>(() => broken.Bytes(1));
        using var unavailable = new PasswordByteStream(new byte[256], count => count == 32 ? throw new IOException("provider failed") : new byte[count]);
        Equal(unavailable.Bytes(16).Length, 16); Throws<IOException>(() => unavailable.Bytes(32)); Throws<ObjectDisposedException>(() => unavailable.Bytes(0));
        byte[] malformed = Enumerable.Repeat((byte)0x9d, 31).ToArray();
        Throws<CryptographicException>(() => generator.Generate(new(GeneratorMode.Bip39, 24), _ => malformed));
        Check(malformed.All(b => b == 0), "Malformed RNG bytes must be erased on rejection");
        using var valid = new PasswordByteStream(new byte[256], count => new byte[count]);
        Throws<ArgumentOutOfRangeException>(() => valid.Bytes(-1)); Throws<ArgumentOutOfRangeException>(() => valid.Bytes(1048577)); Equal(valid.Bytes(1).Length, 1);
    }
    private void PipelineVectors()
    {
        using var fixtures = Fixture("pipeline_expected.json");
        foreach (var fixture in fixtures.RootElement.GetProperty("cases").EnumerateArray())
        {
            var source = new PipelineRandomSource(fixture.GetProperty("randomStyle").GetString()!);
            using var pool = new EntropyPool(source.Bytes);
            var shuffleAfter = fixture.GetProperty("shuffleAfterRecords").EnumerateArray().Select(e => e.GetInt32()).ToHashSet();
            int recordCount = fixture.GetProperty("recordCount").GetInt32();
            for (int i = 0; i < recordCount; i++) { pool.Absorb(Record(i)); if (shuffleAfter.Contains(i + 1)) pool.Shuffle(); }
            using var stream = pool.MakeStream();
            Equal(pool.EventCount, 4096); Equal(pool.AbsorbedEventCount, (ulong)recordCount); Equal(pool.ShuffleCount, 2 + shuffleAfter.Count);
            Check(source.Requests.SequenceEqual(fixture.GetProperty("randomRequestByteCounts").EnumerateArray().Select(e => e.GetInt32())), "OS request sequence differs");
            var output = new List<byte>();
            foreach (int count in new[] { 0, 1, 14, 1, 1, 110, 1, 1, 6, 1, 1, 119, 128, 136, 137, 367 }) output.AddRange(stream.Bytes(count));
            Bytes(output.ToArray(), Hex(fixture, "output"), fixture.GetProperty("name").GetString()!); Equal(source.OutputOffset, 1024);
            var generator = new Generator();
            foreach (var password in fixture.GetProperty("passwords").EnumerateArray())
            {
                int offset = 0;
                using var result = generator.Generate(new(Enum.Parse<GeneratorMode>(password.GetProperty("mode").GetString()!, true), password.GetProperty("length").GetInt32()), count => { var bytes = output.GetRange(offset, count).ToArray(); offset += count; return bytes; });
                Equal(result.Text, password.GetProperty("text").GetString(), fixture.GetProperty("name").GetString()!);
            }
        }
    }
    private void BitShuffleTests()
    {
        using var fixtures = Fixture("pipeline_expected.json");
        foreach (var fixture in fixtures.RootElement.GetProperty("cases").EnumerateArray())
        {
            var source = new PipelineRandomSource(fixture.GetProperty("randomStyle").GetString()!) { ShuffleBufferIndex = fixture.GetProperty("recordShuffleRandomRequests").GetInt32() };
            byte[] mask = source.Bytes(256), digest = Hex(fixture, "digest");
            Bytes(mask, Hex(fixture, "preShuffleMask"));
            for (int i = 0; i < digest.Length; i++) digest[i] ^= mask[i];
            Bytes(digest, Hex(fixture, "maskedDigest"));
            int bits = digest.Sum(b => System.Numerics.BitOperations.PopCount((uint)b));
            EntropyPool.ShuffleDigestBits(digest, source.Bytes);
            Equal(digest.Sum(b => System.Numerics.BitOperations.PopCount((uint)b)), bits); Bytes(digest, Hex(fixture, "shuffledDigest"));
            byte[] masterMask = source.Bytes(256); Bytes(masterMask, Hex(fixture, "masterMask"));
            for (int i = 0; i < digest.Length; i++) digest[i] ^= masterMask[i];
            Bytes(digest, Hex(fixture, "master"));
        }
        byte[] original = Enumerable.Range(0, 256).Select(i => (byte)(i * 73 + 19)).ToArray(), shuffled = original.ToArray();
        byte[] expected = Enumerable.Range(0, 256).Select(i => (byte)((original[i] >> 1) | ((original[(i + 1) % 256] & 1) << 7))).ToArray();
        EntropyPool.ShuffleDigestBits(shuffled, count => new byte[count]); Bytes(shuffled, expected);
        Throws<ArgumentException>(() => EntropyPool.ShuffleDigestBits(new byte[255], SecureRandom.Bytes));
        Throws<CryptographicException>(() => EntropyPool.ShuffleDigestBits(new byte[256], count => Enumerable.Repeat((byte)255, count).ToArray()));
    }
    private void PoolAndMemoryTests()
    {
        int calls = 0;
        using var pool = new EntropyPool(count => { calls++; return new byte[count]; });
        for (int i = 0; i < 4095; i++) pool.Absorb(Record(i));
        Throws<InvalidOperationException>(() => pool.MakeStream()); Equal(calls, 0);
        pool.Absorb(Record(4095));
        using var stream = pool.MakeStream(); Equal(stream.Bytes(32).Length, 32);
        for (int i = 4096; i < 8192; i++) pool.Absorb(Record(i)); Equal(pool.EventCount, 4096); Equal(pool.AbsorbedEventCount, 8192UL);
        pool.Clear(); pool.Clear(); pool.Absorb(Record(0)); Equal(pool.EventCount, 0); Equal(pool.AbsorbedEventCount, 0UL);
        Throws<ObjectDisposedException>(() => pool.MakeStream()); Throws<ObjectDisposedException>(() => pool.Shuffle());
        stream.Clear(); Throws<ObjectDisposedException>(() => stream.Bytes(0));
        using var stalled = new EntropyPool(count => Enumerable.Repeat((byte)255, count).ToArray());
        for (int i = 0; i < 4096; i++) stalled.Absorb(Record(i)); Throws<CryptographicException>(() => stalled.Shuffle());
        foreach (int failureAt in new[] { 4096, 256, 32 })
        {
            using var bad = new EntropyPool(count => new byte[count == failureAt ? count - 1 : count]);
            for (int i = 0; i < 4096; i++) bad.Absorb(Record(i));
            if (failureAt == 32) { using var badStream = bad.MakeStream(); Throws<CryptographicException>(() => badStream.Bytes(32)); Throws<ObjectDisposedException>(() => badStream.Bytes(16)); }
            else Throws<CryptographicException>(() => bad.MakeStream());
        }
        foreach (int failedMask in new[] { 1, 2 })
        {
            foreach (bool malformedReturn in new[] { false, true })
            {
                int masks = 0;
                var requests = new List<int>();
                using var badMask = new EntropyPool(count =>
                {
                    requests.Add(count);
                    if (count == 256 && ++masks == failedMask)
                    {
                        if (malformedReturn) return new byte[count - 1];
                        throw new IOException("mask RNG failed");
                    }
                    return new byte[count];
                });
                for (int i = 0; i < 4096; i++) badMask.Absorb(Record(i));
                if (malformedReturn) Throws<CryptographicException>(() => badMask.MakeStream()); else Throws<IOException>(() => badMask.MakeStream());
                var expected = new List<int> { 4096, 4096, 4096, 4096, 256 };
                if (failedMask == 2) expected.AddRange([4096, 4096, 256]);
                Check(requests.SequenceEqual(expected), "Failure of either master mask must stop later RNG reads"); Equal(masks, failedMask);
            }
        }
        using var password = new Generator().Generate(new(GeneratorMode.Hex, 512), count => Enumerable.Repeat((byte)175, count).ToArray());
        Equal(password.ExportText(uppercaseHex: true), new string('F', 512));
        // Only the owned allocation is expected to clear; exported strings are intentionally outside its control.
        object storage = typeof(GeneratedPassword).GetField("storage", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(password)!;
        password.Clear(); Equal(password.Text, ""); Equal(password.ComponentCount, 0);
        Equal((bool)storage.GetType().GetProperty("IsCleared")!.GetValue(storage)!, true);
    }
    private void MetricsTests()
    {
        foreach (var pair in new[] { (-1.0, NominalSecurityLevel.Below128), (127.999, NominalSecurityLevel.Below128), (128.0, NominalSecurityLevel.AtLeast128), (255.999, NominalSecurityLevel.AtLeast128), (256.0, NominalSecurityLevel.AtLeast256), (1023.999, NominalSecurityLevel.AtLeast256), (1024.0, NominalSecurityLevel.AtLeast1024), (double.NaN, NominalSecurityLevel.Below128), (double.PositiveInfinity, NominalSecurityLevel.Below128) }) Equal(NominalSecurityLevelExtensions.FromBits(pair.Item1), pair.Item2);
        foreach (double invalid in new[] { -1.0, double.NaN, double.PositiveInfinity, double.NegativeInfinity }) Throws<ArgumentOutOfRangeException>(() => new AttackCostEstimate(invalid));
        var zero = new AttackCostEstimate(0); Equal(zero.Classic.Log10Seconds, -18.0); Equal(zero.ClassicalMeanLog10Seconds, -18.0);
        var model = AttackCostEstimate.StandardModel;
        foreach (double bits in new[] { 0.0, 128, 256, 512, 1024, 2048 })
        {
            var estimate = new AttackCostEstimate(bits);
            Check(Math.Abs(estimate.Classic.Log10Seconds - (bits * Math.Log10(2) - 18)) < 1e-12);
            Check(Math.Abs(estimate.Grover.Log10Seconds - (Math.Log10(Math.PI / 4) + bits / 2 * Math.Log10(2) - 15)) < 1e-12);
            Check(Math.Abs(estimate.Classic.Log10Years - (estimate.Classic.Log10Seconds - Math.Log10(model.SecondsPerYear))) < 1e-12);
        }
        Check(!new AttackCostEstimate(model.ClassicalLandauerThresholdBits).Classic.ExceedsLandauerBudget);
        Check(new AttackCostEstimate(model.ClassicalLandauerThresholdBits + 0.001).Classic.ExceedsLandauerBudget);
        Check(!new AttackCostEstimate(model.GroverLandauerThresholdBits).Grover.ExceedsLandauerBudget);
        Check(new AttackCostEstimate(model.GroverLandauerThresholdBits + 0.001).Grover.ExceedsLandauerBudget);
        Check(!new AttackCostEstimate(model.ClassicalCosmicTimeThresholdBits).Classic.ExceedsCosmicTimeHorizon);
        Check(new AttackCostEstimate(model.ClassicalCosmicTimeThresholdBits + 0.001).Classic.ExceedsCosmicTimeHorizon);
        Check(!new AttackCostEstimate(model.GroverCosmicTimeThresholdBits).Grover.ExceedsCosmicTimeHorizon);
        Check(new AttackCostEstimate(model.GroverCosmicTimeThresholdBits + 0.001).Grover.ExceedsCosmicTimeHorizon);
    }
}

internal sealed class PipelineRandomSource(string style)
{
    public int ShuffleBufferIndex { get; set; }
    public int OutputOffset { get; private set; }
    private int maskReadCount;
    public List<int> Requests { get; } = [];
    public byte[] Bytes(int count)
    {
        Requests.Add(count);
        var bytes = new byte[count];
        if (count == 4096)
        {
            int bufferIndex = ShuffleBufferIndex++;
            if (style == "zero") return bytes;
            for (int i = 0; i < 1024; i++)
            {
                uint value = i < 2 ? uint.MaxValue : i == 2 ? 0 : unchecked((uint)((bufferIndex * 1024L + i) * 0x9e3779b9L + 0x7f4a7c15L));
                BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(i * 4), value);
            }
            return bytes;
        }
        if (count == 256 && maskReadCount < 2)
        {
            bool first = maskReadCount++ == 0;
            for (int i = 0; i < count; i++) bytes[i] = style == "zero" ? (first ? (byte)0x3c : (byte)0xa5) : unchecked((byte)(i * (first ? 19 : 37) + (first ? 0x3c : 0xa5)));
            return bytes;
        }
        for (int i = 0; i < count; i++) bytes[i] = style == "zero" ? (byte)0x5a : unchecked((byte)((OutputOffset + i) * 53 + 0x5a));
        OutputOffset += count;
        return bytes;
    }
}
