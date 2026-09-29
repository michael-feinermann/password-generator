import CryptoKit
import Foundation

public enum EFFError: LocalizedError, Equatable {
    case resourceMissing
    case wordListIntegrityFailure
    case invalidWordList

    public var errorDescription: String? {
        switch self {
        case .resourceMissing:
            "Die offizielle EFF-Wortliste wurde nicht gefunden."
        case .wordListIntegrityFailure:
            "Die EFF-Wortliste hat den doppelten Integritätstest nicht bestanden."
        case .invalidWordList:
            "Die EFF-Wortliste ist ungültig."
        }
    }
}

/// EFF's original English long word list, bundled for entirely offline use.
/// Source: https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt
public struct EFF: Sendable {
    public static let wordCount = 7_776
    public static let expectedIntegrity = WordListIntegrity(
        sha256: "addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e",
        sha3_512: "4573a7810c569805ab110b0ce5004d4697079afe2d74ba70daa9dd49bd0a60103c5bce9725db036bd1ebaf5813815a54f821e7d752b5ee6eb57bed4a7e58aa23"
    )

    public let words: [String]
    public let wordListIntegrity: WordListIntegrity

    public init() throws {
        let resourceURL = Bundle.main.url(forResource: "eff_large_wordlist", withExtension: "txt")
            ?? Bundle.module.url(forResource: "eff_large_wordlist", withExtension: "txt")
        guard let resourceURL else { throw EFFError.resourceMissing }
        try self.init(verifiedWordListData: Data(contentsOf: resourceURL))
    }

    public init(verifiedWordListData data: Data) throws {
        // Hash and parse the same immutable snapshot, including original dice labels.
        let integrity = WordListIntegrity(
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            sha3_512: SHA3.hash512(data).map { String(format: "%02x", $0) }.joined()
        )
        guard integrity == Self.expectedIntegrity else {
            throw EFFError.wordListIntegrityFailure
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw EFFError.invalidWordList
        }
        let rows = text.split(whereSeparator: \Character.isNewline)
        guard rows.count == Self.wordCount else { throw EFFError.invalidWordList }
        var parsedWords: [String] = []
        parsedWords.reserveCapacity(Self.wordCount)
        for (index, row) in rows.enumerated() {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false)
            // Dice labels enumerate all five-die outcomes in lexicographic order.
            let expectedLabel = String(index, radix: 6)
                .leftPaddedToFiveDigits
                .utf8.map { $0 + 1 }
            guard fields.count == 2,
                  Array(fields[0].utf8) == expectedLabel,
                  !fields[1].isEmpty,
                  !fields[1].contains(where: \.isWhitespace)
            else { throw EFFError.invalidWordList }
            parsedWords.append(String(fields[1]))
        }
        guard Set(parsedWords).count == Self.wordCount,
              parsedWords == parsedWords.sorted(),
              parsedWords.first == "abacus",
              parsedWords.last == "zoom"
        else { throw EFFError.invalidWordList }
        words = parsedWords
        wordListIntegrity = integrity
    }
}

private extension String {
    var leftPaddedToFiveDigits: String {
        String(repeating: "0", count: max(0, 5 - count)) + self
    }
}
