# Password Generator 2.3.1

## English

Version 2.3.1, build 8, updates the four color-level labels and adds an info button explaining their scope. The visible app name is “Password Generator 2.3.1”; packaging creates `build/Password Generator 2.3.1.app`.

Developer ID signed, notarized through Xcode on 4 October 2026, with a stapled ticket; Gatekeeper accepted the final app.

### Labels and explanation

The configuration, generated result, and legend use these labels. Classification uses the unrounded nominal bit value.

| Nominal bits | Color | Label |
|---|---|---|
| Below 128 | Red | crackable |
| 128 to below 256 | Yellow | not quantum-safe |
| 256 to below 1,024 | Light green | practically unattackable |
| 1,024 or more | Dark green | thermodynamically unattackable |

The info button next to each label opens an explanation and supports keyboard focus. The explanation is also available as a tooltip:

> The classification refers to guessing the password by brute force with uniformly random selection. It describes the nominal selection space. The labels are simplified levels, not a guarantee: they do not assess real quantum hardware and are not thermodynamic proof. Other attack paths are not covered.

The nominal-source notice remains visible alongside the classification. The labels are interface shorthand, not measured entropy, a practical quantum-attack assessment, or proof that attacks are physically impossible. NIST's discussion of Grover search considers hardware costs and parallelization limits and continues to allow AES-128, AES-192, and AES-256. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs)

Defaults remain BIP39 with 24 words (256 nominal bits), EFF with 20 words (about 258.50 bits), ASCII with 40 characters (about 262.18 bits), PIN with six digits (about 19.93 bits), and Hex with 64 characters (256 bits). The selectable length ranges, cryptographic derivation, and output protections retain their existing behavior.

### Current release and history

Release policy: GitHub keeps only the current version as a release with download assets and a release tag. Older releases, their download assets, and their release tags are removed when replaced. The source history and historical release notes remain available for reference. [Download the current release](https://github.com/michael-feinermann/password-generator/releases/latest).

### Verification and package

Test results for version 2.3.1, build 8: 87 tests passed in each of the Debug and Release builds, with no compiler warnings: 67 Core tests and 20 app model tests per build.

The release targets Apple Silicon (`arm64`) on macOS 14 or later. The package consists of `Password.Generator-2.3.1.zip`, SHA256, SHA3-512, and Skein-1024-1024 checksum files covering the final ZIP, and an integrity manifest. `Scripts/verify-release.sh` checks the SHA values independently with Python and Skein with the official C reference implementation, and verifies the extracted app's signature and sandbox. A manifest marked as notarized also triggers stapling and Gatekeeper checks. Checksum files do not modify the app or ZIP, replace Apple's Developer ID signature, or prove provenance by themselves.

## Deutsch

Version 2.3.1, Build 8, aktualisiert die Bezeichnungen der vier Farbstufen und ergänzt einen Info-Button, der ihren Geltungsbereich erklärt. Der sichtbare Appname lautet „Password Generator 2.3.1“; das Paket-Skript erzeugt `build/Password Generator 2.3.1.app`.

Mit Developer ID signiert, am 4. Oktober 2026 über Xcode notarisiert, Ticket angeheftet; Gatekeeper akzeptiert die finale App.

### Bezeichnungen und Erklärung

Konfiguration, generiertes Ergebnis und Legende verwenden diese Bezeichnungen. Die Einordnung nutzt den ungerundeten nominellen Bitwert.

| Nominelle Bits | Farbe | Bezeichnung |
|---|---|---|
| Unter 128 | Rot | knackbar |
| 128 bis unter 256 | Gelb | nicht quantensicher |
| 256 bis unter 1.024 | Hellgrün | praktisch nicht angreifbar |
| Ab 1.024 | Dunkelgrün | thermodynamisch nicht angreifbar |

Der Info-Button neben jeder Bezeichnung öffnet eine Erklärung und lässt sich per Tastatur fokussieren. Die Erklärung ist auch als Tooltip verfügbar:

> Die Einordnung bezieht sich auf das Erraten des Passworts durch Brute-Force bei gleichverteilter Zufallsauswahl. Sie beschreibt den nominellen Auswahlraum. Die Bezeichnungen sind vereinfachte Stufen, keine Garantie: Sie bewerten keine reale Quantenhardware und sind kein thermodynamischer Nachweis. Andere Angriffswege werden nicht erfasst.

Der Hinweis zum nominellen Auswahlraum bleibt neben der Einordnung sichtbar. Die Bezeichnungen sind Kurzformen der Oberfläche, keine gemessene Entropie, keine Bewertung praktischer Quantenangriffe und kein Nachweis physikalisch unmöglicher Angriffe. NIST berücksichtigt bei Grovers Algorithmus Hardwarekosten und Grenzen der Parallelisierung und erlaubt weiterhin AES-128, AES-192 und AES-256. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs)

Die Standardwerte bleiben BIP39 mit 24 Wörtern (256 nominelle Bits), EFF mit 20 Wörtern (etwa 258,50 Bit), ASCII mit 40 Zeichen (etwa 262,18 Bit), PIN mit sechs Ziffern (etwa 19,93 Bit) und Hex mit 64 Zeichen (256 Bit). Die wählbaren Längenbereiche, die kryptografische Ableitung und der Schutz der Ausgabe behalten ihr bisheriges Verhalten.

### Aktuelles Release und Historie

Releasepolitik: Auf GitHub bleibt nur die aktuelle Version als Release mit Downloadassets und Release-Tag erhalten. Ältere Releases, ihre Downloadassets und ihre Release-Tags werden beim Ersetzen entfernt. Die Quellhistorie und historische Release Notes bleiben zum Nachlesen verfügbar. [Aktuelles Release herunterladen](https://github.com/michael-feinermann/password-generator/releases/latest).

### Verifikation und Paket

Testergebnisse für Version 2.3.1, Build 8: Jeweils 87 Tests in Debug und Release bestanden, ohne Compilerwarnungen: pro Build 67 Core-Tests und 20 App-Modelltests.

Das Release ist für Apple Silicon (`arm64`) ab macOS 14 vorgesehen. Das Paket besteht aus `Password.Generator-2.3.1.zip`, Prüfsummendateien für SHA256, SHA3-512 und Skein-1024-1024 über das finale ZIP sowie einem Integritätsmanifest. `Scripts/verify-release.sh` prüft die SHA-Werte unabhängig mit Python und Skein mit der offiziellen C-Referenzimplementierung sowie Signatur und Sandbox der entpackten App. Bei einem als notarisiert gekennzeichneten Manifest folgen zusätzlich Stapling- und Gatekeeper-Prüfung. Prüfsummendateien verändern weder App noch ZIP, ersetzen nicht Apples Developer-ID-Signatur und beweisen für sich allein keine Herkunft.
