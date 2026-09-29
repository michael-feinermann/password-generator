import Foundation
import Security

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
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &result)
        guard status == errSecSuccess else {
            _ = result.withUnsafeMutableBytes {
                $0.initializeMemory(as: UInt8.self, repeating: 0)
            }
            throw EntropyError.secureRandomFailure(status)
        }
        return result
    }
}
