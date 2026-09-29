import Foundation
import PasswordGeneratorCore

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case german
    case english

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
                    german: "Die BIP‑39-Wortliste hat den doppelten Integritätstest nicht bestanden.",
                    english: "The BIP‑39 word list failed the dual integrity check."
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
                return LocalizedMessage(german: "Die EFF-Wortliste hat den doppelten Integritätstest nicht bestanden.", english: "The EFF word list failed the dual integrity check.")
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
