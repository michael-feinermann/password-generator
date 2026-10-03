# Password Generator für macOS

[English](README.md) | Deutsch

<img src="Assets/PasswordGeneratorIcon.png" width="128" alt="Password Generator Icon">

[App herunterladen](https://github.com/michael-feinermann/password-generator/releases/latest) · [Release Notes 2.2.0](docs/RELEASE_NOTES_2.2.0.md) · [Technische Analyse](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)

Version 2.2.0, Build 5. Signatur- und Notarisierungsstatus: mit Developer ID signiert, am 3. Oktober 2026 über Xcode notarisiert, Ticket angeheftet; Gatekeeper akzeptiert die finale App.

Eine native, lokale macOS-App für Seedphrases, EFF-Passphrasen, ASCII-Passwörter, PINs und Hexwerte. Oberfläche auf Deutsch und Englisch, ohne Netzwerkzugriff der App. Der sichtbare Appname lautet „Password Generator 2.2.0“.

| Format | Länge | Alphabet | Angezeigte Entropie |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21 oder 24 Wörter | Offizielle englische Liste | 128, 160, 192, 224 oder 256 Bit |
| EFF | 6 bis 128 Wörter | EFF Long Wordlist, 7.776 Wörter | Wörter × log₂(7.776) |
| ASCII | 8 bis 256 Zeichen | 94 druckbare ASCII-Zeichen, `!` bis `~`, ohne Leerzeichen | Zeichen × log₂(94) |
| PIN | 3 bis 512 Ziffern | `0` bis `9`, führende Nullen erlaubt | Ziffern × log₂(10) |
| Hex | 1 bis 512 Hexzeichen | `0` bis `9`, `a` bis `f` oder `A` bis `F` | Zeichen × 4 Bit |

Die Entropieanzeige beschreibt die Größe des gleichverteilt abgetasteten Ausgaberaums. Sie misst weder die Entropie der Mausbewegungen noch garantiert sie eine entsprechende Angriffssicherheit des Gesamtsystems. BIP39-Prüfsummen zählen nicht als zusätzliche Entropie. Wiederholte Wörter und Zeichen sind zulässig; zusätzliche Zusammensetzungsregeln würden den Ausgaberaum verändern.

## Exportformat

Für EFF und BIP39 ist das Trennzeichen im Textfeld frei wählbar. Standard ist bei BIP39 ein Leerzeichen und bei EFF `-`. Ein leeres Feld verbindet die Wörter ohne Trennzeichen; Leerzeichen und mehrstellige Trenner sind ebenfalls möglich. Bei Hex wählst du kleine oder große Buchstaben. Die Optionen gelten für die Kopie in die Zwischenablage und können nach der Generierung geändert werden. Die Groß-/Kleinschreibung bei Hex gilt zusätzlich für die angezeigte Ausgabe. Dabei bleiben die erzeugten Wörter beziehungsweise Hexwerte erhalten; es findet keine neue Zufallsziehung statt.

BIP39-Wallets erwarten die Wörter üblicherweise mit Leerzeichen. Die interne BIP39-Prüfsumme wird immer über die ursprüngliche Wortfolge geprüft. Ohne Trennzeichen sind BIP39-Wortgrenzen nicht immer eindeutig rekonstruierbar; unterschiedliche gültige Wortfolgen können denselben zusammengefügten Text ergeben. Die angezeigte Entropie beschreibt deshalb die ursprüngliche Auswahl und ist kein Nachweis der Entropie beliebiger Exportdarstellungen. Groß-/Kleinschreibung von Hex und fest vorgegebene Trenner sind keine zusätzlichen Zufallsbits.

## Start und Build

```sh
swift test -Xswiftc -warnings-as-errors
zsh Scripts/package-app.sh
zsh Scripts/verify-release.sh
open "build/Password Generator 2.2.0.app"
```

Das Release ist für Apple Silicon (`arm64`) ab macOS 14 vorgesehen. Das signierte Bundle ist die verwendbare Anwendung. `swift run PasswordGeneratorApp` dient nur der Entwicklung; der nicht entsprechend signierte Prozess erfüllt die Laufzeitbedingungen zur Generierung nicht.

Das Paket-Skript erzeugt `build/Password Generator 2.2.0.app`, `build/Password.Generator-2.2.0.zip`, drei Hash-Sidecars und ein Integritätsmanifest. Ohne explizite `SIGN_IDENTITY` wird lokal ad hoc signiert. Mit einem Developer-ID-Zertifikat im Schlüsselbund kann per Fingerabdruck signiert werden. `NOTARY_PROFILE` aktiviert die optionale Notarisierung über ein vorhandenes Schlüsselbundprofil, anschließend Stapling und erneute ZIP-Erstellung. Zugangsdaten und private Schlüssel werden nicht im Projekt gespeichert. Der konkrete Signatur- und Notarisierungsstatus steht im jeweiligen Release und Integritätsmanifest. Das Projektverzeichnis bleibt `Seed-Phrase`; App, Swift-Paket, Module, Bundle-Kennung und Release-Dateien heißen nun Password Generator beziehungsweise PasswordGenerator.

## Mauspool und Generierung

1. Bewegungen im gesamten Appfenster einschließlich Bewegungen über Bedienelementen und Ziehbewegungen werden erfasst. Es gibt kein begrenztes Sammelfeld und keine globale Überwachung anderer Apps.
2. Der Pool hält die letzten 4.096 vollständigen Mausereignisse. Die Generierung benötigt mindestens 4.096 Bewegungen. Weitere Bewegungen ersetzen den jeweils ältesten Datensatz; der Speicherbedarf bleibt begrenzt. Ein Datensatz enthält laufende Nummer, monotone Zeit, Ereigniszeit, Position, Delta, Fenstergröße, Modifikatortasten und gedrückte Maustasten.
3. Ab dem Appstart läuft im Abstand von sechs Sekunden ein Fisher-Yates-Shuffle in der linearen Durstenfeld-Variante. Er permutiert die Datensätze mit Zufallsbytes aus `SecRandomCopyBytes`. Rejection Sampling vermeidet Modulo-Verzerrungen. Der Startdurchlauf auf dem noch leeren Pool ist ein Leerlauf. Während macOS die App suspendiert oder der Rechner schläft, kann kein Prozess einen Echtzeit-Takt garantieren.
4. Bei der Generierung erfolgt erneut ein Shuffle. Erst danach werden die Datensätze in der gemischten Reihenfolge serialisiert und `Skein-1024-1024(pool)`, `SHA3-512(pool)` und `SHA-512(pool)` berechnet. Beim Sammeln und bei den periodischen Shuffles werden diese Poolhashes nicht berechnet. Die separaten Integritätsprüfungen der eingebetteten Wortlisten finden beim Laden statt.
5. Die Digests werden in der Reihenfolge Skein-1024-1024, SHA3-512, SHA-512 zusammengefügt: 128 + 64 + 64 = 256 Byte beziehungsweise 2.048 Bit. Fisher-Yates permutiert anschließend alle 2.048 einzelnen Bits mit kryptografischen macOS-Zufallsbytes. Dieser zusätzliche Schritt mischt Bitpositionen, nicht lediglich die Reihenfolge der 256 Byte.
6. XOR des gemischten 256-Byte-Werts mit 256 frisch angeforderten macOS-Zufallsbytes ergibt den Masterkey. Die Zufallsbytes für diesen XOR-Schritt werden getrennt von den Zufallsbytes für die Shuffles angefordert.
7. Der Masterkey wird in dieser Reihenfolge in 128, 32, 32, 32 und 32 Byte aufgeteilt. Das erste Fragment initialisiert einen Skein-1024-XOF-Stream, die nächsten beiden jeweils einen eigenen SHAKE256-Stream. Die letzten beiden Fragmente bilden separate AES-256-Schlüssel für zwei AES-256-CTR-Streams. Jeder CTR-Stream beginnt bei null und führt einen eigenen 128-Bit-Zähler in Big-Endian-Reihenfolge fort; noch nicht verbrauchte Blockbytes bleiben über Leseaufrufe hinweg erhalten. Gleich lange Ausgaben aller fünf Streams werden byteweise XOR-verknüpft.
8. Unmittelbar vor der Nutzung wird dieses Material nochmals mit gleich vielen frischen macOS-Zufallsbytes XOR-verknüpft. Bei Nachforderungen durch Rejection Sampling laufen die fünf Streams weiter und erhalten jeweils einen neuen OS-Beitrag. Bereits gelesene Stream-Präfixe werden nicht erneut verwendet.
9. BIP39 codiert die nötigen Entropiebytes mit der SHA256-Prüfsumme. EFF, ASCII, PIN und Hex verwenden unverzerrte Auswahl aus ihrem Alphabet.

Die Hashlänge von insgesamt 2.048 Bit ist kein Nachweis für 2.048 Bit unabhängige Entropie. Eine Bitpermutation erhält die Anzahl der Einsen und Nullen und begründet allein keinen bestimmten Entropiezuwachs. Auch das XOR eines Skein-1024-XOF-Streams, zweier SHAKE256-Streams und zweier AES-256-CTR-Streams erlaubt keine Addition ihrer Sicherheitsstärken. Die Konstruktion wurde entsprechend der gewünschten Reihenfolge implementiert; sie ist keine standardisierte oder extern auditierte Zufallszahlenerzeugung. Die kryptografische Zufallsquelle des Betriebssystems bleibt die tragende Annahme.

Jeder AES-Stream erhält bei jeder Generierung ein neues Schlüsselfragment. Sein Zähler darf sich unter demselben Schlüssel niemals wiederholen; bei Zählererschöpfung bricht der Stream ab. Die AES-Streams ergänzen die individuelle Konstruktion, während bei jeder Ausgabeanforderung weiterhin frische macOS-Zufallsbytes einfließen.

## Schutz der Ausgabe

Die vorhandenen Laufzeitprüfungen bleiben erhalten: gültige laufende Code-Signatur, Hardened Runtime, minimale App Sandbox, deaktivierte POSIX-Core-Dumps und kein erkannter Debugger. Die Prüfung wird unmittelbar vor Generierung, Anzeige und Kopieren wiederholt.

Die Ausgabe erscheint zunächst verdeckt. Anzeigen erfordert eine Bestätigung und endet bestmöglich nach 60 Sekunden oder bei Kontextwechsel. Kopieren erfolgt nur auf ausdrücklichen Klick, mit `currentHostOnly`; die unveränderte Zwischenablage wird nach etwa 45 Sekunden bestmöglich geleert. Mauspool und temporäre Kryptopuffer werden beim Verwerfen bestmöglich überschrieben. Swift-Strings, Register- und Betriebssystemkopien können nicht garantiert vollständig gelöscht werden.

Die App speichert keine erzeugten Passwörter in Dateien oder Preferences. Bildschirmaufnahmen, eine externe Kamera oder ein kompromittiertes Betriebssystem kann eine lokale App nicht zuverlässig verhindern.

## Integrität und Tests

Beide Wortlisten werden vor Verwendung gegen fest eingebaute SHA256- und SHA3-512-Werte geprüft. Das vollständige finale Release-ZIP wird mit SHA256, SHA3-512 und Skein-1024-1024 gehasht. Zu jedem Verfahren gehört eine eigene Prüfsummendatei. Die zusätzliche Skein-Datei heißt `Password.Generator-2.2.0.zip.skein-1024-1024`; das Integritätsmanifest enthält ihren Wert im Feld `skein-1024-1024`.

`Scripts/verify-release.sh` prüft SHA256 und SHA3-512 unabhängig mit Python. Skein-1024-1024 wird über `Scripts/skein-reference-checksum.sh` mit der offiziellen C-Referenzimplementierung unter `Tests/Reference/Skein` kontrolliert. Das Prüfskript entpackt außerdem das ZIP und prüft Code-Signatur sowie Sandbox.

Diese zusätzlichen Integritätsprüfsummen ersetzen oder ändern Apples Developer-ID-Signaturverfahren nicht. Das Erstellen dieser externen Prüfsummendateien und des Integritätsmanifests verändert weder das App-Bundle noch das finale ZIP. Hashwerte allein beweisen keine Herkunft.

Testergebnisse für Version 2.2.0: Jeweils 80 Tests in Debug und Release bestanden, ohne Compilerwarnungen. Der [Verifikationsabschnitt der technischen Analyse](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) dokumentiert den Prüfumfang und die Release-Nachweise. Testergebnisse und Apple-Freigaben früherer Releases belegen nicht den Prüfstatus dieser Version.

## Logo und Icon

`Assets/PasswordGeneratorIcon.png` ist die Vorlage für das macOS-Icon. `Assets/PasswordGeneratorLogo.png` enthält das freigestellte Markenzeichen für die Oberfläche. Die Erzeugung und die verwendeten Prompts sind in [Assets/README.md](Assets/README.md) dokumentiert. Das Paket-Skript erzeugt aus der Iconvorlage alle macOS-Icongrößen und `AppIcon.icns`.

## Quellen und Hinweise zu Fremdmaterial

[Third-party notices](THIRD_PARTY_NOTICES.md) nennen die Herkunft und Lizenzhinweise der eingebetteten Wortlisten und Testdaten.


## Primärquellen

- [BIP39-Spezifikation](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Long Wordlist](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [EFF: Dice-Generated Passphrases](https://www.eff.org/dice)
- [Skein v1.3 und offizielle Testvektoren](https://www.schneier.com/academic/skein/)
- [NIST SP 800-38A: AES-CTR](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [NIST FIPS 180-4: SHA-512](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [NIST FIPS 202: SHA3 und SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [Durstenfeld: Algorithm 235, Random permutation](https://doi.org/10.1145/364520.364540)
- [Apple: SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
