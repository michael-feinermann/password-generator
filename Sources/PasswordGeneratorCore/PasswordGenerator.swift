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
        case .eff: 6...128
        case .ascii: 8...256
        case .pin: 3...512
        case .hex: 1...512
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
        case .eff: 20
        case .ascii: 40
        case .pin: 6
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

    public var nominalSecurityLevel: NominalSecurityLevel {
        NominalSecurityLevel(nominalBits: entropyBits)
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
    private let storage: SensitiveBytes
    private let ranges: [Range<Int>]
    public let entropyBits: Double
    public let mode: GeneratorMode

    init(components: [String], entropyBits: Double, mode: GeneratorMode) {
        var offset = 0
        ranges = components.map { component in
            let start = offset
            offset += component.utf8.count
            return start..<offset
        }
        storage = SensitiveBytes(count: offset)
        storage.withUnsafeMutableBytes { bytes in
            var index = 0
            for component in components {
                for byte in component.utf8 { bytes[index] = byte; index += 1 }
            }
        }
        self.entropyBits = entropyBits
        self.mode = mode
    }

    /// Words for BIP-39/EFF, individual characters for ASCII/PIN/hex.
    /// Strings exist only when requested for display or export, never as stored state.
    public var components: [String] {
        storage.withLiveBytes { bytes in
            ranges.map { String(decoding: bytes[$0], as: UTF8.self) }
        } ?? []
    }

    public var text: String { exportText(wordSeparator: mode.usesWords ? " " : "") }
    public var componentCount: Int { storage.isCleared ? 0 : ranges.count }
    public var isCleared: Bool { storage.isCleared }

    /// Overwrites the one owned byte allocation. Copies of this wrapper are invalidated
    /// together. Previously exported Swift Strings or framework copies cannot be wiped here.
    public func clear() { storage.clear() }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mode == rhs.mode && lhs.entropyBits == rhs.entropyBits
            && lhs.ranges == rhs.ranges && lhs.isCleared == rhs.isCleared
            && lhs.text == rhs.text
    }

    public var nominalSecurityLevel: NominalSecurityLevel {
        NominalSecurityLevel(nominalBits: entropyBits)
    }

    /// Formats an existing result without generating new randomness or changing it.
    /// The default separator is a space for BIP-39 and a hyphen for EFF.
    /// Word separators are literal, including empty or multi-character strings.
    /// The fixed separator and hex letter case add no entropy to the result.
    public func exportText(wordSeparator: String? = nil, uppercaseHex: Bool = false) -> String {
        let separator = wordSeparator ?? (mode == .bip39 ? " " : "-")
        return storage.withLiveBytes { bytes in
            var output: [UInt8] = []
            output.reserveCapacity(bytes.count + (mode.usesWords ? max(0, ranges.count - 1) * separator.utf8.count : 0))
            defer { wipeNumericArray(&output) }
            for (index, range) in ranges.enumerated() {
                if mode.usesWords && index > 0 { output.append(contentsOf: separator.utf8) }
                for byte in bytes[range] {
                    output.append(mode == .hex && uppercaseHex && (97...102).contains(byte) ? byte - 32 : byte)
                }
            }
            return String(decoding: output, as: UTF8.self)
        } ?? ""
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
            var indices = try Self.uniformIndices(
                count: configuration.length,
                upperBound: alphabet.count,
                randomProvider: randomProvider
            )
            defer { wipeNumericArray(&indices) }
            components = indices.map { alphabet[$0] }
        }
        return GeneratedPassword(
            components: components,
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
        var succeeded = false
        defer { if !succeeded { wipeNumericArray(&result) } }
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
        succeeded = true
        return result
    }

    private static func clear(_ bytes: inout [UInt8]) {
        wipeNumericArray(&bytes)
    }
}
