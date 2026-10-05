import Darwin

/// Byte-oriented Skein-1024-1024, version 1.3, sequential unkeyed hashing.
/// The configuration, UBI and Threefish steps follow sections 3.3–3.5 of:
/// https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf
public enum Skein {
    fileprivate static let blockByteCount = 128
    private static let wordCount = 16
    private static let keyScheduleConstant: UInt64 = 0x1BD11BDAA9FC1A22

    private static let permutation = [0, 9, 2, 13, 6, 11, 4, 15, 10, 7, 12, 3, 14, 5, 8, 1]
    private static let rotations = [
        [24, 13, 8, 47, 8, 17, 22, 37],
        [38, 19, 10, 55, 49, 18, 23, 52],
        [33, 4, 51, 13, 34, 41, 59, 17],
        [5, 20, 48, 41, 47, 28, 16, 25],
        [41, 9, 37, 31, 12, 47, 44, 30],
        [16, 34, 56, 51, 4, 53, 42, 41],
        [31, 44, 47, 46, 19, 42, 44, 25],
        [9, 48, 35, 52, 23, 31, 37, 20],
    ]

    /// Computes exactly 128 bytes. This is not Skein-1024 with a truncated output setting.
    public static func hash1024(_ bytes: [UInt8]) -> [UInt8] {
        var chain = messageChain(bytes, outputBitCount: 1024)
        defer { clear(&chain) }

        return outputBlock(chain: chain, counter: 0)
    }

    fileprivate static func messageChain(_ bytes: [UInt8], outputBitCount: UInt64) -> [UInt64] {
        var chain = [UInt64](repeating: 0, count: wordCount)

        // 32-byte configuration: "SHA3", version 1, configured output length,
        // and zero tree parameters (sequential mode). Integers are little-endian.
        var configuration = [UInt8](repeating: 0, count: 32)
        configuration[0] = 0x53
        configuration[1] = 0x48
        configuration[2] = 0x41
        configuration[3] = 0x33
        configuration[4] = 1
        for index in 0..<8 {
            configuration[8 + index] = UInt8(truncatingIfNeeded: outputBitCount >> (index * 8))
        }
        ubi(configuration, type: 4, chain: &chain)
        ubi(bytes, type: 48, chain: &chain)
        return chain
    }

    fileprivate static func outputBlock(chain: [UInt64], counter: UInt64) -> [UInt8] {
        // Each output counter starts from the same finalized message chain.
        var outputChain = chain
        defer { clear(&outputChain) }
        let counterBytes = (0..<8).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) }
        ubi(counterBytes, type: 63, chain: &outputChain)
        return (0..<blockByteCount).map {
            UInt8(truncatingIfNeeded: outputChain[$0 / 8] >> (($0 % 8) * 8))
        }
    }

    private static func ubi(_ bytes: [UInt8], type: UInt64, chain: inout [UInt64]) {
        var block = [UInt64](repeating: 0, count: wordCount)
        defer { clear(&block) }
        var offset = 0
        repeat {
            clear(&block)
            let consumed = min(blockByteCount, bytes.count - offset)
            for index in 0..<consumed {
                block[index / 8] |= UInt64(bytes[offset + index]) << ((index % 8) * 8)
            }

            let first = offset == 0
            offset += consumed
            let final = offset == bytes.count
            var flags = type << 56
            if first { flags |= UInt64(1) << 62 }
            if final { flags |= UInt64(1) << 63 }

            // Swift arrays are limited to Int.max bytes, so the upper 32 bits
            // of the 96-bit UBI position field are always zero here.
            compress(block, position: UInt64(offset), flags: flags, chain: &chain)
        } while offset < bytes.count
    }

    private static func compress(
        _ block: [UInt64],
        position: UInt64,
        flags: UInt64,
        chain: inout [UInt64]
    ) {
        var key = [UInt64](repeating: 0, count: wordCount + 1)
        var tweak = [position, flags, position ^ flags]
        var state = block
        var permuted = [UInt64](repeating: 0, count: wordCount)
        defer {
            clear(&key)
            clear(&tweak)
            clear(&state)
            clear(&permuted)
        }
        key[wordCount] = keyScheduleConstant
        for index in 0..<wordCount {
            key[index] = chain[index]
            key[wordCount] ^= chain[index]
        }

        // Threefish-1024 has 80 rounds and 21 subkey injections.
        for round in 0..<80 {
            if round % 4 == 0 {
                injectSubkey(round / 4, key: key, tweak: tweak, state: &state)
            }
            for pair in 0..<(wordCount / 2) {
                let even = pair * 2
                let odd = even + 1
                state[even] = state[even] &+ state[odd]
                let rotation = rotations[round % 8][pair]
                state[odd] = ((state[odd] << rotation) | (state[odd] >> (64 - rotation))) ^ state[even]
            }
            for index in 0..<wordCount {
                permuted[index] = state[permutation[index]]
            }
            // Copy elements rather than sharing storage and reallocating at the next round.
            for index in 0..<wordCount {
                state[index] = permuted[index]
            }
        }
        injectSubkey(20, key: key, tweak: tweak, state: &state)
        for index in 0..<wordCount {
            chain[index] = state[index] ^ block[index]
        }
    }

    private static func injectSubkey(
        _ subkey: Int,
        key: [UInt64],
        tweak: [UInt64],
        state: inout [UInt64]
    ) {
        for index in 0..<wordCount {
            state[index] = state[index] &+ key[(subkey + index) % (wordCount + 1)]
        }
        state[13] = state[13] &+ tweak[subkey % 3]
        state[14] = state[14] &+ tweak[(subkey + 1) % 3]
        state[15] = state[15] &+ UInt64(subkey)
    }

    /// Best effort only: Swift may retain register values or earlier value-type copies.
    fileprivate static func clear<T>(_ array: inout [T]) {
        array.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}

/// Byte-oriented Skein-1024 XOF using the fixed `N_o = 2^64 - 1` configuration
/// described in Skein 1.3 section 4.12. Input is an unkeyed message, not a MAC key.
/// Successive reads share the same output prefix, unlike separately configured
/// fixed-length Skein hashes. Call `clear()` when the stream is no longer needed.
/// Copying this value copies its logical stream state; clearing cannot erase copies.
public struct Skein1024XOFStream {
    // The final seven configured bits are omitted by this byte-aligned API.
    private static let maximumOutputBytes = UInt64.max / 8

    private var chain: [UInt64]
    private var block: [UInt8] = []
    private var position = 0
    private var nextBlockCounter: UInt64 = 0
    private var emittedByteCount: UInt64 = 0
    private var isCleared = false

    public init(_ bytes: [UInt8]) {
        chain = Skein.messageChain(bytes, outputBitCount: UInt64.max)
    }

    /// Returns subsequent output bytes without changing the configured output length.
    /// At most floor((2^64 - 1) / 8) complete bytes may be read from one stream.
    public mutating func read(count: Int) -> [UInt8] {
        precondition(count >= 0)
        precondition(!isCleared, "A cleared Skein XOF stream cannot be read.")
        precondition(UInt64(count) <= Self.maximumOutputBytes - emittedByteCount)
        var output = [UInt8](repeating: 0, count: count)
        var outputOffset = 0
        while outputOffset < count {
            if position == block.count {
                Skein.clear(&block)
                block = Skein.outputBlock(chain: chain, counter: nextBlockCounter)
                // The configured byte limit prevents counter overflow.
                nextBlockCounter += 1
                position = 0
            }
            let copied = min(block.count - position, count - outputOffset)
            for index in 0..<copied {
                output[outputOffset + index] = block[position + index]
            }
            // Already returned bytes are no longer needed by this stream.
            block.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                _ = memset_s(base.advanced(by: position), buffer.count - position, 0, copied)
            }
            position += copied
            outputOffset += copied
        }
        emittedByteCount += UInt64(count)
        return output
    }

    public mutating func clear() {
        Skein.clear(&chain)
        Skein.clear(&block)
        position = 0
        nextBlockCounter = 0
        emittedByteCount = 0
        isCleared = true
    }
}
