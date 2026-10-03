#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Password Generator 2.2.1.app"
ICONSET_PATH="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$BUILD_DIR/AppIcon-1024.png"
ZIP_NAME="Password.Generator-2.2.1.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
INTEGRITY_MANIFEST_PATH="$BUILD_DIR/Password.Generator-2.2.1.integrity.txt"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
MODULE_CACHE_DIR="$PROJECT_DIR/.build/ModuleCache"

if [[ "$SIGN_IDENTITY" != "-" && "$SIGN_IDENTITY" != "Developer ID Application:"* && ! "$SIGN_IDENTITY" =~ '^[[:xdigit:]]{40}$' ]]; then
    echo "Eine Developer-ID-Application-Identität oder ihr SHA-1-Fingerabdruck ist erforderlich."
    exit 1
fi

if [[ "$APP_PATH" != "$PROJECT_DIR/build/Password Generator 2.2.1.app" ]]; then
    echo "Unerwarteter App-Zielpfad; Abbruch."
    exit 1
fi

if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
    echo "Notarisierung benötigt eine Developer-ID-Signatur."
    exit 1
fi

cd "$PROJECT_DIR"

env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
    swift build -c release -Xswiftc -warnings-as-errors --product PasswordGeneratorApp
env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR" \
    swift build -c release -Xswiftc -warnings-as-errors --product PasswordGeneratorChecksum

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/PasswordGeneratorApp"

if [[ ! -x "$BINARY_PATH" ]]; then
    echo "Release-Binary nicht gefunden: $BINARY_PATH"
    exit 1
fi

rm -rf "$APP_PATH"
rm -rf "$ICONSET_PATH"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256" "$ZIP_PATH.sha3-512" "$ZIP_PATH.skein-1024-1024" "$INTEGRITY_MANIFEST_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

install -m 755 "$BINARY_PATH" "$APP_PATH/Contents/MacOS/PasswordGeneratorApp"
APP_BINARY_PATH="$APP_PATH/Contents/MacOS/PasswordGeneratorApp"

# SwiftPM may embed build-machine fallback RPATHs. The app has no @rpath
# dependencies, so retain only the operating-system Swift runtime location.
while IFS= read -r RPATH; do
    if [[ "$RPATH" != "/usr/lib/swift" ]]; then
        install_name_tool -delete_rpath "$RPATH" "$APP_BINARY_PATH"
    fi
done < <(
    otool -l "$APP_BINARY_PATH" |
        awk '/cmd LC_RPATH/{found=1; next} found && /path /{print $2; found=0}'
)

UNEXPECTED_RPATHS="$(
    otool -l "$APP_BINARY_PATH" |
        awk '/cmd LC_RPATH/{found=1; next} found && /path /{print $2; found=0}' |
        awk '$0 != "/usr/lib/swift"'
)"
if [[ -n "$UNEXPECTED_RPATHS" ]]; then
    echo "Unerwarteter RPATH im Release-Binary: $UNEXPECTED_RPATHS"
    exit 1
fi

UNTRUSTED_DEPENDENCIES="$(
    otool -L "$APP_BINARY_PATH" |
        sed -n '2,$p' |
        awk '{print $1}' |
        awk '$0 !~ "^/System/Library/" && $0 !~ "^/usr/lib/"'
)"
if [[ -n "$UNTRUSTED_DEPENDENCIES" ]]; then
    echo "Nicht-systemeigene Laufzeitabhängigkeit: $UNTRUSTED_DEPENDENCIES"
    exit 1
fi

install -m 644 "$PROJECT_DIR/Config/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 \
    "$PROJECT_DIR/Sources/PasswordGeneratorCore/Resources/english.txt" \
    "$APP_PATH/Contents/Resources/english.txt"

install -m 644 \
    "$PROJECT_DIR/Sources/PasswordGeneratorCore/Resources/eff_large_wordlist.txt" \
    "$APP_PATH/Contents/Resources/eff_large_wordlist.txt"
install -m 644 \
    "$PROJECT_DIR/Assets/PasswordGeneratorLogo.png" \
    "$APP_PATH/Contents/Resources/PasswordGeneratorLogo.png"

install -m 644 "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
install -m 644 "$PROJECT_DIR/Licenses/python-mnemonic-MIT.txt" "$APP_PATH/Contents/Resources/python-mnemonic-MIT.txt"
swift "$PROJECT_DIR/Scripts/generate-app-icon.swift" "$ICON_SOURCE"
mkdir -p "$ICONSET_PATH"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    TIMESTAMP_ARGUMENT="--timestamp=none"
else
    TIMESTAMP_ARGUMENT="--timestamp"
fi

codesign \
    --force \
    --options runtime \
    --entitlements "$PROJECT_DIR/Config/PasswordGenerator.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$TIMESTAMP_ARGUMENT" \
    "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGNATURE_INFORMATION="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
    if [[ "$SIGNATURE_INFORMATION" != *"Authority=Developer ID Application:"* ]]; then
        echo "Die fertige App besitzt keine bestätigte Developer-ID-Application-Signatur."
        exit 1
    fi
    if [[ "$SIGNATURE_INFORMATION" == *"TeamIdentifier=not set"* ]]; then
        echo "TeamIdentifier fehlt in der öffentlichen Signatur."
        exit 1
    fi
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
if [[ -n "$NOTARY_PROFILE" ]]; then
    # Credentials stay in Keychain; no password or private key is exported.
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi
SHA256_VALUE="$("$BIN_DIR/PasswordGeneratorChecksum" sha256 "$ZIP_PATH")"
SHA3_VALUE="$("$BIN_DIR/PasswordGeneratorChecksum" sha3-512 "$ZIP_PATH")"
SKEIN_VALUE="$("$BIN_DIR/PasswordGeneratorChecksum" skein-1024-1024 "$ZIP_PATH")"

printf '%s  %s\n' "$SHA256_VALUE" "$ZIP_NAME" > "$ZIP_PATH.sha256"
printf '%s  %s\n' "$SHA3_VALUE" "$ZIP_NAME" > "$ZIP_PATH.sha3-512"
printf '%s  %s\n' "$SKEIN_VALUE" "$ZIP_NAME" > "$ZIP_PATH.skein-1024-1024"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGNATURE_MODE="local-ad-hoc"
else
    SIGNATURE_MODE="developer-id"
    if [[ -n "$NOTARY_PROFILE" ]]; then SIGNATURE_MODE="developer-id-notarized"; fi
fi

{
    printf 'Password Generator Release Integrity Manifest v1\n'
    printf 'artifact=%s\n' "$ZIP_NAME"
    printf 'coverage=complete-signed-app-archive\n'
    printf 'bundle-identifier=local.passwordgenerator.generator\n'
    printf 'bundle-version=2.2.1\n'
    printf 'bundle-build=6\n'
    printf 'architecture=arm64\n'
    printf 'minimum-macos=14.0\n'
    printf 'signature-mode=%s\n' "$SIGNATURE_MODE"
    printf 'sha256=%s\n' "$SHA256_VALUE"
    printf 'sha3-512=%s\n' "$SHA3_VALUE"
    printf 'skein-1024-1024=%s\n' "$SKEIN_VALUE"
    printf 'authenticity-note=hashes-detect-change-but-require-a-trusted-publication-channel\n'
} > "$INTEGRITY_MANIFEST_PATH"

if [[ "$("$BIN_DIR/PasswordGeneratorChecksum" sha256 "$ZIP_PATH")" != "$SHA256_VALUE" ]]; then
    echo "SHA-256-Gesamtprüfung des Release-Archivs fehlgeschlagen."
    exit 1
fi
if [[ "$("$BIN_DIR/PasswordGeneratorChecksum" sha3-512 "$ZIP_PATH")" != "$SHA3_VALUE" ]]; then
    echo "SHA3-512-Gesamtprüfung des Release-Archivs fehlgeschlagen."
    exit 1
fi
if [[ "$("$BIN_DIR/PasswordGeneratorChecksum" skein-1024-1024 "$ZIP_PATH")" != "$SKEIN_VALUE" ]]; then
    echo "Skein-1024-1024-Gesamtprüfung des Release-Archivs fehlgeschlagen."
    exit 1
fi
unzip -t "$ZIP_PATH" >/dev/null

echo "App-Bundle: $APP_PATH"
echo "Release-ZIP: $ZIP_PATH"
echo "Integritätsmanifest: $INTEGRITY_MANIFEST_PATH"
echo "SHA-256:     $SHA256_VALUE"
echo "SHA3-512:   $SHA3_VALUE"
echo "Skein-1024-1024: $SKEIN_VALUE"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Signatur:     lokal/ad hoc (für Veröffentlichung Developer ID verwenden)"
else
    echo "Signatur:     $SIGN_IDENTITY"
fi
