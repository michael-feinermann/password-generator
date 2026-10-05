import Foundation
import Darwin

/// FIPS 202 SHA3 hashing and SHAKE256 extendable output.
/// https://doi.org/10.6028/NIST.FIPS.202
public enum SHA3 {
    private static let rateBytes512 = 72
    fileprivate static let rateBytesSHAKE256 = 136

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082,
        0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088,
        0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B,
        0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080,
        0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080,
        0x0000000080000001, 0x8000000080008008,
    ]

    /// Rotation offsets indexed as `x + 5 * y`.
    private static let rotationOffsets: [Int] = [
         0,  1, 62, 28, 27,
        36, 44,  6, 55, 20,
         3, 10, 43, 25, 39,
        41, 45, 15, 21,  8,
        18,  2, 61, 56, 14,
    ]

    /// Computes a 64-byte SHA3-512 digest.
    public static func hash512(_ data: Data) -> Data {
        var bytes = Array(data)
        defer { clear(&bytes) }
        var digest = hash512(bytes)
        defer { clear(&digest) }
        return Data(digest)
    }

    /// Computes a 64-byte SHA3-512 digest.
    public static func hash512(_ bytes: [UInt8]) -> [UInt8] {
        var state = initialState(bytes, rate: rateBytes512, suffix: 0x06)
        defer { clear(&state) }
        return (0..<64).map { byteIndex in
            UInt8(truncatingIfNeeded: state[byteIndex / 8] >> ((byteIndex % 8) * 8))
        }
    }

    /// Computes a byte-aligned SHAKE256 output, with a 512-bit capacity.
    public static func shake256(_ bytes: [UInt8], outputByteCount: Int) -> [UInt8] {
        precondition(outputByteCount >= 0)
        var stream = SHAKE256Stream(bytes)
        defer { stream.clear() }
        return stream.read(count: outputByteCount)
    }

    fileprivate static func initialState(
        _ bytes: [UInt8],
        rate: Int,
        suffix: UInt8
    ) -> [UInt64] {
        var state = [UInt64](repeating: 0, count: 25)
        var offset = 0

        while bytes.count - offset >= rate {
            absorb(bytes[offset..<(offset + rate)], into: &state)
            keccakF1600(&state)
            offset += rate
        }

        var finalBlock = [UInt8](repeating: 0, count: rate)
        defer { clear(&finalBlock) }
        let remainder = bytes.count - offset
        if remainder > 0 {
            finalBlock.replaceSubrange(0..<remainder, with: bytes[offset...])
        }

        // Delimited suffix: SHA3 = 0x06, SHAKE = 0x1f; final multi-rate padding bit.
        finalBlock[remainder] ^= suffix
        finalBlock[rate - 1] ^= 0x80
        absorb(finalBlock[...], into: &state)
        keccakF1600(&state)

        return state
    }

    private static func absorb(
        _ block: ArraySlice<UInt8>,
        into state: inout [UInt64]
    ) {
        for (byteIndex, byte) in block.enumerated() {
            let laneIndex = byteIndex / 8
            let shift = UInt64((byteIndex % 8) * 8)
            state[laneIndex] ^= UInt64(byte) << shift
        }
    }

    fileprivate static func keccakF1600(_ state: inout [UInt64]) {
        var columnParity = [UInt64](repeating: 0, count: 5)
        var thetaDelta = [UInt64](repeating: 0, count: 5)
        var permuted = [UInt64](repeating: 0, count: 25)
        defer {
            clear(&columnParity)
            clear(&thetaDelta)
            clear(&permuted)
        }

        for roundConstant in roundConstants {
            // Theta
            for x in 0..<5 {
                columnParity[x] = state[x]
                    ^ state[x + 5]
                    ^ state[x + 10]
                    ^ state[x + 15]
                    ^ state[x + 20]
            }
            for x in 0..<5 {
                thetaDelta[x] = columnParity[(x + 4) % 5]
                    ^ rotateLeft(columnParity[(x + 1) % 5], by: 1)
            }
            for y in 0..<5 {
                for x in 0..<5 {
                    state[x + 5 * y] ^= thetaDelta[x]
                }
            }

            // Rho and Pi: B[y, (2x + 3y) mod 5] = ROT(A[x, y], r[x, y]).
            for y in 0..<5 {
                for x in 0..<5 {
                    let sourceIndex = x + 5 * y
                    let destinationIndex = y + 5 * ((2 * x + 3 * y) % 5)
                    permuted[destinationIndex] = rotateLeft(
                        state[sourceIndex],
                        by: rotationOffsets[sourceIndex]
                    )
                }
            }

            // Chi
            for y in 0..<5 {
                let rowStart = 5 * y
                for x in 0..<5 {
                    state[rowStart + x] = permuted[rowStart + x]
                        ^ ((~permuted[rowStart + (x + 1) % 5])
                            & permuted[rowStart + (x + 2) % 5])
                }
            }

            // Iota
            state[0] ^= roundConstant
        }
    }

    private static func rotateLeft(_ value: UInt64, by offset: Int) -> UInt64 {
        guard offset != 0 else { return value }
        return (value << offset) | (value >> (64 - offset))
    }

    /// Best effort only: Swift may retain register values or earlier value-type copies.
    fileprivate static func clear<T>(_ array: inout [T]) {
        array.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}

/// An advancing SHAKE256 output stream. Call `clear()` when the stream is no longer needed.
/// Copying this value also copies its logical stream state; clearing cannot erase such copies.
public struct SHAKE256Stream {
    private var state: [UInt64]
    private var position = 0
    private var isCleared = false

    public init(_ bytes: [UInt8]) {
        state = SHA3.initialState(bytes, rate: SHA3.rateBytesSHAKE256, suffix: 0x1f)
    }

    /// Returns the next bytes without restarting the XOF for subsequent reads.
    public mutating func read(count: Int) -> [UInt8] {
        precondition(count >= 0)
        precondition(!isCleared, "A cleared SHAKE256 stream cannot be read.")
        var output = [UInt8](repeating: 0, count: count)
        for index in output.indices {
            if position == SHA3.rateBytesSHAKE256 {
                SHA3.keccakF1600(&state)
                position = 0
            }
            output[index] = UInt8(truncatingIfNeeded: state[position / 8] >> ((position % 8) * 8))
            position += 1
        }
        return output
    }

    public mutating func clear() {
        SHA3.clear(&state)
        position = 0
        isCleared = true
    }
}
