# Password Generator for macOS

English | [Deutsch](README.de.md)

<img src="Assets/PasswordGeneratorIcon.png" width="128" alt="Password Generator icon">

[Download the app](https://github.com/michael-feinermann/password-generator/releases/latest) · [Release notes 2.3.0](docs/RELEASE_NOTES_2.3.0.md) · [Technical analysis (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)

Version 2.3.0, build 7. Developer ID signed, notarized through Xcode on 4 October 2026, with a stapled ticket; Gatekeeper accepted the final app.

A native, local macOS app for seed phrases, EFF passphrases, ASCII passwords, PINs, and hexadecimal values. The interface is available in English and German, and the app has no network access. Its visible name is “Password Generator 2.3.0”.

| Format | Length | Alphabet | Displayed entropy |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21, or 24 words | Official English wordlist | 128, 160, 192, 224, or 256 bits |
| EFF | 6 to 128 words | EFF Long Wordlist, 7,776 words | Words × log₂(7,776) |
| ASCII | 8 to 256 characters | 94 printable ASCII characters, `!` through `~`, without spaces | Characters × log₂(94) |
| PIN | 3 to 512 digits | `0` through `9`, leading zeros allowed | Digits × log₂(10) |
| Hex | 1 to 512 hexadecimal characters | `0` through `9`, `a` through `f` or `A` through `F` | Characters × 4 bits |

The entropy display describes the size of the uniformly sampled output space. It neither measures the entropy of mouse movements nor guarantees a corresponding level of resistance to attacks on the overall system. BIP39 checksum bits do not count as additional entropy. Repeated words and characters are allowed; additional composition rules would change the output space.

## Defaults and color levels

Version 2.3.0 starts each format with these lengths:

| Format | Default | Nominal bits |
|---|---|---|
| BIP39 | 24 words | 256 |
| EFF | 20 words | 20 × log₂(7,776) ≈ 258.50 |
| ASCII | 40 characters | 40 × log₂(94) ≈ 262.18 |
| PIN | 6 digits | 6 × log₂(10) ≈ 19.93 |
| Hex | 64 characters | 64 × 4 = 256 |

For BIP39, EFF, ASCII, and Hex, these are the shortest supported lengths reaching at least 256 nominal bits. PIN is deliberately a six-digit exception. The full selectable length ranges remain available.

The configuration and generated result show the nominal bit value together with a color and a text label. The unrounded value determines the level; exactly 128, 256, or 1,024 bits enters the next level.

| Nominal bits | Color | Label |
|---|---|---|
| Below 128 | Red | Limited brute-force reserve |
| 128 to below 256 | Yellow | Limited quantum reserve |
| 256 to below 1,024 | Light green | Very high brute-force cost |
| 1,024 or more | Dark green | Extreme brute-force cost |

These labels refer to the nominal selection space under ideally uniform sampling. They do not measure the random source or guarantee overall security. A six-digit PIN has a small offline guessing space; its suitability also depends on the use case and enforced attempt limits.

The yellow level refers to the idealized Grover search model: searching N possibilities requires on the order of √N quantum queries. It does not claim that every value below 256 bits is practically vulnerable to quantum computers. NIST notes the cost of quantum hardware and the limits on parallelizing Grover's algorithm, and continues to allow AES-128, AES-192, and AES-256. The highest level likewise makes no thermodynamic impossibility claim. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs)

## Export format

For EFF and BIP39, the separator can be freely chosen in a text field. BIP39 defaults to a space, and EFF defaults to `-`. An empty field joins the words without a separator; spaces and separators containing multiple characters are also supported. Hex output can use lowercase or uppercase letters. These settings apply to clipboard output and can be changed after generation. Hex letter case also applies to the displayed output. The generated words or hexadecimal values remain the same; no new random selection takes place.

BIP39 wallets usually expect words separated by spaces. The internal BIP39 checksum is always checked against the original word sequence. Without separators, BIP39 word boundaries cannot always be reconstructed unambiguously; different valid word sequences can produce the same concatenated text. The displayed entropy therefore describes the original selection and does not establish the entropy of arbitrary export representations. Hexadecimal letter case and fixed separators do not add random bits.

## Running and building

```sh
swift test -Xswiftc -warnings-as-errors
zsh Scripts/package-app.sh
zsh Scripts/verify-release.sh
open "build/Password Generator 2.3.0.app"
```

The release targets Apple Silicon (`arm64`) running macOS 14 or later. Use the signed app bundle to run the application. `swift run PasswordGeneratorApp` is intended only for development; a process without the required signature does not satisfy the runtime conditions for generation.

The packaging script creates `build/Password Generator 2.3.0.app`, `build/Password.Generator-2.3.0.zip`, three checksum files, and an integrity manifest. Without an explicit `SIGN_IDENTITY`, the local build uses an ad hoc signature. A Developer ID certificate in the keychain can be selected by its fingerprint. `NOTARY_PROFILE` enables optional notarization using an existing keychain profile, followed by stapling and ZIP recreation. Credentials and private keys are not stored in the project. The actual signing and notarization status is documented in each release and its integrity manifest. The project directory remains `Seed-Phrase`; the app, Swift package, modules, bundle identifier, and release files now use Password Generator or PasswordGenerator.

## Mouse pool and generation

1. Mouse movements throughout the app window are captured, including movement over controls and dragging. There is no restricted collection area or global monitoring of other apps.
2. The pool retains the latest 4,096 complete mouse events. Generation requires at least 4,096 movements. Each subsequent movement replaces the oldest record, keeping memory use bounded. Each record contains a sequence number, monotonic time, event timestamp, position, delta, window size, modifier keys, and pressed mouse buttons.
3. Starting when the app launches, a Fisher-Yates shuffle using the linear-time Durstenfeld variant runs every six seconds. It permutes the records using random bytes from `SecRandomCopyBytes`. Rejection sampling avoids modulo bias. The initial pass over the empty pool is a no-op. No process can guarantee real-time scheduling while macOS suspends the app or the computer sleeps.
4. Generation performs another shuffle. Only then are the records serialized in their shuffled order and `Skein-1024-1024(pool)`, `SHA3-512(pool)`, and `SHA-512(pool)` computed. These pool hashes are not computed during collection or periodic shuffles. Separate integrity checks of the embedded wordlists run when the lists are loaded.
5. The digests are concatenated in Skein-1024-1024, SHA3-512, SHA-512 order: 128 + 64 + 64 = 256 bytes, or 2,048 bits. First, these 256 hash bytes are XORed with 256 freshly requested cryptographic macOS random bytes.
6. Fisher-Yates then permutes all 2,048 individual bits of that XOR result using further cryptographic macOS random bytes. It shuffles bit positions, rather than just the order of the 256 bytes. After the bit shuffle, a second XOR with a separately requested set of 256 fresh macOS random bytes produces the master key. The two XOR masks and the shuffle randomness come from separate requests; neither mask is reused.
7. The master key is split, in order, into 128, 32, 32, 32, and 32 bytes. The first fragment initializes a Skein-1024-XOF stream; the next two initialize separate SHAKE256 streams; the final two are separate AES-256 keys for two AES-256-CTR streams. Each CTR stream starts at zero and advances its own 128-bit big-endian counter, retaining partial blocks across reads. Equal-length outputs from all five streams are combined using bytewise XOR.
8. Immediately before use, this material is XORed with an equal number of fresh macOS random bytes. If rejection sampling requests more bytes, all five streams continue from their current positions and receive a fresh OS contribution. Previously consumed stream prefixes are not reused.
9. BIP39 encodes the required entropy bytes together with the SHA256 checksum. EFF, ASCII, PIN, and Hex use unbiased selection from their respective alphabets.

The combined hash length of 2,048 bits does not establish 2,048 bits of independent entropy. A bit permutation preserves the number of ones and zeros and does not, by itself, establish any particular entropy gain. XORing a Skein-1024-XOF stream, two SHAKE256 streams, and two AES-256-CTR streams does not allow their security strengths to be added together either. This construction implements the requested sequence; it is not a standardized or externally audited random number generator. The operating system's cryptographic random source remains the underlying security assumption.

Each AES stream uses a new key fragment for each generation. Its counter must never repeat under that key; counter exhaustion stops the stream. The AES streams add to the custom construction while fresh macOS random bytes remain part of every output request.

## Output protection

The existing runtime checks remain in place: a valid signature for the running code, Hardened Runtime, a minimal App Sandbox, disabled POSIX core dumps, and no detected debugger. These checks run again immediately before generation, display, and copying.

Output is initially concealed. Revealing it requires confirmation; the app makes a best effort to hide it again after 60 seconds or on a context change. Copying requires an explicit click and uses `currentHostOnly`; the app makes a best effort to clear the clipboard after about 45 seconds if its contents remain unchanged. The mouse pool and temporary cryptographic buffers are overwritten on disposal on a best-effort basis. Complete erasure of Swift strings, registers, and operating system copies cannot be guaranteed.

The app does not save generated passwords to files or preferences. A local app cannot reliably prevent screenshots, recording with an external camera, or exposure on a compromised operating system.

## Integrity and tests

Both wordlists are checked against embedded SHA256 and SHA3-512 values before use. The complete final release ZIP is hashed with SHA256, SHA3-512, and Skein-1024-1024. Each algorithm has its own checksum file. The additional Skein file is named `Password.Generator-2.3.0.zip.skein-1024-1024`, and the integrity manifest records its value in the `skein-1024-1024` field.

`Scripts/verify-release.sh` independently checks SHA256 and SHA3-512 using Python. It checks Skein-1024-1024 through `Scripts/skein-reference-checksum.sh`, which uses the official C reference implementation in `Tests/Reference/Skein`. The verifier also extracts the ZIP and checks the code signature and sandbox.

These additional integrity checksums do not replace or change Apple's Developer ID signing process. Creating these external checksum files and the integrity manifest does not modify the app bundle or the final ZIP. Hash values alone do not prove provenance.

Test results for version 2.3.0, build 7: 87 tests passed in each of the Debug and Release builds, with no compiler warnings: 67 Core tests and 20 app tests per build. The [verification section of the technical analysis (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) documents release checks. Test results and Apple approval for earlier releases do not establish the verification status of this version.

## Logo and icon

`Assets/PasswordGeneratorIcon.png` is the source for the macOS icon. `Assets/PasswordGeneratorLogo.png` contains the standalone brand symbol used in the interface. The generation process and prompts are documented in [Assets/README.md (German)](Assets/README.md). The packaging script generates all macOS icon sizes and `AppIcon.icns` from the icon source.

## Sources and third-party material

[Third-party notices](THIRD_PARTY_NOTICES.md) document the sources and licensing information for the embedded wordlists and test data.


## Primary sources

- [BIP39 specification](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Long Wordlist](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [EFF: Dice-Generated Passphrases](https://www.eff.org/dice)
- [Skein v1.3 and official test vectors](https://www.schneier.com/academic/skein/)
- [NIST SP 800-38A: AES-CTR](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [NIST FIPS 180-4: SHA-512](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [NIST FIPS 202: SHA3 and SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [Durstenfeld: Algorithm 235, Random permutation](https://doi.org/10.1145/364520.364540)
- [Apple: SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
