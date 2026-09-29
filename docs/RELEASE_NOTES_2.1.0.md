# Password Generator 2.1.0

Aktualisiertes Paket: Build 4 mit Versionsnummer im Appnamen, Fenstertitel und Dateinamen, erneut mit Developer ID signiert.

Die Ableitung des Passwort-Bytestroms verwendet jetzt Skein-1024-XOF und zwei SHAKE256-Streams. Die fünf Ausgabeformate, ihre Längenbereiche und die Exportoptionen bleiben erhalten.

Der sichtbare Appname lautet „Password Generator 2.1.0“. Das App-Bundle heißt `Password Generator 2.1.0.app` und liegt nach dem lokalen Paket-Build unter `build/Password Generator 2.1.0.app`.

1. Vor der Generierung wird der Pool aus 4.096 Mausereignissen erneut mit Fisher-Yates gemischt.
2. Skein-1024-1024 und SHA3-512 liefern zusammen 192 Byte. Ihre 1.536 einzelnen Bits werden zusätzlich mit Fisher-Yates und frischen macOS-CSPRNG-Werten gemischt.
3. XOR mit 192 weiteren CSPRNG-Bytes ergibt den Masterkey. Seine aufeinanderfolgenden Segmente sind 128, 32 und 32 Byte lang.
4. Das erste Segment initialisiert Skein-1024-XOF, die beiden übrigen jeweils SHAKE256. Die drei fortlaufenden Ausgaben werden XOR-verknüpft.
5. Unmittelbar vor der Verwendung werden nochmals gleich viele frische CSPRNG-Bytes per XOR eingemischt. Die Passwortauswahl verwendet weiterhin Rejection Sampling gegen Modulo-Verzerrungen.

Der ausklappbare Bereich der App erklärt die vollständige Ableitung auf Deutsch und Englisch. Die Hashberechnung und die zusätzliche Bitmischung erfolgen nur bei der Generierung; der periodische Shuffle des Mausereignispools läuft weiterhin alle sechs Sekunden.

Skein-XOF verwendet die in Skein v1.3 Abschnitt 4.12 beschriebene Konfiguration für unbekannte Ausgabelänge (`N_o = 2^64 − 1`). Unabhängige Referenzberechnungen und die konkreten Prüfergebnisse sind in der technischen Analyse dokumentiert. Die Prüfungen sind kein externer Sicherheitsaudit oder formaler Fehlerfreiheitsnachweis.

Für Apple Silicon ab macOS 14. Das ZIP enthält die mit Developer ID signierte App, ist jedoch nicht notarisiert, da das vorhandene Apple-Notarisierungsprofil nicht akzeptiert wird. macOS kann deshalb die Ausführung nach einem Download blockieren. Die Sandbox und Laufzeitschutzmaßnahmen bleiben aktiviert.

Zum Download gehören das App-ZIP, passende SHA256- und SHA3-512-Prüfsummendateien sowie das Integritätsmanifest.

Verifiziert: jeweils 71 bestandene Tests im Debug- und Release-Build, darunter drei vollständige Ableitungsreferenzen, 45 unabhängig berechnete Passwortfälle und Referenzvektoren der verwendeten Hash-/XOF-Funktionen. Die Code-Signatur und beide ZIP-Prüfsummen wurden am fertigen Paket geprüft.
