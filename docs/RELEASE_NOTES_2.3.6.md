# Password Generator 2.3.6

## English

Version 2.3.6, build 13, starts in English and puts English first, German second. Only the last language choice is remembered among generator settings. Password mode, length, separators, hexadecimal case and security confirmation start fresh on relaunch. Existing macOS window storage remains allowed and unchanged.

An internal security audit addresses secret-lifetime and release-verification weaknesses. The mouse pool and stored result use owned, page-aligned memory with explicit overwriting. The master key is overwritten immediately after the five generators are initialized. Their states are cleared before the result reaches the UI, including on errors. Discarding or orderly shutdown clears the shared result, old mouse pool and unchanged clipboard content owned by the app. Concealed word output no longer constructs plaintext words. BIP39 intermediate entropy, selection indices, random-provider failure buffers and hash contexts receive explicit cleanup.

Release validation now requires notarized Developer ID, the expected signing team/product/version/build, Hardened Runtime and minimal sandbox entitlements by default; unsafe archive paths and payloads are rejected before extraction. Development checks require an explicit opt-in. The custom byte-stream sequence, password alphabets, default lengths and export behavior remain unchanged.

Complete irrevocable erasure of previously exported Swift/UI/operating-system copies cannot be guaranteed. A forced quit can prevent cleanup. This is an internal review, not an independent certification or a formal security proof. See the [audit and remaining limits](SECURITY_AUDIT_2.3.6.md) and [technical verification](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

On 5 October 2026, all 120 XCTest tests passed in Debug, Release and Release with AddressSanitizer (83 Core, 37 App), without failures, compiler warnings or reported memory errors. All 48 release-gate checks passed. The Xcode Direct Distribution export is signed with Developer ID, notarized, stapled and accepted by Gatekeeper; tested code and resources match. The installed app is verified and native quit/relaunch checks confirm both language choices and fresh generator configuration. Only the latest app version is retained as an installation. The public release contains the ZIP, three checksum sidecars and an integrity manifest.

## Deutsch

Version 2.3.6, Build 13, startet auf Englisch und zeigt Englisch zuerst, Deutsch danach. Von den Generatoreinstellungen wird ausschließlich die letzte Sprachwahl gespeichert. Format, Länge, Trennzeichen, Hex-Schreibweise und Sicherheitsbestätigung beginnen nach einem Neustart frisch. Die bestehende macOS-Fensterspeicherung bleibt erlaubt und unverändert.

Ein interner Sicherheits-Audit behebt Schwachstellen bei der Lebensdauer geheimer Daten und der Releaseprüfung. Mauspool und gespeichertes Ergebnis verwenden eigene, seitenausgerichtete Speicherbereiche mit ausdrücklichem Überschreiben. Der Masterkey wird unmittelbar nach Initialisierung der fünf Generatoren überschrieben. Deren Zustände werden vor der Übergabe des Ergebnisses an die Oberfläche bereinigt, auch bei Fehlern. Verwerfen und reguläres Beenden bereinigen den gemeinsamen Ergebnis-Puffer, den alten Mauspool und eigene unveränderte Zwischenablageinhalte. Verdeckte Wörter erzeugen keine Klartextwörter mehr. BIP39-Zwischenentropie, Auswahlindizes, fehlerhafte Zufallsrückgaben und Hashkontexte werden ausdrücklich bereinigt.

Die Releaseprüfung verlangt standardmäßig notarisiertes Developer ID, das erwartete Team/Produkt/Version/Build, Hardened Runtime und minimale Sandboxrechte. Unsichere Archivpfade und Payloads werden vor dem Entpacken abgewiesen. Entwicklungsprüfungen benötigen eine ausdrückliche Option. Die individuelle Bytestream-Ableitung, Zeichenmengen, Standardlängen und Exportfunktionen bleiben unverändert.

Eine unwiderrufliche Löschung bereits exportierter Swift-, UI- oder Betriebssystemkopien ist nicht garantiert. Erzwungenes Beenden kann die Bereinigung verhindern. Das ist eine interne Prüfung, keine unabhängige Zertifizierung und kein formaler Sicherheitsbeweis. [Audit und verbleibende Grenzen](SECURITY_AUDIT_2.3.6.md), [technische Verifikation](CRYPTOGRAPHIC_AND_FUNCTIONAL_ANALYSIS.md#verifikation).

Am 5. Oktober 2026 bestanden jeweils 120 XCTest-Tests in Debug, Release und Release mit AddressSanitizer (83 Core, 37 App), ohne Fehler, Compilerwarnungen oder gemeldete Speicherfehler. Alle 48 Release-Gate-Prüfungen bestanden. Der Xcode-Export ist mit Developer ID signiert, notarisiert, mit gültigem Ticket versehen und von Gatekeeper akzeptiert; Code und Ressourcen stimmen mit dem getesteten Paket überein. Die Installation und beide Sprachen über reguläre Neustarts sind geprüft, die Generatorkonfiguration wird zurückgesetzt. Nur die neueste Appversion bleibt installiert. Das öffentliche Release enthält ZIP, drei Prüfsummendateien und Integritätsmanifest.
