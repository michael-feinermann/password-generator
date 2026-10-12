"""Independent public RSA-PSS/SHA512 and ML-DSA87 interoperability verifier."""
import argparse
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--file", type=Path, required=True)
p.add_argument("--public-dir", type=Path, required=True)
p.add_argument("--openssl", type=Path, required=True)
p.add_argument("--inventory", action="store_true")
a = p.parse_args()
data = a.file.read_bytes()
payload = b"PasswordGenerator.Windows.Inventory.v1\0" + struct.pack("<q", len(data)) + hashlib.sha512(data).digest()
rsa = a.file.parent / ("windows-release.rsa.sig" if a.inventory else a.file.name + ".rsa.sig")
ml = a.file.parent / ("windows-release.mldsa87.sig" if a.inventory else a.file.name + ".mldsa87.sig")
if len(rsa.read_bytes()) != 512 or len(ml.read_bytes()) != 4627:
    raise ValueError("Invalid RSA/ML-DSA signature lengths")
with tempfile.TemporaryDirectory(prefix="PasswordGeneratorPublicVerification-") as temporary:
    path = Path(temporary) / "public-payload.bin"
    path.write_bytes(payload)
    common = [str(a.openssl), "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER", "-in", str(path)]
    subprocess.run(common + ["-inkey", str(a.public_dir / "rsa4096-spki.der"), "-sigfile", str(rsa),
        "-digest", "sha512", "-pkeyopt", "rsa_padding_mode:pss", "-pkeyopt", "rsa_pss_saltlen:64",
        "-pkeyopt", "rsa_mgf1_md:sha512"], check=True, timeout=120)
    subprocess.run(common + ["-inkey", str(a.public_dir / "mldsa87-spki.der"), "-sigfile", str(ml),
        "-pkeyopt", "context-string:PasswordGenerator.Windows.2.3.6", "-pkeyopt", "message-encoding:1"],
        check=True, timeout=120)
print("PASS independent OpenSSL RSA-4096/PSS/SHA512 AND ML-DSA-87 verification")
