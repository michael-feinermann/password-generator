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

`pipeline_expected.json`, Version 4, wurde unabhängig mit der offiziellen C-Referenz für Skein v1.3, Python `hashlib` für SHA3/SHAKE/SHA-512 und der LibreSSL/OpenSSL-CLI für AES-256-CTR berechnet. Der reproduzierbare Generator `generate_pipeline_vectors.py` führt keinen Swift-Produktionscode aus. Er kompiliert die unveränderten, im Repository unter `Tests/Reference/Skein` enthaltenen Dateien `skein.c` und `skein_block.c` mit einem kleinen Ein-/Ausgabe-Harness. Ein abweichendes Referenzverzeichnis kann optional als Argument angegeben werden. Python 3, clang und eine `openssl`-CLI mit AES-256-CTR genügen zur Offline-Reproduktion:

```sh
python3 Tests/PasswordGeneratorCoreTests/Resources/generate_pipeline_vectors.py
```

Die Einträge enthalten Datensätze zu je 89 Byte, Python-Format `<BQQdddddddQQ`. Für Index i: Version 1, Sequenz i, Uptime i+1, Zeit i/120, x=i%127, y=i%83, dx=1.2, dy=-0.8, Breite 800, Höhe 600, Modifier 0, Buttons 0. Im Pool bleiben genau die letzten 4096 Datensätze. Seine Größe beträgt 364544 Byte.

Die Ableitung besteht aus:

1. Fisher-Yates über die Reihenfolge der Datensätze unmittelbar vor der Generierung.
2. `D = Skein-1024-1024(pool) || SHA3-512(pool) || SHA-512(pool)` mit 128 + 64 + 64 = 256 Byte. Die App verwendet CryptoKit für SHA-512, die unabhängige Referenz `hashlib.sha512`.
3. XOR von D mit einer ersten frischen 256-Byte-OS-Testmaske.
4. Fisher-Yates über alle 2048 Einzelbits dieses maskierten Digests. Bitindex 0 bezeichnet das niederwertigste Bit von Byte 0; die Schleife läuft von 2047 bis 1.
5. XOR des permutierten Ergebnisses mit einer zweiten, separat angeforderten frischen 256-Byte-OS-Testmaske zum Masterkey. Die erste Maske wird nicht wiederverwendet.
6. Fünf fortlaufende Streams aus aufeinanderfolgenden Mastersegmenten: Skein-1024-XOF aus Bytes 0 bis 127, SHAKE256 aus 128 bis 159, SHAKE256 aus 160 bis 191, AES-256-CTR aus 192 bis 223 und AES-256-CTR aus 224 bis 255.
7. XOR aller fünf Ausgaben und einer weiteren frischen OS-Testmaske. Beide AES-Ströme starten bei einem 128-Bit-Zähler mit Wert null und inkrementieren den gesamten Zähler big endian. Es wird kein zusätzlicher IV aus der OS-Quelle gelesen. Die Schlüssel werden bei jeder Generierung neu aus dem frisch maskierten Masterkey abgeleitet.

Die AES-Referenz verschlüsselt Nullbytes mit `openssl enc -aes-256-ctr -nosalt -nopad -K <öffentlicher Testkey> -iv 00000000000000000000000000000000`. Die damit erzeugte Ausgabe ist der CTR-Schlüsselstrom. Die App verwendet hingegen die AES-Blockprimitive von CommonCrypto mit expliziter Zählerverwaltung. NIST-KATs, Carry- und Überlaufprüfungen sowie Quellen stehen in `AES_CTR_VECTORS.md`.

Die Skein-XOF-Konfiguration verwendet `UINT64_MAX` als Ausgabelänge in Bit gemäß Skein v1.3, Abschnitt 4.12. Der Harness ruft `Skein1024_Init(UINT64_MAX)`, `Update` und `Final_Pad` auf. Erst nach dem vollständigen Absorbieren der Konfiguration und Nachricht setzt er das Kontextfeld `hashBitLen` auf die gewünschte Testausgabelänge, um die unveränderte offizielle Funktion `Skein1024_Output` zu begrenzen. Das verändert den bereits gebildeten Chaining-State nicht. Die zusätzliche Primitive-Provenienz steht in `SKEIN_XOF_VECTORS.md`.

Jeder Fisher-Yates-Lauf hat einen eigenen 4096-Byte-Puffer. Kandidaten sind Little-Endian-UInt32; der unvollständige letzte Modulo-Bucket wird verworfen. Nicht verbrauchte Pufferbytes werden nach dem jeweiligen Shuffle nicht weiterverwendet. Die JSON-Datei hält die genaue Folge der OS-Anforderungsgrößen vor dem ersten Output-Read fest.

Es gibt drei Szenarien:

* `zero_shuffle`: 4096 Datensätze, keine vorherigen Shuffles, Nullbytes für beide Shuffle-Arten, erste Maske 0x3C, zweite Maske 0xA5 und Ausgabemaske 0x5A. Die Datensatzreihenfolge ist 1 bis 4095, danach 0. Der Pool-SHA256 bleibt `ea963f6f8c9a61cce3fe2988f576f5081f8bb1f4624dd85cd594e45257a98929`. Der Bitshuffle entspricht einer Rotation der gesamten LSB-indizierten Bitfolge um eine Position.
* `patterned_shuffle`: 4096 Datensätze, variierte Shuffle-Kandidaten einschließlich absichtlich verworfener `0xffffffff`-Werte. Die ersten beiden UInt32 jedes Puffers sind `0xffffffff`, der dritte ist 0. Für die restlichen gilt mit Pufferindex b und Wortindex i: `((b * 1024 + i) * 0x9e3779b9 + 0x7f4a7c15) mod 2^32`. Byte i der ersten Maske ist `(19*i + 0x3C) mod 256`, Byte i der zweiten Maske ist `(37*i + 0xA5) mod 256`, Ausgabemaskenbyte i ist `(53*i + 0x5A) mod 256`.
* `wrapped_pool_with_intermediate_shuffles`: dieselbe variierte Testquelle, 8193 aufgenommene Datensätze sowie zusätzliche Pool-Shuffles nach 2048, 4096 und 6144 Aufnahmen. Damit wird insbesondere geprüft, dass die begrenzte Speicherung nach Shuffles weiterhin die ältesten Datensätze überschreibt.

Die deterministischen Quellen sind ausschließlich Testdaten, keine Ersatz-Zufallsquelle für die Anwendung. Jede Fixture enthält den ursprünglichen Digest, die erste Maske (`preShuffleMask`), den maskierten Digest (`maskedDigest`), das Bitshuffle-Ergebnis (`shuffledDigest`), die zweite Maske (`masterMask`), den Masterkey, 1024 Ausgabebytes sowie 15 unabhängig berechnete Generatorergebnisse. Diese decken alle fünf BIP39-Wortanzahlen, minimale und maximale EFF- (6/128), ASCII- (8/256) und PIN-Längen (3/512) sowie Hex mit 1, 3, 511 und 512 Zeichen ab.

Die Swift-Tests vergleichen die vollständige Ableitung und die Zwischenwerte. Unterschiedliche Aufteilungen der Reads bei 0/1/15/16/17, 127/128/129 und 135/136/137 Byte müssen bei identischem fortlaufendem OS-Maskenstrom dieselben Bytes liefern. Zusätzlich prüfen sie Identitäts-Swaps, Swaps innerhalb eines Bytes und über Bytegrenzen, die Erhaltung der Anzahl gesetzter Bits, Rejection Sampling und den Abbruch bei Fehlern in beiden Bitshuffle-Puffern sowie nach bereits erfolgreich gelesenen Ausgabebytes. Ein eigener Test prüft die genaue Aufrufreihenfolge: bei Null-Kandidaten zunächst vier 4096-Byte-Puffer für den Datensatzshuffle, dann die erste 256-Byte-Maske, zwei 4096-Byte-Puffer für den Bitshuffle, die zweite 256-Byte-Maske und erst beim Read die Ausgabemaske. Für beide 256-Byte-Masken werden sowohl geworfene Fehler als auch verkürzte Rückgaben geprüft; nach dem Fehler darf keine spätere RNG-Anforderung erfolgen.
