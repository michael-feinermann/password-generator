using System.Buffers.Binary;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PasswordGenerator.Security;

public sealed record InventoryFile(string Path, long Size, string Sha512);
public sealed record ReleaseInventory(int Schema, string Product, string Version, int Build,
    string Architecture, InventoryFile[] Files, string[] Directories);

public static class HybridIntegrity
{
    public const string ManifestName = "windows-release.json";
    public const string RsaSignatureName = "windows-release.rsa.sig";
    public const string MlSignatureName = "windows-release.mldsa87.sig";
    public const string Product = "com.feinermann.passwordgenerator.windows";
    public const string Version = "2.3.6";
    public const int Build = 14;
    public static readonly byte[] Context = Encoding.ASCII.GetBytes("PasswordGenerator.Windows.2.3.6");
    static readonly HashSet<string> Sidecars = new(StringComparer.OrdinalIgnoreCase)
        { ManifestName, RsaSignatureName, MlSignatureName };
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        WriteIndented = true,
        MaxDepth = 8
    };

    public static byte[] SigningPayload(ReadOnlySpan<byte> manifest)
    {
        var domain = Encoding.ASCII.GetBytes("PasswordGenerator.Windows.Inventory.v1\0");
        byte[] payload = new byte[domain.Length + 8 + 64];
        domain.CopyTo(payload, 0);
        BinaryPrimitives.WriteInt64LittleEndian(payload.AsSpan(domain.Length), manifest.Length);
        SHA512.HashData(manifest, payload.AsSpan(domain.Length + 8));
        return payload;
    }

    public static byte[] ReadEmbeddedKey(string name)
    {
        using var stream = typeof(HybridIntegrity).Assembly.GetManifestResourceStream(name)
            ?? throw new CryptographicException("Missing compiled trust anchor.");
        using var output = new MemoryStream();
        stream.CopyTo(output);
        return output.ToArray();
    }

    public static ReleaseInventory VerifyDirectory(string directory)
        => VerifyDirectory(directory, ReadEmbeddedKey("Signing.Rsa"), ReadEmbeddedKey("Signing.MlDsa"));

    public static ReleaseInventory VerifyDirectory(string directory, byte[] rsaPublic, byte[] mlPublic)
    {
        if (!MLDsa.IsSupported) throw new PlatformNotSupportedException("Windows CNG with ML-DSA support is required.");
        var root = Path.GetFullPath(directory);
        RejectReparse(root);
        var manifest = ReadBounded(Path.Combine(root, ManifestName), 4 * 1024 * 1024);
        var rsaSig = ReadBounded(Path.Combine(root, RsaSignatureName), 512);
        var mlSig = ReadBounded(Path.Combine(root, MlSignatureName), 4627);
        if (rsaSig.Length != 512 || mlSig.Length != 4627 || mlPublic.Length != 2592)
            throw new CryptographicException("Invalid release signature length.");
        using var rsa = RSA.Create();
        rsa.ImportSubjectPublicKeyInfo(rsaPublic, out int consumed);
        if (consumed != rsaPublic.Length || rsa.KeySize != 4096)
            throw new CryptographicException("Invalid RSA-4096 trust anchor.");
        var payload = SigningPayload(manifest);
        if (!rsa.VerifyData(payload, rsaSig, HashAlgorithmName.SHA512, RSASignaturePadding.Pss))
            throw new CryptographicException("RSA-4096 release signature rejected.");
        using var ml = MLDsa.ImportMLDsaPublicKey(MLDsaAlgorithm.MLDsa87, mlPublic);
        if (!ml.VerifyData(payload, mlSig, Context))
            throw new CryptographicException("ML-DSA-87 release signature rejected.");
        var inventory = JsonSerializer.Deserialize<ReleaseInventory>(manifest, JsonOptions)
            ?? throw new CryptographicException("Invalid release inventory.");
        if (inventory.Schema != 1 || inventory.Product != Product || inventory.Version != Version
            || inventory.Build != Build || inventory.Architecture != "win-x64"
            || inventory.Files is null || inventory.Directories is null || inventory.Files.Length is < 1 or > 4096
            || inventory.Directories.Length > 4096)
            throw new CryptographicException("Release identity or bounds mismatch.");
        var expectedFiles = new Dictionary<string, InventoryFile>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in inventory.Files)
        {
            CheckPath(item.Path);
            if (Sidecars.Contains(item.Path) || item.Size < 0 || item.Size > 512L * 1024 * 1024
                || item.Sha512 is null || item.Sha512.Length != 128 || !item.Sha512.All(Uri.IsHexDigit)
                || !expectedFiles.TryAdd(item.Path, item))
                throw new CryptographicException("Invalid or duplicate inventory file.");
        }
        var expectedDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in inventory.Directories)
        {
            CheckPath(item);
            if (expectedFiles.ContainsKey(item) || !expectedDirs.Add(item))
                throw new CryptographicException("Invalid or duplicate inventory directory.");
        }
        var actualFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var actualDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        Walk(root, root, actualFiles, actualDirs);
        if (!actualFiles.SetEquals(expectedFiles.Keys) || !actualDirs.SetEquals(expectedDirs))
            throw new CryptographicException("Installed file or directory set differs from signed inventory.");
        foreach (var item in expectedFiles.Values)
        {
            var path = Path.Combine(root, item.Path.Replace('/', Path.DirectorySeparatorChar));
            RejectReparse(path);
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length != item.Size || !CryptographicOperations.FixedTimeEquals(
                SHA512.HashData(file), Convert.FromHexString(item.Sha512)))
                throw new CryptographicException("Installed file integrity rejected: " + item.Path);
        }
        return inventory;
    }

    public static ReleaseInventory CreateInventory(string directory)
    {
        string root = Path.GetFullPath(directory);
        RejectReparse(root);
        var files = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        Walk(root, root, files, dirs);
        var records = files.Order(StringComparer.Ordinal).Select(relative =>
        {
            using var input = new FileStream(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)),
                FileMode.Open, FileAccess.Read, FileShare.Read);
            return new InventoryFile(relative, input.Length, Convert.ToHexString(SHA512.HashData(input)).ToLowerInvariant());
        }).ToArray();
        return new ReleaseInventory(1, Product, Version, Build, "win-x64", records, dirs.Order(StringComparer.Ordinal).ToArray());
    }

    static void Walk(string root, string directory, HashSet<string> files, HashSet<string> dirs)
    {
        foreach (var path in Directory.EnumerateFileSystemEntries(directory))
        {
            RejectReparse(path);
            var relative = Path.GetRelativePath(root, path).Replace('\\', '/');
            CheckPath(relative);
            if (Directory.Exists(path))
            {
                if (!dirs.Add(relative) || files.Count + dirs.Count > 8192)
                    throw new CryptographicException("Excessive or aliased release entries.");
                Walk(root, path, files, dirs);
            }
            else if (!(directory == root && Sidecars.Contains(relative)))
            {
                if (!files.Add(relative) || files.Count + dirs.Count > 8192)
                    throw new CryptographicException("Excessive or aliased release entries.");
            }
        }
    }

    public static void CheckPath(string path)
    {
        if (string.IsNullOrEmpty(path) || path.Length > 240 || path.Contains('\\') || path.Contains(':')
            || path.Split('/').Any(p => p is "" or "." or ".." || p.EndsWith(' ') || p.EndsWith('.')
                || p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
            throw new CryptographicException("Unsafe release path.");
    }

    static byte[] ReadBounded(string path, int maximum)
    {
        RejectReparse(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length < 1 || input.Length > maximum) throw new CryptographicException("Invalid release metadata size.");
        byte[] result = new byte[checked((int)input.Length)];
        input.ReadExactly(result);
        return result;
    }

    public static void RejectReparse(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new CryptographicException("Reparse points are forbidden in the release.");
    }
}
