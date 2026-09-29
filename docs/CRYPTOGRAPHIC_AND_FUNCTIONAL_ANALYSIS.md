# Technische Analyse von Password Generator 2.0.0

Stand: 29. September 2026. Diese Datei beschreibt die aktuelle Implementierung. Frühere Ergebnisse der Seed-Phrase-App 1.0.0 belegen den neuen Build nicht.

## Datenfluss

Der Pool fasst 4.096 Mausbewegungen mit je 89 serialisierten Byte, insgesamt 364.544 Byte Nutzdaten bei voller Belegung. Ein Datensatz beginnt mit dem Versionsbyte 1. Es folgen elf 64-Bit-Werte in Little-Endian-Reihenfolge: Ereignisnummer, monotone Nanosekunden, Bitmuster der Ereigniszeit, x, y, deltaX, deltaY, Fensterbreite, Fensterhöhe, Modifikatormaske und gedrückte Maustasten. Fließkommazahlen werden über ihr IEEE-754-Bitmuster codiert.

Ein Ringpuffer ersetzt die ältesten Datensätze. Eine getrennte Indexpermutation legt ihre Reihenfolge für das Hashen fest. Dadurch mischt Fisher-Yates die vollständigen Ereignisse; Zeitstempel und Koordinaten innerhalb eines Ereignisses bleiben zusammen. Die Auswahl des nächsten zu ersetzenden Ereignisses bleibt auch nach dem Shuffle chronologisch.

Bei jedem Shuffle läuft der Index von `n - 1` bis `1`. Der Tauschindex liegt gleichverteilt in `0...index`, einschließlich der aktuellen Position. 32-Bit-Werte werden aus gepufferten macOS-Zufallsbytes gelesen. Werte außerhalb des größten durch die jeweilige Bereichsgröße teilbaren Präfixes von `0...2³²-1` werden verworfen. Damit ist die Auswahl unverzerrt. Wiederholt unbrauchbare Bytes führen zum Fehler, statt die App endlos zu blockieren.

Die Hashberechnung des Pools findet ausschließlich beim Generieren statt:

```text
shuffle(records)
P = serialize(records in shuffled order)
D = Skein-1024-1024(P) || SHA3-512(P)              // 192 Byte
M = D XOR fresh_macOS_random(192)
F[i] = M[32*i ..< 32*(i+1)]                      // i = 0...5
X = SHAKE256(F[0]) XOR ... XOR SHAKE256(F[5])
output_bytes = X XOR fresh_macOS_random(length(X))
```

Die sechs SHAKE-Zustände werden pro Generierung genau einmal initialisiert und fortlaufend gelesen. Auch bei verworfenen Auswahlwerten wird kein bereits verwendetes Stream-Präfix erneut ausgegeben. Jeder Nachladevorgang fordert einen frischen gleich langen OS-Beitrag an. Hashes der Ressourcen zur Integritätskontrolle sind hiervon getrennt und werden beim Laden geprüft.

## Aussage der Entropieanzeige

Für EFF, ASCII, PIN und Hex berechnet die App `H = Länge × log₂(Alphabetgröße)` mit 7.776, 94, 10 beziehungsweise 16 Auswahlmöglichkeiten. Hex hat somit nominell vier Bit pro Zeichen, bei 448 Zeichen maximal 1.792 Bit im Auswahlraum. BIP39 verwendet `ENT`, ohne die abgeleiteten Prüfsummenbits mitzuzählen. Die Anzeige ist die nominelle Entropie unter der Annahme gleichverteilter, unabhängiger Auswahl.

Es werden keine Entropiebits für einzelne Mausbewegungen gutgeschrieben. 4.096 Ereignisse sind eine Bedienanforderung, kein kryptografischer Entropienachweis. Das Aneinanderhängen zweier Hashwerte über dieselben Daten vermehrt die enthaltene Entropie nicht automatisch. Sechs SHAKE256-Streams ergeben durch XOR keine bewiesene 1.536-Bit-Sicherheitsstärke. Das OS-XOR stützt die Ausgabe auf frische kryptografische Systemzufallsbytes; die Eigenschaft hängt von deren Unvorhersagbarkeit auch unter Kenntnis des anderen Operanden ab.

## Exportformatierung

Die kanonischen Komponenten bleiben unabhängig von der Exportdarstellung erhalten. EFF und BIP39 werden beim Kopieren mit dem eingegebenen Trenner verbunden; Standard ist bei BIP39 ein Leerzeichen und bei EFF `-`; leer ist zulässig. Hex wird intern in Kleinbuchstaben erzeugt und wahlweise in Großbuchstaben exportiert. Das Formatieren liest keine Zufallsbytes und ändert weder die Komponenten noch ihre nominelle Auswahlentropie.

BIP39 ohne Trenner ist keine eindeutige Codierung: `leg alarm` und `legal arm`, jeweils gefolgt von neunmal `abandon` und `accuse`, sind zwei verschiedene prüfsummengültige 12-Wort-Mnemonics mit identischem zusammengefügtem Export. Daher bezeichnet die Entropieanzeige die ursprüngliche Wortauswahl, nicht eine garantierte Entropie der trennzeichenlosen Darstellung. Für den standardüblichen BIP39-Import sind Leerzeichen zu verwenden.

## Fehlermodell und Grenzen

Fehler oder falsche Ausgabelängen der OS-Quelle brechen die betroffene Generierung ab. Nach einem Fehler beim Lesen eines abgeleiteten Streams wird dieser verworfen und kann nicht wiederverwendet werden. Das Poolminimum wird vor jeder Ableitung geprüft. Manipulierte Wortlisten werden vor der Nutzung abgewiesen.

Die App hält die bisherigen Schutzmaßnahmen bei: minimale Sandbox ohne Netzwerkberechtigung, Hardened Runtime, erneute Signatur-/Debuggerprüfung vor sensitiven Aktionen, deaktivierte POSIX-Core-Dumps, verdeckte Ausgabe, Kontextverdeckung und zeitlich begrenzte Zwischenablage. Sie ersetzt keine unabhängige Prüfung des Betriebssystems. Die Spezialkonstruktion ist weder ein externes Audit noch ein standardisiertes DRBG-Verfahren. Swift-Kopien und Betriebssystempuffer verhindern garantierte vollständige Löschung. Die Implementierung ist nicht formal als konstantzeitlich oder seitenkanalresistent geprüft.

Ein periodischer Task mischt ab Appstart etwa alle sechs Sekunden, auch nach abgeschlossener Generierung. Er läuft unabhängig vom Erreichen des Mausminimums. Schlaf oder Suspendierung können den Termin verschieben. Beim Beenden wird der Task abgebrochen. Die unmittelbare Durchmischung vor jeder Generierung ist davon unabhängig.

## Verifikation

Am 29. September 2026 bestanden alle 57 XCTest-Tests: 39 Core-Tests und 18 App-Modelltests, ohne Fehler oder Compilerwarnungen (`swift test -Xswiftc -warnings-as-errors`). Dazu gehören die Längengrenzen aller fünf Formate, ungerade Hexlängen, Groß-/Kleinschreibung, frei wählbare und leere Trenner, getrennte BIP39-/EFF-Standards sowie Kopieren ohne neue Zufallsziehung. Die Zwischenablagetests verwenden eine eigene Testzwischenablage.

Die Kryptografietests prüfen 49 Skein-, 81 SHA3-512- und 538 SHAKE256-Referenzvektoren. SHAKE-Ausgaben über einer Rate-Länge werden zusätzlich in mehreren Teilstücken gelesen. Ein unabhängig mit der offiziellen Skein-C-Referenz und Python berechneter Erwartungswert prüft die vollständige Ableitung aus 4.096 Ereignissen einschließlich Masterkey-Aufteilung und beider OS-XOR-Schritte. Herkunft und Auswahl stehen in `Tests/PasswordGeneratorCoreTests/Resources/CRYPTO_VECTORS.md`.

Der Release-Build wurde mit Compilerwarnungen als Fehler erstellt, mit Developer ID signiert und anschließend als vollständiges ZIP unabhängig mit Swift und Python gegen SHA256 und SHA3-512 geprüft. Das entpackte Bundle bestand die strenge Code-Signaturprüfung und besitzt ausschließlich die minimale App-Sandbox. Das Binary ist `arm64`, die Mindestversion macOS 14. Logo und mehrstufiges `AppIcon.icns` sind im versiegelten Bundle enthalten. Der Release ist nicht notarisiert; das vorhandene Schlüsselbundprofil wird von Apple nicht akzeptiert.

Die gestartete signierte App zeigte aktiven Laufzeitschutz, die korrekten Standardtrenner, ein tatsächlich leeres Exportfeld sowie Hexlängen 1 und 448 mit den passenden Entropiewerten. Der periodische Mischzähler stieg während dieser Bedienprüfung weiter. Zusätzlich wurden Ansichten mit synthetischen Testwerten bei 900 Punkt Fensterbreite gerendert und visuell geprüft, einschließlich EFF mit 60 Wörtern und Hex mit 448 Großbuchstaben. Die synthetischen Ansichten prüfen das Layout, nicht die Zufallsqualität. Diese Prüfungen ersetzen kein externes Sicherheitsaudit.

SHA256 des veröffentlichten App-ZIPs:
`667c3d94274a7775fcb1c595dc832b645bc9e19e76234dc453cc2a81b1145872`

SHA3-512 desselben App-ZIPs:
`4385cc7951b656980912f33f5fcac11615a51993ab4591dbc624d0e5d35dbbd2dd06e515e0d44e109fdb56d290c368b64709b39fade70177fc30c0fe79b5a6ba`

## Quellen

- [BIP39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
- [EFF Originalwortliste](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt)
- [Skein v1.3](https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf)
- [NIST FIPS 202](https://doi.org/10.6028/NIST.FIPS.202)
- [Durstenfeld, Algorithm 235](https://doi.org/10.1145/364520.364540)
- [Apple SecRandomCopyBytes](https://developer.apple.com/documentation/security/secrandomcopybytes(_:_:_:))
