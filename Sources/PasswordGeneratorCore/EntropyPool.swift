import Foundation
import Darwin

public enum EntropyPoolError: LocalizedError, Equatable {
    case incorrectRandomByteCount(expected: Int, actual: Int)
    case invalidByteCount(Int)
    case cleared
    case randomSourceStalled

    public var errorDescription: String? {
        switch self {
        case let .incorrectRandomByteCount(expected, actual):
            "Die Zufallsquelle lieferte \(actual) statt \(expected) Byte."
        case let .invalidByteCount(count):
            "Ungültige Anzahl angeforderter Zufallsbytes: \(count)."
        case .cleared:
            "Der Zufallspool oder Byte-Stream wurde bereits verworfen."
        case .randomSourceStalled:
            "Die Zufallsquelle lieferte wiederholt keine verwendbaren Auswahlwerte."
        }
    }
}

/// A bounded pool of 4,096 actual mouse records. The permutation is stored
/// separately so new records can always replace the oldest captured event.
/// Access must be serialized by its owner (the app's MainActor).
public final class EntropyPool {
    public static let capacity = 4_096
    public static let requiredMouseEventCount = capacity
    public private(set) var shuffleCount = 0
    public private(set) var absorbedEventCount: UInt64 = 0
    public var eventCount: Int { records.count }

    private var records: [[UInt8]] = []
    private var order: [Int] = []
    private var writeOffset = 0
    private var isCleared = false
    private let randomProvider: (Int) throws -> [UInt8]

    public init(randomProvider: @escaping (Int) throws -> [UInt8] = SecureRandom.bytes) throws {
        self.randomProvider = randomProvider
        records.reserveCapacity(Self.capacity)
        order.reserveCapacity(Self.capacity)
        // The startup shuffle is a no-op for an empty pool. No hash is computed.
        try shuffle()
    }

    /// Capture the complete canonical event. No hashing occurs during collection.
    public func absorb(_ record: MouseEntropyRecord) {
        guard !isCleared else { return }
        var encoded: [UInt8] = [1]
        func append(_ value: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                encoded.append(UInt8(truncatingIfNeeded: value >> shift))
            }
        }
        append(absorbedEventCount)
        append(record.uptimeNanoseconds)
        append(record.eventTimestamp.bitPattern)
        append(record.x.bitPattern)
        append(record.y.bitPattern)
        append(record.deltaX.bitPattern)
        append(record.deltaY.bitPattern)
        append(record.canvasWidth.bitPattern)
        append(record.canvasHeight.bitPattern)
        append(record.modifierFlags)
        append(record.pressedMouseButtons)
        if records.count < Self.capacity {
            order.append(records.count)
            records.append(encoded)
        } else {
            wipePoolBytes(&records[writeOffset])
            records[writeOffset] = encoded
        }
        writeOffset = (writeOffset + 1) % Self.capacity
        absorbedEventCount &+= 1
    }

    /// Durstenfeld's in-place linear-time Fisher-Yates permutation of records.
    /// Indirection keeps insertion chronological even after repeated shuffles.
    public func shuffle() throws {
        guard !isCleared else { throw EntropyPoolError.cleared }
        var random = PoolRandomReader(provider: randomProvider)
        defer { random.clear() }
        if order.count > 1 {
            for index in stride(from: order.count - 1, through: 1, by: -1) {
                let selected = try random.uniform(upperBound: index + 1)
                order.swapAt(index, selected)
            }
        }
        shuffleCount &+= 1
    }

    /// Hashing happens only here, after the mandatory pre-generation shuffle.
    public func makeStream() throws -> PasswordByteStream {
        guard !isCleared else { throw EntropyPoolError.cleared }
        guard eventCount >= Self.requiredMouseEventCount else {
            throw EntropyError.insufficientMouseEvents(actual: eventCount, required: Self.requiredMouseEventCount)
        }
        try shuffle()
        var serializedPool: [UInt8] = []
        serializedPool.reserveCapacity(eventCount * 89)
        for index in order { serializedPool.append(contentsOf: records[index]) }
        var skeinDigest: [UInt8] = []
        var sha3Digest: [UInt8] = []
        var master: [UInt8] = []
        var operatingSystemBytes: [UInt8] = []
        defer {
            wipePoolBytes(&serializedPool)
            wipePoolBytes(&skeinDigest)
            wipePoolBytes(&sha3Digest)
            wipePoolBytes(&master)
            wipePoolBytes(&operatingSystemBytes)
        }
        skeinDigest = Skein.hash1024(serializedPool)
        sha3Digest = SHA3.hash512(serializedPool)
        master = skeinDigest + sha3Digest
        operatingSystemBytes = try checkedRandomBytes(count: 192, provider: randomProvider)
        for index in master.indices { master[index] ^= operatingSystemBytes[index] }
        return PasswordByteStream(master: master, randomProvider: randomProvider)
    }

    public func clear() {
        for index in records.indices { wipePoolBytes(&records[index]) }
        records.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
        writeOffset = 0
        absorbedEventCount = 0
        isCleared = true
    }

    deinit {
        for index in records.indices { wipePoolBytes(&records[index]) }
    }
}

/// Six separate SHAKE256 states, seeded with the six consecutive 32-byte
/// master fragments. They are consumed only once, including across refills.
public final class PasswordByteStream {
    private var streams: [SHAKE256Stream] = []
    private let randomProvider: (Int) throws -> [UInt8]
    private var isCleared = false

    init(master: [UInt8], randomProvider: @escaping (Int) throws -> [UInt8]) {
        precondition(master.count == 192)
        self.randomProvider = randomProvider
        for index in 0..<6 {
            var fragment = Array(master[(index * 32)..<((index + 1) * 32)])
            streams.append(SHAKE256Stream(fragment))
            wipePoolBytes(&fragment)
        }
    }

    public func bytes(count: Int) throws -> [UInt8] {
        guard !isCleared else { throw EntropyPoolError.cleared }
        guard (0...1_048_576).contains(count) else {
            throw EntropyPoolError.invalidByteCount(count)
        }
        var result = [UInt8](repeating: 0, count: count)
        do {
            for index in streams.indices {
                var fragment = streams[index].read(count: count)
                for offset in result.indices { result[offset] ^= fragment[offset] }
                wipePoolBytes(&fragment)
            }
            // Request fresh OS bytes after deriving the complete mixed material.
            var operatingSystemBytes = try checkedRandomBytes(count: count, provider: randomProvider)
            defer { wipePoolBytes(&operatingSystemBytes) }
            for index in result.indices { result[index] ^= operatingSystemBytes[index] }
            return result
        } catch {
            wipePoolBytes(&result)
            clear()
            throw error
        }
    }

    public func clear() {
        for index in streams.indices { streams[index].clear() }
        streams.removeAll(keepingCapacity: false)
        isCleared = true
    }

    deinit {
        for index in streams.indices { streams[index].clear() }
    }
}

/// Buffered OS calls avoid one syscall per swap without substituting a PRNG.
private struct PoolRandomReader {
    let provider: (Int) throws -> [UInt8]
    private var buffer: [UInt8] = []
    private var offset = 0

    init(provider: @escaping (Int) throws -> [UInt8]) { self.provider = provider }

    mutating func uniform(upperBound: Int) throws -> Int {
        let bound = UInt64(upperBound)
        let range = UInt64(UInt32.max) + 1
        let limit = range - range % bound
        for _ in 0..<4_096 {
            if offset + 4 > buffer.count {
                wipePoolBytes(&buffer)
                buffer = try checkedRandomBytes(count: 4_096, provider: provider)
                offset = 0
            }
            var value: UInt64 = 0
            for index in 0..<4 { value |= UInt64(buffer[offset + index]) << (index * 8) }
            offset += 4
            if value < limit { return Int(value % bound) }
        }
        throw EntropyPoolError.randomSourceStalled
    }

    mutating func clear() { wipePoolBytes(&buffer); offset = 0 }
}

private func checkedRandomBytes(count: Int, provider: (Int) throws -> [UInt8]) throws -> [UInt8] {
    var result = try provider(count)
    guard result.count == count else {
        let actual = result.count
        wipePoolBytes(&result)
        throw EntropyPoolError.incorrectRandomByteCount(expected: count, actual: actual)
    }
    return result
}

private func wipePoolBytes(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
        _ = memset_s(base, buffer.count, 0, buffer.count)
    }
}
