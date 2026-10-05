#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$(cd "${RELEASE_BUILD_DIR:-$PROJECT_DIR/build}" && pwd)"
ZIP_NAME="Password.Generator-2.3.6.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
SHA256_PATH="$ZIP_PATH.sha256"
SHA3_PATH="$ZIP_PATH.sha3-512"
SKEIN_PATH="$ZIP_PATH.skein-1024-1024"
MANIFEST_PATH="$BUILD_DIR/Password.Generator-2.3.6.integrity.txt"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/ModuleCache"
ALLOW_UNNOTARIZED_DEVELOPMENT="${ALLOW_UNNOTARIZED_DEVELOPMENT:-0}"
if [[ "$ALLOW_UNNOTARIZED_DEVELOPMENT" != "0" && "$ALLOW_UNNOTARIZED_DEVELOPMENT" != "1" ]]; then
    echo "ALLOW_UNNOTARIZED_DEVELOPMENT muss 0 oder 1 sein."
    exit 1
fi

PYTHON_BIN="/usr/bin/python3"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(command -v python3 || true)"
fi
if [[ -z "$PYTHON_BIN" ]]; then
    echo "Python 3 fehlt für die unabhängigen Release-Prüfungen."
    exit 1
fi

for REQUIRED_PATH in "$ZIP_PATH" "$SHA256_PATH" "$SHA3_PATH" "$SKEIN_PATH" "$MANIFEST_PATH"; do
    if [[ ! -f "$REQUIRED_PATH" ]]; then
        echo "Release-Datei fehlt: $REQUIRED_PATH"
        exit 1
    fi
done

# BEGIN_RELEASE_MANIFEST_VALIDATION
MANIFEST_SIGNATURE_MODE="$("$PYTHON_BIN" - "$MANIFEST_PATH" "$ALLOW_UNNOTARIZED_DEVELOPMENT" <<'PY'
import pathlib
import re
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
if not lines or lines[0] != "Password Generator Release Integrity Manifest v1":
    raise SystemExit("Unbekanntes Integritätsmanifest.")
fields = {}
for line in lines[1:]:
    key, separator, value = line.partition("=")
    if not separator or not key or key in fields:
        raise SystemExit("Ungültiges oder mehrfaches Manifestfeld.")
    fields[key] = value
expected = {
    "artifact": "Password.Generator-2.3.6.zip",
    "coverage": "complete-signed-app-archive",
    "bundle-identifier": "local.passwordgenerator.generator",
    "bundle-version": "2.3.6",
    "bundle-build": "13",
    "architecture": "arm64",
    "minimum-macos": "14.0",
}
for key, value in expected.items():
    if fields.get(key) != value:
        raise SystemExit("Unerwartetes Manifestfeld: " + key)
for key, length in [("sha256", 64), ("sha3-512", 128), ("skein-1024-1024", 256)]:
    if re.fullmatch("[0-9a-f]{" + str(length) + "}", fields.get(key, "")) is None:
        raise SystemExit("Ungültiger Manifest-Hash: " + key)
mode = fields.get("signature-mode")
if mode not in {"local-ad-hoc", "developer-id", "developer-id-notarized"}:
    raise SystemExit("Unbekannter Signaturmodus.")
if sys.argv[2] != "1" and mode != "developer-id-notarized":
    raise SystemExit("Öffentliche Releases benötigen Developer ID und Notarisierung.")
print(mode)
PY
)"
# END_RELEASE_MANIFEST_VALIDATION

cd "$PROJECT_DIR"
env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
    swift build -c release --product PasswordGeneratorChecksum >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
CHECKSUM_BIN="$BIN_DIR/PasswordGeneratorChecksum"

EXPECTED_SHA256="$(awk 'NR == 1 {print $1}' "$SHA256_PATH")"
EXPECTED_SHA3="$(awk 'NR == 1 {print $1}' "$SHA3_PATH")"
EXPECTED_SKEIN="$(awk 'NR == 1 {print $1}' "$SKEIN_PATH")"
MANIFEST_SHA256="$(awk -F= '$1 == "sha256" {print $2}' "$MANIFEST_PATH")"
MANIFEST_SHA3="$(awk -F= '$1 == "sha3-512" {print $2}' "$MANIFEST_PATH")"
MANIFEST_SKEIN="$(awk -F= '$1 == "skein-1024-1024" {print $2}' "$MANIFEST_PATH")"
ACTUAL_SHA256="$("$CHECKSUM_BIN" sha256 "$ZIP_PATH")"
ACTUAL_SHA3="$("$CHECKSUM_BIN" sha3-512 "$ZIP_PATH")"
ACTUAL_SKEIN="$("$CHECKSUM_BIN" skein-1024-1024 "$ZIP_PATH")"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" || "$ACTUAL_SHA256" != "$MANIFEST_SHA256" ]]; then
    echo "SHA-256-Gesamtprüfung fehlgeschlagen."
    exit 1
fi
if [[ "$ACTUAL_SHA3" != "$EXPECTED_SHA3" || "$ACTUAL_SHA3" != "$MANIFEST_SHA3" ]]; then
    echo "SHA3-512-Gesamtprüfung fehlgeschlagen."
    exit 1
fi
if [[ "$ACTUAL_SKEIN" != "$EXPECTED_SKEIN" || "$ACTUAL_SKEIN" != "$MANIFEST_SKEIN" ]]; then
    echo "Skein-1024-1024-Gesamtprüfung fehlgeschlagen."
    exit 1
fi

PYTHON_SHA256="$(
    "$PYTHON_BIN" -c \
        'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' \
        "$ZIP_PATH"
)"
PYTHON_SHA3="$(
    "$PYTHON_BIN" -c \
        'import hashlib, pathlib, sys; print(hashlib.sha3_512(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' \
        "$ZIP_PATH"
)"
if [[ "$PYTHON_SHA256" != "$ACTUAL_SHA256" || "$PYTHON_SHA3" != "$ACTUAL_SHA3" ]]; then
    echo "Die unabhängige Python-Hashimplementierung liefert andere Gesamtwerte."
    exit 1
fi

REFERENCE_SKEIN="$(zsh "$SCRIPT_DIR/skein-reference-checksum.sh" "$ZIP_PATH")"
if [[ "$REFERENCE_SKEIN" != "$ACTUAL_SKEIN" ]]; then
    echo "Die unabhängige Skein-C-Referenz liefert einen anderen Gesamtwert."
    exit 1
fi

unzip -t "$ZIP_PATH" >/dev/null

# Validate paths before an untrusted archive is extracted. This app does not use
# symlinked frameworks or nonregular payloads.
# BEGIN_RELEASE_ARCHIVE_VALIDATION
"$PYTHON_BIN" - "$ZIP_PATH" <<'PY'
import pathlib
import stat
import sys
import zipfile

app_name = "Password Generator 2.3.6.app"
seen = set()
with zipfile.ZipFile(sys.argv[1]) as archive:
    for entry in archive.infolist():
        name = entry.filename
        path = pathlib.PurePosixPath(name)
        raw_parts = name[:-1].split("/") if name.endswith("/") else name.split("/")
        if (not name or entry.orig_filename != name or "\\" in name
                or path.is_absolute() or any(part in {"", ".", ".."} for part in raw_parts)
                or name in seen):
            raise SystemExit("Unsicherer oder mehrfacher ZIP-Pfad.")
        seen.add(name)
        if path.parts[0] == "__MACOSX":
            if len(path.parts) > 1 and path.parts[1] not in {app_name, "._" + app_name}:
                raise SystemExit("Unerwartete ZIP-Metadaten.")
        elif path.parts[0] != app_name:
            raise SystemExit("Unerwarteter ZIP-Inhalt.")
        mode = stat.S_IFMT(entry.external_attr >> 16)
        if mode not in {0, stat.S_IFREG, stat.S_IFDIR}:
            raise SystemExit("ZIP darf keine Symlinks oder Spezialdateien enthalten.")
PY
# END_RELEASE_ARCHIVE_VALIDATION

VERIFY_TEMP_DIR="$(mktemp -d)"
if [[ "$VERIFY_TEMP_DIR" != /var/folders/*/T/* && "$VERIFY_TEMP_DIR" != /tmp/* ]]; then
    echo "Unerwarteter temporärer Pfad; Abbruch."
    exit 1
fi
trap 'rm -rf -- "$VERIFY_TEMP_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VERIFY_TEMP_DIR"
EXTRACTED_APP="$VERIFY_TEMP_DIR/Password Generator 2.3.6.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"
SIGNATURE_INFORMATION="$(/usr/bin/codesign -dv --verbose=4 "$EXTRACTED_APP" 2>&1)"

# BEGIN_RELEASE_IDENTITY_VALIDATION
"$PYTHON_BIN" - "$EXTRACTED_APP" "$MANIFEST_SIGNATURE_MODE" "$SIGNATURE_INFORMATION" <<'PY'
import pathlib
import plistlib
import re
import sys

app_path = pathlib.Path(sys.argv[1])
metadata = plistlib.loads((app_path / "Contents/Info.plist").read_bytes())
expected = {
    "CFBundleIdentifier": "local.passwordgenerator.generator",
    "CFBundleShortVersionString": "2.3.6",
    "CFBundleVersion": "13",
    "CFBundleExecutable": "PasswordGeneratorApp",
}
for key, value in expected.items():
    if metadata.get(key) != value:
        raise SystemExit("Unerwartete Bundle-Angabe: " + key)

information = sys.argv[3].splitlines()
def unique_value(key):
    values = [line.partition("=")[2] for line in information if line.startswith(key + "=")]
    if len(values) != 1:
        raise SystemExit("Fehlende oder mehrfache Signaturangabe: " + key)
    return values[0]

if unique_value("Identifier") != expected["CFBundleIdentifier"]:
    raise SystemExit("Produkt-ID der Code-Signatur stimmt nicht überein.")
code_directories = [line for line in information if line.startswith("CodeDirectory ")]
if len(code_directories) != 1:
    raise SystemExit("Eindeutige CodeDirectory-Angabe fehlt.")
flags = re.search(r"(?:^| )flags=0x([0-9a-fA-F]+)(?:\(| |$)", code_directories[0])
# kSecCodeSignatureRuntime is 0x10000 in Security.framework/Headers/CSCommon.h.
if flags is None or int(flags.group(1), 16) & 0x10000 == 0:
    raise SystemExit("Hardened Runtime fehlt in der Code-Signatur.")

if sys.argv[2] == "local-ad-hoc":
    if "Signature=adhoc" not in information:
        raise SystemExit("Manifest und Ad-hoc-Signatur stimmen nicht überein.")
else:
    if unique_value("TeamIdentifier") != "2T6K9PGS55":
        raise SystemExit("Unerwartetes Developer-ID-Team.")
    authorities = [line.partition("=")[2] for line in information if line.startswith("Authority=")]
    if (not authorities or not authorities[0].startswith("Developer ID Application: ")
            or not authorities[0].endswith(" (2T6K9PGS55)")):
        raise SystemExit("Erwartete Developer-ID-Application-Authority fehlt.")
PY
# END_RELEASE_IDENTITY_VALIDATION

ENTITLEMENTS="$(/usr/bin/codesign -d --entitlements :- "$EXTRACTED_APP" 2>/dev/null)"
# BEGIN_RELEASE_ENTITLEMENTS_VALIDATION
"$PYTHON_BIN" - "$ENTITLEMENTS" <<'PY'
import plistlib
import sys

entitlements = plistlib.loads(sys.argv[1].encode("utf-8"))
allowed = {
    "com.apple.security.app-sandbox",
    "com.apple.application-identifier",
    "com.apple.developer.team-identifier",
}
if entitlements.get("com.apple.security.app-sandbox") is not True:
    raise SystemExit("App-Sandbox-Entitlement fehlt oder ist nicht true.")
unexpected = set(entitlements) - allowed
if unexpected:
    raise SystemExit("Unerwartete Entitlements: " + ", ".join(sorted(unexpected)))
if ("com.apple.developer.team-identifier" in entitlements
        and entitlements["com.apple.developer.team-identifier"] != "2T6K9PGS55"):
    raise SystemExit("Team-ID im Entitlement stimmt nicht überein.")
if ("com.apple.application-identifier" in entitlements
        and entitlements["com.apple.application-identifier"]
        != "2T6K9PGS55.local.passwordgenerator.generator"):
    raise SystemExit("Produkt-ID im Entitlement stimmt nicht überein.")
PY
# END_RELEASE_ENTITLEMENTS_VALIDATION

if [[ "$MANIFEST_SIGNATURE_MODE" == "developer-id-notarized" ]]; then
    /usr/bin/xcrun stapler validate "$EXTRACTED_APP"
    GATEKEEPER_INFORMATION="$(/usr/sbin/spctl --assess --type execute --verbose=2 "$EXTRACTED_APP" 2>&1)"
    if [[ "$GATEKEEPER_INFORMATION" != *"source=Notarized Developer ID"* ]]; then
        echo "Gatekeeper bestätigt kein notarisiertes Developer-ID-Release."
        exit 1
    fi
    printf '%s\n' "$GATEKEEPER_INFORMATION"
else
    echo "Entwicklungsprüfung ausdrücklich aktiviert: Notarisierung nicht bestätigt."
fi

echo "Gesamt-App-Integrität bestanden."
echo "SHA-256:   $ACTUAL_SHA256"
echo "SHA3-512: $ACTUAL_SHA3"
echo "Skein-1024-1024: $ACTUAL_SKEIN"
echo "Unabhängige Python-Gegenprüfung (SHA256/SHA3-512): identisch"
echo "Unabhängige C-Referenzprüfung (Skein-1024-1024): identisch"
echo "Produkt-ID, Version, Build, Hardened Runtime und minimale Sandbox: gültig"
if [[ "$MANIFEST_SIGNATURE_MODE" == "developer-id-notarized" ]]; then
    echo "Erwartetes Developer-ID-Team, angeheftetes Ticket und Gatekeeper: gültig"
fi
