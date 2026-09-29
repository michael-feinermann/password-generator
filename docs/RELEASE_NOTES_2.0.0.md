# Password Generator 2.0.0

Native macOS-App für BIP39, EFF-Wortpasswörter, ASCII-Passwörter, PINs und Hexwerte. Ab macOS 14 auf Apple Silicon.

- BIP39 mit 12, 15, 18, 21 oder 24 Wörtern; EFF mit 6 bis 60 Wörtern.
- ASCII mit 94 druckbaren Zeichen ohne Leerzeichen, Länge 8 bis 256; PINs mit 3 bis 256 Ziffern.
- Hex mit 1 bis 448 Zeichen und wählbarer Groß-/Kleinschreibung.
- Frei wählbares Exporttrennzeichen: BIP39 standardmäßig Leerzeichen, EFF standardmäßig Bindestrich. Ein leeres Feld verbindet Wörter ohne Trenner. Beide Einstellungen bleiben unabhängig erhalten.
- Entropieanzeige für den theoretischen Auswahlraum. Trennzeichen und Großschreibung liefern keine zusätzlichen Zufallsbits.
- Pool aus den letzten 4.096 Mausbewegungen im gesamten Fenster; Fisher-Yates alle sechs Sekunden sowie direkt vor jeder Generierung.
- Poolhashes ausschließlich bei Generierung: Skein-1024-1024, SHA3-512, sechs SHAKE256-Streams und frische macOS-Zufallsbytes entsprechend der dokumentierten Ableitung.
- Neues Logo und macOS-Icon; deutsche und englische Oberfläche.

Das ZIP enthält die mit Developer ID signierte App. Dieser Release ist nicht notarisiert: Das vorhandene Apple-Notarisierungsprofil wird derzeit nicht akzeptiert. macOS kann die Ausführung einer aus dem Internet geladenen App deshalb blockieren. Die Sandbox und Laufzeitschutzmaßnahmen bleiben aktiviert. Es wurden keine Ausnahmen von den Schutzprüfungen eingebaut.

BIP39-Wallets erwarten die Wörter üblicherweise mit Leerzeichen. Die Variante ohne Trenner verliert Wortgrenzen. Die App implementiert eine individuelle Zufallskonstruktion; die Tests ersetzen kein externes Sicherheitsaudit. Vollständige Beschreibung und Quellen stehen im Repository.

Zum Download gehören das App-ZIP, SHA256- und SHA3-512-Prüfsummen sowie ein gemeinsames Integritätsmanifest.

Verifiziert mit 57 bestandenen Tests, kryptografischen Referenzvektoren, Prüfung des gestarteten signierten Bundles und unabhängiger Gegenprüfung beider ZIP-Prüfsummen mit Python.
