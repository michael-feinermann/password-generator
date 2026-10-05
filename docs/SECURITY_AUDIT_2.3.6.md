# Internal security audit, Password Generator 2.3.6

Date: 5 October 2026. Version 2.3.6, build 13. English is primary; a German account follows below.

## Scope and conclusion

This internal audit covers the complete app and core source, local mouse-event acquisition, random-source interfaces, the hash and five-stream construction, unbiased password selection, BIP39 checksums, both wordlists, secret storage and destruction, UI exposure, clipboard lifecycle, persistence, sandbox/runtime protections and the packaging/public-release verification scripts. It includes manual source review, independent existing cryptographic fixtures, boundary/error tests and adversarial release checks. This is not an independent third-party audit, a proof of cryptographic security or a certification of the host operating system.

The concrete findings below are addressed in this version. The cryptographic sequence and output alphabets are unchanged; the unchanged independent pipeline fixtures must still pass. Final verification evidence is recorded below once complete.

## Findings and corrections

The priority labels indicate remediation order within this audit, not a CVSS score or demonstrated exploit.

| Finding | Priority | Correction | Evidence |
|---|---|---|---|
| The result stored immutable `String` and `[String]` values and discarded them with `nil`, without overwriting their password bytes. | P1 | `GeneratedPassword` now owns a shared `SensitiveBytes` reference buffer. `clear()` uses `memset_s`; all wrapper aliases become empty together. Only explicit access constructs display/export strings. | Owned-memory and model tests inspect live storage and retained wrappers after clearing, including before published removal. |
| BIP39 bit arrays, checksum digests and partially decoded entropy on error could remain after release. | P1 | Explicit `defer` wipes for bit arrays, digests, validation entropy and error entropy; an owned SHA256 context is wiped. | Official vectors, invalid checksum/unknown-word checks and the complete existing generation tests. |
| Array growth, digest concatenation and `Data` conversion created avoidable copies of mouse records and pool material. | P2 | Fixed owned mouse storage; raw owned 256-byte master; direct digest copy; SHA512 hashes the serialized array directly with a wiped CommonCrypto context. | Unchanged full-pipeline fixtures, including ring-buffer replacement and intermediate OS masks. |
| Password selection indices and partially accumulated indices on failure lacked explicit wipes; some erasure used ordinary assignments. | P2 | `memset_s` for owned numeric arrays, returned indices after use, partial failure indices and partially filled random-source buffers. | Bounded rejection/malformed provider tests; an injected random error leaves its still-live buffer entirely zero. |
| Derived stream states lived until after publication; concealed word output reconstructed plaintext unnecessarily. | P2 | A scoped helper clears streams before publishing results. Hidden word cells use counts/placeholders only; reveal/copy validate runtime before constructing strings. Consumed Skein block bytes are wiped. | Model tests for discard, termination and runtime failures; live Skein/SHAKE/AES state checks. |
| The release checker could accept a manifest changed to a development signature mode and did not require the expected distribution identity. | P1 | Default validation requires notarized Developer ID, the expected team/product/version/build, Hardened Runtime, minimal entitlements, stapling and Gatekeeper acceptance. Development mode needs an explicit opt-in. ZIP paths/types are checked before extraction. | Reproducible negative checks in `Scripts/test-release-checks.py`, plus verification of the exported and downloaded public artifacts. |

## Secret lifetime and persistence

The master key is never an app-model field. It is overwritten as soon as Skein-XOF, both SHAKE256 states and both AES contexts are initialized, including initialization errors. It is already cleared before password bytes are requested. The five derived states are cleared after generation, before UI publication, and on failures. They therefore do not remain until password discard.

Password discard explicitly overwrites the shared result buffer, clears the owned clipboard item when unchanged, conceals output and clears the old mouse pool. Orderly window closure and application termination run these cleanup paths. Termination stops timers and prevents further collection/generation. Owned buffers also overwrite themselves during deinitialization. Exclusive page-aligned `mmap` allocations avoid heap-sharing and alignment ambiguity. The complete allocated pages are overwritten before `munmap`. `mlock` is attempted to reduce paging of the owned pool, master and result; a failed lock does not silently become a guarantee against paging.

Among generator preferences, only `preferredLanguage` is written, containing `en` or `de`. English is the fallback and first choice, German second. Password mode, length, separators, hex case, confirmations, mouse data and result are session state. Existing window storage is allowed and unchanged. Persistence tests use isolated stores and pasteboards; they do not write production-language preferences.

## Remaining limits

- A trusted macOS CSPRNG, host, compiler and system cryptographic implementation remain assumptions. Fresh OS bytes are requested separately for both master masks, shuffle randomness and every output mask. The five-stream combination is custom, not a standardized DRBG; hash lengths, mouse-event counts and generator strengths cannot simply be added as independent entropy.
- The displayed entropy is the nominal uniformly sampled selection space. Assuming 0.5 conditional bits per mouse event is an input-model assumption, not an observed entropy estimate. A 256-bit CSPRNG security assumption does not prove a 1024-bit computational security guarantee for the whole application or an arbitrary cipher cascade. Existing analysis preserves this distinction.
- Swift Strings and framework/pasteboard copies constructed for explicit reveal/copy cannot all be located and overwritten reliably. Registers, earlier temporary value copies, UI rendering, OS snapshots or a compromised host remain outside the owned-buffer guarantee. Page locking is best effort. Crash, forced quit, power loss or `SIGKILL` can prevent cleanup hooks. No claim of complete irrevocable physical RAM erasure is made.
- Clipboard managers or another local process may read an explicitly copied password before it is cleared. The app suppresses Universal Clipboard through `currentHostOnly` and avoids deleting unrelated replacement contents. It cannot revoke an external copy.
- Empty word separators can make exported representations ambiguous. Entropy applies to the selected word sequence, not every formatting transformation. PIN defaults intentionally remain six digits.
- Code signatures and notarization establish distribution identity and Apple's acceptance checks; they do not prove the absence of implementation flaws. Sidecar hashes detect changes only when obtained through a trusted channel. Reproducible source-to-binary proof, formal verification, physical attacks and a third-party penetration test are outside this internal audit.

## Verification

Source verification passed on 5 October 2026: 120 XCTest tests each in Debug, Release and Release with AddressSanitizer (83 Core, 37 App), with no failures, compiler warnings or reported AddressSanitizer memory errors. The 48 release-gate checks passed (8 positive, 40 negative). The Xcode Direct Distribution export is notarized, stapled and accepted by Gatekeeper; its tested code and resources match before installation. Native quit/relaunch checks confirm both saved languages and fresh generator configuration. Public downloads are checked separately after publication; the technical analysis records artifact hashes and the notarization ID. Reproduce source checks with:

```sh
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
swift test -c release --sanitize=address -Xswiftc -warnings-as-errors
python3 Scripts/test-release-checks.py
zsh Scripts/verify-release.sh
```

The last command requires the five final notarized release assets. Local development packages use the explicit `ALLOW_UNNOTARIZED_DEVELOPMENT=1` flag; passing that mode does not prove notarization.

## Deutsch

Der interne Audit umfasst den gesamten aktuellen App- und Kryptografiecode sowie Paketierung und Releaseprüfung. Die belegten Lücken bei Ergebnis- und Zwischenpuffern, verdeckter Darstellung und dem Release-Prüfgate sind behoben. Der Masterkey wird unmittelbar nach Initialisierung der Generatoren überschrieben. Deren Zustände werden vor der Übergabe des Passworts an die Oberfläche bereinigt. Beim Verwerfen und regulären Beenden wird der gemeinsame Passwortpuffer ausdrücklich überschrieben; der alte Mauspool und eigene unveränderte Zwischenablageinhalte werden bereinigt.

Das ist eine überprüfbare Bereinigung der kontrollierten Puffer, keine Garantie einer unwiderruflichen Löschung aller Swift-, UI-, Register- oder Betriebssystemkopien. Erzwungenes Beenden kann Bereinigung verhindern. Der Audit ersetzt weder ein unabhängiges Gutachten noch einen formalen Sicherheitsbeweis. Nur die Sprachwahl wird unter den Generatoreinstellungen gespeichert; die vorhandene Fensterspeicherung bleibt erlaubt.

## Primary references

- [Apple mlock requirements](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/mlock.2.html)
- [Apple mmap](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/mmap.2.html)
- [Apple SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
- [Swift: Strings are value types](https://docs.swift.org/latest/documentation/the-swift-programming-language/stringsandcharacters/#Strings-Are-Value-Types)
- [Apple CommonCrypto context destruction](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/lib/CommonCryptor.c)
- [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Skein/Threefish specification v1.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
- [NIST FIPS 202, SHA3 and SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [NIST SP 800-38A, CTR mode](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [Technical analysis and full attack-model assumptions](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)
