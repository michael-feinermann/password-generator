# Password Generator 2.0.0

## English

A native macOS app for BIP39, EFF word passwords, ASCII passwords, PINs, and hexadecimal values. Requires macOS 14 or later on Apple Silicon.

- BIP39 with 12, 15, 18, 21, or 24 words; EFF with 6 to 60 words.
- ASCII with 94 printable characters excluding spaces, lengths from 8 to 256; PINs with 3 to 256 digits.
- Hexadecimal output with 1 to 448 characters and selectable uppercase or lowercase letters.
- A configurable export separator: BIP39 defaults to a space, EFF to a hyphen. An empty field joins words without a separator. Both settings are retained independently.
- An entropy display for the theoretical selection space. Separators and uppercase formatting do not provide additional random bits.
- A pool containing the most recent 4,096 mouse movements across the entire window; Fisher-Yates shuffling every six seconds and immediately before each generation.
- Pool hashes computed only during generation: Skein-1024-1024, SHA3-512, six SHAKE256 streams, and fresh macOS random bytes, following the documented derivation.
- A new logo and macOS icon; English and German interfaces.

The ZIP contains the app signed with Developer ID. This release is not notarized: the available Apple notarization profile was not accepted. macOS may therefore block an app downloaded from the internet. The sandbox and runtime protections remain enabled. No exceptions to the security checks have been introduced.

BIP39 wallets usually expect words separated by spaces. Omitting the separator removes word boundaries. The app implements a custom random-generation construction; its tests do not replace an external security audit. The full description and sources are available in the repository.

Downloads include the app ZIP, SHA256 and SHA3-512 checksums, and a shared integrity manifest.

Verified with 57 passing tests, cryptographic reference vectors, checks of the running signed app bundle, and independent verification of both ZIP checksums using Python.

## Deutsch

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
