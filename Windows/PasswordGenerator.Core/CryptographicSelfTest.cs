using System.Security.Cryptography;
using System.Text;

namespace PasswordGenerator.Core;

public static class CryptographicSelfTest
{
    public static void Run()
    {
        Check(SHA256.HashData("abc"u8), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256");
        Check(SHA512.HashData("abc"u8), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "SHA-512");
        Check(SHA3_512.HashData([]), "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26", "SHA3-512");
        Check(Skein.Hash1024([]), "0fff9563bb3279289227ac77d319b6fff8d7e9f09da1247b72a0a265cd6d2a62645ad547ed8193db48cff847c06494a03f55666d3b47eb4c20456c9373c86297d630d5578ebd34cb40991578f9f52b18003efa35d3da6553ff35db91b81ab890bec1b189b7f52cb2a783ebb7d823d725b0b4a71f6824e88f68f982eefc6d19c6", "Skein-1024-1024");
        using var skeinXof = new Skein1024XofStream([]);
        Check(skeinXof.Read(32), "643e13582daf9270f5b232682806e775530d6aad56f7d531c302c421db2834b3", "Skein-1024-XOF");
        using var shake = new Shake256Stream([]);
        byte[] first = shake.Read(1), rest = shake.Read(31);
        byte[] shakeOutput = [..first, ..rest];
        try { Check(shakeOutput, "46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f", "SHAKE256 advancing stream"); }
        finally { SecretMemory.Clear(first); SecretMemory.Clear(rest); }
        using var aes = new Aes256CtrStream(new byte[32]);
        Check(aes.Read(16), "dc95c078a2408989ad48a21492842087", "AES-256-CTR");
        var generator = new PasswordGenerator();
        using var password = generator.Generate(new GeneratorConfiguration(GeneratorMode.Bip39, 12), count => new byte[count]);
        if (password.Text != "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about") throw new CryptographicException("BIP-39 self-test failed.");
        byte[] osBytes = SecureRandom.Bytes(64);
        try { if (osBytes.All(b => b == 0)) throw new CryptographicException("Windows RNG self-test returned only zeros."); }
        finally { SecretMemory.Clear(osBytes); }
    }
    private static void Check(byte[] actual, string expected, string algorithm)
    {
        try { if (!CryptographicOperations.FixedTimeEquals(actual, Convert.FromHexString(expected))) throw new CryptographicException($"{algorithm} self-test failed."); }
        finally { SecretMemory.Clear(actual); }
    }
}
