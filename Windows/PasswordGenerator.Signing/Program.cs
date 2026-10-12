using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using PasswordGenerator.Security;
using PasswordGenerator.Signing;
using PasswordGenerator.Core;

try
{
    if (args.Length < 2) throw new ArgumentException("Usage: provision KEY-DIR PUBLIC-DIR | sign KEY-DIR APP-DIR | verify APP-DIR | sign-file KEY-DIR FILE");
    switch (args[0])
    {
        case "provision" when args.Length == 3: Provision(args[1], args[2]); break;
        case "sign" when args.Length == 3:
            var inventory = HybridIntegrity.CreateInventory(args[2]);
            var manifest = Path.Combine(args[2], HybridIntegrity.ManifestName);
            File.WriteAllBytes(manifest, JsonSerializer.SerializeToUtf8Bytes(inventory, HybridIntegrity.JsonOptions));
            Sign(args[1], manifest, Path.Combine(args[2], HybridIntegrity.RsaSignatureName), Path.Combine(args[2], HybridIntegrity.MlSignatureName));
            Console.WriteLine($"Signed inventory: {inventory.Files.Length} files, {inventory.Directories.Length} directories.");
            break;
        case "verify" when args.Length == 2:
            var verified = HybridIntegrity.VerifyDirectory(args[1]);
            Console.WriteLine($"RSA-4096 AND ML-DSA-87 verified; exact inventory: {verified.Files.Length} files.");
            break;
        case "sign-file" when args.Length == 3:
            Sign(args[1], args[2], args[2] + ".rsa.sig", args[2] + ".mldsa87.sig");
            Console.WriteLine("Both detached artifact signatures created.");
            break;
        default: throw new ArgumentException("Invalid signing command.");
    }
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine("Signing/verification FAILED: " + error.Message);
    return 1;
}

static void Provision(string keyDirectory, string publicDirectory)
{
    if (!OperatingSystem.IsWindows() || !MLDsa.IsSupported) throw new PlatformNotSupportedException("Windows CNG ML-DSA is required.");
    string root = Path.GetFullPath(keyDirectory);
    if (Directory.Exists(root) && Directory.EnumerateFileSystemEntries(root).Any())
        throw new IOException("Refusing to overwrite a nonempty key directory.");
    Directory.CreateDirectory(root);
    HybridIntegrity.RejectReparse(root);
    Directory.CreateDirectory(publicDirectory);
    using var rsa = RSA.Create(4096);
    var request = new CertificateRequest("CN=Password Generator Windows Release", rsa, HashAlgorithmName.SHA512, RSASignaturePadding.Pkcs1);
    request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
    request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
    var oids = new OidCollection { new Oid("1.3.6.1.5.5.7.3.3") };
    request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(oids, false));
    using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddYears(5));
    byte[] passwordBytes = [], passwordUtf8 = [], pfx = [], mlPrivate = [];
    try
    {
        passwordBytes = RandomNumberGenerator.GetBytes(48);
        string password = Convert.ToBase64String(passwordBytes);
        passwordUtf8 = Encoding.UTF8.GetBytes(password);
        pfx = certificate.ExportPkcs12(new PbeParameters(PbeEncryptionAlgorithm.Aes256Cbc, HashAlgorithmName.SHA256, 200_000), password);
        using var ml = MLDsa.GenerateKey(MLDsaAlgorithm.MLDsa87);
        mlPrivate = ml.ExportPkcs8PrivateKey();
        File.WriteAllBytes(Path.Combine(root, "rsa4096-private.pfx"), pfx);
        File.WriteAllBytes(Path.Combine(root, "rsa4096-password.dpapi"), Dpapi.Transform(passwordUtf8, true));
        File.WriteAllBytes(Path.Combine(root, "mldsa87-private.pkcs8.dpapi"), Dpapi.Transform(mlPrivate, true));
        byte[] spki = rsa.ExportSubjectPublicKeyInfo();
        byte[] raw = ml.ExportMLDsaPublicKey();
        byte[] mlSpki = ml.ExportSubjectPublicKeyInfo();
        foreach (string destination in new[] { root, Path.GetFullPath(publicDirectory) })
        {
            File.WriteAllBytes(Path.Combine(destination, "rsa4096-spki.der"), spki);
            File.WriteAllBytes(Path.Combine(destination, "rsa4096-certificate.cer"), certificate.Export(X509ContentType.Cert));
            File.WriteAllBytes(Path.Combine(destination, "mldsa87-public.bin"), raw);
            File.WriteAllBytes(Path.Combine(destination, "mldsa87-spki.der"), mlSpki);
        }
        var proof = new { product = HybridIntegrity.Product, version = HybridIntegrity.Version,
            build = HybridIntegrity.Build, protection = "RSA encrypted PKCS12 AES256-CBC/PBKDF2-SHA256 200000; password and ML-DSA PKCS8 DPAPI CurrentUser",
            rsaSpkiSha256 = Convert.ToHexString(SHA256.HashData(spki)), mlDsaPublicSha256 = Convert.ToHexString(SHA256.HashData(raw)),
            rsaSpkiSha3_512 = Convert.ToHexString(SHA3_512.HashData(spki)), rsaSpkiSkein1024 = Convert.ToHexString(Skein.Hash1024(spki)),
            mlDsaPublicSha3_512 = Convert.ToHexString(SHA3_512.HashData(raw)), mlDsaPublicSkein1024 = Convert.ToHexString(Skein.Hash1024(raw)),
            certificateSha256 = Convert.ToHexString(SHA256.HashData(certificate.RawData)) };
        File.WriteAllText(Path.Combine(publicDirectory, "trust.json"), JsonSerializer.Serialize(proof, HybridIntegrity.JsonOptions));
        Console.WriteLine("Created and encrypted independent RSA-4096/ML-DSA-87 signing keys; public anchors exported.");
    }
    finally
    {
        CryptographicOperations.ZeroMemory(passwordBytes);
        CryptographicOperations.ZeroMemory(passwordUtf8);
        CryptographicOperations.ZeroMemory(pfx);
        CryptographicOperations.ZeroMemory(mlPrivate);
    }
}

static void Sign(string keyDirectory, string file, string rsaOutput, string mlOutput)
{
    byte[] password = [], privateKey = [];
    try
    {
        password = Dpapi.Transform(File.ReadAllBytes(Path.Combine(keyDirectory, "rsa4096-password.dpapi")), false);
        privateKey = Dpapi.Transform(File.ReadAllBytes(Path.Combine(keyDirectory, "mldsa87-private.pkcs8.dpapi")), false);
        using var cert = X509CertificateLoader.LoadPkcs12(File.ReadAllBytes(Path.Combine(keyDirectory, "rsa4096-private.pfx")),
            Encoding.UTF8.GetString(password), X509KeyStorageFlags.EphemeralKeySet);
        using var rsa = cert.GetRSAPrivateKey() ?? throw new CryptographicException("Missing RSA key.");
        using var ml = MLDsa.ImportPkcs8PrivateKey(privateKey);
        if (rsa.KeySize != 4096 || ml.Algorithm != MLDsaAlgorithm.MLDsa87) throw new CryptographicException("Wrong signing algorithm.");
        byte[] data = File.ReadAllBytes(file);
        byte[] payload = HybridIntegrity.SigningPayload(data);
        byte[] rs = rsa.SignData(payload, HashAlgorithmName.SHA512, RSASignaturePadding.Pss);
        byte[] ms = ml.SignData(payload, HybridIntegrity.Context);
        if (!rsa.VerifyData(payload, rs, HashAlgorithmName.SHA512, RSASignaturePadding.Pss) || !ml.VerifyData(payload, ms, HybridIntegrity.Context))
            throw new CryptographicException("Signing self-verification failed.");
        File.WriteAllBytes(rsaOutput, rs);
        File.WriteAllBytes(mlOutput, ms);
    }
    finally
    {
        CryptographicOperations.ZeroMemory(password);
        CryptographicOperations.ZeroMemory(privateKey);
    }
}
