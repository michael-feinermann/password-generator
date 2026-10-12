# Internal Windows security audit: Password Generator 2.3.6

Date: 12 October 2026. Windows build 14. Upstream baseline:
3300f560dcbb2ff7396e3250e66afcca04e2ca10 (macOS 2.3.6/build 13).

## Scope and result

The reviewed Windows implementation passes the recorded cryptographic,
model/clipboard/timer, adversarial inventory and final artifact checks. The
findings below were corrected and reviewed. No unresolved critical finding was
identified within this scope. The installed application launched and responded;
a prior installed GUI check reported a successful production runtime gate.
The final 405-file installation was independently verified, but a fresh final
GUI accessibility read was unavailable. Interactive generation through the
installed GUI was not exercised: capture exclusion prevented reliable coordinate
input through the available screenshot automation.

This internal review covers the .NET 10/WPF application and core, exact
wordlists, bounded mouse pool, Skein/XOF/SHA3/SHAKE/AES-CTR pipeline, unbiased
selection, secret lifetime, reveal/clipboard/preferences, hybrid runtime
verification, signer and installation/release scripts. Source review was
separate from implementation work; execution evidence was reviewed from the
test and release agents. This is not a third-party audit, cryptographic proof,
CAVP validation, antivirus assessment or certification of Windows.

| Review dimension | Assessment | Basis |
|---|---|---|
| Security | Pass within the stated application boundary | Fail-closed hybrid inventory, independent OpenSSL checks, corrected secret/clipboard cleanup, adversarial rejection |
| Correctness | Pass for tested source and artifacts | Independent upstream fixtures, complete pipeline/model generation, real native clipboard/timers, installed/ZIP inventory |
| Performance | Bounded design; no performance certification | 4,096-record ring buffer, linear shuffles, bounded rejection/read sizes, local events only |
| Maintainability | Satisfactory | Separate core/app/security/signer projects, warnings as errors, no external NuGet packages, documented native-platform limits |

## Findings and corrections

Priorities describe remediation order, not CVSS scores or demonstrated exploits.
All listed corrections are present in the reviewed source.

| Finding | Priority | Final correction and evidence |
|---|---|---|
| Initial managed secret allocation had no page-lock attempt. | P2 | SensitiveBytes owns page-aligned VirtualAlloc memory, attempts VirtualLock, zeroes the entire allocation before unlock/free and disposes idempotently. Core tests cover cleared output and reuse rejection; native wiping is verified by source inspection. |
| Clipboard operations could race with another writer; Windows text-format synthesis changed the committed sequence and made own cleanup skip. | P1 | PrivateClipboard writes under OpenClipboard, then reacquires the lock to bind the committed sequence to the owner HWND. Cleanup rechecks both under the lock. Real native tests preserve replacement contents and clear own content on reset and after 45 seconds. |
| Clipboard error paths could leave native plaintext unwiped or retain the lock after character allocation failed. | P2 | Character allocation is inside try/finally; an untransferred HGLOBAL is overwritten before GlobalFree. Transferred memory belongs to Windows. |
| Window closure could destroy the clipboard-owner HWND before cleanup. | P2 | MainWindow.Closing clears materialized controls and disposes the model before HWND destruction; Closed stops native hooks/timers. Disposal is idempotent. |
| Initial runtime integration lacked the signed inventory gate. | P1 | RuntimeSecurity.Check requires both RSA4096-PSS/SHA512 and ML-DSA-87 against embedded keys, exact inventory, debugger checks, restricted search and WER readback before generation, reveal and copy. Installed verification passed. |
| Native DLL lookup before inventory validation exposed an avoidable planting path. | P1 | App/signer assemblies restrict imports to System32. WER calls use kernel32 exports and verified flag readback on the tested host. |
| Private-key exception paths could skip wiping an already produced/decrypted buffer. | P2 | Signer provisioning/unwrapping starts its outer cleanup scope before the first secret operation. DPAPI native output is wiped before LocalFree; PKCS12 import uses EphemeralKeySet. |
| BIP39 production checksum validation was initially absent; an early correction exported a joined phrase to validate it. | P2 | Core.Generate now validates original shared-wordlist components before owned result creation and clears the selection array. The model does not export a joined phrase before reveal. Official vectors and complete model generation pass. |
| Captured drags could include coordinates outside the app client area. | P2 | GetClientRect bounds native coordinates and records dimensions in the same pixel units. No global mouse hook exists. |
| Configurable installation could recurse into its own source or escape through an ancestor junction. | P2 | Installer rejects targets inside the package, outside the user's Programs directory, under reparse ancestors or already existing; verifies before/after copy. Existing installations are never overwritten. |
| Windows checkout line endings could invalidate exact wordlist pins. | P2 | Canonical LF resources and .gitattributes preserve upstream byte identities. All three hashes and tamper rejection pass. |

## Recorded verification

All recorded tests below passed on .NET 10.0.12 / Windows 10.0.26300. Windows
checks do not reuse macOS XCTest or notarization results.

| Check | Result | Recorded output |
|---|---|---|
| Core | 13 groups, 9,743 assertions, zero failures | [core-tests.txt](evidence/windows-2.3.6/core-tests.txt) |
| App model | 33 assertions, real 45-second clipboard and 60-second reveal timers | [app-model-tests.txt](evidence/windows-2.3.6/app-model-tests.txt) |
| Adversarial security | 37 positive/negative checks | [security-tests.txt](evidence/windows-2.3.6/security-tests.txt) |
| Final publish | Self-contained Release win-x64 publish succeeded | [publish.txt](evidence/windows-2.3.6/publish.txt) |
| Installed payload | Both signatures and exact 405-file payload verified | [installed-inventory.txt](evidence/windows-2.3.6/installed-inventory.txt) |
| Final ZIP payload | Exact 405 signed files / 14 directories; 147,817,322 uncompressed bytes reported | [archive-inventory.txt](evidence/windows-2.3.6/archive-inventory.txt) |
| Independent signatures | OpenSSL accepted both algorithms for final inventory and ZIP | [inventory](evidence/windows-2.3.6/openssl-inventory.txt), [ZIP](evidence/windows-2.3.6/openssl-archive.txt) |
| Final release record | Artifact hashes, exclusion checks and explicit limits | [verification.json](evidence/windows-2.3.6/verification.json) |

Core tests consume upstream independent Skein, SHA3, SHAKE, AES-CTR, BIP39 and
full-pipeline fixtures, including split-read/block boundaries, AES carry and
exhaustion, overwritten pools after intermediate shuffles, exact OS request
sequence and all modes. They cover invalid lengths, biased tails, bounded
stalls, provider mismatches/exceptions, both master-mask failure positions with
no later RNG calls, and output failure after a successful read. A retained
malformed RNG buffer is inspected and found zero after rejection. Native result
memory is freed on clear; tests assert cleared state and empty exports, rather
than reading freed memory or claiming physical RAM proof.

Model tests link production model/clipboard/preferences code with an isolated
runtime-check test double. They exercise complete BIP39 generation after 4,096
test records, initial concealment, readiness/confirmation/runtime gates,
discard, context concealment, language persistence, clipboard exclusion formats
and actual timers. Production signature/runtime checking is verified separately
on installed artifacts. These tests do not establish interactive installed-GUI
generation, cross-launch visual identity or a screenshot guarantee.

Security negatives include corrupted/truncated signatures/metadata, wrong
product/version/build/architecture/schema, unsafe/duplicate paths, alternate
streams, changed file/directory sets, signed size/digest mismatches, unknown
signed JSON fields, different anchors and an actual directory junction.
Both algorithms are mandatory; either failure rejects the release.

Source scans found no HTTP/socket/telemetry API use in app/core. The only app
disk write is the fixed en/de language value. Passwords, records, mode/length,
separators/case and confirmation are never persisted. Repository filename and
PEM-header scans found no private keys; final publish/installed-file scans found
no private container/envelope filenames. These are concrete exclusion checks,
not proof against arbitrarily encoded secret data. Passwords are not logged.

## Trust, key storage and remaining limits

Standalone WPF does not provide Apple's App Sandbox, Hardened Runtime, Developer
ID or notarization. Inventory/debugger checks do not create OS containment.
The self-signed certificate does not establish a publicly trusted Authenticode
publisher; the executable has no publicly trusted Authenticode signature.
Signatures authenticate exact bytes only with an independently obtained anchor.
A maliciously replaced executable can replace its own verifier. Signatures do
not establish source-to-binary reproducibility. Running requires Windows CNG
ML-DSA/SHA3/SHAKE support; unsupported hosts fail closed.

Private material is stored only in A:\Passoword Generator Keys. RSA-4096 uses an
AES256-CBC/PBKDF2-SHA256 PKCS12 with 200,000 iterations; its independent random
password and ML-DSA-87 PKCS8 use DPAPI CurrentUser protection. FAT32 has no
enforced NTFS ACLs. Recovery depends on the Windows profile's DPAPI material;
copying encrypted files alone to another account/machine is insufficient.
Only public keys/certificate/pins are committed. Provisioning refuses to replace
a nonempty key directory.

The custom five-stream construction relies on trusted Windows CSPRNG bytes.
Mouse-event counts and 2,048 concatenated hash bits do not establish independent
entropy; stream strengths cannot be added. Nominal bits describe the uniformly
sampled output space, with the upstream attack-model assumptions.

Page locking, capture exclusion, WER heap exclusion and cleanup are best effort.
Explicit reveal/copy creates managed strings, WPF rendering and Windows copies
that cannot all be erased or revoked. Forced termination/power loss can prevent
cleanup. Clipboard consumers can read output before clearing; privacy formats
cannot force every third-party manager to comply. WER exclusion does not prevent
administrator dumps or every crash report. Administrators, session malware or a
compromised host can defeat application checks. No complete irrevocable
RAM-erasure or screenshot guarantee is made. No independent antivirus scanner
was run.

See the [parity target](WINDOWS_PARITY_2.3.6.md) and
[Windows build/signing instructions](../Windows/README.md) for reproduction.
