# Password Generator 2.3.6 for Windows

Native Windows x64/.NET 10 WPF port of the macOS 2.3.6 application. Windows build
14 has its own signing identity and release inventory. The original Swift app,
macOS release tag and signing identity are retained.

The five formats, defaults/ranges, wordlists, unbiased sampling, canonical
4,096-event pool, six-second shuffle, Skein/SHA3/SHA512 master-key pipeline,
five continuous streams and fresh OS mask follow the Swift implementation.
Windows uses `RandomNumberGenerator` backed by the Windows cryptographic provider.
The interface uses the original artwork, English/German text, concealed output,
explicit reveal/copy, time/context concealment and conditional clipboard cleanup.
Only the language selection is persisted.

The [Windows design correction](../docs/WINDOWS_DESIGN_2.3.6.md) records the
macOS-aligned control theme, source comparison and public-fixture previews.

This is a functional port, with native Windows controls. Apple's App Sandbox,
Hardened Runtime and notarization cannot be reproduced by a standalone WPF app.
The Windows runtime checks both detached signatures on an exact file/directory
inventory before generation, reveal and copy, rejects debugger attachment, and
requests WER heap exclusion and window capture exclusion. These are application
checks, not an OS sandbox. See the [security audit](../docs/WINDOWS_SECURITY_AUDIT_2.3.6.md)
and [parity record](../docs/WINDOWS_PARITY_2.3.6.md).

## Requirements and build

Building requires the .NET 10 SDK and Windows x64. Running the self-contained
distribution requires current Windows CNG support for ML-DSA, SHA3 and SHAKE;
unsupported hosts fail closed. Install current Windows updates. There are no
external NuGet dependencies. The application has no network code.

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run --project Windows/PasswordGenerator.Tests -c Release
& 'C:\Program Files\dotnet\dotnet.exe' run --project Windows/PasswordGenerator.App.Tests -c Release
& 'C:\Program Files\dotnet\dotnet.exe' run --project Windows/PasswordGenerator.Security.Tests -c Release
& .\Windows\Scripts\Build-Windows.ps1 -Publish
& .\Windows\Scripts\Install-Windows.ps1 -PackageDirectory .\Windows\artifacts\app
```

Ordinary `dotnet run` builds are intentionally blocked from generating secrets
because they lack the signed inventory. No development override or synthetic
mouse-event shortcut is compiled into the app. Rebuilding needs a new inventory
signature from the private key owner. Publish refuses to overwrite an existing
output directory, and installation refuses to overwrite an existing app.

Installation creates `Password Generator` in the Start menu Programs folder,
with the installed executable as its icon and target. To repair this entry
without reinstalling or changing the signed files, run
`Windows/Scripts/Register-StartMenu.ps1`. Its `-AllUsers` switch places the
shortcut in the shared Programs folder and requires administrator rights;
the application itself stays in the original user's installation directory.
For a new installation, `Install-Windows.ps1 -AllUsersStartMenu` selects this
same shared shortcut location.

## Signing keys and verification

Private signing material is stored only in `A:\Passoword Generator Keys`, exactly
as requested. RSA-4096 uses an AES256-CBC/PBKDF2-SHA256 encrypted PKCS12 with 200,000
iterations. Its random password and the ML-DSA-87 PKCS8 are separately protected
with DPAPI CurrentUser. Key loading uses ephemeral Windows key handles. Private
keys/passwords are excluded from Git and never included in the installed app.

FAT32 does not enforce NTFS ACLs. DPAPI binds decryption to the Windows user profile;
back up that profile's DPAPI recovery material as well as the encrypted key files.
Copying the files to another account or machine alone does not make them usable.
This protection is not a portable password-based recovery scheme.

Public keys are in `Windows/Signing`, and independently embedded in the verifier.
The self-signed certificate identifies this app's private release signer; it is
not a publicly trusted Authenticode certificate. The shipped executable has no
publicly trusted Authenticode signature and Windows may warn about its publisher.

`windows-release.json` specifies schema 1, product
`com.feinermann.passwordgenerator.windows`, version `2.3.6`, build `14`, architecture
`win-x64`, and the exact relative paths, sizes and SHA512 of all regular files and
directories. Reparse points, duplicate aliases, unsafe paths and extra/missing
entries are rejected. The only files outside the inventory are that manifest and
its two detached signatures. The signature payload is ASCII
`PasswordGenerator.Windows.Inventory.v1` followed by NUL, an Int64 little-endian
artifact byte length, and the artifact's 64-byte SHA512 digest. RSA uses
PSS/SHA512, MGF1-SHA512 and a 64-byte salt; ML-DSA-87 signs the same payload with
context `PasswordGenerator.Windows.2.3.6`. Both are mandatory. The final ZIP is
also signed with both algorithms.

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run --project Windows/PasswordGenerator.Signing -c Release -- verify '<installed app directory>'
python Windows/Scripts/Verify-OpenSsl.py --inventory --file '<app directory>/windows-release.json' --public-dir Windows/Signing --openssl '<OpenSSL 3.5+ executable>'
```

Obtain the public trust anchor/verifier through an independently trusted channel.
A modified executable can modify its own verifier; runtime self-checks do not
authenticate a maliciously replaced process. Signatures bind distributed bytes,
not a reproducible proof of correspondence between source and executable.

## Secret memory limits

Owned byte buffers are explicitly cleared; page locking and framework cleanup
are best effort. Revealing or copying creates framework strings and OS copies
which cannot all be erased. No plaintext passwords are written to files or
settings by this app. A compromised Windows session, administrator, debugger
injected after a check, clipboard consumer or external camera remains outside
the protection boundary. WER heap exclusion does not prevent administrator dumps
or every Windows crash report.
