import CryptoKit
import Foundation
import CommonCrypto
import Darwin

public enum MnemonicWordCount: Int, CaseIterable, Identifiable, Sendable {
    case twelve = 12
    case fifteen = 15
    case eighteen = 18
    case twentyOne = 21
    case twentyFour = 24

    public var id: Int { rawValue }

    public var entropyByteCount: Int {
        switch self {
        case .twelve: 16
        case .fifteen: 20
        case .eighteen: 24
        case .twentyOne: 28
        case .twentyFour: 32
        }
    }

    public var entropyBitCount: Int { entropyByteCount * 8 }
    public var checksumBitCount: Int { entropyBitCount / 32 }
}

public enum BIP39Error: LocalizedError, Equatable {
    case resourceMissing
    case wordListIntegrityFailure
    case invalidWordList
    case invalidEntropyLength(Int)
    case invalidWordCount(Int)
    case unknownWord(String)
    case invalidChecksum

    public var errorDescription: String? {
        switch self {
        case .resourceMissing:
            "Die offizielle BIP-39-Wortliste wurde nicht gefunden."
        case .wordListIntegrityFailure:
            "Die BIP-39-Wortliste hat den dreifachen Integritätstest nicht bestanden."
        case .invalidWordList:
            "Die BIP-39-Wortliste ist ungültig."
        case let .invalidEntropyLength(length):
            "Ungültige Entropielänge: \(length) Byte."
        case let .invalidWordCount(count):
            "Ungültige Wortanzahl: \(count)."
        case let .unknownWord(word):
            "Unbekanntes BIP-39-Wort: \(word)."
        case .invalidChecksum:
            "Die BIP-39-Prüfsumme ist ungültig."
        }
    }
}

public struct WordListIntegrity: Equatable, Sendable {
    public let sha256: String
    public let sha3_512: String
    public let skein1024_1024: String

    public static let expected = WordListIntegrity(
        sha256: "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda",
        sha3_512: "862e1642f46f0e81d81fa48ad5a806a12a5578130ddf13c4c302aec44a03c710bc6574e965f9084b1918b4ce0a95dac282499e2cdcd8cf50e48f3851e2f32d32",
        skein1024_1024: "8f63cf649dc0938e25c164849d164cfef2f80ea256e290c27eda407bfb0bdffa1e9027d55eb2f193a799e5a61fa56334b4847ac7871c52079e84cf7f0eecad198ae6eb9b63cfb29ba8a9ecfb63a95ed7f30c0708e80ab25ceb95f0370a863800987fb98875ee0c9e0f6b1be1af7b31cbd9525410cd72e2ec380eae37f902fed4"
    )
}

public struct BIP39: Sendable {
    public let words: [String]
    public let wordListIntegrity: WordListIntegrity
    private let indexByWord: [String: Int]

    public init() throws {
        let resourceURL = Bundle.main.url(forResource: "english", withExtension: "txt")
            ?? Bundle.module.url(forResource: "english", withExtension: "txt")
        guard let resourceURL else { throw BIP39Error.resourceMissing }
        // Copy one immutable snapshot so hashing and parsing see identical bytes.
        let data = try Data(contentsOf: resourceURL)
        try self.init(verifiedWordListData: data)
    }

    public init(verifiedWordListData data: Data) throws {
        let integrity = WordListIntegrity(
            sha256: Self.hex(Data(SHA256.hash(data: data))),
            sha3_512: Self.hex(SHA3.hash512(data)),
            skein1024_1024: Self.hex(Data(Skein.hash1024(Array(data))))
        )
        guard integrity == .expected else {
            throw BIP39Error.wordListIntegrityFailure
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw BIP39Error.invalidWordList
        }
        let parsedWords = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard parsedWords.count == 2_048,
              Set(parsedWords).count == 2_048,
              parsedWords == parsedWords.sorted(),
              parsedWords.first == "abandon",
              parsedWords.last == "zoo"
        else {
            throw BIP39Error.invalidWordList
        }

        words = parsedWords
        wordListIntegrity = integrity
        indexByWord = Dictionary(uniqueKeysWithValues: parsedWords.enumerated().map { ($1, $0) })
    }

    public func mnemonic(from entropy: [UInt8]) throws -> [String] {
        guard let wordCount = Self.wordCount(forEntropyByteCount: entropy.count) else {
            throw BIP39Error.invalidEntropyLength(entropy.count)
        }

        var checksum = Self.checksum(entropy)
        defer { Self.clear(&checksum) }
        let totalBitCount = wordCount.entropyBitCount + wordCount.checksumBitCount
        var result: [String] = []
        result.reserveCapacity(wordCount.rawValue)

        for wordOffset in 0..<wordCount.rawValue {
            var index = 0
            for bitOffset in 0..<11 {
                let sourceBit = wordOffset * 11 + bitOffset
                index <<= 1
                if sourceBit < wordCount.entropyBitCount {
                    index |= Self.bit(at: sourceBit, in: entropy)
                } else {
                    index |= Self.bit(
                        at: sourceBit - wordCount.entropyBitCount,
                        in: checksum
                    )
                }
            }
            result.append(words[index])
        }

        precondition(result.count * 11 == totalBitCount)
        return result
    }

    public func validate(_ mnemonicWords: [String]) -> Bool {
        do {
            var recoveredEntropy = try entropy(from: mnemonicWords)
            defer { Self.clear(&recoveredEntropy) }
            return true
        } catch {
            return false
        }
    }

    public func entropy(from mnemonicWords: [String]) throws -> [UInt8] {
        guard let wordCount = MnemonicWordCount(rawValue: mnemonicWords.count) else {
            throw BIP39Error.invalidWordCount(mnemonicWords.count)
        }

        var allBits: [UInt8] = []
        allBits.reserveCapacity(mnemonicWords.count * 11)
        defer { Self.clear(&allBits) }
        for word in mnemonicWords {
            guard let index = indexByWord[word] else { throw BIP39Error.unknownWord(word) }
            for shift in stride(from: 10, through: 0, by: -1) {
                allBits.append(UInt8((index >> shift) & 1))
            }
        }

        var entropy = [UInt8](repeating: 0, count: wordCount.entropyByteCount)
        var returnsEntropy = false
        defer {
            // On success ownership passes to the caller; error paths retain no entropy.
            if !returnsEntropy { Self.clear(&entropy) }
        }
        for bitIndex in 0..<wordCount.entropyBitCount where allBits[bitIndex] == 1 {
            entropy[bitIndex / 8] |= UInt8(1 << (7 - (bitIndex % 8)))
        }

        var digest = Self.checksum(entropy)
        defer { Self.clear(&digest) }
        for checksumIndex in 0..<wordCount.checksumBitCount {
            let supplied = allBits[wordCount.entropyBitCount + checksumIndex]
            let expected = UInt8(Self.bit(at: checksumIndex, in: digest))
            guard supplied == expected else { throw BIP39Error.invalidChecksum }
        }
        returnsEntropy = true
        return entropy
    }

    /// Hash the caller's bytes directly, without creating a second Data allocation.
    /// Only the digest is returned; the caller remains responsible for its input.
    private static func checksum(_ entropy: [UInt8]) -> [UInt8] {
        var context = CC_SHA256_CTX()
        defer {
            withUnsafeMutableBytes(of: &context) { buffer in
                if let base = buffer.baseAddress {
                    _ = memset_s(base, buffer.count, 0, buffer.count)
                }
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = CC_SHA256_Init(&context)
        entropy.withUnsafeBytes { input in
            _ = CC_SHA256_Update(&context, input.baseAddress, CC_LONG(input.count))
        }
        digest.withUnsafeMutableBytes { output in
            _ = CC_SHA256_Final(output.bindMemory(to: UInt8.self).baseAddress!, &context)
        }
        return digest
    }

    private static func clear(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }

    private static func bit(at bitIndex: Int, in bytes: [UInt8]) -> Int {
        Int((bytes[bitIndex / 8] >> (7 - (bitIndex % 8))) & 1)
    }

    private static func wordCount(forEntropyByteCount count: Int) -> MnemonicWordCount? {
        MnemonicWordCount.allCases.first { $0.entropyByteCount == count }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
