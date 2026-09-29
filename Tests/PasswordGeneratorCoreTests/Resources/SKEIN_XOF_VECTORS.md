# Skein-1024-XOF: Konvention und unabhängige Referenzwerte

## Festgelegte Konvention

Quelle: Skein v1.3, https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf

Abschnitt 4.12 beschreibt für vorab unbekannte Ausgabelängen die Alternative `N_o = 2^64 - 1`. Der Generator verwendet diese feste Konfiguration als fortlaufenden, byteorientierten XOF. Die Autoren empfehlen diese Alternative allgemein nicht, weil unterschiedliche angeforderte Ausgabelängen dasselbe Präfix erhalten und eine Implementierung für partielle Ausgabe benötigt wird. Die hier bewusst verwendete XOF-Schnittstelle besitzt genau diese Präfixeigenschaft. Das ist eine aus der Spezifikation abgeleitete API, keine eigenständige Standardisierung als XOF.

Die Eingabe ist eine ungeschlüsselte Nachricht, kein Skein-MAC-Schlüssel. Die 32 Byte lange Konfiguration nach Abschnitt 3.5.2 enthält `SHA3`, Version 1, acht `ff`-Bytes als Ausgabelänge und ausschließlich Nullbytes für Baumparameter und reservierte Felder. Nach Nachrichtenabschluss entsteht der Chainingwert `G`. Jeder 128 Byte lange Ausgabeblock ist gemäß Abschnitt 3.5.3 unabhängig `UBI(G, LE64(counter), type=63)`, beginnend bei Counter 0. Vor jedem Ausgabeblock wird derselbe Chainingwert verwendet. Der Ausgabeblock wird nicht als neuer Nachrichtenzustand verkettet.

Getrennte `read(count:)`-Aufrufe setzen die Ausgabe fort. Nullbytes als angeforderte Länge verändern die Position nicht. Die API gibt nur vollständige Bytes aus und ist auf `floor((2^64 - 1) / 8)` Bytes je Instanz begrenzt; die letzten sieben konfigurierten Bits werden nicht ausgegeben. `Skein.hash1024` verwendet weiterhin die separate Konfiguration `N_o = 1024`.

## Herkunft und Erzeugung

Die 22 Einträge in `skein1024_xof_vectors.json` wurden mit der unveränderten offiziellen C-Referenz von Doug Whiting erzeugt. Es wurde kein Swift-Code zur Erzeugung der Erwartungswerte verwendet.

Archiv: https://www.schneier.com/wp-content/uploads/2015/01/skein.zip

SHA-256 des Archivs: `121b73a4d5300b4977d3757064a29ba5e11c0fb01786171b2bc729ef099b89ad`

Verwendete Dateien: `NIST/CD/Reference_Implementation/skein.c`, `skein_block.c` und die zugehörigen Header. Die Referenz ist laut ihrem Dateikopf Public Domain. Kompiliert auf einem 64-Bit-System mit Apple clang, `-O2 -DSKEIN_ERR_CHECK=1`.

Der C-Aufrufablauf ist:

```c
Skein1024_Init(&ctx, (size_t)UINT64_MAX);
Skein1024_Update(&ctx, input, inputByteCount);
Skein1024_Final_Pad(&ctx, chainingBytes);
ctx.h.hashBitLen = requestedOutputBytes * 8;
Skein1024_Output(&ctx, output);
```

Die Zuweisung nach `Final_Pad` verändert keinen bereits absorbierten Konfigurationswert und keinen Chainingzustand. Sie begrenzt ausschließlich die Anzahl ausgegebener Bytes in der vorhandenen Referenzfunktion `Skein1024_Output`. Diese Funktion verwendet intern die originale OUT-Counter-Schleife und stellt vor jedem Block den gespeicherten Chainingwert wieder her. Ein unveränderter Aufruf von `Final` mit `UINT64_MAX` wäre für eine partielle Ausgabe ungeeignet.

## Abdeckung

18 Eingaben bestehen aus aufsteigenden Bytes modulo 256, mit Längen 0, 1, 31, 32, 63, 64, 127, 128, 129, 255, 256, 257, 1023, 1024, 1025, 4095, 4096 und 4097. Ihre Ausgabelänge beträgt jeweils 1025 Byte. Drei weitere Eingaben sind 128 Nullbytes, 128 Bytes `ff` und die Verkettung von `SHA256([0])`, `SHA256([1])`, `SHA256([2])`, `SHA256([3])`; auch diese erhalten jeweils 1025 Ausgabebytes.

Ein letzter Vektor verwendet die 128 Eingabebytes 0 bis 127 und 32769 Ausgabebytes. Er prüft die Ausgabe über Counter 255 hinaus bis zum ersten Byte von Counter 256. Die Swift-Tests vergleichen alle 22 Vektoren vollständig und mit getrennten Leseaufrufen. Weitere Vergleiche prüfen 22 verschiedene Ausgabelängen gegen Präfixe dieses letzten Referenzvektors, einschließlich Nullausgabe sowie Grenzen direkt vor, auf und nach 128-Byte-Blöcken. Die bisherigen 49 bekannten Skein-1024-1024-Erwartungswerte bleiben eine separate Regressionprüfung.

Die Tests sind Implementierungsprüfungen, keine Zertifizierung und kein externes Sicherheitsaudit.
