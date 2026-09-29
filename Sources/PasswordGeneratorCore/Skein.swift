import Darwin

/// Byte-oriented Skein-1024-1024, version 1.3, sequential unkeyed hashing.
/// The configuration, UBI and Threefish steps follow sections 3.3–3.5 of:
/// https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf
public enum Skein {
    private static let blockByteCount = 128
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
        var chain = [UInt64](repeating: 0, count: wordCount)
        defer { clear(&chain) }

        // 32-byte configuration: "SHA3", version 1, output length 1024 bits,
        // and zero tree parameters (sequential mode). Integers are little-endian.
        var configuration = [UInt8](repeating: 0, count: 32)
        configuration[0] = 0x53
        configuration[1] = 0x48
        configuration[2] = 0x41
        configuration[3] = 0x33
        configuration[4] = 1
        configuration[9] = 4
        ubi(configuration, type: 4, chain: &chain)
        ubi(bytes, type: 48, chain: &chain)

        // A 1024-bit digest needs only output block counter 0, encoded in 8 bytes.
        ubi([UInt8](repeating: 0, count: 8), type: 63, chain: &chain)
        return (0..<blockByteCount).map {
            UInt8(truncatingIfNeeded: chain[$0 / 8] >> (($0 % 8) * 8))
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
    private static func clear<T>(_ array: inout [T]) {
        array.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}
