# Password Generator für macOS

[English](README.md) | Deutsch

<img src="Assets/PasswordGeneratorIcon.png" width="128" alt="Password Generator Icon">

[App herunterladen](https://github.com/michael-feinermann/password-generator/releases/latest) · [Release Notes 2.3.4](docs/RELEASE_NOTES_2.3.4.md) · [Technische Analyse](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md)

Version 2.3.4, Build 11. Mit Developer ID signiert und am 4. Oktober 2026 über Xcode notarisiert. Signatur, angeheftetes Notarisierungsticket und Gatekeeper-Prüfung des finalen Pakets sind gültig.

Releasepolitik: Auf GitHub bleibt nur die aktuelle Version als Release mit Downloadassets und Release-Tag erhalten. Die Quellhistorie und historische Release Notes bleiben zum Nachlesen verfügbar. Der Downloadlink oben verweist stets auf das aktuelle Release.

Eine native, lokale macOS-App für Seedphrases, EFF-Passphrasen, ASCII-Passwörter, PINs und Hexwerte. Oberfläche auf Deutsch und Englisch, ohne Netzwerkzugriff der App. Der sichtbare Appname lautet „Password Generator 2.3.4“.

Die normale Fenstergröße von 1.060 × 840 Punkten ist die Mindestgröße. Inhalt und Typografie wachsen mit größeren Fenstern und im Vollbild. Apptexte verwenden mindestens Schriftgröße 14; Potenzen erscheinen gut lesbar in der Schreibweise `10^106` und `2^(n/2)`.

| Format | Länge | Alphabet | Angezeigte Entropie |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21 oder 24 Wörter | Offizielle englische Liste | 128, 160, 192, 224 oder 256 Bit |
| EFF | 6 bis 128 Wörter | EFF Long Wordlist, 7.776 Wörter | Wörter × log₂(7.776) |
| ASCII | 8 bis 256 Zeichen | 94 druckbare ASCII-Zeichen, `!` bis `~`, ohne Leerzeichen | Zeichen × log₂(94) |
| PIN | 3 bis 512 Ziffern | `0` bis `9`, führende Nullen erlaubt | Ziffern × log₂(10) |
| Hex | 1 bis 512 Hexzeichen | `0` bis `9`, `a` bis `f` oder `A` bis `F` | Zeichen × 4 Bit |

Die Entropieanzeige beschreibt die Größe des gleichverteilt abgetasteten Ausgaberaums. Sie misst weder die Entropie der Mausbewegungen noch garantiert sie eine entsprechende Angriffssicherheit des Gesamtsystems. BIP39-Prüfsummen zählen nicht als zusätzliche Entropie. Wiederholte Wörter und Zeichen sind zulässig; zusätzliche Zusammensetzungsregeln würden den Ausgaberaum verändern.

## Standardlängen und Farbstufen

Version 2.3.4 startet die Formate mit diesen Längen:

| Format | Standard | Nominelle Bits |
|---|---|---|
| BIP39 | 24 Wörter | 256 |
| EFF | 20 Wörter | 20 × log₂(7.776) ≈ 258,50 |
| ASCII | 40 Zeichen | 40 × log₂(94) ≈ 262,18 |
| PIN | 6 Ziffern | 6 × log₂(10) ≈ 19,93 |
| Hex | 64 Zeichen | 64 × 4 = 256 |

Für BIP39, EFF, ASCII und Hex sind dies die kürzesten unterstützten Längen mit mindestens 256 nominellen Bits. Die sechsstellige PIN ist eine bewusste Ausnahme. Die vollständigen wählbaren Längenbereiche bleiben verfügbar.

Die Konfiguration und das generierte Ergebnis zeigen den nominellen Bitwert mit Farbe und Textbezeichnung. Der ungerundete Wert bestimmt die Stufe; genau 128, 256 oder 1.024 Bit gehören bereits zur jeweils höheren Stufe.

| Nominelle Bits | Farbe | Bezeichnung |
|---|---|---|
| Unter 128 | Rot | knackbar |
| 128 bis unter 256 | Gelb | nicht quantensicher |
| 256 bis unter 1.024 | Hellgrün | praktisch nicht angreifbar |
| Ab 1.024 | Dunkelgrün | thermodynamisch nicht angreifbar |

Der Info-Button neben jeder Stufe erläutert ihren Aussagebereich und die Angriffsmodelle; die Informationen sind auch per Tastatur erreichbar. Die Bezeichnungen beziehen sich auf das Erraten gleichverteilt zufälliger Passwörter mit diesen Einschränkungen:

- Rot bezeichnet den niedrigsten Bereich. Nicht jedes Passwort unter 128 nominellen Bits ist mit verfügbarer Hardware praktisch knackbar.
- Gelb bezeichnet die geringere Suchreserve im idealisierten Grover-Modell. Damit wird nicht jedes Verfahren, das solche Passwörter verwendet, als durch Quantencomputer gebrochen eingestuft.
- Hellgrün steht für einen sehr großen modellierten Suchaufwand. Angriffe auf Zufallsquelle, Schlüsselableitung, Verschlüsselung, Implementierung oder Endgerät sind dadurch nicht ausgeschlossen.
- Dunkelgrün überschreitet sowohl den bedingten Energievergleich als auch den unten angenommenen Zeithorizont. Eine uneingeschränkte thermodynamische Unmöglichkeit ist damit nicht bewiesen.

Der Bitwert misst den nominellen Auswahlraum, nicht die tatsächlich von den Zufallsquellen gelieferte Entropie. Eine sechsstellige PIN besitzt einen kleinen Suchraum für Offline-Angriffe; ihre Eignung hängt auch vom Einsatzzweck und durchgesetzten Versuchslimits ab. Diese Bezeichnungen sind keine NIST-Sicherheitskategorien. [NISTs Hinweise zu Quantencomputern](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs) berücksichtigen praktische Kosten und erlauben weiterhin AES-128, AES-192 und AES-256.

## Modelle für Angriffszeit und physikalische Vergleiche

Für `n` nominelle Bits und ein gültiges Ziel unter `N = 2^n` gleich wahrscheinlichen Kandidaten schätzt die App:

| Modell | Angenommene Rate | Angezeigte Zeit in Sekunden |
|---|---|---|
| Klassische vollständige Suche | 10¹⁸ vollständige Kandidatenprüfungen pro Sekunde | `2^n / 10^18` |
| Idealisierter Petahertz-Quantencomputer mit Grover-Suche | 10¹⁵ vollständige Grover-Iterationen pro Sekunde | `(π/4) × 2^(n/2) / 10^15` |

Der klassische Wert erfasst den gesamten Suchraum, nicht die mittlere Fundzeit. Der Grover-Wert ist eine kontinuierliche Näherung für nahezu sicheren Erfolg bei einem Ziel. Beide Raten sind Annahmen und keine Benchmarks. Exascale-FLOPS zählen Gleitkommaoperationen, keine Passwortprüfungen; die optoelektronische 1-PHz-Forschung belegt ebenfalls weder eine universelle Prozessorgrenze noch ein realisierbares Quantenorakel. [DOE: Supercomputing](https://www.energy.gov/topics/supercomputing), [Zalka: Grover's quantum searching algorithm is optimal](https://arxiv.org/abs/quant-ph/9711070), [Ossiander et al.: The speed limit of optoelectronics](https://pmc.ncbi.nlm.nih.gov/articles/PMC8956609/).

Der Energievergleich nimmt ein irreversibel gelöschtes Informationsbit pro Prüfung beziehungsweise Grover-Iteration bei 2,7 K an. Dies kostet mindestens `k_B × T × ln(2) ≈ 2,58388 × 10^-23 J`. Das Budget von `3 × 10^71 J` ist eine aufgerundete kosmologische Vergleichsgröße einschließlich Dunkler Energie, keine verfügbare Arbeitsenergie. Reversible Berechnung erfordert diese Löschung nicht nach jedem Schritt. Insbesondere ist der angesetzte Aufwand pro Grover-Iteration eine zusätzliche Annahme zum Landauer-Prinzip. [Landauer (1961)](https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf), [Bennett (1973)](https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html).

Ein getrennter Zeitvergleich erlaubt `10^106` Jahre mit jeweils 31.557.600 Sekunden. Dies ist ein ausdrücklich angenommener kosmischer Zeithorizont, kein gesicherter Zeitpunkt maximaler Entropie des Universums und keine universelle Frist für Berechnungen. Hawking-Verdampfung motiviert die astronomische Größenordnung; die langfristige kosmologische Entwicklung bleibt bedingt. [Hawking (1975)](https://doi.org/10.1007/BF02345020), [Adams und Laughlin (1997), Abschnitte IV.G und VI.D](https://sites.astro.caltech.edu/ay1/RevModPhys.69.337.pdf).

Bei 1.024 nominellen Bits beträgt die modellierte Grover-Zeit etwa `3,34 × 10^131` Jahre beziehungsweise das `3,34 × 10^25`-Fache dieses Horizonts. Dieser Zeitvergleich benötigt keine Landauer-Kosten pro Iteration, hängt aber weiterhin von der angenommenen Rate, dem Horizont und dem Suchproblem ab. Auch ein überschrittenes Budget schließt einen frühen Glückstreffer nicht aus.

Threefish-1024 akzeptiert einen 1.024-Bit-Schlüssel. Ein nomineller Passwortauswahlraum von 1.024 Bit beweist allein weder ebenso hohe Quellenentropie noch entsprechend starkes Schlüsselmaterial; geeignete Ableitung und sichere Implementierung bleiben erforderlich. Die Erweiterung eines Passworts zu mehreren Schlüsseln erzeugt keine zusätzliche unabhängige Entropie, und Kaskadenstärken lassen sich nicht einfach addieren. Eine Garantie für jede Verschlüsselung oder Kaskade folgt daraus nicht. [Skein-/Threefish-Spezifikation v1.3, Abschnitte 3.3 und 6.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf). [Vollständige Annahmen, Schwellen und Quellen](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#attack-cost-models).

## Exportformat

Für EFF und BIP39 ist das Trennzeichen im Textfeld frei wählbar. Standard ist bei BIP39 ein Leerzeichen und bei EFF `-`. Ein leeres Feld verbindet die Wörter ohne Trennzeichen; Leerzeichen und mehrstellige Trenner sind ebenfalls möglich. Bei Hex wählst du kleine oder große Buchstaben. Die Optionen gelten für die Kopie in die Zwischenablage und können nach der Generierung geändert werden. Die Groß-/Kleinschreibung bei Hex gilt zusätzlich für die angezeigte Ausgabe. Dabei bleiben die erzeugten Wörter beziehungsweise Hexwerte erhalten; es findet keine neue Zufallsziehung statt.

BIP39-Wallets erwarten die Wörter üblicherweise mit Leerzeichen. Die interne BIP39-Prüfsumme wird immer über die ursprüngliche Wortfolge geprüft. Ohne Trennzeichen sind BIP39-Wortgrenzen nicht immer eindeutig rekonstruierbar; unterschiedliche gültige Wortfolgen können denselben zusammengefügten Text ergeben. Die angezeigte Entropie beschreibt deshalb die ursprüngliche Auswahl und ist kein Nachweis der Entropie beliebiger Exportdarstellungen. Groß-/Kleinschreibung von Hex und fest vorgegebene Trenner sind keine zusätzlichen Zufallsbits.

## Start und Build

```sh
swift test -Xswiftc -warnings-as-errors
zsh Scripts/package-app.sh
zsh Scripts/verify-release.sh
open "build/Password Generator 2.3.4.app"
```

Das Release ist für Apple Silicon (`arm64`) ab macOS 14 vorgesehen. Das signierte Bundle ist die verwendbare Anwendung. `swift run PasswordGeneratorApp` dient nur der Entwicklung; der nicht entsprechend signierte Prozess erfüllt die Laufzeitbedingungen zur Generierung nicht.

Das Paket-Skript erzeugt `build/Password Generator 2.3.4.app`, `build/Password.Generator-2.3.4.zip`, drei Hash-Sidecars und ein Integritätsmanifest. Ohne explizite `SIGN_IDENTITY` wird lokal ad hoc signiert. Mit einem Developer-ID-Zertifikat im Schlüsselbund kann per Fingerabdruck signiert werden. `NOTARY_PROFILE` aktiviert die optionale Notarisierung über ein vorhandenes Schlüsselbundprofil, anschließend Stapling und erneute ZIP-Erstellung. Zugangsdaten und private Schlüssel werden nicht im Projekt gespeichert. Der konkrete Signatur- und Notarisierungsstatus steht im jeweiligen Release und Integritätsmanifest. Das Projektverzeichnis bleibt `Seed-Phrase`; App, Swift-Paket, Module, Bundle-Kennung und Release-Dateien heißen nun Password Generator beziehungsweise PasswordGenerator.

## Mauspool und Generierung

1. Bewegungen im gesamten Appfenster einschließlich Bewegungen über Bedienelementen und Ziehbewegungen werden erfasst. Es gibt kein begrenztes Sammelfeld und keine globale Überwachung anderer Apps.
2. Der Pool hält die letzten 4.096 vollständigen Mausereignisse. Die Generierung benötigt mindestens 4.096 Bewegungen. Weitere Bewegungen ersetzen den jeweils ältesten Datensatz; der Speicherbedarf bleibt begrenzt. Ein Datensatz enthält laufende Nummer, monotone Zeit, Ereigniszeit, Position, Delta, Fenstergröße, Modifikatortasten und gedrückte Maustasten.
3. Ab dem Appstart läuft im Abstand von sechs Sekunden ein Fisher-Yates-Shuffle in der linearen Durstenfeld-Variante. Er permutiert die Datensätze mit Zufallsbytes aus `SecRandomCopyBytes`. Rejection Sampling vermeidet Modulo-Verzerrungen. Der Startdurchlauf auf dem noch leeren Pool ist ein Leerlauf. Während macOS die App suspendiert oder der Rechner schläft, kann kein Prozess einen Echtzeit-Takt garantieren.
4. Bei der Generierung erfolgt erneut ein Shuffle. Erst danach werden die Datensätze in der gemischten Reihenfolge serialisiert und `Skein-1024-1024(pool)`, `SHA3-512(pool)` und `SHA-512(pool)` berechnet. Beim Sammeln und bei den periodischen Shuffles werden diese Poolhashes nicht berechnet. Die separaten Integritätsprüfungen der eingebetteten Wortlisten finden beim Laden statt.
5. Die Digests werden in der Reihenfolge Skein-1024-1024, SHA3-512, SHA-512 zusammengefügt: 128 + 64 + 64 = 256 Byte beziehungsweise 2.048 Bit. Zuerst werden diese 256 Hashbytes mit 256 frisch angeforderten kryptografischen macOS-Zufallsbytes XOR-verknüpft.
6. Fisher-Yates permutiert anschließend alle 2.048 einzelnen Bits dieses XOR-Ergebnisses mit weiteren kryptografischen macOS-Zufallsbytes. Dabei werden Bitpositionen gemischt, nicht lediglich die Reihenfolge der 256 Byte. Nach der Bitmischung ergibt ein zweites XOR mit separat angeforderten 256 frischen macOS-Zufallsbytes den Masterkey. Die beiden XOR-Masken und die Zufallsbytes für die Shuffles stammen aus getrennten Anforderungen; keine Maske wird wiederverwendet.
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

Die BIP39- und EFF-Wortlisten werden vor Verwendung gegen fest eingebaute SHA256-, SHA3-512- und Skein-1024-1024-Werte geprüft. Die App zeigt für jede Liste alle drei Digests an, Skein-1024-1024 jeweils nach SHA256 und SHA3-512. Die erwarteten Skein-Wortlistenwerte werden unabhängig mit der offiziellen C-Referenzimplementierung unter `Tests/Reference/Skein` über `Scripts/skein-reference-checksum.sh` gegengeprüft. Das vollständige finale Release-ZIP wird mit SHA256, SHA3-512 und Skein-1024-1024 gehasht. Zu jedem Verfahren gehört eine eigene Prüfsummendatei. Die zusätzliche Skein-Datei heißt `Password.Generator-2.3.4.zip.skein-1024-1024`; das Integritätsmanifest enthält ihren Wert im Feld `skein-1024-1024`.

`Scripts/verify-release.sh` prüft SHA256 und SHA3-512 unabhängig mit Python. Skein-1024-1024 wird über `Scripts/skein-reference-checksum.sh` mit der offiziellen C-Referenzimplementierung unter `Tests/Reference/Skein` kontrolliert. Das Prüfskript entpackt außerdem das ZIP und prüft Code-Signatur sowie Sandbox.

Diese zusätzlichen Integritätsprüfsummen ersetzen oder ändern Apples Developer-ID-Signaturverfahren nicht. Das Erstellen dieser externen Prüfsummendateien und des Integritätsmanifests verändert weder das App-Bundle noch das finale ZIP. Hashwerte allein beweisen keine Herkunft.

Testergebnisse für Version 2.3.4, Build 11: Jeweils 103 Tests in Debug und Release bestanden, ohne Compilerwarnungen: pro Build 74 Core-Tests und 29 App-Tests. [Verifikation und Release-Nachweise](docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

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
