# Herkunft der Kryptografie-Testvektoren

Die Dateien enthalten unabhängige Erwartungswerte. Sie werden nicht mit den Swift-Primitiven erzeugt.

## Skein-1024-1024, Version 1.3

Quelle: https://www.schneier.com/academic/skein/

Spezifikation: https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf

Archiv: https://www.schneier.com/wp-content/uploads/2015/01/skein.zip

SHA-256 des heruntergeladenen Archivs:
`121b73a4d5300b4977d3757064a29ba5e11c0fb01786171b2bc729ef099b89ad`

`skein1024_vectors.json` enthält alle 36 byteorientierten, ungeschlüsselten Skein-1024-1024-Vektoren aus `NIST/CD/KAT_MCT/skein_golden_kat.txt`. Nicht byteorientierte Vektoren, andere Ausgabelängen und MAC-Vektoren wurden ausgeschlossen. Die Eingaben sind leer oder 1 bis 256 Byte lang, mit Nullbytes, aufsteigenden Bytes und Pseudozufallsdaten.

Zusätzlich enthalten sind 13 Grenzfälle mit Eingabelängen 0, 1, 31, 32, 127, 128, 129, 255, 256, 257, 4095, 4096 und 4097 Byte. Eingabebyte i ist jeweils i modulo 256. Diese Erwartungswerte wurden durch Kompilieren von `NIST/CD/Reference_Implementation/skein.c` und `skein_block.c` mit Apple clang erzeugt. Jeder Vektor verwendet `Skein1024_Init(&ctx, 1024)`, `Skein1024_Update(&ctx, msg, length)` und `Skein1024_Final(&ctx, output)`.

## SHA3-512 und SHAKE256

Standard: https://doi.org/10.6028/NIST.FIPS.202

NIST CAVP: https://csrc.nist.gov/Projects/cryptographic-algorithm-validation-program/Secure-Hashing

Archive:

* https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/sha3/sha-3bytetestvectors.zip
* https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-Validation-Program/documents/sha3/shakebytetestvectors.zip

SHA-256 der Archive, in derselben Reihenfolge:

* `cd07701af2e47f5cc889d642528b4bf11f8b6eb55797c7307a96828ed8d8fc8c`
* `debfebc3157b3ceea002b84ca38476420389a3bf7e97dc5f53ea4689a16de4c7`

`sha3_nist_vectors.json` enthält alle 73 Einträge aus `SHA3_512ShortMsg.rsp` und die Einträge mit nullbasiertem Index 0, 1, 2, 9, 24, 49, 74 und 99 aus `SHA3_512LongMsg.rsp`, insgesamt 81 Vektoren.

`shake_nist_vectors.json` enthält alle 273 Einträge aus `SHAKE256ShortMsg.rsp`, dieselbe Auswahl von 8 Indizes aus `SHAKE256LongMsg.rsp` und jeweils den ersten Eintrag jeder der 249 verschiedenen Ausgabelängen aus `SHAKE256VariableOut.rsp`. Bei NISTs `Len = 0` ist `Msg = 00` ein Platzhalter für die leere Eingabe.

Hinzu kommen 8 SHAKE256-Vektoren mit je 513 Ausgabebytes, erzeugt mit Python `hashlib.shake_256(message).hexdigest(513)`. Die Eingabelängen sind 0, 135, 136, 137, 271, 272, 273 und 4096 Byte; Eingabebyte i ist i modulo 256. Damit werden mehrere Squeeze-Blöcke und die Absorb-Grenzen unabhängig geprüft. Insgesamt enthält die Datei 538 Vektoren.

Bekannte Testvektoren prüfen Implementierungsfehler. Sie sind weder eine CAVP-Zertifizierung noch ein unabhängiges Sicherheitsaudit des Generators.

## Vollständige Ableitungskette

`pipeline_expected.json` wurde unabhängig mit der offiziellen C-Referenz für Skein v1.3 und Python `hashlib` für SHA3/SHAKE berechnet. Die Eingabe enthält 4096 Records zu je 89 Byte, Python-Format `<BQQdddddddQQ`. Für Index i: Version 1, Sequenz i, Uptime i+1, Zeit i/120, x=i%127, y=i%83, dx=1.2, dy=-0.8, Breite 800, Höhe 600, Modifier 0, Buttons 0. Nullbytes als Shufflequelle ergeben die Reihenfolge 1 bis 4095, danach 0. Poolgröße 364544 Byte; SHA256 `ea963f6f8c9a61cce3fe2988f576f5081f8bb1f4624dd85cd594e45257a98929`.

Der Masterkey entsteht aus Skein-1024-1024 || SHA3-512, XOR mit 192 Bytes 0xA5. Seine sechs 32-Byte-Fragmente initialisieren SHAKE256. 160 Bytes jeder SHAKE-Ausgabe werden per XOR kombiniert und mit 160 Bytes 0x5A verknüpft. Der Swift-Test liest 137 und anschließend 23 Bytes und prüft so auch Streamfortsetzung und erneute OS-Mischung.
