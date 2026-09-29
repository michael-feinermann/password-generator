import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class SkeinXOFTests: XCTestCase {
    func testMatchesIndependentCReferenceAcrossMessageAndOutputBlockBoundaries() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 22)
        for vector in vectors {
            var stream = Skein1024XOFStream(vector.messageBytes)
            defer { stream.clear() }
            let expected = vector.outputBytes
            XCTAssertEqual(stream.read(count: expected.count), expected, vector.label)
        }
    }

    func testChunkedReadsAndZeroReadsMatchIndependentCReference() throws {
        for vector in try loadVectors() {
            var stream = Skein1024XOFStream(vector.messageBytes)
            defer { stream.clear() }
            let expected = vector.outputBytes
            var actual = [UInt8]()
            // Ends on, immediately before, and immediately after 128-byte boundaries.
            let chunks = [0, 1, 0, 126, 0, 1, 0, 1, 127, 128, 129, 255, 256, 257]
            var index = 0
            while actual.count < expected.count {
                let count = min(chunks[index % chunks.count], expected.count - actual.count)
                actual += stream.read(count: count)
                index += 1
            }
            XCTAssertEqual(stream.read(count: 0), [])
            XCTAssertEqual(actual, expected, vector.label)
        }
    }

    func testRequestedReadLengthDoesNotChangeXOFConfiguration() throws {
        let vector = try XCTUnwrap(loadVectors().last)
        let expected = vector.outputBytes
        XCTAssertEqual(expected.count, 32_769)
        // The final three cases also cross the OUT-counter 255 -> 256 boundary.
        let counts = [0, 1, 7, 63, 127, 128, 129, 255, 256, 257, 383, 384, 385,
                      511, 512, 513, 1_023, 1_024, 1_025, 32_767, 32_768, 32_769]
        for count in counts {
            var stream = Skein1024XOFStream(vector.messageBytes)
            defer { stream.clear() }
            XCTAssertEqual(stream.read(count: count), Array(expected.prefix(count)), "length \(count)")
        }
    }

    func testXOFIsDomainSeparatedFromFixed1024BitHash() {
        for message in [[UInt8](), Array(UInt8(0)...UInt8(127))] {
            var stream = Skein1024XOFStream(message)
            defer { stream.clear() }
            XCTAssertNotEqual(stream.read(count: 128), Skein.hash1024(message))
        }
    }

    func testCopiedStreamsHaveIndependentPositionsAndClearIsIdempotent() throws {
        let vector = try XCTUnwrap(loadVectors().first)
        let expected = vector.outputBytes
        var stream = Skein1024XOFStream(vector.messageBytes)
        XCTAssertEqual(stream.read(count: 127), Array(expected.prefix(127)))
        var copy = stream
        defer { copy.clear() }
        XCTAssertEqual(stream.read(count: 130), Array(expected[127..<257]))
        stream.clear()
        stream.clear()
        XCTAssertEqual(copy.read(count: 0), [])
        XCTAssertEqual(copy.read(count: 258), Array(expected[127..<385]))
    }

    private struct Vector: Decodable {
        let label: String
        let message: String
        let output: String

        var messageBytes: [UInt8] { Self.decodeHex(message) }
        var outputBytes: [UInt8] { Self.decodeHex(output) }

        private static func decodeHex(_ string: String) -> [UInt8] {
            let characters = Array(string.utf8)
            precondition(characters.count.isMultiple(of: 2))
            return stride(from: 0, to: characters.count, by: 2).map {
                UInt8(String(decoding: characters[$0..<($0 + 2)], as: UTF8.self), radix: 16)!
            }
        }
    }

    private func loadVectors() throws -> [Vector] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "skein1024_xof_vectors", withExtension: "json"))
        return try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    }
}
