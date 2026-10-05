import Foundation
import Security
import Darwin

public enum EntropyError: LocalizedError, Equatable {
    case insufficientMouseEvents(actual: Int, required: Int)
    case emptyMouseTranscript
    case secureRandomFailure(OSStatus)
    case invalidRandomByteCount(Int)

    public var errorDescription: String? {
        switch self {
        case let .insufficientMouseEvents(actual, required):
            "Es wurden erst \(actual) von \(required) Mausbewegungen erfasst."
        case .emptyMouseTranscript:
            "Die Mausdaten fehlen."
        case let .secureRandomFailure(status):
            "macOS konnte keine sicheren Zufallsbytes liefern (Status \(status))."
        case let .invalidRandomByteCount(count):
            "Die Zufallsquelle lieferte \(count) statt 64 Byte."
        }
    }
}

public enum SecureRandom {
    public static func bytes(count: Int) throws -> [UInt8] {
        guard (0...1_048_576).contains(count) else {
            throw EntropyPoolError.invalidByteCount(count)
        }
        if count == 0 { return [] }
        var result = [UInt8](repeating: 0, count: count)
        try fill(&result) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return result
    }

    /// Erases even a partially filled buffer before reporting a provider failure.
    /// The caller owns this buffer; this does not erase copies made by a provider.
    static func fill(
        _ bytes: inout [UInt8],
        using provider: (UnsafeMutableRawBufferPointer) -> OSStatus
    ) throws {
        try bytes.withUnsafeMutableBytes { buffer in
            let status = provider(buffer)
            guard status == errSecSuccess else {
                if let base = buffer.baseAddress, !buffer.isEmpty {
                    _ = memset_s(base, buffer.count, 0, buffer.count)
                }
                throw EntropyError.secureRandomFailure(status)
            }
        }
    }
}
