# Technische Analyse von Password Generator 2.3.1

Stand: 4. Oktober 2026. Diese Datei beschreibt die Ableitung und Verifikation für Version 2.3.1, Build 8. Den vorigen Release beschreibt [die Analyse zu 2.3.0](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS_2.3.0.md).

## Datenfluss

Der Pool hält die letzten 4.096 tatsächlichen Mausbewegungen. Ein Datensatz umfasst 89 Byte: Versionsbyte 1 und elf 64-Bit-Werte in Little-Endian-Reihenfolge für Ereignisnummer, monotone Nanosekunden, Ereigniszeit, x, y, deltaX, deltaY, Fensterbreite, Fensterhöhe, Modifikatormaske und gedrückte Maustasten. Fließkommazahlen werden über ihr IEEE-754-Bitmuster codiert. Ein voller Pool enthält 364.544 Byte Nutzdaten.

Ein begrenzter Ringpuffer ersetzt die ältesten Datensätze. Eine getrennte Indexpermutation bestimmt die Reihenfolge für das Hashen. Bewegungen über Bedienelementen und Ziehbewegungen werden im gesamten Appfenster erfasst; stationäre Ereignisse und Ereignisse anderer Fenster werden ausgeschlossen.

Fisher-Yates verwendet die lineare Durstenfeld-Variante mit absteigenden Indizes und gleichverteilter Auswahl einschließlich der aktuellen Position. Kandidaten stammen als Little-Endian-UInt32 aus frischen, gepufferten macOS-CSPRNG-Bytes. Rejection Sampling verwirft den unvollständigen letzten Modulo-Bucket. Wiederholt unbrauchbare Kandidaten führen zum Fehler. Ab Appstart läuft ein Poolshuffle etwa alle sechs Sekunden, zusätzlich unmittelbar vor jeder Generierung. Auf dem anfangs leeren Pool ist der Shuffle ein Leerlauf. Suspendierung und Schlaf können den periodischen Termin verschieben.

Alle Poolhashes und die folgende Ableitung erfolgen ausschließlich bei der Generierung:

```text
shuffle(records)
P = serialize(records in shuffled order)
D = Skein-1024-1024(P) || SHA3-512(P) || SHA512(P)  // 128 + 64 + 64 Byte
A = D XOR fresh_macOS_random(256)                  // erster separat angeforderter OS-Beitrag
B = fisher_yates_shuffle_all_2048_bits(A)
M = B XOR fresh_macOS_random(256)                  // 256-Byte-Masterkey
S0 = Skein1024XOF(M[0..<128])
S1 = SHAKE256(M[128..<160])
S2 = SHAKE256(M[160..<192])
S3 = AES256CTR(key: M[192..<224], counter: 0)
S4 = AES256CTR(key: M[224..<256], counter: 0)
X = read(S0,n) XOR read(S1,n) XOR read(S2,n) XOR read(S3,n) XOR read(S4,n)
output_bytes = X XOR fresh_macOS_random(n)
```

Skein-1024-1024 liefert 128 Byte, SHA3-512 und SHA512 jeweils 64 Byte. SHA512 wird über CryptoKit berechnet. Die Reihenfolge der Verkettung ist fest. Zuerst werden die 256 Hashbytes mit einem frischen, gleich langen macOS-CSPRNG-Beitrag XOR-verknüpft. Danach permutiert Fisher-Yates sämtliche 2.048 einzelnen Bits dieses Ergebnisses, nicht nur die 256 Byte. Bitindex null bezeichnet das niederwertigste Bit von Byte null. Erst der zweite XOR mit weiteren frischen 256 macOS-CSPRNG-Bytes ergibt den Masterkey. Beide Masken werden separat angefordert und weder untereinander noch mit den Zufallsbytes für den Shuffle oder den späteren Ausgabe-XOR wiederverwendet.

Skein-XOF folgt Skein v1.3, Abschnitt 4.12: Das Ausgabelängenfeld ist `N_o = 2^64 - 1`. Das erste Masterkey-Fragment wird als ungeschlüsselte Nachricht absorbiert. Die Ausgabe besteht aus UBI-Blöcken vom Typ 63 mit fortlaufenden Little-Endian-64-Bit-Ausgabezählern. Diese XOF-Konfiguration unterscheidet sich vom Poolhash mit fester 1.024-Bit-Ausgabe.

Die zwei SHAKE256-Streams erhalten jeweils eigene 32-Byte-Fragmente. Ihre Absorb- und Squeeze-Zustände bleiben über alle Reads erhalten. Die beiden AES-256-CTR-Streams erhalten die letzten zwei separaten 32-Byte-Fragmente als AES-Schlüssel. CommonCrypto übernimmt ausschließlich die AES-Blockverschlüsselung im ECB-Modus ohne Padding; daraus erzeugt die Anwendung den CTR-Strom durch Verschlüsselung des expliziten 128-Bit-Zählers. AES wird nicht im Projekt selbst implementiert.

Jeder AES-Zähler beginnt bei null und wird über alle 128 Bit in Big-Endian-Reihenfolge inkrementiert. Ein teilweise gelesener 16-Byte-Ausgabeblock bleibt für die nächsten Reads erhalten. Nach dem letzten gültigen Zählerblock dürfen nur dessen noch nicht gelesene Bytes ausgegeben werden; eine weitere Blockanforderung bricht ab. Ein Umlauf auf null wird niemals unter demselben Schlüssel verwendet. Die Streams werden pro Generierung neu mit den frischen Masterkey-Fragmenten initialisiert. Dieselbe Kombination aus Schlüssel und Zähler darf nicht wiederverwendet werden.

Alle fünf Streams laufen bei Nachforderungen durch Rejection Sampling von ihrer aktuellen Position weiter. Jede Ausgabeanforderung erhält anschließend einen frischen, gleich langen OS-XOR-Beitrag. Bei einem Ableitungs- oder OS-Fehler wird der betroffene Passwortstream vollständig verworfen; erfolgreich konsumierte Präfixe werden nicht erneut ausgegeben. Der periodische Task mischt nur Mausereignisse und berechnet weder Poolhashes noch Masterkeys.

## Ausgabeformate und Entropieanzeige

| Format | Zulässige Länge | Alphabetgröße | Nominelle Entropie |
|---|---|---|---|
| BIP39 | 12, 15, 18, 21 oder 24 Wörter | 2.048 Wörter | 128, 160, 192, 224 oder 256 Bit |
| EFF | 6 bis 128 Wörter | 7.776 Wörter | Wörter × log₂(7.776) |
| ASCII | 8 bis 256 Zeichen | 94 Zeichen ohne Leerzeichen | Zeichen × log₂(94) |
| PIN | 3 bis 512 Ziffern | 10 Ziffern | Ziffern × log₂(10) |
| Hex | 1 bis 512 Zeichen | 16 Zeichen | Zeichen × 4 Bit |

Die Anzeige beschreibt die Größe des gleichverteilt abgetasteten Auswahlraums. BIP39-Prüfsummenbits zählen nicht als zusätzliche Entropie. Bei maximaler Länge ergeben sich rechnerisch etwa 1.654,376 Bit für EFF und 1.700,827 Bit für PIN sowie 2.048 Bit für Hex. Diese Größen messen weder Mausentropie noch die Sicherheitsstärke der gesamten Konstruktion. Wiederholte Zeichen oder Wörter bleiben zulässig.

Die Hashlänge von 2.048 Bit beweist keine entsprechende unabhängige Eingabeentropie. Alle drei Poolhashes verarbeiten dieselben Ereignisse. Die Bitpermutation erhält die Anzahl der gesetzten Bits. Die Sicherheitsstärken der fünf XOR-verknüpften Streams dürfen nicht addiert werden. Die individuelle Konstruktion ist weder ein standardisiertes DRBG-Verfahren noch extern kryptografisch auditiert. Ihre Sicherheit stützt sich weiterhin auf die Unvorhersagbarkeit der frischen Systemzufallsbytes. Die beiden ergänzten AES-CTR-Streams sind keine Aussage über den internen Aufbau von Apples CSPRNG.

## Vorschläge und farbliche Einordnung

Beim Start und bei jedem Formatwechsel schlägt die App die kleinste unterstützte Länge mit mindestens 256 nominellen Bit vor: 24 BIP39-Wörter (256 Bit), 20 EFF-Wörter (rund 258,50 Bit), 40 ASCII-Zeichen (rund 262,18 Bit) und 64 Hexzeichen (256 Bit). Die gewünschte Ausnahme ist eine PIN mit sechs Ziffern (rund 19,93 Bit). Andere erlaubte Längen bleiben frei wählbar.

Die Einstufung verwendet den ungerundeten Wert, während die Oberfläche eine Dezimalstelle zeigt. Unter 128 Bit erscheint die Anzeige rot, von 128 bis unter 256 Bit gelb, von 256 bis unter 1.024 Bit hellgrün und ab 1.024 Bit dunkelgrün. Text, Symbol und eine vierteilige Legende ergänzen die Farbe. Ungültige Eingaben erhalten eine neutrale Anzeige. Konfiguration und erzeugtes Ergebnis verwenden dieselbe Einordnung.

Die deutschen Stufentexte lauten auf Nutzerwunsch „knackbar“, „nicht quantensicher“, „praktisch nicht angreifbar“ und „thermodynamisch nicht angreifbar“. Die Erläuterungen beziehen sich auf ideal gleichverteilte Auswahl beziehungsweise das idealisierte Grover-Suchmodell. Sie bewerten keine konkrete Quantenhardware. Ein fokussierbarer Info-Button unmittelbar hinter jeder Bezeichnung öffnet den Hinweis, dass diese Einordnung für Brute-Force-Raten bei gleichverteilter Zufallsauswahl gedacht ist. Der Hinweis kennzeichnet die Texte als vereinfachte Stufenbezeichnungen und grenzt sie von Garantien, realer Quantenhardware und einem thermodynamischen Nachweis ab. Der Info-Button zeigt zusätzlich einen Tooltip mit demselben Hinweis. Die Beschriftungen sind damit keine mathematischen oder physikalischen Nachweise der jeweiligen Aussage. Ein Hinweis erklärt unmittelbar bei der Anzeige, dass der nominelle Auswahlraum weder gemessene Quellenentropie noch eine Garantie der Gesamtsicherheit ist. Diese Grenzen sind keine NIST-Sicherheitsklassifizierung; auch ein kleinerer Suchraum ist nicht automatisch praktisch knackbar. [NIST: Post-Quantum Cryptography FAQ](https://csrc.nist.gov/Projects/post-quantum-cryptography/faqs).

## Export und Laufzeitschutz

BIP39 verwendet standardmäßig ein Leerzeichen, EFF einen Bindestrich. Beide Trennzeichen bleiben unabhängig und frei wählbar, einschließlich leerer oder mehrstelliger Texte. Hex lässt sich mit kleinen oder großen Buchstaben exportieren. Eine Formatänderung erhält die ursprünglichen Komponenten und zieht keine neuen Zufallswerte.

BIP39 ohne Trenner ist nicht immer eindeutig rekonstruierbar: `leg alarm` und `legal arm`, jeweils gefolgt von neunmal `abandon` und `accuse`, ergeben zwei verschiedene prüfsummengültige 12-Wort-Mnemonics mit demselben zusammengefügten Text. Die Entropieanzeige gilt deshalb für die ursprüngliche Auswahl. Für den üblichen BIP39-Import sind Leerzeichen zu verwenden.

Die App benötigt vor Generierung, Anzeige und Kopieren eine gültige laufende Code-Signatur, Hardened Runtime, minimale Sandbox und keinen erkannten Debugger. POSIX-Core-Dumps sind deaktiviert. Die Ausgabe bleibt zunächst verdeckt; Anzeigen erfordert Bestätigung und wird bestmöglich nach 60 Sekunden beziehungsweise bei Kontextwechsel beendet. Die auf ausdrücklichen Klick befüllte Zwischenablage verwendet `currentHostOnly` und wird bestmöglich nach etwa 45 Sekunden geleert, wenn der Inhalt unverändert ist.

Mauspool und temporäre Kryptopuffer werden beim Verwerfen bestmöglich überschrieben, CommonCrypto-Kontexte freigegeben. Swift-Kopien, Register und Betriebssystempuffer verhindern eine garantierte vollständige Löschung. Screenshots, externe Kameras oder ein kompromittiertes Betriebssystem lassen sich damit nicht zuverlässig abwehren. Die App speichert erzeugte Passwörter nicht in Dateien oder Preferences und besitzt keine Netzwerkberechtigung.

## Verifikation

Am 4. Oktober 2026 bestanden jeweils 87 XCTest-Tests im Debug- und Release-Build: 67 Core-Tests und 20 App-Modelltests, ohne Fehler oder Compilerwarnungen. Verwendet wurden `swift test -Xswiftc -warnings-as-errors` und `swift test -c release -Xswiftc -warnings-as-errors`. Die unveränderten Tests umfassen die vollständige kryptografische Ableitung, die Passwortformate, Fehlerverhalten und exakte Schwellen. Der SHA256-Wert der unveränderten Pipeline-Fixtures lautet `50541a981bb2fca83307cbfb86aec2643533a2675efc21301630e0d3afdfee0b`.

Die zusätzlichen Tests prüfen die minimalen Vorschlagslängen einschließlich der PIN-Ausnahme, den initialen Appzustand und jeden Formatwechsel, die ungerundeten Schwellen direkt darunter, darauf und darüber sowie die Einordnung ungültiger Zahlen. Reale Hex-Konfigurationen an allen vier Grenzen prüfen die Verbindung zwischen Format und Stufe. Die vorhandenen Tests für Kryptografie, vollständige Ableitung, Passworterzeugung und Fehlerverhalten bleiben enthalten.

Die vollständigen Referenzen werden mit der unveränderten offiziellen Skein-C-Referenz, Python `hashlib` für SHA3/SHA512/SHAKE sowie einer unabhängigen AES-Referenz berechnet. Der reproduzierbare Generator und die Zwischenwerte stehen unter `Tests/PasswordGeneratorCoreTests/Resources/`; die Herkunft dokumentiert `CRYPTO_VECTORS.md`. Sie prüfen Null-Shuffle-Kandidaten, variierte Kandidaten mit gezielten Rejections und einen mehrfach überschreibenden Ringpuffer mit zwischenzeitlichen Shuffles. Die erwarteten Werte werden nicht aus dem Swift-Produktionscode erzeugt. Fixture-Version 4 enthält zusätzlich die erste OS-Maske, den bereits maskierten Digest und die zweite OS-Maske als getrennte Zwischenwerte. Die Tests prüfen die Reihenfolge beider 256-Byte-Anforderungen relativ zu den Shuffle-Bytes. Sie prüfen außerdem für jede Maske sowohl eine zu kurze Rückgabe als auch einen geworfenen Fehler und stellen sicher, dass danach keine späteren Zufallsanforderungen erfolgen.

Die AES-Prüfungen enthalten den AES-256-CTR-Testvektor aus NIST SP 800-38A, getrennte und zusammenhängende Reads, Zählerüberträge, das Ende des 128-Bit-Zählerraums, Clear und Fehlerbehandlung. Die vollständige Ableitung wird über die Blockgrenzen von AES, Skein-XOF und SHAKE hinweg verglichen. Alle fünf Ausgabeformate sowie ihre gültigen und ungültigen Grenzlängen und Exportoptionen werden geprüft.

Das Release-ZIP erhält weiterhin separate SHA256-, SHA3-512- und Skein-1024-1024-Prüfsummendateien und ein Integritätsmanifest. `Scripts/verify-release.sh` vergleicht jedes Verfahren mit ZIP, Sidecar und Manifest. Python kontrolliert beide SHA-Werte unabhängig; `Scripts/skein-reference-checksum.sh` verwendet die offizielle C-Referenz. Das entpackte App-Bundle wird zusätzlich auf Code-Signatur und minimale Sandbox geprüft. Für notarisierte Pakete folgen Ticket- und Gatekeeper-Prüfung. Hashwerte allein beweisen keine Herkunft.

## Release-Nachweis

Version 2.3.1, Build 8, wurde am 4. Oktober 2026 mit Developer ID signiert und über Xcodes Direct Distribution notarisiert. Xcode meldete „Ready to distribute“. Die Submission-ID lautet `FF1F795C-8627-46AB-9007-3C3E2E0D490E`, der finale CodeDirectory-Hash `dd2c0c0e7e4c3fda132b7be254d36c87e06a512c` und das Developer-ID-Team `2T6K9PGS55`.

Nach Entfernen ausschließlich der Signatur auf temporären Kopien stimmte der ausführbare Mach-O-Code aus dem Paket-Build und dem Xcode-Export byteweise überein; sein normalisierter SHA256-Wert lautet `c4f638ea8b1fbc7a3a7f6fa3e4bf29fcc7876b4eb98b85652ec36d1d3f9fbbbf`. Alle Ressourcen waren ebenfalls identisch. Das finale ZIP wurde unmittelbar aus dem notarisierten Xcode-Export erstellt, ohne anschließenden Neubau oder erneute Signierung.

Die finalen Paketprüfsummen lauten:

```text
SHA256: 073224f4e93a08b60281c3d6d1ac6a89d4ffdbc0b5e66680c003ee5466e7c9cc
SHA3-512: 26f46b977d8471d47734e30bcfcb1f39eaf7dafa6ff4740b5cc4c28280ccbc581ffa30ea64d35c4c9bca1d489073fd57e51315bde0b1645864e721ebcdfad7c7
Skein-1024-1024: d706d89a556f14c9a59cc0ebe8333488f090e2cb03b6df118f7db35933574f79828d48d3023d11559b9ec0beb79b13533cf823cf0f75d720010062f2923083e97f75ef2fc2cc019f5cf1d1f623a0e8a7071ca366869839350d9fe71b047de1d6135efb37055908b42329eb6dc7523bf159c106f6d80e7a4ff717e6fe858b0dd0
```

Die Paketprüfung bestand einschließlich unabhängiger SHA-Gegenprüfung durch Python und Skein-C-Referenz. `codesign --verify --deep --strict`, `xcrun stapler validate` und `spctl --assess --type execute` bestanden für das entpackte Paket und die installierte App. Gatekeeper meldete `accepted` und `source=Notarized Developer ID`. Bundle-Version, Build, Manifest, Developer-ID-Team und Hardened Runtime wurden zusätzlich abgeglichen.

Die aktuelle Installation unter `/Applications/Password Generator 2.3.1.app` ist anhand sämtlicher Dateihashes identisch mit dem Xcode-Export. Die alte Installation 2.3.0 sowie deren zusätzliche App-Bundles im Build- und Exportordner wurden bei LaunchServices abgemeldet und in den Papierkorb verschoben. In `/Applications` und `~/Applications` bleibt ausschließlich die aktuelle Installation mit der Bundle-Kennung. Historische Xcode-Archive sind keine installierten Apps und bleiben als Release-Nachweise erhalten.

Die installierte App wurde geöffnet und zeigte Version 2.3.1, 24 BIP39-Wörter und gültigen Laufzeitschutz. Im Paket-Build wurden alle vier exakten deutschen Bezeichnungen durch Format- beziehungsweise Längenwechsel geprüft. Infofenster der Hauptanzeige und der Legende öffneten den vollständigen Hinweis. Schließen per Escape und Schaltfläche sowie die englische Übersetzung wurden geprüft. Die Info-Schaltflächen bleiben im Accessibility-Baum erreichbar. Eine Pixelprüfung war wie beim vorigen Release durch den bestehenden Fensterschutz nicht möglich; die Prüfung erfolgte über die native Bedienoberfläche und deren Accessibility-Baum.

Auf Nutzerwunsch wird nur die aktuelle Version als GitHub-Release mit Downloadpaket und Release-Tag angeboten; ersetzte Releases und Tags werden entfernt. Die Quellcodehistorie und historische Dokumentation bleiben nachvollziehbar. Der aktuelle Download ist [GitHub Release v2.3.1](https://github.com/michael-feinermann/password-generator/releases/tag/v2.3.1).

## Quellen

- [BIP39-Spezifikation](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Originalwortliste](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [Skein v1.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
- [NIST FIPS 202: SHA3 und SHAKE](https://csrc.nist.gov/pubs/fips/202/final)
- [NIST FIPS 180-4: SHA512](https://csrc.nist.gov/pubs/fips/180-4/upd1/final)
- [NIST SP 800-38A: CTR und AES-256-CTR-Testvektor](https://csrc.nist.gov/pubs/sp/800/38/a/final)
- [Apple CommonCrypto](https://github.com/apple-oss-distributions/CommonCrypto)
- [Apple SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
- [Durstenfeld, Algorithm 235](https://doi.org/10.1145/364520.364540)
