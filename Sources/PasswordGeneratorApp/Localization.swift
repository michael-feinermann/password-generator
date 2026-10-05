import Foundation
import PasswordGeneratorCore

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .german: "DE"
        case .english: "EN"
        }
    }

    var displayName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .german: Locale(identifier: "de_DE")
        case .english: Locale(identifier: "en_US")
        }
    }

    func text(_ german: String, _ english: String) -> String {
        switch self {
        case .german: german
        case .english: english
        }
    }

    func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }
}

struct LocalizedMessage: Equatable, Sendable {
    let german: String
    let english: String

    func value(in language: AppLanguage) -> String {
        language.text(german, english)
    }

    static let randomGenerationExplanation = LocalizedMessage(
        german: """
        Vor jeder Generierung mischt Fisher-Yates die 4.096 Mausereignisse mit kryptografischen macOS-Zufallsbytes. Skein-1024-1024 liefert danach 128 Byte, SHA3-512 und SHA-512 jeweils weitere 64 Byte. Die drei Hashwerte des Pools werden in dieser Reihenfolge zu 256 Byte verbunden. Zuerst werden diese Hashbytes mit 256 frischen macOS-Zufallsbytes XOR-verknüpft. Danach mischt Fisher-Yates alle 2.048 einzelnen Bits des XOR-Ergebnisses mit weiteren kryptografischen macOS-Zufallsbytes. Erst anschließend ergibt ein zweites XOR mit separat angeforderten 256 frischen macOS-Zufallsbytes den Masterkey. Die beiden XOR-Masken und die Zufallsbytes für die Mischvorgänge werden getrennt angefordert; keine Maske wird wiederverwendet.

        Die ersten 128 Byte initialisieren einen Skein-1024-XOF-Stream. Die folgenden zwei Fragmente mit je 32 Byte initialisieren je einen SHAKE256-Stream. Die letzten zwei Fragmente mit je 32 Byte bilden jeweils den eigenen Schlüssel eines AES-256-CTR-Streams. Beide AES-Streams beginnen mit einem 128-Bit-Zähler in Big-Endian-Reihenfolge bei null. Gleich lange Ausgaben aller fünf Streams werden per XOR kombiniert und unmittelbar vor der Zeichenauswahl nochmals mit gleich vielen frischen macOS-Zufallsbytes XOR-verknüpft. Bei Nachforderungen laufen alle fünf Streams ohne Neustart weiter, einschließlich der AES-Zähler und noch nicht verbrauchten Blockbytes. Die periodische Mischung alle sechs Sekunden betrifft nur den Mauspool; Hashberechnung und Ableitung erfolgen ausschließlich bei der Generierung.

        Der Masterkey wird unmittelbar nach Initialisierung der fünf Generatoren überschrieben. Ihre Zustände werden nach der Generierung und vor Übergabe des Passworts an die Oberfläche bereinigt. Beim Verwerfen beziehungsweise regulären Beenden werden der eigene Passwortpuffer und der Mauspool überschrieben. Bereits für Anzeige oder Kopieren erzeugte Swift- und Betriebssystemkopien lassen sich nicht vollständig und unwiderruflich löschen; erzwungenes Beenden kann die Bereinigung verhindern.
        """,
        english: """
        Before each generation, Fisher-Yates shuffles the 4,096 mouse records using cryptographic macOS random bytes. Skein-1024-1024 then produces 128 bytes, while SHA3-512 and SHA-512 each produce another 64 bytes. The three pool hashes are concatenated in that order to form 256 bytes. First, these hash bytes are XORed with 256 fresh macOS random bytes. Fisher-Yates then shuffles all 2,048 individual bits of the XOR result using further cryptographic macOS random bytes. Only after that shuffle does a second XOR with a separately requested set of 256 fresh macOS random bytes produce the master key. Both XOR masks and the shuffle randomness are requested separately; neither mask is reused.

        The first 128 bytes initialize one Skein-1024-XOF stream. The following two fragments of 32 bytes each initialize one SHAKE256 stream each. The final two fragments of 32 bytes each provide a separate key for each AES-256-CTR stream. Both AES streams start with a 128-bit big-endian counter at zero. Equal-length outputs of all five streams are combined using XOR, then XORed with an equal number of fresh macOS random bytes immediately before character selection. All five streams continue without restarting when more bytes are requested, including the AES counters and unused block bytes. The periodic shuffle every six seconds only affects the mouse pool; hashing and derivation occur exclusively during generation.

        The master key is overwritten immediately after the five generators are initialized. Their states are cleared after generation and before the password is published to the UI. Discarding the result or quitting normally overwrites the owned password buffer and mouse pool. Swift and operating-system copies already created for display or copying cannot all be erased completely and irrevocably; forced termination may prevent cleanup.
        """
    )

    static let clipboardFailed = LocalizedMessage(
        german: "Das Passwort konnte nicht in die Zwischenablage kopiert werden.",
        english: "The password could not be copied to the clipboard."
    )

    static let secureRuntimeUnavailable = LocalizedMessage(
        german: "Die gesicherte Laufzeitprüfung ist fehlgeschlagen. Starte das signierte App-Bundle ohne Debugger neu.",
        english: "The secure runtime check failed. Restart the signed app bundle without a debugger."
    )

    static let secureEnvironmentConfirmationRequired = LocalizedMessage(
        german: "Bestätige vor der Generierung die sichere Umgebung.",
        english: "Confirm the secure environment before generation."
    )

    static func from(_ error: Error) -> LocalizedMessage {
        if let error = error as? BIP39Error {
            switch error {
            case .resourceMissing:
                return LocalizedMessage(
                    german: "Die offizielle BIP‑39-Wortliste wurde nicht gefunden.",
                    english: "The official BIP‑39 word list could not be found."
                )
            case .wordListIntegrityFailure:
                return LocalizedMessage(
                    german: "Die BIP‑39-Wortliste hat den dreifachen Integritätstest nicht bestanden.",
                    english: "The BIP‑39 word list failed the triple integrity check."
                )
            case .invalidWordList:
                return LocalizedMessage(
                    german: "Die BIP‑39-Wortliste ist ungültig.",
                    english: "The BIP‑39 word list is invalid."
                )
            case let .invalidEntropyLength(length):
                return LocalizedMessage(
                    german: "Ungültige Entropielänge: \(length) Byte.",
                    english: "Invalid entropy length: \(length) bytes."
                )
            case let .invalidWordCount(count):
                return LocalizedMessage(
                    german: "Ungültige Wortanzahl: \(count).",
                    english: "Invalid word count: \(count)."
                )
            case let .unknownWord(word):
                return LocalizedMessage(
                    german: "Unbekanntes BIP‑39-Wort: \(word).",
                    english: "Unknown BIP‑39 word: \(word)."
                )
            case .invalidChecksum:
                return LocalizedMessage(
                    german: "Die BIP‑39-Prüfsumme ist ungültig.",
                    english: "The BIP‑39 checksum is invalid."
                )
            }
        }

        if let error = error as? EntropyError {
            switch error {
            case let .insufficientMouseEvents(actual, required):
                return LocalizedMessage(
                    german: "Es wurden erst \(actual) von mindestens \(required) Mausbewegungen erfasst.",
                    english: "Only \(actual) of at least \(required) mouse movements have been collected."
                )
            case .emptyMouseTranscript:
                return LocalizedMessage(
                    german: "Die Mausdaten fehlen.",
                    english: "The mouse data is missing."
                )
            case let .secureRandomFailure(status):
                return LocalizedMessage(
                    german: "macOS konnte keine sicheren Zufallsbytes liefern (Status \(status)).",
                    english: "macOS could not provide secure random bytes (status \(status))."
                )
            case let .invalidRandomByteCount(count):
                return LocalizedMessage(
                    german: "Die Zufallsquelle lieferte \(count) statt 64 Byte.",
                    english: "The random source returned \(count) instead of 64 bytes."
                )
            }
        }

        if let error = error as? EFFError {
            switch error {
            case .resourceMissing:
                return LocalizedMessage(german: "Die offizielle EFF-Wortliste wurde nicht gefunden.", english: "The official EFF word list could not be found.")
            case .wordListIntegrityFailure:
                return LocalizedMessage(german: "Die EFF-Wortliste hat den dreifachen Integritätstest nicht bestanden.", english: "The EFF word list failed the triple integrity check.")
            case .invalidWordList:
                return LocalizedMessage(german: "Die EFF-Wortliste ist ungültig.", english: "The EFF word list is invalid.")
            }
        }

        if let error = error as? PasswordGeneratorError {
            switch error {
            case let .invalidLength(mode, length):
                return LocalizedMessage(german: "Ungültige Länge für \(mode.rawValue.uppercased()): \(length).", english: "Invalid length for \(mode.rawValue.uppercased()): \(length).")
            case let .invalidRandomByteCount(expected, actual):
                return incorrectByteCount(expected: expected, actual: actual)
            case .rejectionLimitExceeded:
                return .randomSourceStalled
            }
        }

        if let error = error as? EntropyPoolError {
            switch error {
            case let .incorrectRandomByteCount(expected, actual):
                return incorrectByteCount(expected: expected, actual: actual)
            case let .invalidByteCount(count):
                return LocalizedMessage(german: "Ungültige Anzahl angeforderter Zufallsbytes: \(count).", english: "Invalid requested random byte count: \(count).")
            case .cleared:
                return LocalizedMessage(german: "Der Zufallspool oder Byte-Stream wurde bereits verworfen.", english: "The random pool or byte stream has already been discarded.")
            case .randomSourceStalled:
                return .randomSourceStalled
            }
        }

        return LocalizedMessage(
            german: "Unerwarteter Fehler: \(error.localizedDescription)",
            english: "Unexpected error: \(error.localizedDescription)"
        )
    }

    private static let randomSourceStalled = LocalizedMessage(
        german: "Die Zufallsquelle lieferte wiederholt keine verwendbaren Auswahlwerte.",
        english: "The random source repeatedly returned unusable sampling values."
    )

    private static func incorrectByteCount(expected: Int, actual: Int) -> LocalizedMessage {
        LocalizedMessage(
            german: "Die Zufallsquelle lieferte \(actual) statt \(expected) Byte.",
            english: "The random source returned \(actual) instead of \(expected) bytes."
        )
    }

}
