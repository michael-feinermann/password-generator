using System.Security.Cryptography;
using System.Text.Json;
using System.Diagnostics;
using PasswordGenerator.Security;

var root = Path.Combine(Path.GetTempPath(), "PasswordGeneratorSecurityTests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
using var rsa = RSA.Create(4096);
using var ml = MLDsa.GenerateKey(MLDsaAlgorithm.MLDsa87);
byte[] rp = rsa.ExportSubjectPublicKeyInfo(), mp = ml.ExportMLDsaPublicKey();
int passed = 0;
byte[] original = [];
try
{
    File.WriteAllText(Path.Combine(root, "app.exe"), "test fixture, never executable");
    Directory.CreateDirectory(Path.Combine(root, "resources"));
    File.WriteAllText(Path.Combine(root, "resources", "words.txt"), "alpha beta");
    var inventory = HybridIntegrity.CreateInventory(root);
    original = JsonSerializer.SerializeToUtf8Bytes(inventory, HybridIntegrity.JsonOptions);
    Sign(original);
    Positive("both signatures and exact inventory", () => HybridIntegrity.VerifyDirectory(root, rp, mp));
    Negative("manifest mutation", () => File.AppendAllText(Path.Combine(root, HybridIntegrity.ManifestName), " "));
    Negative("manifest truncated", () => File.WriteAllBytes(Path.Combine(root, HybridIntegrity.ManifestName), []));
    Negative("RSA mutation", () => Mutate(HybridIntegrity.RsaSignatureName));
    Negative("ML-DSA mutation", () => Mutate(HybridIntegrity.MlSignatureName));
    Negative("RSA truncated", () => File.WriteAllBytes(Path.Combine(root, HybridIntegrity.RsaSignatureName), new byte[511]));
    Negative("ML-DSA trailing byte", () => File.WriteAllBytes(Path.Combine(root, HybridIntegrity.MlSignatureName), new byte[4628]));
    Negative("file modified", () => File.WriteAllText(Path.Combine(root, "app.exe"), "changed"),
        () => File.WriteAllText(Path.Combine(root, "app.exe"), "test fixture, never executable"));
    Negative("extra file", () => File.WriteAllText(Path.Combine(root, "extra.dll"), "extra"),
        () => File.Delete(Path.Combine(root, "extra.dll")));
    Negative("extra directory", () => Directory.CreateDirectory(Path.Combine(root, "extra")),
        () => Directory.Delete(Path.Combine(root, "extra")));
    Negative("missing file", () => File.Move(Path.Combine(root, "resources", "words.txt"), Path.Combine(root, "words.old")),
        () => File.Move(Path.Combine(root, "words.old"), Path.Combine(root, "resources", "words.txt")));
    SignedNegative("wrong product", inventory with { Product = "other.product" });
    SignedNegative("wrong version", inventory with { Version = "2.3.5" });
    SignedNegative("wrong build", inventory with { Build = 13 });
    SignedNegative("wrong architecture", inventory with { Architecture = "win-arm64" });
    SignedNegative("unknown schema", inventory with { Schema = 2 });
    SignedNegative("path traversal", inventory with { Files = [inventory.Files[0] with { Path = "../app.exe" }] });
    SignedNegative("alternate stream", inventory with { Files = [inventory.Files[0] with { Path = "app.exe:stream" }] });
    SignedNegative("case alias", inventory with { Files = [inventory.Files[0], inventory.Files[0] with { Path = "APP.EXE" }, inventory.Files[1]] });
    SignedNegative("directory aliases file", inventory with { Directories = ["app.exe"] });
    SignedNegative("negative size", inventory with { Files = [inventory.Files[0] with { Size = -1 }, inventory.Files[1]] });
    SignedNegative("invalid digest", inventory with { Files = [inventory.Files[0] with { Sha512 = new string('z', 128) }, inventory.Files[1]] });
    SignedNegative("signed size mismatch", inventory with { Files = [inventory.Files[0] with { Size = inventory.Files[0].Size + 1 }, inventory.Files[1]] });
    SignedNegative("signed digest mismatch", inventory with { Files = [inventory.Files[0] with { Sha512 = new string('0', 128) }, inventory.Files[1]] });
    var unknownMember = System.Text.Encoding.UTF8.GetString(original).Replace("\"schema\": 1", "\"unrecognized\": true, \"schema\": 1");
    Sign(System.Text.Encoding.UTF8.GetBytes(unknownMember));
    ExpectRejected("unknown signed JSON member", () => HybridIntegrity.VerifyDirectory(root, rp, mp));
    Sign(original);
    string junction = Path.Combine(root, "junction");
    var psi = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
    psi.ArgumentList.Add("/c"); psi.ArgumentList.Add("mklink"); psi.ArgumentList.Add("/J");
    psi.ArgumentList.Add(junction); psi.ArgumentList.Add(Path.Combine(root, "resources"));
    using (var child = Process.Start(psi) ?? throw new IOException("Cannot create reparse fixture."))
    {
        if (!child.WaitForExit(10000) || child.ExitCode != 0) throw new IOException("Reparse fixture creation failed.");
    }
    try { ExpectRejected("actual directory junction", () => HybridIntegrity.VerifyDirectory(root, rp, mp)); }
    finally { Directory.Delete(junction); }
    Sign(original);
    ExpectRejected("wrong RSA anchor", () => { using var other = RSA.Create(4096); HybridIntegrity.VerifyDirectory(root, other.ExportSubjectPublicKeyInfo(), mp); });
    ExpectRejected("wrong ML-DSA anchor", () => { using var other = MLDsa.GenerateKey(MLDsaAlgorithm.MLDsa87); HybridIntegrity.VerifyDirectory(root, rp, other.ExportMLDsaPublicKey()); });
    foreach (var bad in new[] { "", "/root", "../file", "file\\path", "folder//file", "file.", "file ", "folder/../file", "f:stream" })
        ExpectRejected("unsafe path [" + bad + "]", () => HybridIntegrity.CheckPath(bad));
    Console.WriteLine($"PASS: {passed} security checks (positive, signatures, identity, inventory, paths).");
    return 0;
}
finally { Directory.Delete(root, true); }

void Sign(byte[] manifest)
{
    File.WriteAllBytes(Path.Combine(root, HybridIntegrity.ManifestName), manifest);
    var payload = HybridIntegrity.SigningPayload(manifest);
    File.WriteAllBytes(Path.Combine(root, HybridIntegrity.RsaSignatureName), rsa.SignData(payload, HashAlgorithmName.SHA512, RSASignaturePadding.Pss));
    File.WriteAllBytes(Path.Combine(root, HybridIntegrity.MlSignatureName), ml.SignData(payload, HybridIntegrity.Context));
}
void Mutate(string name) { var path = Path.Combine(root, name); var bytes = File.ReadAllBytes(path); bytes[^1] ^= 1; File.WriteAllBytes(path, bytes); }
void Positive(string name, Action action) { action(); passed++; Console.WriteLine("PASS " + name); }
void ExpectRejected(string name, Action action)
{
    bool rejected = false;
    try { action(); }
    catch (Exception error) when (error is CryptographicException or IOException or JsonException) { rejected = true; }
    if (!rejected) throw new Exception("SECURITY TEST FAILED: " + name);
    passed++; Console.WriteLine("PASS rejects " + name);
}
void Negative(string name, Action mutation, Action? cleanup = null)
{
    mutation();
    try { ExpectRejected(name, () => HybridIntegrity.VerifyDirectory(root, rp, mp)); }
    finally { cleanup?.Invoke(); Sign(original); }
}
void SignedNegative(string name, ReleaseInventory bad)
{
    Sign(JsonSerializer.SerializeToUtf8Bytes(bad, HybridIntegrity.JsonOptions));
    ExpectRejected(name, () => HybridIntegrity.VerifyDirectory(root, rp, mp));
    Sign(original);
}
