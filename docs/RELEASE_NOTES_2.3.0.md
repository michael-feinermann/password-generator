# Password Generator 2.3.0

## English

Version 2.3.0, build 7, introduces longer default lengths and a color-coded description of the nominal selection space. The visible app name is “Password Generator 2.3.0”; a local package build creates `build/Password Generator 2.3.0.app`. The cryptographic derivation is unchanged from version 2.2.1.

Developer ID signed, notarized through Xcode on 4 October 2026, with a stapled ticket; Gatekeeper accepted the final app.

### New defaults

| Format | Default | Nominal bits |
|---|---|---|
| BIP39 | 24 words | 256, excluding checksum bits |
| EFF | 20 words | 20 × log₂(7,776) ≈ 258.50 |
| ASCII | 40 characters | 40 × log₂(94) ≈ 262.18 |
| PIN | 6 digits | 6 × log₂(10) ≈ 19.93 |
| Hex | 64 characters | 64 × 4 = 256 |

BIP39, EFF, ASCII, and Hex default to the shortest supported length reaching at least 256 nominal bits. PIN deliberately defaults to six digits. The selectable ranges remain BIP39 with 12, 15, 18, 21, or 24 words; EFF with 6 to 128 words; ASCII with 8 to 256 characters from the 94 printable ASCII characters without spaces; PIN with 3 to 512 digits; and Hex with 1 to 512 characters.

### Four color levels

The configuration and generated result display the nominal bit value, a color, and a text label. The configuration also includes a four-level legend. Classification uses the unrounded value.

| Nominal bits | Color | Label |
|---|---|---|
| Below 128 | Red | Limited brute-force reserve |
| 128 to below 256 | Yellow | Limited quantum reserve |
| 256 to below 1,024 | Light green | Very high brute-force cost |
| 1,024 or more | Dark green | Extreme brute-force cost |

These are descriptions of the selection space under ideally uniform sampling, not measured source entropy or guaranteed attack resistance. A six-digit PIN has a small offline guessing space; enforced attempt limits and the use case also matter. The highest level makes no thermodynamic impossibility claim.

“Limited quantum reserve” refers to the idealized Grover search model, in which searching N possibilities takes on the order of √N quantum queries. It does not mean that all values below 256 bits are practically vulnerable to quantum computers. NIST notes hardware costs and parallelization limits and continues to allow AES-128, AES-192, and AES-256. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs)

### Cryptographic processing and protection

The pool retains 4,096 mouse-event records and is shuffled every six seconds from startup and again before generation. Pool hashes are computed only during generation. The existing three-hash digest, first OS XOR, 2,048-bit Fisher-Yates shuffle, second OS XOR, five advancing streams, and final OS XOR remain in place. Runtime checks, concealed output, clipboard handling, and best-effort buffer wiping retain their existing behavior and limitations. This release changes defaults and presentation; it does not establish a new security guarantee for the custom random-number construction.

### Release verification

Test results for version 2.3.0, build 7: 87 tests passed in each of the Debug and Release builds, with no compiler warnings: 67 Core tests and 20 app tests per build. Test results and Apple approval for earlier releases do not establish this version's verification status.

The release targets Apple Silicon (`arm64`) on macOS 14 or later. Packaging creates `Password.Generator-2.3.0.zip`, three checksum files covering the final ZIP with SHA256, SHA3-512, and Skein-1024-1024, and an integrity manifest. `Scripts/verify-release.sh` checks both SHA values independently with Python and Skein with the official C reference implementation. These external checksum files do not modify the app bundle or ZIP, replace Apple's Developer ID signature, or prove provenance by themselves.

## Deutsch

Version 2.3.0, Build 7, führt längere Standardlängen und eine farbliche Beschreibung des nominellen Auswahlraums ein. Der sichtbare Appname lautet „Password Generator 2.3.0“; ein lokaler Paket-Build erzeugt `build/Password Generator 2.3.0.app`. Die kryptografische Ableitung bleibt gegenüber Version 2.2.1 unverändert.

Mit Developer ID signiert, am 4. Oktober 2026 über Xcode notarisiert, Ticket angeheftet; Gatekeeper akzeptiert die finale App.

### Neue Standardlängen

| Format | Standard | Nominelle Bits |
|---|---|---|
| BIP39 | 24 Wörter | 256, ohne Prüfsummenbits |
| EFF | 20 Wörter | 20 × log₂(7.776) ≈ 258,50 |
| ASCII | 40 Zeichen | 40 × log₂(94) ≈ 262,18 |
| PIN | 6 Ziffern | 6 × log₂(10) ≈ 19,93 |
| Hex | 64 Zeichen | 64 × 4 = 256 |

BIP39, EFF, ASCII und Hex starten mit der kürzesten unterstützten Länge, die mindestens 256 nominelle Bits erreicht. Die PIN startet bewusst mit sechs Ziffern. Die wählbaren Bereiche bleiben BIP39 mit 12, 15, 18, 21 oder 24 Wörtern; EFF mit 6 bis 128 Wörtern; ASCII mit 8 bis 256 Zeichen aus den 94 druckbaren ASCII-Zeichen ohne Leerzeichen; PIN mit 3 bis 512 Ziffern und Hex mit 1 bis 512 Zeichen.

### Vier Farbstufen

Die Konfiguration und das generierte Ergebnis zeigen den nominellen Bitwert, eine Farbe und eine Textbezeichnung. Die Konfiguration enthält zusätzlich eine Legende mit vier Stufen. Die Einordnung verwendet den ungerundeten Wert.

| Nominelle Bits | Farbe | Bezeichnung |
|---|---|---|
| Unter 128 | Rot | Geringe Brute-Force-Reserve |
| 128 bis unter 256 | Gelb | Begrenzte Quantenreserve |
| 256 bis unter 1.024 | Hellgrün | Sehr hoher Brute-Force-Aufwand |
| Ab 1.024 | Dunkelgrün | Extremer Brute-Force-Aufwand |

Die Stufen beschreiben den Auswahlraum bei ideal gleichverteilter Auswahl, keine gemessene Quellenentropie oder garantierte Angriffssicherheit. Eine sechsstellige PIN besitzt einen kleinen Suchraum für Offline-Angriffe; durchgesetzte Versuchslimits und der Einsatzzweck spielen ebenfalls eine Rolle. Die höchste Stufe behauptet keine thermodynamische Unmöglichkeit eines Angriffs.

„Begrenzte Quantenreserve“ bezieht sich auf das idealisierte Grover-Suchmodell, in dem das Durchsuchen von N Möglichkeiten Quantenabfragen in der Größenordnung √N benötigt. Es bedeutet nicht, dass alle Werte unter 256 Bit praktisch durch Quantencomputer angreifbar wären. NIST berücksichtigt Hardwarekosten und Grenzen der Parallelisierung und erlaubt weiterhin AES-128, AES-192 und AES-256. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs)

### Kryptografische Verarbeitung und Schutz

Der Pool hält 4.096 Mausereignisse und wird ab dem Appstart alle sechs Sekunden sowie erneut vor der Generierung gemischt. Poolhashes werden ausschließlich bei der Generierung berechnet. Der bestehende Digest aus drei Hashwerten, das erste OS-XOR, der Fisher-Yates-Shuffle aller 2.048 Bits, das zweite OS-XOR, die fünf fortlaufenden Streams und das abschließende OS-XOR bleiben erhalten. Laufzeitprüfungen, verdeckte Ausgabe, Zwischenablage und bestmögliches Überschreiben von Puffern behalten ihr bisheriges Verhalten und ihre Grenzen. Dieses Release ändert Standardwerte und Darstellung; es begründet keine neue Sicherheitsgarantie für die individuelle Zufallszahlenerzeugung.

### Release-Verifikation

Testergebnisse für Version 2.3.0, Build 7: Jeweils 87 Tests in Debug und Release bestanden, ohne Compilerwarnungen: pro Build 67 Core-Tests und 20 App-Tests. Testergebnisse und Apple-Freigaben früherer Releases belegen nicht den Prüfstatus dieser Version.

Das Release ist für Apple Silicon (`arm64`) ab macOS 14 vorgesehen. Das Paket enthält `Password.Generator-2.3.0.zip`, drei Prüfsummendateien über das finale ZIP für SHA256, SHA3-512 und Skein-1024-1024 sowie ein Integritätsmanifest. `Scripts/verify-release.sh` prüft beide SHA-Werte unabhängig mit Python und Skein mit der offiziellen C-Referenzimplementierung. Diese externen Prüfsummendateien verändern weder das App-Bundle noch das ZIP, ersetzen nicht Apples Developer-ID-Signatur und beweisen für sich allein keine Herkunft.
