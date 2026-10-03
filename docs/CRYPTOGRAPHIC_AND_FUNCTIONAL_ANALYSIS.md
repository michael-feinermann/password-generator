# Technische Analyse von Password Generator 2.2.0

Stand: 3. Oktober 2026. Diese Datei beschreibt die Ableitung und Verifikation für Version 2.2.0, Build 5. Den vorigen Release beschreibt [die Analyse zu 2.1.0](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS_2.1.0.md).

## Datenfluss

Der Pool hält die letzten 4.096 tatsächlichen Mausbewegungen. Ein Datensatz umfasst 89 Byte: Versionsbyte 1 und elf 64-Bit-Werte in Little-Endian-Reihenfolge für Ereignisnummer, monotone Nanosekunden, Ereigniszeit, x, y, deltaX, deltaY, Fensterbreite, Fensterhöhe, Modifikatormaske und gedrückte Maustasten. Fließkommazahlen werden über ihr IEEE-754-Bitmuster codiert. Ein voller Pool enthält 364.544 Byte Nutzdaten.

Ein begrenzter Ringpuffer ersetzt die ältesten Datensätze. Eine getrennte Indexpermutation bestimmt die Reihenfolge für das Hashen. Bewegungen über Bedienelementen und Ziehbewegungen werden im gesamten Appfenster erfasst; stationäre Ereignisse und Ereignisse anderer Fenster werden ausgeschlossen.

Fisher-Yates verwendet die lineare Durstenfeld-Variante mit absteigenden Indizes und gleichverteilter Auswahl einschließlich der aktuellen Position. Kandidaten stammen als Little-Endian-UInt32 aus frischen, gepufferten macOS-CSPRNG-Bytes. Rejection Sampling verwirft den unvollständigen letzten Modulo-Bucket. Wiederholt unbrauchbare Kandidaten führen zum Fehler. Ab Appstart läuft ein Poolshuffle etwa alle sechs Sekunden, zusätzlich unmittelbar vor jeder Generierung. Auf dem anfangs leeren Pool ist der Shuffle ein Leerlauf. Suspendierung und Schlaf können den periodischen Termin verschieben.

Alle Poolhashes und die folgende Ableitung erfolgen ausschließlich bei der Generierung:

```text
shuffle(records)
P = serialize(records in shuffled order)
D = Skein-1024-1024(P) || SHA3-512(P) || SHA512(P)  // 128 + 64 + 64 Byte
B = fisher_yates_shuffle_all_2048_bits(D)
M = B XOR fresh_macOS_random(256)                  // 256-Byte-Masterkey
S0 = Skein1024XOF(M[0..<128])
S1 = SHAKE256(M[128..<160])
S2 = SHAKE256(M[160..<192])
S3 = AES256CTR(key: M[192..<224], counter: 0)
S4 = AES256CTR(key: M[224..<256], counter: 0)
X = read(S0,n) XOR read(S1,n) XOR read(S2,n) XOR read(S3,n) XOR read(S4,n)
output_bytes = X XOR fresh_macOS_random(n)
```

Skein-1024-1024 liefert 128 Byte, SHA3-512 und SHA512 jeweils 64 Byte. SHA512 wird über CryptoKit berechnet. Die Reihenfolge der Verkettung ist fest. Der anschließende Fisher-Yates-Durchlauf permutiert sämtliche 2.048 einzelnen Bits, nicht nur die 256 Byte. Bitindex null bezeichnet das niederwertigste Bit von Byte null. Die OS-Bytes für den Masterkey-XOR werden unabhängig von den Shuffle-Bytes angefordert.

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

## Export und Laufzeitschutz

BIP39 verwendet standardmäßig ein Leerzeichen, EFF einen Bindestrich. Beide Trennzeichen bleiben unabhängig und frei wählbar, einschließlich leerer oder mehrstelliger Texte. Hex lässt sich mit kleinen oder großen Buchstaben exportieren. Eine Formatänderung erhält die ursprünglichen Komponenten und zieht keine neuen Zufallswerte.

BIP39 ohne Trenner ist nicht immer eindeutig rekonstruierbar: `leg alarm` und `legal arm`, jeweils gefolgt von neunmal `abandon` und `accuse`, ergeben zwei verschiedene prüfsummengültige 12-Wort-Mnemonics mit demselben zusammengefügten Text. Die Entropieanzeige gilt deshalb für die ursprüngliche Auswahl. Für den üblichen BIP39-Import sind Leerzeichen zu verwenden.

Die App benötigt vor Generierung, Anzeige und Kopieren eine gültige laufende Code-Signatur, Hardened Runtime, minimale Sandbox und keinen erkannten Debugger. POSIX-Core-Dumps sind deaktiviert. Die Ausgabe bleibt zunächst verdeckt; Anzeigen erfordert Bestätigung und wird bestmöglich nach 60 Sekunden beziehungsweise bei Kontextwechsel beendet. Die auf ausdrücklichen Klick befüllte Zwischenablage verwendet `currentHostOnly` und wird bestmöglich nach etwa 45 Sekunden geleert, wenn der Inhalt unverändert ist.

Mauspool und temporäre Kryptopuffer werden beim Verwerfen bestmöglich überschrieben, CommonCrypto-Kontexte freigegeben. Swift-Kopien, Register und Betriebssystempuffer verhindern eine garantierte vollständige Löschung. Screenshots, externe Kameras oder ein kompromittiertes Betriebssystem lassen sich damit nicht zuverlässig abwehren. Die App speichert erzeugte Passwörter nicht in Dateien oder Preferences und besitzt keine Netzwerkberechtigung.

## Verifikation

Am 3. Oktober 2026 bestanden jeweils 80 XCTest-Tests im Debug- und Release-Build: 61 Core-Tests und 19 App-Modelltests, ohne Fehler oder Compilerwarnungen. Verwendet wurden `swift test -Xswiftc -warnings-as-errors` und `swift test -c release -Xswiftc -warnings-as-errors`. Enthalten sind sieben gezielte AES-CTR-Tests mit fünf unabhängigen Vektoren, drei vollständige Ableitungsreferenzen, 45 unabhängig berechnete Passwortfälle sowie die bestehenden 49 Skein-1024-1024-, 81 SHA3-512-, 538 SHAKE256- und 22 Skein-XOF-Vektoren. Die Referenzgeneratoren für Pipeline und AES wurden offline erneut ausgeführt und erzeugten byteidentische JSON-Fixtures.

Die vollständigen Referenzen werden mit der unveränderten offiziellen Skein-C-Referenz, Python `hashlib` für SHA3/SHA512/SHAKE sowie einer unabhängigen AES-Referenz berechnet. Der reproduzierbare Generator und die Zwischenwerte stehen unter `Tests/PasswordGeneratorCoreTests/Resources/`; die Herkunft dokumentiert `CRYPTO_VECTORS.md`. Sie prüfen Null-Shuffle-Kandidaten, variierte Kandidaten mit gezielten Rejections und einen mehrfach überschreibenden Ringpuffer mit zwischenzeitlichen Shuffles. Die erwarteten Werte werden nicht aus dem Swift-Produktionscode erzeugt.

Die AES-Prüfungen enthalten den AES-256-CTR-Testvektor aus NIST SP 800-38A, getrennte und zusammenhängende Reads, Zählerüberträge, das Ende des 128-Bit-Zählerraums, Clear und Fehlerbehandlung. Die vollständige Ableitung wird über die Blockgrenzen von AES, Skein-XOF und SHAKE hinweg verglichen. Alle fünf Ausgabeformate sowie ihre gültigen und ungültigen Grenzlängen und Exportoptionen werden geprüft.

Das Release-ZIP erhält weiterhin separate SHA256-, SHA3-512- und Skein-1024-1024-Prüfsummendateien und ein Integritätsmanifest. `Scripts/verify-release.sh` vergleicht jedes Verfahren mit ZIP, Sidecar und Manifest. Python kontrolliert beide SHA-Werte unabhängig; `Scripts/skein-reference-checksum.sh` verwendet die offizielle C-Referenz. Das entpackte App-Bundle wird zusätzlich auf Code-Signatur und minimale Sandbox geprüft. Für notarisierte Pakete folgen Ticket- und Gatekeeper-Prüfung. Hashwerte allein beweisen keine Herkunft.

## Release-Nachweis

Version 2.2.0, Build 5, wurde am 3. Oktober 2026 um 10:17 Uhr (Europe/Berlin) über Xcode Direct Distribution hochgeladen und von Apple zur Verteilung freigegeben. Die Submission-ID lautet `F9C89067-06A5-459E-A728-AE6C30B6B579`. Das exportierte Bundle trägt eine Developer-ID-Signatur für Team `2T6K9PGS55`, ein angeheftetes Notarisierungsticket und den CodeDirectory-Hash `0ce21ec26af00d19a82b5a82266e6ed838c1a7f2`.

Zwischen dem getesteten Paket und dem Xcode-Export wurden sämtliche Ressourcen und Metadaten byteweise verglichen. Der ausführbare Code ist nach Entfernung ausschließlich der Signatur aus temporären Kopien ebenfalls byteidentisch; sein normalisierter SHA256-Wert lautet `e8854c6fe5e2917ae0381956731173f31335b4e0b594e270acd84c1d80df0843`. Das finale ZIP wurde unmittelbar aus dem notarisierten Xcode-Export erstellt, ohne anschließenden Neubau oder erneute Signierung.

Das endgültige Paket hat folgende Prüfsummen:

```text
SHA256: ab222f7f1b044fee8eda66b43ce40a5ea04eef2941a05d018354c9a091e4bcd8
SHA3-512: 5a284c608f4d5d047dc88b65b0eedfdba78c902f0559fceb602d073c85600df27bc167761366f5bb9c45f756acb504e9ef3bf01e45c9e2bd48a54a95382b8bfe
Skein-1024-1024: d41bf9ac0f0beea08bdf2af28c984c031f60f485abb9c7f80c6e1d854a8477ddbf67f3eff7ca68f56290ea8f326ba22b9ae36ef5086446ddc0f5adac8abc183583c66a1402f0b74e268bbe00d9f2d2e98a6d3630d85e4ac5140b8dc390c04540e7958d1bcc099e2c4cf437ee298fbaaf9c6b09de7305e2c3c9dc29e76f954e51
```

Die ZIP-Prüfung bestand für alle drei Hashverfahren einschließlich der unabhängigen Skein-C-Referenz. `codesign --verify --deep --strict`, `xcrun stapler validate` und `spctl --assess --type execute` bestanden für das entpackte Release sowie die installierte App. Gatekeeper meldete `accepted` und `source=Notarized Developer ID`. Die installierte Kopie unter `/Applications/Password Generator 2.2.0.app` stimmt byteweise mit dem Xcode-Export überein; die frühere Installation und zusätzliche aktive Build-Kopien wurden in den Papierkorb verschoben.

Der Release-Link dieser Version lautet [GitHub Release v2.2.0](https://github.com/michael-feinermann/password-generator/releases/tag/v2.2.0). Die hier dokumentierten Paketprüfungen beziehen sich auf die oben angegebenen finalen Bytes.

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
