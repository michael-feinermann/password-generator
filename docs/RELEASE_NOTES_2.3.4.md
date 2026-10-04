# Password Generator 2.3.4

## English

Version 2.3.4, build 11, adds a Skein-1024-1024 digest to the BIP39 and EFF wordlist details. For each list, the interface now displays SHA256, SHA3-512, and then Skein-1024-1024.

Both wordlists are checked against all three embedded expected digests before use. The Skein values receive an independent cross-check through `Scripts/skein-reference-checksum.sh`, using the official C reference implementation in `Tests/Reference/Skein`.

Password generation, supported formats, export options, attack-cost models, layout, and runtime protections remain unchanged. The additional wordlist checksum does not add password entropy or alter Apple's Developer ID signing process.

All 103 tests passed in each of the Debug and Release builds, with compiler warnings treated as errors. The app is signed with Developer ID and notarized through Xcode. The final ZIP passes independent verification of all three checksums, code signature, sandbox, stapled ticket, and Gatekeeper. Detailed evidence appears in the [technical analysis](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

## Deutsch

Version 2.3.4, Build 11, ergänzt einen Skein-1024-1024-Digest in den Angaben zu den BIP39- und EFF-Wortlisten. Die Oberfläche zeigt für jede Liste jetzt SHA256, SHA3-512 und anschließend Skein-1024-1024 an.

Beide Wortlisten werden vor Verwendung gegen alle drei fest eingebauten Sollwerte geprüft. Die Skein-Werte werden über `Scripts/skein-reference-checksum.sh` unabhängig mit der offiziellen C-Referenzimplementierung unter `Tests/Reference/Skein` gegengeprüft.

Passwortgenerierung, unterstützte Formate, Exportoptionen, Angriffszeitmodelle, Layout und Laufzeitschutz bleiben unverändert. Die zusätzliche Wortlistenprüfsumme erhöht nicht die Passwortentropie und ändert Apples Developer-ID-Signaturverfahren nicht.

Alle 103 Tests je Debug- und Release-Build bestanden, mit Compilerwarnungen als Fehler. Die App ist mit Developer ID signiert und über Xcode notarisiert. Das finale ZIP besteht die unabhängige Prüfung aller drei Hashwerte sowie von Code-Signatur, Sandbox, angeheftetem Ticket und Gatekeeper. Die [technische Analyse](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation) dokumentiert die Nachweise.
