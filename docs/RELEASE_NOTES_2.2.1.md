# Password Generator 2.2.1

## English

Version 2.2.1, build 6, adds a fresh macOS random contribution before the bit shuffle in the password derivation. The visible app name is “Password Generator 2.2.1”; a local package build creates `build/Password Generator 2.2.1.app`.

Signing and notarization status: Developer ID signed, notarized through Xcode on 3 October 2026, with a stapled ticket; Gatekeeper accepted the final app.

### Updated derivation

After the generation-time shuffle of the 4,096 mouse records, the three pool hashes are concatenated in their existing order: Skein-1024-1024 (128 bytes), SHA3-512 (64 bytes), and SHA-512 (64 bytes). The resulting 256 bytes now pass through these steps:

1. XOR the 256 hash bytes with a freshly requested set of 256 cryptographic macOS random bytes.
2. Use Fisher-Yates to shuffle all 2,048 individual bits of that XOR result, with separately requested cryptographic macOS random bytes.
3. XOR the shuffled value with a second, separately requested set of 256 fresh macOS random bytes to produce the 256-byte master key. The first XOR mask is not reused.

The subsequent derivation keeps the consecutive 128/32/32/32/32-byte split: one Skein-1024-XOF stream, two SHAKE256 streams, and two AES-256-CTR streams with separate keys. Each AES stream starts with its own 128-bit big-endian counter at zero; counters and unused block bytes continue across reads. Equal-length outputs of all five streams are combined using XOR and then XORed with an equal number of freshly requested macOS random bytes immediately before sampling. Additional requests continue the streams without restarting them or reusing consumed prefixes.

Pool hashing, both 256-byte XOR steps, and the bit shuffle occur only during generation. The mouse pool continues to shuffle every six seconds from app startup and again immediately before generation. The expandable explanation in the app now describes the order “first XOR, bit shuffle, second XOR” in English and German.

### Formats and protection

The supported ranges remain BIP39 with 12, 15, 18, 21, or 24 words; EFF with 6 to 128 words; ASCII with 8 to 256 characters from the 94 printable characters without spaces; PIN with 3 to 512 digits; and Hex with 1 to 512 characters. BIP39 defaults to a space separator and EFF to `-`; both allow freely chosen separators, including an empty value. Hex supports lowercase and uppercase output. Export formatting can be changed after generation without selecting a new secret.

The entropy display still describes the original selection space, not measured mouse entropy or the overall construction's security strength. Hash lengths and individual stream security strengths cannot be added together. The extra XOR step does not establish a quantified security gain. This is a custom construction, not a standardized or externally audited random number generator. AES-CTR is an additional application-level stream and does not describe the internal implementation of Apple's random source. Existing runtime, concealment, clipboard, and best-effort buffer-wiping protections remain in place, with the same limitations on screen capture, compromised systems, and complete memory erasure.

### Release verification

Test results for version 2.2.1: 82 tests passed in each of the Debug and Release builds, with no compiler warnings. Test results and Apple approval for previous releases do not establish the verification status of this version. The [technical analysis (German)](https://github.com/michael-feinermann/password-generator/blob/main/docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) records the verification scope and release evidence.

The release targets Apple Silicon on macOS 14 or later. Packaging creates `Password.Generator-2.2.1.zip`, three checksum files covering that final ZIP with SHA256, SHA3-512, and Skein-1024-1024, and an integrity manifest. `Scripts/verify-release.sh` checks both SHA values independently with Python and Skein with the official C reference implementation. These external checksums do not modify the app bundle or ZIP, replace Apple's Developer ID signing process, or prove provenance by themselves.

## Deutsch

Version 2.2.1, Build 6, ergänzt die Passwortableitung um einen frischen macOS-Zufallsbeitrag vor der Bitmischung. Der sichtbare Appname lautet „Password Generator 2.2.1“; ein lokaler Paket-Build erzeugt `build/Password Generator 2.2.1.app`.

Signatur- und Notarisierungsstatus: mit Developer ID signiert, am 3. Oktober 2026 über Xcode notarisiert, Ticket angeheftet; Gatekeeper akzeptiert die finale App.

### Aktualisierte Ableitung

Nach dem Shuffle der 4.096 Mausereignisse bei der Generierung werden die drei Poolhashes in der bisherigen Reihenfolge verbunden: Skein-1024-1024 (128 Byte), SHA3-512 (64 Byte) und SHA-512 (64 Byte). Die daraus entstehenden 256 Byte durchlaufen jetzt diese Schritte:

1. Die 256 Hashbytes mit frisch angeforderten 256 kryptografischen macOS-Zufallsbytes XOR-verknüpfen.
2. Alle 2.048 einzelnen Bits dieses XOR-Ergebnisses mit Fisher-Yates und separat angeforderten kryptografischen macOS-Zufallsbytes mischen.
3. Den gemischten Wert mit einem zweiten, separat angeforderten Satz von 256 frischen macOS-Zufallsbytes XOR-verknüpfen. Das Ergebnis ist der 256-Byte-Masterkey. Die erste XOR-Maske wird nicht wiederverwendet.

Die anschließende Ableitung behält die aufeinanderfolgende Aufteilung in 128/32/32/32/32 Byte: ein Skein-1024-XOF-Stream, zwei SHAKE256-Streams und zwei AES-256-CTR-Streams mit separaten Schlüsseln. Jeder AES-Stream beginnt mit einem eigenen 128-Bit-Zähler in Big-Endian-Reihenfolge bei null; Zähler und nicht verbrauchte Blockbytes bleiben über Leseaufrufe hinweg erhalten. Gleich lange Ausgaben aller fünf Streams werden XOR-verknüpft und unmittelbar vor der Auswahl nochmals mit gleich vielen frisch angeforderten macOS-Zufallsbytes XOR-verknüpft. Nachforderungen setzen die Streams fort, ohne sie neu zu starten oder bereits verbrauchte Präfixe erneut zu verwenden.

Poolhashes, beide XOR-Schritte mit je 256 Byte und die Bitmischung erfolgen ausschließlich bei der Generierung. Der Mauspool wird weiterhin ab dem Appstart alle sechs Sekunden und zusätzlich unmittelbar vor der Generierung gemischt. Die ausklappbare Erklärung in der App beschreibt jetzt auf Deutsch und Englisch die Reihenfolge „erstes XOR, Bitmischung, zweites XOR“.

### Formate und Schutz

Die unterstützten Bereiche bleiben BIP39 mit 12, 15, 18, 21 oder 24 Wörtern; EFF mit 6 bis 128 Wörtern; ASCII mit 8 bis 256 Zeichen aus den 94 druckbaren Zeichen ohne Leerzeichen; PIN mit 3 bis 512 Ziffern und Hex mit 1 bis 512 Zeichen. Standardtrennzeichen ist bei BIP39 ein Leerzeichen und bei EFF `-`; beide erlauben frei gewählte und leere Trenner. Hex unterstützt kleine und große Buchstaben. Die Exportformatierung lässt sich nach der Generierung ändern, ohne ein neues Geheimnis auszuwählen.

Die Entropieanzeige beschreibt weiterhin den ursprünglichen Auswahlraum, nicht gemessene Mausentropie oder die Sicherheitsstärke der Gesamtkonstruktion. Hashlängen und Sicherheitsstärken einzelner Streams lassen sich nicht addieren. Der zusätzliche XOR-Schritt belegt keinen bezifferten Sicherheitsgewinn. Es handelt sich um eine individuelle Konstruktion, nicht um eine standardisierte oder extern auditierte Zufallszahlenerzeugung. AES-CTR ist ein zusätzlicher Stream innerhalb der Anwendung und beschreibt nicht die interne Implementierung von Apples Zufallsquelle. Die bisherigen Schutzmaßnahmen für Laufzeit, Verdeckung, Zwischenablage und bestmögliches Überschreiben von Puffern bleiben erhalten, mit denselben Grenzen bei Bildschirmaufnahmen, kompromittierten Systemen und vollständiger Speicherlöschung.

### Release-Verifikation

Testergebnisse für Version 2.2.1: Jeweils 82 Tests in Debug und Release bestanden, ohne Compilerwarnungen. Testergebnisse und Apple-Freigaben früherer Releases belegen nicht den Prüfstatus dieser Version. Die [technische Analyse](https://github.com/michael-feinermann/password-generator/blob/main/docs/CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) dokumentiert den Prüfumfang und die Release-Nachweise.

Das Release ist für Apple Silicon ab macOS 14 vorgesehen. Das Paket enthält `Password.Generator-2.2.1.zip`, drei Prüfsummendateien über dieses finale ZIP für SHA256, SHA3-512 und Skein-1024-1024 sowie ein Integritätsmanifest. `Scripts/verify-release.sh` prüft beide SHA-Werte unabhängig mit Python und Skein mit der offiziellen C-Referenzimplementierung. Diese externen Prüfsummen verändern weder das App-Bundle noch das ZIP, ersetzen nicht Apples Developer-ID-Signaturverfahren und beweisen für sich allein keine Herkunft.
