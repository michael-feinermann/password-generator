# Windows parity target: Password Generator 2.3.6

The Windows port targets the behavior of the upstream macOS 2.3.6/build 13
source at `3300f560dcbb2ff7396e3250e66afcca04e2ca10`. Native Windows controls,
fonts, window chrome and platform protections differ. This checklist is a
specification, not evidence that every item has already passed. The Windows
security audit records the final implementation and verification status.

## Generation and export

| Mode | Supported lengths | Default | Selection space |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21, 24 words | 24 | 128/160/192/224/256 entropy bits; SHA256 checksum excluded |
| EFF | 6–128 words | 20 | 7,776 words; `length × log2(7776)` bits |
| ASCII | 8–256 characters | 40 | 94 printable characters U+0021–U+007E; no composition rules |
| PIN | 3–512 digits | 6 | Digits 0–9, including leading zero; `length × log2(10)` bits |
| Hex | 1–512 characters | 64 | Lowercase 0–9/a–f; `length × 4` bits |

- Switching mode restores its default length; invalid drafts disable generation.
- BIP39 uses the exact English list, SHA256 checksum and bit ordering. EFF
  uses the original dice-labelled long list. The SHA256, SHA3-512 and
  Skein-1024-1024 pins validate the same byte snapshot before parsing.
- EFF/ASCII/PIN/Hex use unbiased rejection sampling; EFF candidates are
  big-endian 16-bit values. Broken providers fail on byte-count mismatch or
  1,024 consecutive rejected candidates.
- BIP39 defaults to a space separator, EFF to `-`. Separators are literal and
  may be empty or multi-character. Hex uppercase changes presentation only.
  Export changes do not reroll an existing result or add entropy.
- Security colors use the unrounded nominal selection bits: red below 128,
  yellow 128–<256, light green 256–<1,024, dark green at least 1,024. Tooltips
  qualify those labels. Classical/Grover values retain logarithmic arithmetic,
  rates 10^18 checks/sec and 10^15 iterations/sec, and the upstream physical
  model assumptions. They do not measure source entropy or promise security
  of a downstream cipher or endpoint.

## Mouse pool and byte stream

- Capture movement and drag events throughout the app window only, including
  controls. No global mouse hook. Ignore nonmovement events.
- Retain the latest 4,096 complete records. Each canonical record is 89 bytes:
  version byte 1, then 11 little-endian UInt64 fields (sequence, uptime in ns,
  timestamp/x/y/deltaX/deltaY/width/height IEEE-754 bit patterns, modifier flags,
  pressed-button flags). Platform event values differ from macOS; serialization
  and the deterministic cryptographic pipeline remain compatible.
- Initial empty shuffle, then six-second timer and another shuffle immediately
  before generation. Durstenfeld/Fisher-Yates uses OS CSPRNG bytes, buffered
  little-endian UInt32 rejection sampling and a bounded stall error. Index
  indirection preserves chronological replacement after pool shuffles.
- Hash the shuffled serialized pool only at generation: Skein-1024-1024 (128
  bytes), SHA3-512 (64), SHA512 (64), concatenated in that order. XOR 256 fresh
  OS bytes, permute all 2,048 bits using independent OS randomness, XOR another
  independently requested 256-byte OS mask.
- Split the 256-byte master into 128/32/32/32/32 bytes for Skein-1024-XOF,
  SHAKE256, SHAKE256, AES256-CTR, AES256-CTR. The two AES streams start at zero
  and retain partial blocks under big-endian 128-bit counters. Reject exhaustion.
- XOR equal outputs of all five advancing streams, then an equal fresh OS mask
  on every read, including reads requested by rejection sampling. Bound each
  request to 0–1,048,576 bytes. Disposed streams reject use.
- Clear master immediately after initializing states; clear all states before
  publishing the result and on errors. Clear temporary buffers, selection indices,
  stored result and pool on discard/orderly shutdown. Concealed UI rendering
  avoids reconstructing plaintext; explicit reveal or copy creates managed
  strings outside owned buffers. Page locking is best effort.

## User workflow and persistence

- Generation requires 4,096 movements, valid configuration, an explicit secure
  environment confirmation and a current successful runtime assessment.
- Output starts concealed. Reveal asks for confirmation; hide after about 60
  seconds and immediately on deactivation/lock/session change. Context changes
  also reset the secure-environment confirmation.
- Copy is an explicit action on visible output, with another runtime check.
  Use Windows clipboard-history/cloud exclusion flags. Clear after about 45
  seconds only while the app still owns unchanged clipboard content. Discard
  and orderly exit attempt immediate removal under the same ownership rule.
- Discard asks for confirmation, clears result and old pool, starts collecting
  again. Mode/length are disabled while generated; separator/case may still change.
- English first, German second. Only the `en|de` language value persists; absent
  or invalid value starts English. Mode, length, separators, hex case, passwords,
  mouse records and security confirmations start fresh after relaunch.
- Preserve the supplied logo, dark panel layout, status/progress, wordlist digest
  details and localized explanatory copy with Windows platform terminology.

## Windows security replacements and limits

| macOS behavior | Windows treatment |
|---|---|
| SecRandomCopyBytes | .NET `RandomNumberGenerator` backed by Windows CSPRNG; propagate errors |
| Apple signature validity | Independently anchored signed file inventory; both RSA4096-PSS/SHA512 and ML-DSA-87 must verify |
| Hardened Runtime/App Sandbox | No equivalent claim for standalone WPF; document Windows process checks and their narrower scope |
| No debugger/core dumps | Fail closed on detected debugger or failed required checks; best-effort Windows Error Reporting suppression |
| `mmap`/`mlock`/`memset_s` | Owned memory, attempted `VirtualLock`, explicit `CryptographicOperations.ZeroMemory` and disposal |
| `currentHostOnly` pasteboard | Windows history/cloud exclusion formats plus clipboard sequence ownership |
| Best-effort concealment | WPF deactivation/session events and capture exclusion if available; no screenshot guarantee |

The Windows build number is 14. Windows uses a distinct inventory-signing domain
`PasswordGenerator.Windows.Inventory.v1\0` and ML-DSA context
`PasswordGenerator.Windows.2.3.6`, rather than macOS/Keep Vault's sidecar format.

Private Windows signing material belongs only under `A:\Passoword Generator Keys`, never
in the repository, publish directory, installation or logs. Use a separate
Password Generator identity and never overwrite pre-existing keys. The requested
FAT32 volume does not enforce NTFS ACLs; private PKCS8 and the independently
protected PFX password therefore use Windows DPAPI CurrentUser wrapping. This
depends on the Windows profile's DPAPI recovery material; copying these files
alone to another account or machine does not make them usable. Public keys
and trust pins may be committed. A self-signed certificate does not establish a
publicly trusted Authenticode publisher. Both detached signatures authenticate
artifact bytes only when the trust anchor came from a separately trusted source.

The inventory must bind product, 2.3.6 version/build, safe relative paths, sizes,
hashes and exact directories/files. Reject symlinks/reparse points, missing or
extra payload, duplicate/traversal paths, malformed signature parameters and
either invalid signature. Recheck the gate before generation, reveal and copy.
Verification cannot defeat an administrator changing process memory or Windows;
forced termination cannot guarantee cleanup; visible text, framework strings,
clipboard and operating-system copies cannot all be irrevocably wiped.

## Required verification

1. Run the upstream BIP39, Skein, SHA3, SHAKE, Skein-XOF, AES-CTR and full
   pipeline vectors against Windows, including absorb/squeeze/block boundaries
   and split reads. Test selection boundaries, invalid inputs, provider failures,
   cleared state and pool replacement/shuffle behavior.
2. Validate signed release and installed inventories. Tamper RSA signature,
   ML-DSA signature, inventory, key, executable/resource; add/delete files and
   reparse paths. Every required check must fail closed.
3. Exercise fresh launch, both language choices across relaunch, all formats,
   visibility confirmation/timer/deactivation, clipboard ownership/timer,
   discard and orderly shutdown without exporting test secrets to logs.
4. Scan tracked files and release artifacts for private-key/envelope/password
   leakage and app source for networking/password persistence. Record the
   exact build, tests and installation evidence in the Windows audit.

The recorded Windows verification passes 13 core groups/9,743 assertions,
33 model assertions with actual clipboard/concealment timers and 37 adversarial
security checks. Installed and ZIP payloads match the exact signed 405 files
and 14 directories; independent OpenSSL checks accept both signatures. The
installed app launched and responded; a prior installed GUI check reported a
successful runtime gate. Interactive generation through the installed GUI,
a fresh final GUI accessibility check and visual identity were not established.
Capture exclusion prevented reliable coordinate automation. See the
[audit](WINDOWS_SECURITY_AUDIT_2.3.6.md) for recorded evidence and scope.
