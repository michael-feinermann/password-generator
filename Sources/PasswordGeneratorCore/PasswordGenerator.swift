import Foundation

public enum GeneratorMode: String, CaseIterable, Identifiable, Sendable {
    case bip39
    case eff
    case ascii
    case pin
    case hex

    public var id: String { rawValue }

    public var lengthRange: ClosedRange<Int> {
        switch self {
        case .bip39: 12...24
        case .eff: 6...60
        case .ascii: 8...256
        case .pin: 3...256
        case .hex: 1...448
        }
    }

    public var supportedLengths: [Int] {
        switch self {
        case .bip39: MnemonicWordCount.allCases.map(\.rawValue)
        default: Array(lengthRange)
        }
    }

    public var defaultLength: Int {
        switch self {
        case .bip39: 24
        case .eff: 10
        case .ascii: 20
        case .pin: 12
        case .hex: 64
        }
    }

    public var usesWords: Bool { self == .bip39 || self == .eff }

    /// BIP-39 includes checksum bits, so its entropy must be computed separately.
    public var alphabetSize: Int? {
        switch self {
        case .bip39: nil
        case .eff: EFF.wordCount
        case .ascii: 94
        case .pin: 10
        case .hex: 16
        }
    }
}

public struct GeneratorConfiguration: Equatable, Sendable {
    public var mode: GeneratorMode
    public var length: Int

    public init(mode: GeneratorMode, length: Int) {
        self.mode = mode
        self.length = length
    }

    public func validate() throws {
        guard mode.lengthRange.contains(length),
              mode != .bip39 || MnemonicWordCount(rawValue: length) != nil
        else { throw PasswordGeneratorError.invalidLength(mode: mode, length: length) }
    }

    /// The log2 size of the uniformly sampled output space, not measured RNG entropy.
    /// Invalid configurations return zero and are rejected before generation.
    public var entropyBits: Double {
        guard (try? validate()) != nil else { return 0 }
        if mode == .bip39 {
            return Double(MnemonicWordCount(rawValue: length)!.entropyBitCount)
        }
        return Double(length) * log2(Double(mode.alphabetSize!))
    }
}

public enum PasswordGeneratorError: LocalizedError, Equatable {
    case invalidLength(mode: GeneratorMode, length: Int)
    case invalidRandomByteCount(expected: Int, actual: Int)
    case rejectionLimitExceeded

    public var errorDescription: String? {
        switch self {
        case let .invalidLength(mode, length):
            "Ungültige Länge für \(mode.rawValue.uppercased()): \(length)."
        case let .invalidRandomByteCount(expected, actual):
            "Die Zufallsquelle lieferte \(actual) statt \(expected) Byte."
        case .rejectionLimitExceeded:
            "Die Zufallsquelle lieferte wiederholt ungeeignete Auswahlwerte."
        }
    }
}

public struct GeneratedPassword: Equatable, Sendable {
    /// Words for BIP-39/EFF, individual characters for ASCII/PIN/hex.
    public let components: [String]
    public let text: String
    public let entropyBits: Double
    public let mode: GeneratorMode

    /// Formats an existing result without generating new randomness or changing it.
    /// The default separator is a space for BIP-39 and a hyphen for EFF.
    /// Word separators are literal, including empty or multi-character strings.
    /// The fixed separator and hex letter case add no entropy to the result.
    public func exportText(wordSeparator: String? = nil, uppercaseHex: Bool = false) -> String {
        let separator = wordSeparator ?? (mode == .bip39 ? " " : "-")
        switch mode {
        case .bip39, .eff:
            return components.joined(separator: separator)
        case .hex:
            return uppercaseHex ? text.uppercased() : text
        case .ascii, .pin:
            return text
        }
    }
}

public struct PasswordGenerator: Sendable {
    public let bip39: BIP39
    public let eff: EFF

    /// All printable ASCII characters except space: U+0021 through U+007E.
    public static let asciiAlphabet = (UInt8(0x21)...UInt8(0x7e)).map {
        String(UnicodeScalar($0))
    }
    public static let pinAlphabet = (0...9).map(String.init)
    public static let hexAlphabet = Array("0123456789abcdef").map(String.init)

    public init() throws {
        bip39 = try BIP39()
        eff = try EFF()
    }

    /// The provider must return exactly the requested number of cryptographic bytes.
    /// Rejection sampling can require several consecutive reads from the same stream.
    public func generate(
        configuration: GeneratorConfiguration,
        randomProvider: (Int) throws -> [UInt8]
    ) throws -> GeneratedPassword {
        try configuration.validate()
        let components: [String]
        switch configuration.mode {
        case .bip39:
            let byteCount = MnemonicWordCount(rawValue: configuration.length)!.entropyByteCount
            var entropy = try randomProvider(byteCount)
            defer { Self.clear(&entropy) }
            guard entropy.count == byteCount else {
                throw PasswordGeneratorError.invalidRandomByteCount(
                    expected: byteCount, actual: entropy.count
                )
            }
            components = try bip39.mnemonic(from: entropy)
        case .eff, .ascii, .pin, .hex:
            let alphabet: [String]
            switch configuration.mode {
            case .eff: alphabet = eff.words
            case .ascii: alphabet = Self.asciiAlphabet
            case .pin: alphabet = Self.pinAlphabet
            case .hex: alphabet = Self.hexAlphabet
            case .bip39: preconditionFailure("Handled separately")
            }
            components = try Self.uniformIndices(
                count: configuration.length,
                upperBound: alphabet.count,
                randomProvider: randomProvider
            ).map { alphabet[$0] }
        }
        return GeneratedPassword(
            components: components,
            text: components.joined(separator: configuration.mode.usesWords ? " " : ""),
            entropyBits: configuration.entropyBits,
            mode: configuration.mode
        )
    }

    /// Reject the incomplete final bucket instead of using biased modulo reduction.
    /// A bounded failure prevents a broken provider from hanging the application.
    static func uniformIndices(
        count: Int,
        upperBound: Int,
        randomProvider: (Int) throws -> [UInt8]
    ) throws -> [Int] {
        precondition(count >= 0 && upperBound > 0 && upperBound <= 65_536)
        let bytesPerCandidate = upperBound <= 256 ? 1 : 2
        let sourceRange = bytesPerCandidate == 1 ? 256 : 65_536
        let acceptanceLimit = sourceRange - sourceRange % upperBound
        var result: [Int] = []
        result.reserveCapacity(count)
        var consecutiveRejections = 0
        while result.count < count {
            let requestedCount = (count - result.count) * bytesPerCandidate
            var bytes = try randomProvider(requestedCount)
            defer { clear(&bytes) }
            guard bytes.count == requestedCount else {
                throw PasswordGeneratorError.invalidRandomByteCount(
                    expected: requestedCount, actual: bytes.count
                )
            }
            for offset in stride(from: 0, to: bytes.count, by: bytesPerCandidate) {
                let candidate = bytesPerCandidate == 1
                    ? Int(bytes[offset])
                    : (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
                guard candidate < acceptanceLimit else {
                    consecutiveRejections += 1
                    guard consecutiveRejections < 1_024 else {
                        throw PasswordGeneratorError.rejectionLimitExceeded
                    }
                    continue
                }
                result.append(candidate % upperBound)
                consecutiveRejections = 0
            }
        }
        return result
    }

    private static func clear(_ bytes: inout [UInt8]) {
        _ = bytes.withUnsafeMutableBytes {
            $0.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}
