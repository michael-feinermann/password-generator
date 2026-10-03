# Password Generator 2.2.0

## English

Version 2.2.0, build 5, expands the EFF, PIN, and hexadecimal length ranges and adds SHA-512 plus two AES-256-CTR streams to the password byte derivation. The visible app name is “Password Generator 2.2.0”; a local package build creates `build/Password Generator 2.2.0.app`. The app targets Apple Silicon running macOS 14 or later and provides English and German interfaces without network access.

Signing and notarization status: Developer ID signed, notarized through Xcode on 3 October 2026, with a stapled ticket; Gatekeeper accepted the final app.

### Output formats and export

| Format | Length | Displayed entropy |
|---|---|---|
| BIP39 | 12, 15, 18, 21, or 24 English words | 128, 160, 192, 224, or 256 bits, excluding checksum bits |
| EFF | 6 to 128 words from the 7,776-word English EFF Long Wordlist | Words × log₂(7,776) |
| ASCII | 8 to 256 characters from the 94 printable ASCII characters `!` through `~`, without spaces | Characters × log₂(94) |
| PIN | 3 to 512 digits, including leading zeros | Digits × log₂(10) |
| Hex | 1 to 512 characters, `0` through `9` and `a` through `f` or `A` through `F` | Characters × 4 bits |

EFF and BIP39 separators remain freely editable, including spaces, multiple characters, and an empty separator. The default is a space for BIP39 and `-` for EFF; each mode retains its chosen separator during the session. Hex output supports lowercase and uppercase letters in both the display and clipboard output. Export settings can be changed after generation without drawing new random values or deriving a new key.

The entropy display describes the original uniformly sampled output space. It does not measure mouse entropy or establish an equivalent security strength for the overall construction. Repeated words and characters are allowed. BIP39 checksum bits, fixed separators, and hexadecimal letter case do not add entropy. Wallet import usually requires spaces between BIP39 words. With no separator, different valid BIP39 word sequences can produce the same text; the displayed entropy does not establish the entropy of arbitrary export representations. BIP39 checksum validation continues to use the original word sequence.

### Byte stream derivation

1. The pool retains the latest 4,096 complete mouse-event records, collected throughout the app window, including over controls and during dragging. At least 4,096 movements are required before generation. Before each generation, Fisher-Yates shuffles the records using fresh cryptographic macOS random bytes.
2. Skein-1024-1024, SHA3-512, and SHA-512 hash the same serialized pool. Their digests are concatenated in that order: 128 + 64 + 64 = 256 bytes. Fisher-Yates then shuffles all 2,048 individual bits using cryptographic macOS random bytes.
3. XOR with 256 separately requested fresh macOS random bytes produces the master key. Its consecutive fragments contain 128, 32, 32, 32, and 32 bytes.
4. The first fragment initializes Skein-1024-XOF; the next two initialize separate SHAKE256 streams. Each of the final two fragments supplies a separate AES-256 key for an AES-256-CTR stream. Each AES stream starts its own 128-bit big-endian counter at zero, retains unused block bytes across reads, and stops if its counter is exhausted.
5. Equal-length outputs of all five streams are combined using bytewise XOR. Immediately before use, an equal number of fresh macOS random bytes is mixed in using XOR. Additional requests continue all streams from their current positions without reusing consumed prefixes.
6. BIP39 encodes the required entropy bytes and its checksum. EFF, ASCII, PIN, and Hex select uniformly from their alphabets; rejection sampling avoids modulo bias.

Pool hashing, the bit shuffle, and derivation occur only during generation. The periodic shuffle of mouse-event records continues every six seconds from app startup; the initial empty-pool shuffle is a no-op. Scheduling remains subject to macOS suspension and sleep. The expandable explanation in the app describes the complete derivation in English and German.

Skein-XOF retains the unknown-output-length configuration from Skein v1.3, section 4.12 (`N_o = 2^64 − 1`). The AES streams are additional components of this custom construction. They do not describe the internal implementation of Apple's random source. Fresh macOS random bytes remain part of each output request. Hash lengths and the security strengths of individual streams cannot be added to establish overall security; a bit permutation alone does not establish any particular entropy gain. The construction is not a standardized or externally audited random number generator.

### Protection and verification

The app retains its running-code signature checks, Hardened Runtime, minimal App Sandbox, disabled POSIX core dumps, and debugger detection. Output remains concealed until explicitly revealed and is hidden again on a best-effort basis after about 60 seconds or a context change. Copying is explicit and uses `currentHostOnly`; unchanged clipboard contents are cleared on a best-effort basis after about 45 seconds. Generated passwords are not saved in files or preferences. Buffer wiping is best effort and cannot guarantee erasure of Swift strings or operating-system copies. Screen capture and a compromised system remain outside the app's reliable protection.

Release packaging creates `Password.Generator-2.2.0.zip`, three checksum files for SHA256, SHA3-512, and Skein-1024-1024, and an integrity manifest. Each checksum covers the complete final ZIP. The Skein sidecar is `Password.Generator-2.2.0.zip.skein-1024-1024`; the manifest field is `skein-1024-1024`. `Scripts/verify-release.sh` checks SHA256 and SHA3-512 independently using Python and checks Skein through `Scripts/skein-reference-checksum.sh` with the official C reference implementation in `Tests/Reference/Skein`. The verifier also extracts the ZIP and checks its code signature and sandbox. These external checksums do not modify the app bundle or ZIP, replace Apple's Developer ID signing process, or prove provenance by themselves.

Test results for version 2.2.0: 80 tests passed in each of the Debug and Release builds, with no compiler warnings. The [technical analysis (German)](https://github.com/michael-feinermann/password-generator/blob/main/docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) records the scope of verification and the release evidence. Test results and Apple approval for earlier releases do not establish the verification status of this version. Tests are not an external security audit or a formal proof of correctness.

## Deutsch

Version 2.2.0, Build 5, erweitert die Längenbereiche für EFF, PIN und Hex und ergänzt die Ableitung des Passwort-Bytestroms um SHA-512 und zwei AES-256-CTR-Streams. Der sichtbare Appname lautet „Password Generator 2.2.0“; ein lokaler Paket-Build erzeugt `build/Password Generator 2.2.0.app`. Die App ist für Apple Silicon ab macOS 14 vorgesehen und bietet eine deutsche und englische Oberfläche ohne Netzwerkzugriff.

Signatur- und Notarisierungsstatus: mit Developer ID signiert, am 3. Oktober 2026 über Xcode notarisiert, Ticket angeheftet; Gatekeeper akzeptiert die finale App.

### Ausgabeformate und Export

| Format | Länge | Angezeigte Entropie |
|---|---|---|
| BIP39 | 12, 15, 18, 21 oder 24 englische Wörter | 128, 160, 192, 224 oder 256 Bit ohne Prüfsummenbits |
| EFF | 6 bis 128 Wörter aus der englischen EFF Long Wordlist mit 7.776 Wörtern | Wörter × log₂(7.776) |
| ASCII | 8 bis 256 Zeichen aus den 94 druckbaren ASCII-Zeichen `!` bis `~`, ohne Leerzeichen | Zeichen × log₂(94) |
| PIN | 3 bis 512 Ziffern, einschließlich führender Nullen | Ziffern × log₂(10) |
| Hex | 1 bis 512 Zeichen, `0` bis `9` und `a` bis `f` oder `A` bis `F` | Zeichen × 4 Bit |

Die Trennzeichen für EFF und BIP39 bleiben frei wählbar, einschließlich Leerzeichen, mehrstelliger und leerer Trenner. Standard ist bei BIP39 ein Leerzeichen und bei EFF `-`; jeder Modus behält seinen gewählten Trenner während der Sitzung. Hex unterstützt kleine und große Buchstaben sowohl in der Anzeige als auch beim Kopieren. Die Exportoptionen können nach der Generierung geändert werden, ohne neue Zufallswerte auszuwählen oder einen neuen Schlüssel abzuleiten.

Die Entropieanzeige beschreibt den ursprünglichen gleichverteilt abgetasteten Ausgaberaum. Sie misst keine Mausentropie und belegt keine entsprechende Sicherheitsstärke der Gesamtkonstruktion. Wiederholte Wörter und Zeichen sind zulässig. BIP39-Prüfsummenbits, feste Trennzeichen und die Groß-/Kleinschreibung bei Hex liefern keine zusätzliche Entropie. Für den Wallet-Import sind üblicherweise Leerzeichen zwischen BIP39-Wörtern erforderlich. Ohne Trenner können unterschiedliche gültige BIP39-Wortfolgen denselben Text ergeben; die angezeigte Entropie belegt nicht die Entropie beliebiger Exportdarstellungen. Die BIP39-Prüfsumme wird weiterhin anhand der ursprünglichen Wortfolge validiert.

### Ableitung des Bytestroms

1. Der Pool hält die letzten 4.096 vollständigen Mausereignisse aus dem gesamten Appfenster, einschließlich Bewegungen über Bedienelementen und Ziehbewegungen. Vor der Generierung sind mindestens 4.096 Bewegungen erforderlich. Vor jeder Generierung mischt Fisher-Yates die Datensätze mit frischen kryptografischen macOS-Zufallsbytes.
2. Skein-1024-1024, SHA3-512 und SHA-512 hashen denselben serialisierten Pool. Ihre Digests werden in dieser Reihenfolge verbunden: 128 + 64 + 64 = 256 Byte. Fisher-Yates mischt anschließend alle 2.048 einzelnen Bits mit kryptografischen macOS-Zufallsbytes.
3. XOR mit 256 separat angeforderten frischen macOS-Zufallsbytes ergibt den Masterkey. Seine aufeinanderfolgenden Fragmente sind 128, 32, 32, 32 und 32 Byte lang.
4. Das erste Fragment initialisiert Skein-1024-XOF; die nächsten beiden initialisieren jeweils einen eigenen SHAKE256-Stream. Jedes der letzten beiden Fragmente liefert einen separaten AES-256-Schlüssel für einen AES-256-CTR-Stream. Jeder AES-Stream beginnt mit einem eigenen 128-Bit-Zähler in Big-Endian-Reihenfolge bei null, bewahrt nicht verbrauchte Blockbytes über Leseaufrufe hinweg und bricht bei Zählererschöpfung ab.
5. Gleich lange Ausgaben aller fünf Streams werden byteweise XOR-verknüpft. Unmittelbar vor der Verwendung fließen nochmals gleich viele frische macOS-Zufallsbytes per XOR ein. Bei Nachforderungen laufen alle Streams ab ihrer aktuellen Position weiter, ohne bereits verbrauchte Präfixe erneut zu verwenden.
6. BIP39 codiert die benötigten Entropiebytes und seine Prüfsumme. EFF, ASCII, PIN und Hex wählen gleichverteilt aus ihren Alphabeten; Rejection Sampling vermeidet Modulo-Verzerrungen.

Poolhashes, Bitmischung und Ableitung werden nur bei der Generierung berechnet. Der periodische Shuffle der Mausereignisse läuft weiterhin ab dem Appstart alle sechs Sekunden; der erste Shuffle des noch leeren Pools ist ein Leerlauf. Die Zeitplanung unterliegt weiterhin macOS-Suspendierung und Ruhezustand. Der ausklappbare Bereich der App erklärt die vollständige Ableitung auf Deutsch und Englisch.

Skein-XOF behält die Konfiguration für unbekannte Ausgabelänge aus Skein v1.3, Abschnitt 4.12 (`N_o = 2^64 − 1`). Die AES-Streams sind zusätzliche Bestandteile dieser individuellen Konstruktion. Sie beschreiben nicht die interne Implementierung von Apples Zufallsquelle. Frische macOS-Zufallsbytes fließen weiterhin bei jeder Ausgabeanforderung ein. Hashlängen und Sicherheitsstärken einzelner Streams lassen sich nicht zur Gesamtsicherheit addieren; eine Bitpermutation allein belegt keinen bestimmten Entropiezuwachs. Die Konstruktion ist keine standardisierte oder extern auditierte Zufallszahlenerzeugung.

### Schutz und Verifikation

Die App behält ihre Prüfung der laufenden Code-Signatur, Hardened Runtime, minimale App Sandbox, deaktivierte POSIX-Core-Dumps und Debuggererkennung. Die Ausgabe bleibt bis zur ausdrücklichen Freigabe verdeckt und wird bestmöglich nach etwa 60 Sekunden oder bei Kontextwechsel wieder verborgen. Kopieren erfolgt ausdrücklich und mit `currentHostOnly`; unveränderte Zwischenablageinhalte werden nach etwa 45 Sekunden bestmöglich geleert. Erzeugte Passwörter werden nicht in Dateien oder Preferences gespeichert. Das Überschreiben von Puffern erfolgt bestmöglich und garantiert keine Löschung von Swift-Strings oder Betriebssystemkopien. Bildschirmaufnahmen und ein kompromittiertes System bleiben außerhalb des zuverlässig möglichen Appschutzes.

Das Release-Paket enthält `Password.Generator-2.2.0.zip`, drei Prüfsummendateien für SHA256, SHA3-512 und Skein-1024-1024 sowie ein Integritätsmanifest. Jede Prüfsumme erfasst das vollständige finale ZIP. Die Skein-Datei heißt `Password.Generator-2.2.0.zip.skein-1024-1024`; das Manifestfeld lautet `skein-1024-1024`. `Scripts/verify-release.sh` prüft SHA256 und SHA3-512 unabhängig mit Python und Skein über `Scripts/skein-reference-checksum.sh` mit der offiziellen C-Referenzimplementierung unter `Tests/Reference/Skein`. Das Prüfskript entpackt außerdem das ZIP und prüft Code-Signatur sowie Sandbox. Diese externen Prüfsummen verändern weder das App-Bundle noch das ZIP, ersetzen nicht Apples Developer-ID-Signaturverfahren und beweisen für sich allein keine Herkunft.

Testergebnisse für Version 2.2.0: Jeweils 80 Tests in Debug und Release bestanden, ohne Compilerwarnungen. Die [technische Analyse](https://github.com/michael-feinermann/password-generator/blob/main/docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) dokumentiert den Prüfumfang und die Release-Nachweise. Testergebnisse und Apple-Freigaben früherer Releases belegen nicht den Prüfstatus dieser Version. Tests sind kein externer Sicherheitsaudit oder formaler Korrektheitsnachweis.
