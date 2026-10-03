import CommonCrypto
import Darwin
import Foundation

public enum AES256CTRStreamError: LocalizedError, Equatable {
    case invalidKeyByteCount(Int)
    case invalidCounterByteCount(Int)
    case invalidByteCount(Int)
    case cryptographicFailure(Int32)
    case unexpectedBlockByteCount(Int)
    case counterExhausted
    case cleared

    public var errorDescription: String? {
        switch self {
        case let .invalidKeyByteCount(count): "AES-256 benötigt 32 Schlüsselbytes, erhalten: \(count)."
        case let .invalidCounterByteCount(count): "AES-CTR benötigt 16 Zählerbytes, erhalten: \(count)."
        case let .invalidByteCount(count): "Ungültige AES-CTR-Ausgabelänge: \(count)."
        case let .cryptographicFailure(status): "AES-CTR konnte nicht ausgeführt werden (Status \(status))."
        case let .unexpectedBlockByteCount(count): "AES lieferte \(count) statt 16 Blockbytes."
        case .counterExhausted: "Der AES-CTR-Zähler ist ausgeschöpft."
        case .cleared: "Der AES-CTR-Stream wurde bereits verworfen."
        }
    }
}

/// AES-256 counter-mode keystream, using CommonCrypto only for AES block encryption.
/// The entire 128-bit counter is incremented big endian. The application starts at
/// zero under each newly derived key; reusing the same key would repeat the stream.
/// Access must be serialized. Reference semantics prevent accidental state copies.
public final class AES256CTRStream {
    private var cryptor: CCCryptorRef?
    private var counter: [UInt8]
    private var block = [UInt8](repeating: 0, count: 16)
    private var blockOffset = 16
    private var counterExhausted = false
    private var isCleared = false

    public init(key: [UInt8], initialCounter: [UInt8] = [UInt8](repeating: 0, count: 16)) throws {
        guard key.count == kCCKeySizeAES256 else { throw AES256CTRStreamError.invalidKeyByteCount(key.count) }
        guard initialCounter.count == kCCBlockSizeAES128 else {
            throw AES256CTRStreamError.invalidCounterByteCount(initialCounter.count)
        }
        counter = initialCounter
        let status = key.withUnsafeBytes {
            CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            $0.baseAddress, key.count, nil, &cryptor)
        }
        guard status == kCCSuccess, cryptor != nil else {
            clear()
            throw AES256CTRStreamError.cryptographicFailure(status)
        }
    }

    public func read(count: Int) throws -> [UInt8] {
        guard !isCleared else { throw AES256CTRStreamError.cleared }
        guard (0...1_048_576).contains(count) else { throw AES256CTRStreamError.invalidByteCount(count) }
        var result = [UInt8](repeating: 0, count: count)
        do {
            var written = 0
            while written < count {
                if blockOffset == block.count { try refill() }
                let copied = min(count - written, block.count - blockOffset)
                for index in 0..<copied {
                    result[written + index] = block[blockOffset + index]
                    block[blockOffset + index] = 0
                }
                written += copied
                blockOffset += copied
            }
            return result
        } catch {
            wipeAESBytes(&result)
            clear()
            throw error
        }
    }

    private func refill() throws {
        guard !counterExhausted else { throw AES256CTRStreamError.counterExhausted }
        guard let cryptor else { throw AES256CTRStreamError.cleared }
        var moved = 0
        let status = counter.withUnsafeBytes { input in
            block.withUnsafeMutableBytes { output in
                CCCryptorUpdate(cryptor, input.baseAddress, input.count, output.baseAddress, output.count, &moved)
            }
        }
        guard status == kCCSuccess else { throw AES256CTRStreamError.cryptographicFailure(status) }
        guard moved == 16 else { throw AES256CTRStreamError.unexpectedBlockByteCount(moved) }
        blockOffset = 0
        // The final all-ones counter is usable once, including its buffered tail.
        // Never encrypt the wrapped zero counter under this same key.
        for index in counter.indices.reversed() {
            counter[index] &+= 1
            if counter[index] != 0 { return }
        }
        counterExhausted = true
    }

    public func clear() {
        if let cryptor { CCCryptorRelease(cryptor) }
        cryptor = nil
        wipeAESBytes(&counter)
        wipeAESBytes(&block)
        blockOffset = block.count
        counterExhausted = true
        isCleared = true
    }

    deinit { clear() }
}

private func wipeAESBytes(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
        _ = memset_s(base, buffer.count, 0, buffer.count)
    }
}
