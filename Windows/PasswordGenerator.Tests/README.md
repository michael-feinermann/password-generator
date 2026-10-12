# Windows core verification

This executable test harness has no NuGet test dependencies. Run it on a Windows
system with .NET 10 and native SHA3/SHAKE support:

```powershell
dotnet run --project Windows/PasswordGenerator.Tests/PasswordGenerator.Tests.csproj -c Release
```

The final line is a JSON result with group, assertion and failure counts. A failed
group makes the process exit nonzero. The original committed macOS test resources
are embedded unchanged: 81 SHA3-512 and 538 SHAKE256 NIST vectors, 49 Skein-1024
hash vectors, 22 Skein XOF reference vectors, 5 AES-CTR vectors, 24 Trezor BIP39
vectors and 3 full pipeline cases. See the source fixture attribution in
`Tests/PasswordGeneratorCoreTests/Resources/CRYPTO_VECTORS.md`,
`AES_CTR_VECTORS.md`, and `SKEIN_XOF_VECTORS.md`.

The pipeline cases independently exercise canonical little endian mouse records,
record permutations, chronological overwrite after earlier shuffles, all three
hashes, both master masks, the 2048-bit permutation, five advancing streams,
split reads at their block boundaries and every generated output format. Sampler
tests enumerate the complete byte or two-byte candidate domains and check equal
accepted multiplicities. Failure tests check invalid configurations before any
random read, provider exceptions, wrong lengths, stalled rejection sources,
insufficient mouse samples, both failed master masks and fail-closed stream reuse.

Disposal tests verify empty result exports, rejection of disposed streams and
zeroing of retained malformed provider buffers. The native owned allocation's
wipe-before-free behavior is verified by source review; these tests do not inspect
freed memory. Framework and exported string copies cannot be erased by the core.

The runtime primitive/word-list/RNG self-test can run separately:

```powershell
dotnet run --project Windows/PasswordGenerator.Tests -c Release -- --selftest
```

The harness also provides deterministic checksum tooling for public release
artifacts (SHA256, SHA512, SHA3-512 and Skein-1024):

```powershell
dotnet run --project Windows/PasswordGenerator.Tests -c Release -- --checksum Skein-1024 path/to/file
```

Canonical word-list bytes are bundled under `Windows/PasswordGenerator.Core/Resources`.
Those files must remain UTF-8 without a BOM and with LF newlines because all three
expected integrity values hash the original complete byte sequences. The code
rejects altered resources before password generation.
