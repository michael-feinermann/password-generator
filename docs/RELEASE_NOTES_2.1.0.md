# Password Generator 2.1.0

## English

Updated package: build 4 includes the version number in the app name, window title, and filename. It is signed with Developer ID and was notarized by Apple through Xcode.

The password byte stream is now derived using Skein-1024-XOF and two SHAKE256 streams. The five output formats, their length ranges, and the export options remain available.

The visible app name is “Password Generator 2.1.0”. The app bundle is named `Password Generator 2.1.0.app` and is located at `build/Password Generator 2.1.0.app` after a local package build.

1. Before generation, the pool of 4,096 mouse events is shuffled again using Fisher-Yates.
2. Skein-1024-1024 and SHA3-512 produce a combined 192 bytes. Their 1,536 individual bits are additionally shuffled using Fisher-Yates and fresh macOS CSPRNG values.
3. XOR with another 192 CSPRNG bytes produces the master key. Its consecutive segments contain 128, 32, and 32 bytes.
4. The first segment initializes Skein-1024-XOF; each of the other two initializes SHAKE256. The three advancing outputs are combined using XOR.
5. Immediately before use, an equal number of fresh CSPRNG bytes is mixed in using XOR. Password sampling continues to use rejection sampling to avoid modulo bias.

The app's expandable section explains the complete derivation in English and German. Pool hashing and the additional bit shuffle occur only during generation; the periodic mouse-event pool shuffle continues to run every six seconds.

Skein-XOF uses the configuration for an unknown output length described in Skein v1.3, section 4.12 (`N_o = 2^64 − 1`). Independent reference calculations and specific verification results are documented in the technical analysis. These checks are neither an external security audit nor a formal proof that the implementation is free of defects.

For Apple Silicon running macOS 14 or later. Xcode submitted the app through “Direct Distribution”; Apple approved it for distribution on September 29, 2026. The ZIP contains the output of “Export Notarized App” with a stapled ticket. The code signature and ticket were also checked after extraction; Gatekeeper accepts the app as `Notarized Developer ID`. The sandbox and runtime protections remain enabled.

Downloads include the app ZIP, matching SHA256 and SHA3-512 checksum files, and the integrity manifest.

Verified: 71 passing tests in each of the Debug and Release builds, including three complete derivation references, 45 independently calculated password cases, and reference vectors for the hash/XOF functions used. The code signature and both ZIP checksums were verified against the finished package.

## Deutsch

Aktualisiertes Paket: Build 4 mit Versionsnummer im Appnamen, Fenstertitel und Dateinamen, mit Developer ID signiert und über Xcode von Apple notarisiert.

Die Ableitung des Passwort-Bytestroms verwendet jetzt Skein-1024-XOF und zwei SHAKE256-Streams. Die fünf Ausgabeformate, ihre Längenbereiche und die Exportoptionen bleiben erhalten.

Der sichtbare Appname lautet „Password Generator 2.1.0“. Das App-Bundle heißt `Password Generator 2.1.0.app` und liegt nach dem lokalen Paket-Build unter `build/Password Generator 2.1.0.app`.

1. Vor der Generierung wird der Pool aus 4.096 Mausereignissen erneut mit Fisher-Yates gemischt.
2. Skein-1024-1024 und SHA3-512 liefern zusammen 192 Byte. Ihre 1.536 einzelnen Bits werden zusätzlich mit Fisher-Yates und frischen macOS-CSPRNG-Werten gemischt.
3. XOR mit 192 weiteren CSPRNG-Bytes ergibt den Masterkey. Seine aufeinanderfolgenden Segmente sind 128, 32 und 32 Byte lang.
4. Das erste Segment initialisiert Skein-1024-XOF, die beiden übrigen jeweils SHAKE256. Die drei fortlaufenden Ausgaben werden XOR-verknüpft.
5. Unmittelbar vor der Verwendung werden nochmals gleich viele frische CSPRNG-Bytes per XOR eingemischt. Die Passwortauswahl verwendet weiterhin Rejection Sampling gegen Modulo-Verzerrungen.

Der ausklappbare Bereich der App erklärt die vollständige Ableitung auf Deutsch und Englisch. Die Hashberechnung und die zusätzliche Bitmischung erfolgen nur bei der Generierung; der periodische Shuffle des Mausereignispools läuft weiterhin alle sechs Sekunden.

Skein-XOF verwendet die in Skein v1.3 Abschnitt 4.12 beschriebene Konfiguration für unbekannte Ausgabelänge (`N_o = 2^64 − 1`). Unabhängige Referenzberechnungen und die konkreten Prüfergebnisse sind in der technischen Analyse dokumentiert. Die Prüfungen sind kein externer Sicherheitsaudit oder formaler Fehlerfreiheitsnachweis.

Für Apple Silicon ab macOS 14. Xcode hat die App über „Direct Distribution“ eingereicht; Apple hat sie am 29. September 2026 zur Verteilung freigegeben. Das ZIP enthält den Export von „Export Notarized App“ mit angeheftetem Ticket. Code-Signatur und Ticket wurden auch nach dem Entpacken geprüft; Gatekeeper akzeptiert die App als `Notarized Developer ID`. Die Sandbox und Laufzeitschutzmaßnahmen bleiben aktiviert.

Zum Download gehören das App-ZIP, passende SHA256- und SHA3-512-Prüfsummendateien sowie das Integritätsmanifest.

Verifiziert: jeweils 71 bestandene Tests im Debug- und Release-Build, darunter drei vollständige Ableitungsreferenzen, 45 unabhängig berechnete Passwortfälle und Referenzvektoren der verwendeten Hash-/XOF-Funktionen. Die Code-Signatur und beide ZIP-Prüfsummen wurden am fertigen Paket geprüft.
