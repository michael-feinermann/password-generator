# AES-256-CTR: Konvention und unabhängige Testvektoren

## Primitive und Konvention

Die App verwendet CommonCrypto ausschließlich für die Verschlüsselung einzelner AES-Blöcke: `CCCryptorCreate(kCCEncrypt, kCCAlgorithmAES, kCCOptionECBMode, key, 32, nil, ...)`, gefolgt von `CCCryptorUpdate` mit genau 16 Eingabebytes. Padding ist ausgeschaltet. `CCCryptorRelease` gibt den Kontext bei Clear oder Deinitialisierung frei. Eigene Zähler- und Pufferbytes werden nach Möglichkeit mit `memset_s` überschrieben; das ist keine Garantie über sämtliche Compiler- oder Betriebssystemkopien.

Apple-Dokumentation: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/CCCryptorCreate.3cc.html

Der AES-Schlüsselstrom ist `AES_K(counter)`. Der gesamte 128-Bit-Zähler wird nach jedem Block big endian inkrementiert, einschließlich Übertrag aus den unteren 64 Bit. Der letzte Zählerwert `ff...ff` darf einmal verwendet werden. Seine restlichen gepufferten Bytes bleiben lesbar; ein weiterer Block löst einen Fehler aus und verwirft den Stream. Ein fehlschlagender Read gibt keine Teilausgabe zurück. Leere Reads verändern die Position nicht.

Beide AES-Ströme der Passwortableitung starten mit Zähler null. Sie verwenden zwei verschiedene aufeinanderfolgende 32-Byte-Segmente des bei jeder Generierung frisch gebildeten Masterkeys. Derselbe Schlüssel darf nicht erneut für einen neuen Stream mit gleichem Startzähler verwendet werden, weil dadurch derselbe Schlüsselstrom entstünde. Die Konstruktion ist Teil der bestehenden Ableitung und kein Verschlüsselungsformat mit Authentifizierung.

## Quellen und Erzeugung

NIST SP 800-38A, Abschnitt 6.5, Anhang B und F.5.5/F.5.6:
https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38a.pdf

`aes256ctr_vectors.json` enthält fünf Vektoren:

1. Den vollständigen AES-256-CTR-Vektor F.5.5 mit vier Klartext-/Ciphertextblöcken. Die Tests vergleichen `plaintext XOR stream` direkt mit dem veröffentlichten Ciphertext.
2. Nullschlüssel, Nullzähler, 257 Ausgabebytes.
3. Aufsteigende Schlüsselbytes 0 bis 31, Nullzähler, 4097 Ausgabebytes.
4. Derselbe aufsteigende Schlüssel, Startzähler `0000000000000000ffffffffffffffff`, 33 Ausgabebytes. Dieser Fall prüft den Übertrag über die Grenze zwischen den beiden 64-Bit-Hälften.
5. Derselbe Schlüssel, Startzähler `fffffffffffffffffffffffffffffffe`, 32 Ausgabebytes, also die letzten zwei erlaubten Zählerblöcke.

Die zusätzlichen vier Vektoren wurden mit `/usr/bin/openssl` (LibreSSL 3.3.6) aus Null-Klartext erzeugt. Das ist eine von CommonCrypto getrennte AES-Implementierung. Der Generator prüft außerdem, dass diese Referenz den vollständigen NIST-Vektor reproduziert. Alle Schlüssel und Eingaben sind öffentliche Testdaten.

Offline-Reproduktion, benötigt Python 3 und eine `openssl`-CLI mit AES-256-CTR:

```sh
python3 Tests/PasswordGeneratorCoreTests/Resources/generate_aes_ctr_vectors.py
```

Die CLI verwendet `enc -aes-256-ctr -nosalt -nopad -K <Testkey> -iv <Startzähler>` ohne Passwortableitung. Quellen zur CLI: https://docs.openssl.org/3.0/man1/openssl-enc/

Die Swift-Tests vergleichen vollständige Ausgaben, byteweise Reads und geteilte Reads bei 0, 1, 15, 16, 17, 127, 128, 129, 135, 136, 137, 255, 256 und 257 Byte, soweit die Fixture lang genug ist. Weitere Fälle prüfen unzulässige Schlüssel-/Zählerlängen, negative und zu große Ausgabelängen, Clear, die letzte gepufferte Blockhälfte und einen fehlgeschlagenen Read über das Zählerende hinaus. Diese Tests sind keine CAVP-Zertifizierung oder externe Sicherheitsprüfung.
