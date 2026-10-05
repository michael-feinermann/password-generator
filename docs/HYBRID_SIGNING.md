# Hybrid release signatures

## English

Password Generator 2.3.6, build 13, has additional detached signatures made with
RSA-PSS/SHA-512 using an independent RSA-4096 key and ML-DSA-87 from FIPS 204.
Verification requires both signatures. Apple's Developer ID signature, notarized
export and stapled ticket remain intact. The application bundle and its release
ZIP are not changed by the additional signing step.

Three targets are signed: the complete release ZIP, the existing integrity
manifest, and a canonical JSON inventory of every regular file and directory in
the installed app. The inventory binds the product identifier, version, build,
relative paths, file sizes and SHA-512 digests. Symlinks and special files are
rejected. The sidecars use Keep Vault's `KZVHSIG1` format without changing its
payload domain or ML-DSA context. This reuse does not share signing keys between
the applications. The signature payload includes the file length and SHA-512
digest; RSA uses PSS, SHA-512 for both digest and MGF1, and a 64-byte salt.
ML-DSA signs that payload using the existing explicit application context.

The signer's SHA3-512 and Skein-1024-1024 sidecars are also signed by both
algorithms. The public RSA SubjectPublicKeyInfo and raw ML-DSA public key are
pinned using SHA-256, SHA3-512 and Skein-1024-1024 in `Signing/trust.json`.
The trust file must come from a separately trusted source. Keys or a verifier
obtained only from an untrusted package cannot authenticate that package.

`Scripts/verify-hybrid-signatures.py` verifies the format and both signatures
independently with OpenSSL 3.5 or newer, checks all public-key fingerprints, and
compares the exact file and directory inventory with an optional installed app.
The existing release verifier additionally checks Apple's signature,
notarization, Gatekeeper, entitlements and release hashes. macOS itself checks
Apple's code signature. These detached hybrid signatures are checked by the
verification tools, not by a new ML-DSA check inside the running app.

Download the additional `Password.Generator-2.3.6.hybrid-signatures.zip` asset and
extract it beside the five original release assets. From a trusted checkout,
build the checksum tool and verify both the release and installed app:

```sh
swift build -c release --product PasswordGeneratorChecksum
python3 Scripts/verify-hybrid-signatures.py \
  --release-dir /path/to/downloaded-release \
  --trust Signing/trust.json \
  --checksum-tool "$(swift build -c release --show-bin-path)/PasswordGeneratorChecksum" \
  --app '/Applications/Password Generator 2.3.6.app'
```

`--openssl` can select the full path of a trusted OpenSSL 3.5+ executable. Private
keys and the key volume are not needed for verification. The signatures attest
the distributed bytes, not a reproducible mapping from Git source to binary.

Private keys are kept exclusively in the APFS sparsebundle stored at:

```text
/Volumes/NO NAME/Password Generator Keys/Password Generator Signing Keys.sparsebundle
```

The outer volume was verified as the mounted VeraCrypt volume when provisioning.
APFS provides enforced ownership and private file permissions inside that volume;
the sparsebundle does not add another encryption layer. RSA is stored in an
encrypted PKCS#12 container. Its password and the ML-DSA private key use the
existing separate AES-256-GCM envelopes and independent wrapping keys. All secret
files have mode 0600 inside a mode-0700 directory. The wrapping keys reside in
the same protected volume, so confidentiality depends on that volume's
protection. No private key, wrapping key or password is committed or published.

For future signing, attach the existing image without replacing its keys:

```sh
hdiutil attach -nobrowse -owners on \
  -mountpoint '/Volumes/Password Generator Signing Keys' \
  '/Volumes/NO NAME/Password Generator Keys/Password Generator Signing Keys.sparsebundle'
```

The signer's existing checks require ownership enforcement to be enabled; a
normal `noowners` mount is rejected. Provisioning is a separate operation that
requires an empty private key directory. It never overwrites an existing key set.
After signing, detach the signing volume to close access to the stored keys.

The provisioned signer reuses the Keep Vault implementation with only the
self-signed certificate subject changed to `CN=Password Generator Release`.
The certificate is an application signing identity, not a publicly trusted
replacement for Apple's Developer ID certificate. The ML-DSA implementation is
cross-checked in both directions with Keep Vault's pinned native reference.
Public provisioning and verification evidence records the source and tool hashes.

Sources: [NIST FIPS 204](https://csrc.nist.gov/pubs/fips/204/final),
[OpenSSL ML-DSA signature documentation](https://docs.openssl.org/3.5/man7/EVP_SIGNATURE-ML-DSA/).

## Deutsch

Password Generator 2.3.6, Build 13, erhält zusätzliche abgetrennte Signaturen mit
RSA-PSS/SHA-512, einem eigenen RSA-4096-Schlüssel und ML-DSA-87 nach FIPS 204.
Beide Signaturen müssen gültig sein. Die Apple-Signatur, Notarisierung und das
angeheftete Ticket bleiben erhalten. App-Bundle und Release-ZIP werden durch
die zusätzliche Signierung nicht verändert.

Signiert werden das vollständige Release-ZIP, das Integritätsmanifest und ein
kanonisches Inventar aller Dateien und Verzeichnisse der installierten App.
Das Inventar bindet Produktkennung, Version, Build, relative Pfade, Dateigrößen
und SHA-512-Hashwerte. Auch die zusätzlichen SHA3-512- und
Skein-1024-1024-Prüfsummendateien tragen beide Signaturen. Die beiden öffentlichen
Schlüssel werden über drei Hashverfahren in `Signing/trust.json` gebunden.
Diese Vertrauensanker müssen aus einer unabhängig vertrauenswürdigen Quelle
stammen. Ein Schlüssel und Prüfprogramm allein aus einem unvertrauenswürdigen Paket können
dessen Herkunft nicht belegen.

Die Prüfung erfolgt unabhängig mit OpenSSL sowie den bestehenden Release- und
App-Inventarprüfungen. macOS prüft weiterhin Apples Code-Signatur. Die zusätzlichen
hybriden Signaturen werden durch die Prüfprogramme kontrolliert; es wird dadurch
keine neue ML-DSA-Prüfung in der laufenden App eingebaut.

Die privaten Schlüssel liegen ausschließlich im oben genannten APFS-Sparsebundle
innerhalb des angegebenen Ordners auf dem VeraCrypt-Datenträger. Der
RSA-PKCS#12-Container ist verschlüsselt. RSA-Passwort und privater ML-DSA-Schlüssel
verwenden getrennte AES-256-GCM-Hüllen mit unabhängigen Wrapping-Schlüsseln.
Die Geheimdateien haben Rechte 0600, das Verzeichnis 0700. Das Sparsebundle
ergänzt die Dateirechte, aber keine eigene Verschlüsselung. Da auch die
Wrapping-Schlüssel dort liegen, hängt die Vertraulichkeit vom Schutz des äußeren
Datenträgers ab. Private Schlüssel, Wrapping-Schlüssel und Passwörter werden weder
im Repository gespeichert noch veröffentlicht.

Zum erneuten Einhängen muss `-owners on` verwendet werden. Der Signierer weist
einen Mount ohne Besitzerprüfung zurück. Vorhandene Schlüssel werden nicht
überschrieben. Nach der Signierung wird das Schlüsselvolume ausgehängt.
