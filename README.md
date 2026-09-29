# Password Generator for macOS

English | [Deutsch](README.de.md)

<img src="Assets/PasswordGeneratorIcon.png" width="128" alt="Password Generator icon">

[Download the app](https://github.com/michael-feinermann/password-generator/releases/latest) · [Technical analysis (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)

Version 2.1.0, build 4, was notarized by Apple through Xcode. The published ZIP contains the Developer ID-signed app with a stapled notarization ticket; Gatekeeper accepts it as `Notarized Developer ID`.

A native, local macOS app for seed phrases, EFF passphrases, ASCII passwords, PINs, and hexadecimal values. The interface is available in English and German, and the app has no network access. Its visible name is “Password Generator 2.1.0”.

| Format | Length | Alphabet | Displayed entropy |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21, or 24 words | Official English wordlist | 128, 160, 192, 224, or 256 bits |
| EFF | 6 to 60 words | EFF Long Wordlist, 7,776 words | Words × log₂(7,776) |
| ASCII | 8 to 256 characters | 94 printable ASCII characters, `!` through `~`, without spaces | Characters × log₂(94) |
| PIN | 3 to 256 digits | `0` through `9`, leading zeros allowed | Digits × log₂(10) |
| Hex | 1 to 448 hexadecimal characters | `0` through `9`, `a` through `f` or `A` through `F` | Characters × 4 bits |

The entropy display describes the size of the uniformly sampled output space. It neither measures the entropy of mouse movements nor guarantees a corresponding level of resistance to attacks on the overall system. BIP39 checksum bits do not count as additional entropy. Repeated words and characters are allowed; additional composition rules would change the output space.

## Export format

For EFF and BIP39, the separator can be freely chosen in a text field. BIP39 defaults to a space, and EFF defaults to `-`. An empty field joins the words without a separator; spaces and separators containing multiple characters are also supported. Hex output can use lowercase or uppercase letters. These settings apply to clipboard output and can be changed after generation. The generated words or hexadecimal values remain the same; no new random selection takes place.

BIP39 wallets usually expect words separated by spaces. The internal BIP39 checksum is always checked against the original word sequence. Without separators, BIP39 word boundaries cannot always be reconstructed unambiguously; different valid word sequences can produce the same concatenated text. The displayed entropy therefore describes the original selection and does not establish the entropy of arbitrary export representations. Hexadecimal letter case and fixed separators do not add random bits.

## Running and building

```sh
swift test -Xswiftc -warnings-as-errors
zsh Scripts/package-app.sh
zsh Scripts/verify-release.sh
open "build/Password Generator 2.1.0.app"
```

The release targets Apple Silicon (`arm64`) running macOS 14 or later. Use the signed app bundle to run the application. `swift run PasswordGeneratorApp` is intended only for development; a process without the required signature does not satisfy the runtime conditions for generation.

The packaging script creates `build/Password Generator 2.1.0.app`, `build/Password.Generator-2.1.0.zip`, two checksum files, and an integrity manifest. Without an explicit `SIGN_IDENTITY`, the local build uses an ad hoc signature. A Developer ID certificate in the keychain can be selected by its fingerprint. `NOTARY_PROFILE` enables optional notarization using an existing keychain profile, followed by stapling and ZIP recreation. Credentials and private keys are not stored in the project. The actual signing and notarization status is documented in each release and its integrity manifest. The project directory remains `Seed-Phrase`; the app, Swift package, modules, bundle identifier, and release files now use Password Generator or PasswordGenerator.

## Mouse pool and generation

1. Mouse movements throughout the app window are captured, including movement over controls and dragging. There is no restricted collection area or global monitoring of other apps.
2. The pool retains the latest 4,096 complete mouse events. Generation requires at least 4,096 movements. Each subsequent movement replaces the oldest record, keeping memory use bounded. Each record contains a sequence number, monotonic time, event timestamp, position, delta, window size, modifier keys, and pressed mouse buttons.
3. Starting when the app launches, a Fisher-Yates shuffle using the linear-time Durstenfeld variant runs every six seconds. It permutes the records using random bytes from `SecRandomCopyBytes`. Rejection sampling avoids modulo bias. The initial pass over the empty pool is a no-op. No process can guarantee real-time scheduling while macOS suspends the app or the computer sleeps.
4. Generation performs another shuffle. Only then are the records serialized in their shuffled order and `Skein-1024-1024(pool)` and `SHA3-512(pool)` computed. These pool hashes are not computed during collection or periodic shuffles. Separate integrity checks of the embedded wordlists run when the lists are loaded.
5. The digests are concatenated in Skein, SHA3 order: 128 + 64 = 192 bytes, or 1,536 bits. Fisher-Yates then permutes all 1,536 individual bits using cryptographically secure random bytes from macOS. This additional step shuffles bit positions, rather than just the order of the 192 bytes.
6. XORing the shuffled 192-byte value with 192 freshly requested macOS random bytes produces the master key. Random bytes for this XOR step are requested separately from the bytes used for the shuffles.
7. The master key is split, in order, into 128, 32, and 32 bytes. The first fragment initializes a Skein-1024-XOF stream, and each remaining fragment initializes a SHAKE256 stream. Equal-length outputs from these three streams are combined using bytewise XOR.
8. Immediately before use, this material is XORed with an equal number of fresh macOS random bytes. If rejection sampling requests more bytes, all three streams continue from their current positions and receive a fresh OS contribution. Previously consumed stream prefixes are not reused.
9. BIP39 encodes the required entropy bytes together with the SHA256 checksum. EFF, ASCII, PIN, and Hex use unbiased selection from their respective alphabets.

The combined hash length of 1,536 bits does not establish 1,536 bits of independent entropy. A bit permutation preserves the number of ones and zeros and does not, by itself, establish any particular entropy gain. XORing a Skein-1024-XOF stream with two SHAKE256 streams does not allow their security strengths to be added together either. This construction implements the requested sequence; it is not a standardized or externally audited random number generator. The operating system's cryptographic random source remains the underlying security assumption.

## Output protection

The existing runtime checks remain in place: a valid signature for the running code, Hardened Runtime, a minimal App Sandbox, disabled POSIX core dumps, and no detected debugger. These checks run again immediately before generation, display, and copying.

Output is initially concealed. Revealing it requires confirmation; the app makes a best effort to hide it again after 60 seconds or on a context change. Copying requires an explicit click and uses `currentHostOnly`; the app makes a best effort to clear the clipboard after about 45 seconds if its contents remain unchanged. The mouse pool and temporary cryptographic buffers are overwritten on disposal on a best-effort basis. Complete erasure of Swift strings, registers, and operating system copies cannot be guaranteed.

The app does not save generated passwords to files or preferences. A local app cannot reliably prevent screenshots, recording with an external camera, or exposure on a compromised operating system.

## Integrity and tests

Both wordlists are checked against embedded SHA256 and SHA3-512 values before use. The exact signed app is also packaged as a ZIP and hashed with both algorithms. `verify-release.sh` independently checks the values using Python, extracts the ZIP, and verifies the code signature and sandbox. Hash values alone do not prove provenance.

For version 2.1.0, all 71 tests passed in both Debug and Release builds with no errors or compiler warnings. These include three independently calculated references for the complete derivation, 45 password cases, and checks covering the hash/XOF functions, bit shuffle, stream continuation, error handling, and app model. Details of these checks and the release evidence are recorded in the [verification section of the technical analysis (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

## Logo and icon

`Assets/PasswordGeneratorIcon.png` is the source for the macOS icon. `Assets/PasswordGeneratorLogo.png` contains the standalone brand symbol used in the interface. The generation process and prompts are documented in [Assets/README.md (German)](Assets/README.md). The packaging script generates all macOS icon sizes and `AppIcon.icns` from the icon source.

## Sources and third-party material

[Third-party notices](THIRD_PARTY_NOTICES.md) document the sources and licensing information for the embedded wordlists and test data.

## Primary sources

- [BIP39 specification](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Long Wordlist](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [EFF: Dice-Generated Passphrases](https://www.eff.org/dice)
- [Skein v1.3 and official test vectors](https://www.schneier.com/academic/skein/)
- [NIST FIPS 202: SHA3 and SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [Durstenfeld: Algorithm 235, Random permutation](https://doi.org/10.1145/364520.364540)
- [Apple: SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
