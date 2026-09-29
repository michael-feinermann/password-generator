#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ZIP_NAME="Password.Generator-2.0.0.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
SHA256_PATH="$ZIP_PATH.sha256"
SHA3_PATH="$ZIP_PATH.sha3-512"
MANIFEST_PATH="$BUILD_DIR/Password.Generator-2.0.0.integrity.txt"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/ModuleCache"

for REQUIRED_PATH in "$ZIP_PATH" "$SHA256_PATH" "$SHA3_PATH" "$MANIFEST_PATH"; do
    if [[ ! -f "$REQUIRED_PATH" ]]; then
        echo "Release-Datei fehlt: $REQUIRED_PATH"
        exit 1
    fi
done

cd "$PROJECT_DIR"
env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
    swift build -c release --product PasswordGeneratorChecksum >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
CHECKSUM_BIN="$BIN_DIR/PasswordGeneratorChecksum"

EXPECTED_SHA256="$(awk 'NR == 1 {print $1}' "$SHA256_PATH")"
EXPECTED_SHA3="$(awk 'NR == 1 {print $1}' "$SHA3_PATH")"
MANIFEST_SHA256="$(awk -F= '$1 == "sha256" {print $2}' "$MANIFEST_PATH")"
MANIFEST_SHA3="$(awk -F= '$1 == "sha3-512" {print $2}' "$MANIFEST_PATH")"
ACTUAL_SHA256="$("$CHECKSUM_BIN" sha256 "$ZIP_PATH")"
ACTUAL_SHA3="$("$CHECKSUM_BIN" sha3-512 "$ZIP_PATH")"

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" || "$ACTUAL_SHA256" != "$MANIFEST_SHA256" ]]; then
    echo "SHA-256-Gesamtprüfung fehlgeschlagen."
    exit 1
fi
if [[ "$ACTUAL_SHA3" != "$EXPECTED_SHA3" || "$ACTUAL_SHA3" != "$MANIFEST_SHA3" ]]; then
    echo "SHA3-512-Gesamtprüfung fehlgeschlagen."
    exit 1
fi

PYTHON_BIN="/usr/bin/python3"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="$(command -v python3 || true)"
fi
if [[ -z "$PYTHON_BIN" ]]; then
    echo "Python 3 fehlt für die unabhängige SHA‑3-Gegenprüfung."
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

unzip -t "$ZIP_PATH" >/dev/null

VERIFY_TEMP_DIR="$(mktemp -d)"
if [[ "$VERIFY_TEMP_DIR" != /var/folders/*/T/* && "$VERIFY_TEMP_DIR" != /tmp/* ]]; then
    echo "Unerwarteter temporärer Pfad; Abbruch."
    exit 1
fi
trap 'rm -rf -- "$VERIFY_TEMP_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VERIFY_TEMP_DIR"
EXTRACTED_APP="$VERIFY_TEMP_DIR/Password Generator.app"
codesign --verify --deep --strict --verbose=2 "$EXTRACTED_APP"

ENTITLEMENTS="$(codesign -d --entitlements :- "$EXTRACTED_APP" 2>/dev/null)"
printf '%s' "$ENTITLEMENTS" | "$PYTHON_BIN" -c '
import plistlib
import sys

entitlements = plistlib.loads(sys.stdin.buffer.read())
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
'

if /usr/bin/grep -qx 'signature-mode=developer-id-notarized' "$MANIFEST_PATH"; then
    xcrun stapler validate "$EXTRACTED_APP"
    spctl --assess --type execute --verbose=2 "$EXTRACTED_APP"
fi

echo "Gesamt-App-Integrität bestanden."
echo "SHA-256:   $ACTUAL_SHA256"
echo "SHA3-512: $ACTUAL_SHA3"
echo "Unabhängige Python-Gegenprüfung: identisch"
echo "Signatur und minimale Sandbox des entpackten App-Bundles: gültig"
