# Technische Analyse von Password Generator 2.1.0

Stand: 29. September 2026. Diese Datei beschreibt die implementierte und getestete Ableitung für Version 2.1.0. Die unten aufgeführten Prüfergebnisse und Release-Hashes beziehen sich auf diesen Stand.

## Datenfluss

Der Pool fasst 4.096 Mausbewegungen mit je 89 serialisierten Byte, insgesamt 364.544 Byte Nutzdaten bei voller Belegung. Ein Datensatz beginnt mit dem Versionsbyte 1. Es folgen elf 64-Bit-Werte in Little-Endian-Reihenfolge: Ereignisnummer, monotone Nanosekunden, Bitmuster der Ereigniszeit, x, y, deltaX, deltaY, Fensterbreite, Fensterhöhe, Modifikatormaske und gedrückte Maustasten. Fließkommazahlen werden über ihr IEEE-754-Bitmuster codiert.

Ein Ringpuffer ersetzt die ältesten Datensätze. Eine getrennte Indexpermutation legt ihre Reihenfolge für das Hashen fest. Dadurch mischt Fisher-Yates die vollständigen Ereignisse; Zeitstempel und Koordinaten innerhalb eines Ereignisses bleiben zusammen. Die Auswahl des nächsten zu ersetzenden Ereignisses bleibt auch nach dem Shuffle chronologisch.

Bei jedem Shuffle läuft der Index von `n - 1` bis `1`. Der Tauschindex liegt gleichverteilt in `0...index`, einschließlich der aktuellen Position. 32-Bit-Werte werden aus gepufferten macOS-Zufallsbytes gelesen. Werte außerhalb des größten durch die jeweilige Bereichsgröße teilbaren Präfixes von `0...2³²-1` werden verworfen. Damit ist die Auswahl unverzerrt. Wiederholt unbrauchbare Bytes führen zum Fehler, statt die App endlos zu blockieren.

Die Hashberechnung und die folgende Ableitung finden ausschließlich beim Generieren statt:

```text
shuffle(records)                               // Fisher-Yates mit macOS-CSPRNG
P = serialize(records in shuffled order)
D = Skein-1024-1024(P) || SHA3-512(P)              // 128 + 64 = 192 Byte
B = fisher_yates_shuffle_all_bits(D)            // alle 1536 Bitpositionen
M = B XOR fresh_macOS_random(192)               // 192-Byte-Masterkey
S0 = Skein1024XOF(M[0..<128])                    // erstes Fragment: 128 Byte
S1 = SHAKE256(M[128..<160])                      // zweites Fragment: 32 Byte
S2 = SHAKE256(M[160..<192])                      // drittes Fragment: 32 Byte
X = read(S0, n) XOR read(S1, n) XOR read(S2, n)
output_bytes = X XOR fresh_macOS_random(n)
```

Der zweite Fisher-Yates-Durchlauf permutiert sämtliche einzelnen Bits des zusammengesetzten Hashwerts. Er ist vom Shuffle der Mausdatensätze getrennt und findet nach beiden Poolhashes, aber vor dem Masterkey-XOR statt. Seine Tauschindizes stammen ebenfalls aus kryptografischen macOS-Zufallsbytes. Es werden weder nur ganze Bytes vertauscht noch die Hashwerte jeweils getrennt gemischt. Nach der Bitpermutation umfasst der Wert weiterhin 192 Byte. Für das anschließende XOR werden weitere 192 frische OS-Bytes angefordert.

Die Skein-1024-XOF-Konvention folgt Skein v1.3, Abschnitt 4.12: Das Ausgabelängenfeld `N_o` der Konfiguration ist `2^64 - 1`, also acht Byte `FF`. Das erste 128-Byte-Masterkey-Fragment wird als Nachricht ohne separaten Skein-Schlüsselparameter absorbiert. Die Ausgabe entsteht gemäß Abschnitt 3.5.3 über fortlaufende UBI-Ausgabeblöcke vom Typ 63. Jeder Block verwendet einen fortlaufenden, als Little-Endian-64-Bit-Wert codierten Zähler. Diese XOF-Konfiguration ist vom zuvor verwendeten Poolhash Skein-1024-1024 mit fester Ausgabelänge getrennt.

Die drei XOF-Zustände werden pro Generierung genau einmal mit ihren jeweiligen Masterkey-Fragmenten initialisiert und fortlaufend gelesen. Die Skein-1024-XOF-Ausgabe verwendet das erste 128-Byte-Fragment; die beiden SHAKE256-Ausgaben verwenden die folgenden 32-Byte-Fragmente. Die gleich langen Ausgaben werden byteweise XOR-verknüpft. Auch bei verworfenen Auswahlwerten wird kein bereits verwendetes Stream-Präfix erneut ausgegeben. Jeder Nachladevorgang fordert zusätzlich einen frischen, gleich langen OS-Beitrag für das letzte XOR an.

Hashes der Ressourcen zur Integritätskontrolle sind von dieser Ableitung getrennt und werden beim Laden geprüft. Der Sechs-Sekunden-Task mischt ausschließlich den Mauspool. Er berechnet keine Poolhashes, permutiert keine Digest-Bits und erzeugt keinen Masterkey.

## Aussage der Entropieanzeige

Für EFF, ASCII, PIN und Hex berechnet die App `H = Länge × log₂(Alphabetgröße)` mit 7.776, 94, 10 beziehungsweise 16 Auswahlmöglichkeiten. Hex hat somit nominell vier Bit pro Zeichen, bei 448 Zeichen maximal 1.792 Bit im Auswahlraum. BIP39 verwendet `ENT`, ohne die abgeleiteten Prüfsummenbits mitzuzählen. Die Anzeige ist die nominelle Entropie unter der Annahme gleichverteilter, unabhängiger Auswahl.

Es werden keine Entropiebits für einzelne Mausbewegungen gutgeschrieben. 4.096 Ereignisse sind eine Bedienanforderung, kein kryptografischer Entropienachweis. Das Aneinanderhängen zweier Hashwerte über dieselben Daten vermehrt die enthaltene Entropie nicht automatisch. Die Bitpermutation erhält das Hamming-Gewicht, also die Anzahl der gesetzten Bits; aus ihr folgt kein bestimmter Entropiezuwachs. Auch die XOR-Verknüpfung eines Skein-1024-XOF-Streams mit zwei SHAKE256-Streams beweist keine 1.536-Bit-Sicherheitsstärke. Die Sicherheitsstärken der beteiligten Funktionen dürfen nicht einfach addiert werden. Das OS-XOR stützt die Ausgabe auf frische kryptografische Systemzufallsbytes; die Eigenschaft hängt von deren Unvorhersagbarkeit auch unter Kenntnis des anderen Operanden ab.

## Exportformatierung

Die kanonischen Komponenten bleiben unabhängig von der Exportdarstellung erhalten. EFF und BIP39 werden beim Kopieren mit dem eingegebenen Trenner verbunden; Standard ist bei BIP39 ein Leerzeichen und bei EFF `-`; leer ist zulässig. Hex wird intern in Kleinbuchstaben erzeugt und wahlweise in Großbuchstaben exportiert. Das Formatieren liest keine Zufallsbytes und ändert weder die Komponenten noch ihre nominelle Auswahlentropie.

BIP39 ohne Trenner ist keine eindeutige Codierung: `leg alarm` und `legal arm`, jeweils gefolgt von neunmal `abandon` und `accuse`, sind zwei verschiedene prüfsummengültige 12-Wort-Mnemonics mit identischem zusammengefügtem Export. Daher bezeichnet die Entropieanzeige die ursprüngliche Wortauswahl, nicht eine garantierte Entropie der trennzeichenlosen Darstellung. Für den standardüblichen BIP39-Import sind Leerzeichen zu verwenden.

## Fehlermodell und Grenzen

Fehler oder falsche Ausgabelängen der OS-Quelle brechen die betroffene Generierung ab. Nach einem Fehler beim Lesen eines abgeleiteten Streams wird dieser verworfen und kann nicht wiederverwendet werden. Das Poolminimum wird vor jeder Ableitung geprüft. Manipulierte Wortlisten werden vor der Nutzung abgewiesen.

Die App hält die bisherigen Schutzmaßnahmen bei: minimale Sandbox ohne Netzwerkberechtigung, Hardened Runtime, erneute Signatur-/Debuggerprüfung vor sensitiven Aktionen, deaktivierte POSIX-Core-Dumps, verdeckte Ausgabe, Kontextverdeckung und zeitlich begrenzte Zwischenablage. Sie ersetzt keine unabhängige Prüfung des Betriebssystems. Die Spezialkonstruktion ist weder ein externes Audit noch ein standardisiertes DRBG-Verfahren. Swift-Kopien und Betriebssystempuffer verhindern garantierte vollständige Löschung. Die Implementierung ist nicht formal als konstantzeitlich oder seitenkanalresistent geprüft.

Ein periodischer Task mischt ab Appstart etwa alle sechs Sekunden, auch nach abgeschlossener Generierung. Er läuft unabhängig vom Erreichen des Mausminimums. Schlaf oder Suspendierung können den Termin verschieben. Beim Beenden wird der Task abgebrochen. Die unmittelbare Durchmischung vor jeder Generierung ist davon unabhängig.

## Verifikation

Am 29. September 2026 bestanden jeweils alle 71 XCTest-Tests im Debug- und im optimierten Release-Build: 53 Core-Tests und 18 App-Modelltests, ohne Fehler oder Compilerwarnungen. Verwendet wurden `swift test -Xswiftc -warnings-as-errors` und `swift test -c release -Xswiftc -warnings-as-errors`.

Die vollständige Ableitung stimmt in drei Szenarien mit unabhängig erzeugten Referenzwerten überein: Nullwerte für die Shuffle-Kandidaten, variierte Werte einschließlich gezielter Rejections und ein mehrfach überschreibender Ringpuffer mit zwischenzeitlichen Shuffles. Erwartungswerte stammen aus der offiziellen Skein-C-Referenz und Python `hashlib`, nicht aus dem Swift-Produktionscode. Der reproduzierbare Generator und Zwischenwerte stehen unter `Tests/PasswordGeneratorCoreTests/Resources/`; die Provenienz beschreibt `CRYPTO_VECTORS.md`.

Gezielte Tests prüfen die Permutation aller 1.536 Bits, Identitätstausche, Swaps innerhalb eines Bytes und über Bytegrenzen, die Erhaltung der gesetzten Bits, die unverzerrte Indexauswahl und den Fehlerabbruch in beiden Bitshuffle-Puffern. Getrennte Reads vor, auf und nach 128- und 136-Byte-Grenzen ergeben bei identischem fortlaufendem OS-Maskenstrom dieselbe Ausgabe. Ein OS-Fehler nach erfolgreicher Teilausgabe macht den gesamten Passwortstream unbrauchbar.

Die Primitivprüfungen umfassen 49 Skein-1024-1024-, 81 SHA3-512- und 538 SHAKE256-Referenzvektoren sowie 22 neue Skein-1024-XOF-Vektoren. Zusätzlich werden segmentierte Ausgaben und XOF-Präfixe verglichen, bei Skein bis zum Übergang des Ausgabeblockzählers von 255 auf 256. Die XOF-Konvention und die unabhängige Erzeugung beschreibt `SKEIN_XOF_VECTORS.md`.

45 unabhängig berechnete Passwortfälle prüfen die Kombination aus neuer Streamableitung und Zeichenauswahl für alle fünf Formate, sämtliche BIP39-Wortanzahlen und relevante Randlängen. Weitere Tests zählen die akzeptierten Auswahlwerte im vollständigen Ein- und Zwei-Byte-Eingaberaum, prüfen ungültige Längen, führende Nullen, freie Trennzeichen, Hex-Schreibweise, Poolgrenzen, Timer, Runtime-Prüfungen und Verdeckung. Die bereits vom Nutzer geprüfte Oberfläche wurde für diese Änderung nicht erneut per GUI-Automation getestet.

Das endgültige `arm64`-Bundle für macOS 14 wurde mit Developer ID signiert und über Xcode 27 „Direct Distribution“ bei Apple notarisiert. Die strenge Signaturprüfung und die Prüfung der minimalen Sandbox bestanden auch nach dem Entpacken des Release-ZIPs. SHA256 und SHA3-512 des gesamten ZIPs wurden unabhängig mit Swift und Python gegengeprüft. Zusätzlich wurde Skein-1024-1024 mit der Swift-Implementierung und der unveränderten offiziellen C-Referenz unabhängig berechnet; beide Werte stimmen überein. `xcrun stapler validate` bestätigt das angeheftete Ticket; `spctl --assess --type execute --verbose=2` meldet `accepted`, `source=Notarized Developer ID`. Diese internen Prüfungen und die Apple-Notarisierung sind kein externes kryptografisches Sicherheitsaudit und kein formaler Beweis vollständiger Fehlerfreiheit.

Build 4 ergänzt die Versionsnummer im sichtbaren Appnamen, Fenstertitel, Menü und Bundle-Dateinamen (`Password Generator 2.1.0.app`). Die kryptografische Ableitung bleibt gegenüber dem mit 71 Tests je Konfiguration geprüften Stand unverändert. Für Build 4 wurden der Release-Build, die Developer-ID-Signatur, die ZIP-Prüfsummen und der sichtbare Versionsname in der geöffneten App erneut geprüft. Die folgenden Hashwerte beziehen sich auf Build 4.

Notarisierung: Einreichung am 29. September 2026 um 09:54 Uhr MESZ; Freigabe um 09:57 Uhr. Xcode zeigt „Ready to distribute“. Submission-ID: `398D2CB0-5B59-4D75-AACA-3E92BCF0ED80`. Veröffentlicht wird der geprüfte Xcode-Export mit angeheftetem Ticket, ohne anschließenden Neubuild oder erneute Signierung. Der CodeDirectory-Hash dieses Exports lautet `29f8530e98bb506ced4c6eb034b05f41753217fe`.

Der Programmcode wurde vor und nach dem Xcode-Export verglichen: Nach Signaturentfernung ausschließlich auf temporären Dateikopien sind die Mach-O-Dateien byteidentisch (1.323.744 Byte, SHA256 `4c1fc4b2d804535f615d2a62873ed8f49c2660e026c2ed91b631f6d1dc93ece5`). Info.plist, sämtliche Ressourcen und Sandbox-Entitlements sind ebenfalls unverändert. Unterschiede beschränken sich auf die Signatur und das angeheftete Ticket; die geprüften Originaldateien wurden dabei nicht verändert.

SHA256 des App-ZIPs `Password.Generator-2.1.0.zip`:
`cf893f58927495d75cb2c3ad4d7d4c0720ac1c6ba39a1787a91ba43876c6fb04`

SHA3-512 desselben App-ZIPs:
`b30394f6efcc649714f46f9fac608d7e1c0c0fd1c4b2f73e7480af32dc52d0010d40556f4d0f536e3cd03bfd567f246942abbba4adcc03b695de9df153d204c4`

Skein-1024-1024 desselben App-ZIPs (128 Byte, 256 Hexadezimalzeichen):
`a1c100eef289383b3a383138942b94aec35958c1eb3aaecf433f5eb77a0e941166d8ea9d185a7ea392e86e4e551e719515d6536bf48dcc1817e8a33130f17745cea1d0c04ba0e79820e709e27e461715668e15a7b553ea5a1131250d4b00659d5024b7ff0a6c1fb6bcd225d98cfc1490edb5d34695f9acb9aeb4fb3f1d34f1ba`

## Ergänzung der Release-Prüfsummen

Skein-1024-1024 ergänzt SHA256 und SHA3-512 als dritte Prüfsumme des vollständigen finalen ZIPs. `PasswordGeneratorChecksum skein-1024-1024 <Datei>` verwendet die feste 1.024-Bit-Ausgabelänge, nicht Skein-XOF. `Scripts/package-app.sh` erzeugt die zusätzliche Datei `Password.Generator-2.1.0.zip.skein-1024-1024` und das Feld `skein-1024-1024` im Integritätsmanifest. Die notarisierten ZIP-Bytes, die Developer-ID-Signatur und das angeheftete Ticket bleiben unverändert. Die externen Prüfsummen ändern Apples Signaturverfahren nicht.

`Scripts/verify-release.sh` fordert alle drei Prüfsummendateien an, vergleicht jeden Wert mit dem tatsächlichen ZIP und dem Manifest und bricht bei Abweichungen ab. Zusätzlich zu Python für beide SHA-Verfahren kontrolliert `Scripts/skein-reference-checksum.sh` den Skein-Wert mit der offiziellen C-Referenz. Die Referenzquellen liegen einschließlich Herkunfts- und Lizenzhinweisen unter [Tests/Reference/Skein](../Tests/Reference/Skein/NOTICE.md). Sie werden ausschließlich für die lokale Verifikation in einem temporären Verzeichnis kompiliert und sind kein Bestandteil der App. Ein alternatives Downloadverzeichnis lässt sich mit `RELEASE_BUILD_DIR` angeben.

Die Ergänzung wurde am 29. September 2026 separat geprüft: Das Release-Prüfsummenwerkzeug bestand alle 49 vorhandenen Skein-Vektoren, 20 SHA256-/SHA3-512-Randfälle sowie vier Fehlerfälle für fehlende oder ungültige Argumente und fehlende Dateien. Der eigenständige C-Prüfer bestand ebenfalls alle 49 Skein-Vektoren sowie zusätzliche Dateifälle an seinen Lesegrenzen (65.535, 65.536, 65.537 und 131.073 Byte), vier Fehlerfälle und Prüfungen von Ausgabeformat und temporärer Bereinigung. Die 36 offiziellen Golden-Vektoren wurden zusätzlich mit dem Originalarchiv verglichen. Eine isolierte vollständige Paketierung mit lokaler Ad-hoc-Signatur erzeugte alle drei Prüfsummen und bestand die anschließende unabhängige Verifikation. Fehlende oder veränderte Skein-Prüfsummendateien sowie fehlende, veränderte oder doppelte Skein-Manifestfelder wurden in fünf gezielten Fällen abgewiesen. Auch ein relativer Downloadpfad mit Leerzeichen wurde erfolgreich geprüft. Am unveränderten notarisierten Release bestanden alle drei Hashvergleiche, die strenge Code-Signaturprüfung, die minimale Sandbox, die Ticketprüfung und Gatekeeper erneut.

## Quellen

- [BIP39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Originalwortliste](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [Skein v1.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
- [NIST FIPS 202](https://doi.org/10.6028/NIST.FIPS.202)
- [Durstenfeld, Algorithm 235](https://doi.org/10.1145/364520.364540)
- [Apple SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
