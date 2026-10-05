#!/usr/bin/env python3
"""Verify detached Password Generator release signatures using public data only.

The KZVHSIG1 envelope and legacy domains are interoperable with Keep Vault's
HybridSigner. Both RSA-PSS/SHA-512 and pure ML-DSA-87 must verify. The trusted
public-key fingerprints must themselves come from an independently trusted
channel. This release check does not change the app's Apple-only runtime gate.
"""

import argparse
import hashlib
import hmac
import io
import json
import os
import pathlib
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile


PRODUCT_ID = "local.passwordgenerator.generator"
VERSION = "2.3.6"
BUILD = "13"
APP_NAME = "Password Generator 2.3.6.app"
STEM = "Password.Generator-2.3.6"
TARGETS = (STEM + ".zip", STEM + ".integrity.txt", STEM + ".bundle-inventory.json")
MAGIC = b"KZVHSIG1"
PAYLOAD_DOMAIN = b"KalynaZpaqVault/HybridArtifactSignature/SHA-512/v1\0"
ML_CONTEXT = "KalynaZpaqVault/HybridArtifactSignature/v1"
HEADER = struct.Struct("<8siq64siii")
MAX_SIDECAR = 65536
MAX_CERTIFICATE = 32768
MAX_TRUST = 65536
MAX_INVENTORY = 8 * 1024 * 1024
MAX_ZIP = 512 * 1024 * 1024
MAX_BUNDLE_BYTES = 512 * 1024 * 1024
MAX_ENTRIES = 100000
HASH_LENGTHS = {"sha256": 64, "sha3-512": 128, "skein-1024-1024": 256}


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def exact_keys(value, keys, name):
    require(type(value) is dict and set(value) == set(keys), "Invalid " + name + " schema")


def safe_path(value, basename=False):
    require(type(value) is str and 0 < len(value) <= 1024, "Invalid relative path")
    require(all(32 <= ord(c) <= 126 for c in value), "Paths must be printable ASCII")
    require("\\" not in value and ":" not in value, "Unsafe path separator")
    parts = value.split("/")
    require(all(part not in {"", ".", ".."} for part in parts), "Unsafe relative path")
    require(not basename or len(parts) == 1, "Public key must be a basename")
    return value


def read_regular(path, limit):
    """Bind reads to an open regular file, without following a final symlink."""
    path = pathlib.Path(path)
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as source:
            before = os.fstat(source.fileno())
            require(stat.S_ISREG(before.st_mode), "Nonregular input: " + path.name)
            require(0 <= before.st_size <= limit, "Input exceeds bound: " + path.name)
            data = source.read(limit + 1)
            after = os.fstat(source.fileno())
        current = path.lstat()
    except OSError as error:
        raise VerificationError("Cannot read public input: " + path.name) from error
    fields = ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns", "st_mode")
    require(all(getattr(before, f) == getattr(after, f) == getattr(current, f) for f in fields),
            "Input changed while reading: " + path.name)
    require(len(data) == before.st_size and len(data) <= limit, "Incomplete input: " + path.name)
    return data, stat.S_IMODE(before.st_mode)


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def parse_json(data):
    try:
        return json.loads(data.decode("utf-8"), object_pairs_hook=reject_duplicate_keys,
                          parse_constant=lambda value: (_ for _ in ()).throw(VerificationError("Invalid JSON number")))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise VerificationError("Invalid JSON") from error


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8") + b"\n"


def validate_hashes(value):
    exact_keys(value, HASH_LENGTHS, "fingerprints")
    for algorithm, length in HASH_LENGTHS.items():
        require(type(value[algorithm]) is str and re.fullmatch("[0-9a-f]{%d}" % length, value[algorithm]),
                "Invalid " + algorithm + " fingerprint")


def parse_trust(data):
    trust = parse_json(data)
    exact_keys(trust, {"schema", "product_id", "rsa_spki", "mldsa_public_key",
                       "rsa_spki_hashes", "mldsa_public_key_hashes"}, "trust")
    require(trust["schema"] == "password-generator-hybrid-trust-v1" and trust["product_id"] == PRODUCT_ID,
            "Wrong trust product or schema")
    safe_path(trust["rsa_spki"], basename=True)
    safe_path(trust["mldsa_public_key"], basename=True)
    require(trust["rsa_spki"] != trust["mldsa_public_key"], "Public key filenames must differ")
    validate_hashes(trust["rsa_spki_hashes"])
    validate_hashes(trust["mldsa_public_key_hashes"])
    return trust


def parse_inventory(data):
    inventory = parse_json(data)
    exact_keys(inventory, {"schema", "product_id", "version", "build", "app_name", "files", "directories"}, "inventory")
    expected = {"schema": "password-generator-bundle-inventory-v1", "product_id": PRODUCT_ID,
                "version": VERSION, "build": BUILD, "app_name": APP_NAME}
    require(all(inventory[key] == value for key, value in expected.items()), "Wrong inventory identity")
    require(type(inventory["files"]) is list and 0 < len(inventory["files"]) <= MAX_ENTRIES, "Invalid inventory files")
    require(type(inventory["directories"]) is list and len(inventory["directories"]) <= MAX_ENTRIES, "Invalid inventory directories")
    paths = []
    total = 0
    for item in inventory["files"]:
        exact_keys(item, {"path", "size", "mode", "sha512"}, "inventory file")
        paths.append(safe_path(item["path"]))
        require(type(item["size"]) is int and 0 <= item["size"] <= MAX_BUNDLE_BYTES, "Invalid file size")
        require(type(item["mode"]) is int and 0 <= item["mode"] <= 0o777, "Invalid file mode")
        require(type(item["sha512"]) is str and re.fullmatch(r"[0-9a-f]{128}", item["sha512"]), "Invalid file SHA-512")
        total += item["size"]
    require(total <= MAX_BUNDLE_BYTES, "Bundle exceeds size bound")
    require(paths == sorted(set(paths)), "Files must be sorted and unique")
    directories = [safe_path(path) for path in inventory["directories"]]
    require(directories == sorted(set(directories)), "Directories must be sorted and unique")
    require(not set(paths).intersection(directories), "Path is both file and directory")
    for path in paths + directories:
        parts = path.split("/")
        for index in range(1, len(parts)):
            require("/".join(parts[:index]) in directories, "Missing inventory parent directory")
    require("Contents/Info.plist" in paths, "Missing app metadata")
    require(data == canonical_json(inventory), "Inventory JSON is not canonical")
    return inventory


def parse_envelope(data, artifact):
    require(HEADER.size == 96 and 96 <= len(data) <= MAX_SIDECAR, "Invalid signature size")
    magic, version, length, digest, cert_length, rsa_length, ml_length = HEADER.unpack_from(data)
    require(magic == MAGIC and version == 1, "Unknown signature envelope")
    require(length >= 0 and length == len(artifact), "Signature file length mismatch")
    actual_digest = hashlib.sha512(artifact).digest()
    require(hmac.compare_digest(digest, actual_digest), "Signature SHA-512 binding mismatch")
    require(1 <= cert_length <= MAX_CERTIFICATE and rsa_length == 512 and ml_length == 4627,
            "Invalid signature field lengths")
    require(len(data) == 96 + cert_length + rsa_length + ml_length, "Truncated or trailing signature bytes")
    offset = 96
    certificate = data[offset:offset + cert_length]
    offset += cert_length
    rsa = data[offset:offset + rsa_length]
    ml = data[offset + rsa_length:]
    payload = PAYLOAD_DOMAIN + struct.pack("<q", length) + actual_digest
    return certificate, rsa, ml, payload


def der(tag, content):
    length = len(content)
    if length < 128:
        prefix = bytes([length])
    else:
        encoded = length.to_bytes((length.bit_length() + 7) // 8, "big")
        prefix = bytes([0x80 | len(encoded)]) + encoded
    return bytes([tag]) + prefix + content


def mldsa_spki(raw):
    require(len(raw) == 2592, "ML-DSA-87 public key must contain exactly 2592 bytes")
    algorithm = bytes.fromhex("300b0609608648016503040313")
    return der(0x30, algorithm + der(0x03, b"\0" + raw))


def validate_der_sequence(data):
    require(len(data) >= 2 and data[0] == 0x30, "Invalid certificate DER")
    first = data[1]
    if first < 128:
        length, header_size = first, 2
    else:
        count = first & 127
        require(1 <= count <= 4 and len(data) >= 2 + count and data[2] != 0, "Invalid DER length")
        length, header_size = int.from_bytes(data[2:2 + count], "big"), 2 + count
        require(length >= 128 and (length.bit_length() + 7) // 8 == count, "Noncanonical DER length")
    require(header_size + length == len(data), "Trailing or truncated certificate DER")


class PublicVerifier:
    def __init__(self, openssl, checksum_tool, temporary):
        self.openssl = str(pathlib.Path(openssl).resolve())
        self.checksum_tool = str(pathlib.Path(checksum_tool).resolve())
        require(os.access(self.openssl, os.X_OK) and os.access(self.checksum_tool, os.X_OK), "Verification executable missing")
        self.temporary = pathlib.Path(temporary)
        self.environment = {k: v for k, v in os.environ.items()
                            if not k.startswith(("OPENSSL_", "DYLD_", "LD_"))}
        self.environment.update({"OPENSSL_CONF": os.devnull, "LC_ALL": "C"})
        version = self.run([self.openssl, "version"]).decode("ascii", "strict")
        match = re.match(r"OpenSSL (\d+)\.(\d+)\.(\d+)(?:\s|[-+])", version)
        require(match is not None and tuple(map(int, match.groups())) >= (3, 5, 0), "OpenSSL 3.5 or newer is required")
        self.certificates = {}
        self.serial = 0

    def run(self, command, input_data=None):
        try:
            result = subprocess.run(command, input=input_data, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, env=self.environment, timeout=120, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise VerificationError("Public verification command failed") from error
        require(result.returncode == 0, "Public verification command rejected input: " + pathlib.Path(command[0]).name)
        require(len(result.stdout) <= 1024 * 1024 and len(result.stderr) <= 1024 * 1024, "Excessive verification output")
        return result.stdout

    def snapshot(self, data, suffix):
        self.serial += 1
        path = self.temporary / (str(self.serial) + suffix)
        path.write_bytes(data)
        return str(path)

    def hashes(self, data):
        path = self.snapshot(data, ".public-data")
        skein = self.run([self.checksum_tool, "skein-1024-1024", path]).decode("ascii", "strict")
        require(re.fullmatch(r"[0-9a-f]{256}\n", skein), "Invalid checksum tool output")
        return {"sha256": hashlib.sha256(data).hexdigest(), "sha3-512": hashlib.sha3_512(data).hexdigest(),
                "skein-1024-1024": skein[:-1]}

    def check_certificate(self, certificate, pinned_rsa):
        cache_key = (hashlib.sha512(certificate).digest(), hashlib.sha512(pinned_rsa).digest())
        if cache_key in self.certificates:
            return self.certificates[cache_key]
        validate_der_sequence(certificate)
        cert_path = self.snapshot(certificate, ".certificate.der")
        pem = self.run([self.openssl, "x509", "-inform", "DER", "-in", cert_path, "-outform", "PEM"])
        pem_path = self.snapshot(pem, ".certificate.pem")
        pub_pem = self.run([self.openssl, "x509", "-in", pem_path, "-pubkey", "-noout"])
        spki = self.run([self.openssl, "pkey", "-pubin", "-outform", "DER"], pub_pem)
        require(hmac.compare_digest(spki, pinned_rsa), "Certificate RSA key does not match trusted SPKI")
        key_path = self.snapshot(spki, ".rsa-spki.der")
        text = self.run([self.openssl, "pkey", "-pubin", "-inform", "DER", "-in", key_path, "-text_pub", "-noout"])
        require(re.search(rb"^Public-Key: \(4096 bit\)$", text, re.MULTILINE), "Signing key must be RSA-4096")
        cert_text = self.run([self.openssl, "x509", "-in", pem_path, "-text", "-noout"])
        algorithms = re.findall(rb"Signature Algorithm: ([^\r\n]+)", cert_text)
        require(algorithms == [b"sha512WithRSAEncryption", b"sha512WithRSAEncryption"], "Certificate must use SHA-512 with RSA")
        usage = self.run([self.openssl, "x509", "-in", pem_path, "-noout", "-ext", "keyUsage"])
        eku = self.run([self.openssl, "x509", "-in", pem_path, "-noout", "-ext", "extendedKeyUsage"])
        require(b"Digital Signature" in usage and b"Code Signing" in eku, "Certificate signing usage is missing")
        subject = self.run([self.openssl, "x509", "-in", pem_path, "-noout", "-subject", "-nameopt", "RFC2253"])
        issuer = self.run([self.openssl, "x509", "-in", pem_path, "-noout", "-issuer", "-nameopt", "RFC2253"])
        require(subject.removeprefix(b"subject=") == issuer.removeprefix(b"issuer="), "Signing certificate must be self-issued")
        # A pinned key establishes trust. The self-signature binds the certificate
        # policy; verify also enforces NotBefore and NotAfter at current UTC time.
        self.run([self.openssl, "verify", "-trusted", pem_path, "-check_ss_sig", "-purpose", "any", pem_path])
        self.certificates[cache_key] = key_path
        return key_path

    def verify(self, sidecar, artifact, pinned_rsa, ml_spki_path):
        certificate, rsa, ml, payload = parse_envelope(sidecar, artifact)
        rsa_path = self.check_certificate(certificate, pinned_rsa)
        payload_path = self.snapshot(payload, ".payload")
        rsa_sig_path = self.snapshot(rsa, ".rsa-signature")
        ml_sig_path = self.snapshot(ml, ".ml-signature")
        self.run([self.openssl, "pkeyutl", "-verify", "-rawin", "-digest", "sha512", "-pubin", "-keyform", "DER",
                  "-inkey", rsa_path, "-in", payload_path, "-sigfile", rsa_sig_path,
                  "-pkeyopt", "rsa_padding_mode:pss", "-pkeyopt", "rsa_pss_saltlen:64", "-pkeyopt", "rsa_mgf1_md:sha512"])
        self.run([self.openssl, "pkeyutl", "-verify", "-rawin", "-pubin", "-keyform", "DER",
                  "-inkey", ml_spki_path, "-in", payload_path, "-sigfile", ml_sig_path,
                  "-pkeyopt", "context-string:" + ML_CONTEXT, "-pkeyopt", "message-encoding:1"])


def check_metadata(data):
    try:
        metadata = plistlib.loads(data)
    except (ValueError, plistlib.InvalidFileException) as error:
        raise VerificationError("Invalid bundle metadata") from error
    require(type(metadata) is dict, "Invalid bundle metadata type")
    expected = {"CFBundleIdentifier": PRODUCT_ID, "CFBundleShortVersionString": VERSION,
                "CFBundleVersion": BUILD, "CFBundleExecutable": "PasswordGeneratorApp"}
    require(all(metadata.get(key) == value for key, value in expected.items()), "Wrong app identity, version or build")


def file_record(path, data, mode):
    require(0 <= mode <= 0o777, "Special file permission bits are forbidden")
    return {"path": path, "size": len(data), "mode": mode, "sha512": hashlib.sha512(data).hexdigest()}


def compare_bundle(files, directories, metadata, inventory):
    require(sorted(files, key=lambda item: item["path"]) == inventory["files"], "Bundle file set, bytes or modes differ from signed inventory")
    require(sorted(directories) == inventory["directories"], "Bundle directories differ from signed inventory")
    require(metadata is not None, "Missing app Info.plist")
    check_metadata(metadata)


def verify_zip(data, inventory):
    files, directories, names = [], [], set()
    metadata = None
    total = 0
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            require(0 < len(entries) <= MAX_ENTRIES, "Invalid ZIP entry count")
            for entry in entries:
                name = entry.filename
                require(name == entry.orig_filename, "NUL-truncated ZIP name")
                directory = entry.is_dir()
                normalized = safe_path(name[:-1] if directory else name)
                require(normalized not in names, "Duplicate or aliased ZIP path")
                names.add(normalized)
                raw_mode = entry.external_attr >> 16
                kind = stat.S_IFMT(raw_mode)
                require(kind in {0, stat.S_IFREG, stat.S_IFDIR}, "ZIP symlink or nonregular payload")
                require(not entry.flag_bits & 1, "Encrypted ZIP entry")
                require(kind != stat.S_IFDIR or directory, "ZIP directory type mismatch")
                require(kind != stat.S_IFREG or not directory, "ZIP file type mismatch")
                parts = normalized.split("/")
                if parts[0] == "__MACOSX":
                    require(len(parts) == 1 or parts[1] in {APP_NAME, "._" + APP_NAME}, "Unexpected ZIP metadata")
                    # ditto's AppleDouble records are authenticated by the ZIP
                    # signature but are not ordinary files inside the app tree.
                    require(directory or parts[-1].startswith("._"), "Unexpected AppleDouble metadata file")
                    continue
                require(parts[0] == APP_NAME, "Unexpected ZIP root")
                if len(parts) == 1:
                    require(directory, "App root must be a directory")
                    continue
                relative = "/".join(parts[1:])
                if directory:
                    require(entry.file_size == 0, "Nonempty ZIP directory")
                    directories.append(relative)
                else:
                    require(0 <= entry.file_size <= MAX_BUNDLE_BYTES, "ZIP file exceeds size bound")
                    total += entry.file_size
                    require(total <= MAX_BUNDLE_BYTES, "ZIP bundle exceeds size bound")
                    contents = archive.read(entry)
                    require(len(contents) == entry.file_size, "ZIP length mismatch")
                    files.append(file_record(relative, contents, stat.S_IMODE(raw_mode)))
                    if relative == "Contents/Info.plist":
                        metadata = contents
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise VerificationError("Invalid release ZIP") from error
    compare_bundle(files, directories, metadata, inventory)


def verify_app(app, inventory):
    app = pathlib.Path(app)
    require(app.name == APP_NAME and stat.S_ISDIR(app.lstat().st_mode), "Wrong app directory")
    files, directories = [], []
    metadata = None
    total = 0
    try:
        def walk_error(error):
            raise VerificationError("Cannot enumerate app bundle") from error
        for directory, dirs, filenames in os.walk(app, followlinks=False, onerror=walk_error):
            for name in dirs:
                path = pathlib.Path(directory) / name
                require(stat.S_ISDIR(path.lstat().st_mode), "App contains a symlink or non-directory")
                directories.append(safe_path(path.relative_to(app).as_posix()))
            for name in filenames:
                path = pathlib.Path(directory) / name
                relative = safe_path(path.relative_to(app).as_posix())
                contents, mode = read_regular(path, MAX_BUNDLE_BYTES)
                total += len(contents)
                require(total <= MAX_BUNDLE_BYTES and len(files) + len(directories) <= MAX_ENTRIES, "App exceeds size bound")
                files.append(file_record(relative, contents, mode))
                if relative == "Contents/Info.plist":
                    metadata = contents
    except OSError as error:
        raise VerificationError("Cannot enumerate app bundle") from error
    compare_bundle(files, directories, metadata, inventory)


def verify_manifest(data, hashes):
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeError as error:
        raise VerificationError("Invalid integrity manifest encoding") from error
    require(lines and lines[0] == "Password Generator Release Integrity Manifest v1", "Invalid integrity manifest")
    fields = {}
    for line in lines[1:]:
        key, separator, value = line.partition("=")
        require(separator and key and key not in fields, "Duplicate or invalid integrity field")
        fields[key] = value
    expected = {"artifact": TARGETS[0], "coverage": "complete-signed-app-archive", "bundle-identifier": PRODUCT_ID,
                "bundle-version": VERSION, "bundle-build": BUILD, "architecture": "arm64", "minimum-macos": "14.0",
                "signature-mode": "developer-id-notarized"}
    require(all(fields.get(key) == value for key, value in expected.items()), "Wrong integrity manifest identity or release policy")
    require(all(fields.get(key) == value for key, value in hashes.items()), "Integrity manifest ZIP hashes mismatch")


def verify_release(release_dir, trust_path, checksum_tool, openssl, app=None):
    release_dir, trust_path = pathlib.Path(release_dir), pathlib.Path(trust_path)
    trust = parse_trust(read_regular(trust_path, MAX_TRUST)[0])
    rsa = read_regular(trust_path.parent / trust["rsa_spki"], MAX_CERTIFICATE)[0]
    ml = read_regular(trust_path.parent / trust["mldsa_public_key"], 2592)[0]
    validate_der_sequence(rsa)
    ml_der = mldsa_spki(ml)
    with tempfile.TemporaryDirectory(prefix="password-generator-public-verification-") as temporary:
        verifier = PublicVerifier(openssl, checksum_tool, temporary)
        require(verifier.hashes(rsa) == trust["rsa_spki_hashes"], "RSA public key fingerprint mismatch")
        require(verifier.hashes(ml) == trust["mldsa_public_key_hashes"], "ML-DSA public key fingerprint mismatch")
        ml_path = verifier.snapshot(ml_der, ".ml-spki.der")
        artifacts, hashes = {}, {}
        for name, limit in zip(TARGETS, (MAX_ZIP, MAX_TRUST, MAX_INVENTORY)):
            data = read_regular(release_dir / name, limit)[0]
            artifacts[name] = data
            hashes[name] = verifier.hashes(data)
            verifier.verify(read_regular(release_dir / (name + ".khsig"), MAX_SIDECAR)[0], data, rsa, ml_path)
            for suffix, algorithm in ((".sha3", "sha3-512"), (".skein", "skein-1024-1024")):
                digest_name = name + suffix
                digest_data = read_regular(release_dir / digest_name, 1024)[0]
                expected = (hashes[name][algorithm].upper() + "\n").encode("ascii")
                require(hmac.compare_digest(digest_data, expected), "Digest sidecar contents mismatch: " + digest_name)
                verifier.verify(read_regular(release_dir / (digest_name + ".khsig"), MAX_SIDECAR)[0], digest_data, rsa, ml_path)
        inventory = parse_inventory(artifacts[TARGETS[2]])
        verify_manifest(artifacts[TARGETS[1]], hashes[TARGETS[0]])
        verify_zip(artifacts[TARGETS[0]], inventory)
        if app is not None:
            verify_app(app, inventory)
    return {"signatures": 9, "files": len(inventory["files"]), "directories": len(inventory["directories"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-dir", required=True, type=pathlib.Path)
    parser.add_argument("--trust", required=True, type=pathlib.Path,
                        help="Public trust JSON obtained through an independently trusted channel")
    parser.add_argument("--checksum-tool", required=True, type=pathlib.Path,
                        help="Built PasswordGeneratorChecksum executable for Skein-1024-1024")
    parser.add_argument("--openssl", default=shutil.which("openssl"))
    parser.add_argument("--app", type=pathlib.Path, help="Also verify the installed app's exact files, modes and directories")
    args = parser.parse_args()
    try:
        require(args.openssl is not None, "OpenSSL 3.5 or newer is required")
        result = verify_release(args.release_dir, args.trust, args.checksum_tool, args.openssl, args.app)
    except (VerificationError, UnicodeError, OSError) as error:
        print("Hybrid release verification FAILED: " + str(error), file=sys.stderr)
        return 1
    print("Hybrid release verification passed: RSA-4096-PSS/SHA-512 AND ML-DSA-87 for all 9 signed artifacts.")
    print("Signed bundle inventory: %d files, %d directories; product %s, version %s, build %s." %
          (result["files"], result["directories"], PRODUCT_ID, VERSION, BUILD))
    if args.app:
        print("Installed app matches the signed inventory, including file permissions and empty directories.")
    print("Detached release signatures are external; the app's runtime integrity checks continue to use Apple code signing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
