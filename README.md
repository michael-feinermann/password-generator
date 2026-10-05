# Password Generator for macOS

English | [Deutsch](README.de.md)

<img src="Assets/PasswordGeneratorIcon.png" width="128" alt="Password Generator icon">

[Download the app](https://github.com/michael-feinermann/password-generator/releases/latest) · [Release notes 2.3.6](docs/RELEASE_NOTES_2.3.6.md) · [Technical analysis (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)

Version 2.3.6, build 13. Signed with Developer ID and notarized through Xcode on 5 October 2026; stapling, Gatekeeper and the final release verifier passed.

Release policy: GitHub keeps only the current version as a release with download assets and a release tag. The source history and historical release notes remain available for reference. The download link above always points to the current release.

A native, local macOS app for seed phrases, EFF passphrases, ASCII passwords, PINs, and hexadecimal values. The interface is available in English and German, and the app has no network access. Its visible name is “Password Generator 2.3.6”.

The regular window size of 1,060 × 840 points is the minimum. The content and typography grow with larger windows and full-screen mode. App text uses at least 14-point type; powers use readable caret notation such as `10^106` and `2^(n/2)`.

| Format | Length | Alphabet | Displayed entropy |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21, or 24 words | Official English wordlist | 128, 160, 192, 224, or 256 bits |
| EFF | 6 to 128 words | EFF Long Wordlist, 7,776 words | Words × log₂(7,776) |
| ASCII | 8 to 256 characters | 94 printable ASCII characters, `!` through `~`, without spaces | Characters × log₂(94) |
| PIN | 3 to 512 digits | `0` through `9`, leading zeros allowed | Digits × log₂(10) |
| Hex | 1 to 512 hexadecimal characters | `0` through `9`, `a` through `f` or `A` through `F` | Characters × 4 bits |

The entropy display describes the size of the uniformly sampled output space. It neither measures the entropy of mouse movements nor guarantees a corresponding level of resistance to attacks on the overall system. BIP39 checksum bits do not count as additional entropy. Repeated words and characters are allowed; additional composition rules would change the output space.

## Defaults and color levels

Version 2.3.6 starts each format with these lengths:

| Format | Default | Nominal bits |
|---|---|---|
| BIP39 | 24 words | 256 |
| EFF | 20 words | 20 × log₂(7,776) ≈ 258.50 |
| ASCII | 40 characters | 40 × log₂(94) ≈ 262.18 |
| PIN | 6 digits | 6 × log₂(10) ≈ 19.93 |
| Hex | 64 characters | 64 × 4 = 256 |

For BIP39, EFF, ASCII, and Hex, these are the shortest supported lengths reaching at least 256 nominal bits. PIN is deliberately a six-digit exception. The full selectable length ranges remain available.

The configuration and generated result show the nominal bit value together with a color and a text label. The unrounded value determines the level; each next level starts at exactly 128, 256, or 1,024 bits.

| Nominal bits | Color | Label |
|---|---|---|
| Below 128 | Red | crackable |
| 128 to below 256 | Yellow | not quantum-safe |
| 256 to below 1,024 | Light green | practically unattackable |
| 1,024 or more | Dark green | thermodynamically unattackable |

The info button beside each level explains its scope and the attack models; the information is also accessible by keyboard. The labels describe uniformly random password guessing, with these qualifications:

- Red identifies the lowest range. It does not mean that every password below 128 nominal bits can be cracked with available equipment.
- Yellow identifies reduced resistance in the idealized Grover model. It does not classify every algorithm using these passwords as broken by quantum computers.
- Light green denotes a very large modeled search effort. It does not exclude attacks on the random source, key derivation, encryption, implementation, or endpoint.
- Dark green exceeds both the conditional energy comparison and the assumed time horizon described below. It does not establish unconditional thermodynamic impossibility.

The displayed bits measure the nominal selection space, not the actual entropy supplied by the random sources. A six-digit PIN has a small offline guessing space; its suitability also depends on the use case and enforced attempt limits. These labels are not NIST security categories. [NIST's quantum-computing guidance](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs) considers practical costs and continues to permit AES-128, AES-192, and AES-256.

## Attack-time and physical comparison models

For `n` nominal bits and one valid target among `N = 2^n` equally likely candidates, the app estimates:

| Model | Assumed rate | Displayed time in seconds |
|---|---|---|
| Classical exhaustive search | 10¹⁸ complete candidate checks per second | `2^n / 10^18` |
| Idealized Petahertz quantum computer using Grover search | 10¹⁵ complete Grover iterations per second | `(π/4) × 2^(n/2) / 10^15` |

The classical value covers the entire space, rather than the average discovery time. The Grover value is a continuous approximation for near-certain success with one target. Both rates are assumptions, not benchmarks. Exascale FLOPS count floating-point operations, not password checks; likewise, the optoelectronic 1-PHz research does not establish a universal processor limit or a realizable quantum oracle. [DOE: Supercomputing](https://www.energy.gov/topics/supercomputing), [Zalka: Grover's quantum searching algorithm is optimal](https://arxiv.org/abs/quant-ph/9711070), [Ossiander et al.: The speed limit of optoelectronics](https://pmc.ncbi.nlm.nih.gov/articles/PMC8956609/).

The energy comparison assumes one irreversibly erased information bit per check or Grover iteration at 2.7 K, costing at least `k_B × T × ln(2) ≈ 2.58388 × 10^-23 J`. Its budget is `3 × 10^71 J`, an upward-rounded cosmological comparison scale including dark energy, not available work energy. Reversible computation does not require this erasure after every step. In particular, the assumed cost per Grover iteration is additional to Landauer's principle. [Landauer (1961)](https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf), [Bennett (1973)](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html).

A separate time comparison allows `10^106` years, each of 31,557,600 seconds. This rests on the explicit model assumption that the universe has reached maximum entropy by then, also known as heat death. Without usable energy gradients, no free energy remains for sustained computer operation and the disposal of generated heat. In this scenario, both available free energy and usable computing time therefore limit every physically operated computer, including quantum computers. In particular, irreversible information erasure requires heat release and a corresponding entropy increase outside the memory; ideal reversible steps do not require a fixed entropy increase per step. [Bennett (1973)](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html).

This order of magnitude is inspired by scenarios for the evaporation of exceptionally massive black holes. It is not an established latest heat-death deadline for the entire universe; the long-term cosmological outcome remains conditional. [Hawking (1975)](https://doi.org/10.1007/BF02345020), [An et al. (2020), section 3.2](https://doi.org/10.1093/mnras/staa1343), [Adams and Laughlin (1997), section VI.D](https://arxiv.org/pdf/astro-ph/9701131).

At 1,024 nominal bits, the modeled Grover time is about `3.34 × 10^131` years, or `3.34 × 10^25` times that horizon. This time comparison does not depend on assigning a Landauer cost to every iteration, but it still depends on the assumed rate, horizon, and search problem. Exceeding either budget does not make an early lucky guess impossible.

Threefish-1024 accepts a 1,024-bit key. A 1,024-bit nominal password space alone does not prove equally strong source entropy or key material; a suitable derivation and secure implementation are still required. Expanding a password into several keys does not add independent entropy, and cascade strengths cannot simply be added. No guarantee for every cipher or cascade follows. [Skein/Threefish specification v1.3, sections 3.3 and 6.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf). [Full assumptions, thresholds, and sources](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#attack-cost-models).

## Export format

For EFF and BIP39, the separator can be freely chosen in a text field. BIP39 defaults to a space, and EFF defaults to `-`. An empty field joins the words without a separator; spaces and separators containing multiple characters are also supported. Hex output can use lowercase or uppercase letters. These settings apply to clipboard output and can be changed after generation. Hex letter case also applies to the displayed output. The generated words or hexadecimal values remain the same; no new random selection takes place.

BIP39 wallets usually expect words separated by spaces. The internal BIP39 checksum is always checked against the original word sequence. Without separators, BIP39 word boundaries cannot always be reconstructed unambiguously; different valid word sequences can produce the same concatenated text. The displayed entropy therefore describes the original selection and does not establish the entropy of arbitrary export representations. Hexadecimal letter case and fixed separators do not add random bits.

## Running and building

```sh
swift test -Xswiftc -warnings-as-errors
zsh Scripts/package-app.sh
ALLOW_UNNOTARIZED_DEVELOPMENT=1 zsh Scripts/verify-release.sh
python3 Scripts/test-release-checks.py
open "build/Password Generator 2.3.6.app"
```

The release targets Apple Silicon (`arm64`) running macOS 14 or later. Use the signed app bundle to run the application. `swift run PasswordGeneratorApp` is intended only for development; a process without the required signature does not satisfy the runtime conditions for generation.

The packaging script creates `build/Password Generator 2.3.6.app`, `build/Password.Generator-2.3.6.zip`, three checksum files, and an integrity manifest. Without an explicit `SIGN_IDENTITY`, the local build uses an ad hoc signature. A Developer ID certificate in the keychain can be selected by its fingerprint. `NOTARY_PROFILE` enables optional notarization using an existing keychain profile, followed by stapling and ZIP recreation. Credentials and private keys are not stored in the project. The actual signing and notarization status is documented in each release and its integrity manifest. The project directory remains `Seed-Phrase`; the app, Swift package, modules, bundle identifier, and release files now use Password Generator or PasswordGenerator.

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

Among generator preferences, only the last selected language is saved across launches, stored locally as `preferredLanguage=en` or `preferredLanguage=de`. A fresh launch without a valid preference starts in English; the language buttons show English first and German second. Passwords, mouse records, generator mode and length, separators, hexadecimal letter case, and security confirmations are never written to this preference store and start fresh on each launch. Existing macOS window storage remains allowed and unchanged. The app does not save generated passwords to files or preferences. A local app cannot reliably prevent screenshots, recording with an external camera, or exposure on a compromised operating system.

The raw master key is overwritten immediately after the five generator states have been initialized, before any password bytes are requested. These states are cleared before the result is published to the UI, including on errors. The stored password and mouse pool use owned reference buffers, with `memset_s` overwriting on discard or orderly application shutdown; password wrapper copies share the same cleared storage. Buffers use exclusive, page-aligned `mmap` allocations; page locking is attempted with `mlock` and is best effort. Hidden word output does not materialize plaintext strings. Explicit display and copying still create Swift and framework strings, so complete irrevocable erasure of every RAM, register, UI or operating-system copy cannot be guaranteed. Forced termination cannot run cleanup hooks. [Internal security audit and remaining limits](docs/SECURITY_AUDIT_2.3.6.md).

`Scripts/verify-release.sh` requires notarized Developer ID distribution by default, including the expected team, product, version, build, Hardened Runtime, minimal entitlements and safe archive paths. `ALLOW_UNNOTARIZED_DEVELOPMENT=1` explicitly enables local development checks and does not establish notarization.

## Integrity and tests

Both the BIP39 and EFF wordlists are checked against embedded SHA256, SHA3-512, and Skein-1024-1024 values before use. The app displays all three digests for each list, with Skein-1024-1024 after SHA256 and SHA3-512. The expected Skein wordlist values are independently cross-checked using the official C reference implementation in `Tests/Reference/Skein` through `Scripts/skein-reference-checksum.sh`. The complete final release ZIP is hashed with SHA256, SHA3-512, and Skein-1024-1024. Each algorithm has its own checksum file. The additional Skein file is named `Password.Generator-2.3.6.zip.skein-1024-1024`, and the integrity manifest records its value in the `skein-1024-1024` field.

`Scripts/verify-release.sh` independently checks SHA256 and SHA3-512 using Python. It checks Skein-1024-1024 through `Scripts/skein-reference-checksum.sh`, which uses the official C reference implementation in `Tests/Reference/Skein`. The verifier also extracts the ZIP and checks the code signature and sandbox.

These additional integrity checksums do not replace or change Apple's Developer ID signing process. Creating these external checksum files and the integrity manifest does not modify the app bundle or the final ZIP. Hash values alone do not prove provenance.

On 5 October 2026, all 120 XCTest tests passed in Debug, Release and Release with AddressSanitizer (83 Core, 37 App), without failures, compiler warnings or reported memory errors. All 48 release-gate checks passed (8 positive, 40 negative). [Verification scope and release evidence (German)](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

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
