import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class CryptographicKnownAnswerTests: XCTestCase {
    func testSkein1024OfficialGoldenAndReferenceBoundaryVectors() throws {
        let vectors = try loadVectors("skein1024_vectors")
        XCTAssertEqual(vectors.count, 49)
        for vector in vectors {
            XCTAssertEqual(Skein.hash1024(vector.messageBytes), vector.outputBytes, vector.label)
        }
    }

    func testSHA3512NISTByteOrientedVectors() throws {
        let vectors = try loadVectors("sha3_nist_vectors")
        XCTAssertEqual(vectors.count, 81)
        for vector in vectors {
            XCTAssertEqual(SHA3.hash512(vector.messageBytes), vector.outputBytes, vector.label)
        }
    }

    func testSHAKE256NISTAndIndependentLongOutputVectors() throws {
        let vectors = try loadVectors("shake_nist_vectors")
        XCTAssertEqual(vectors.count, 538)
        for vector in vectors {
            let expected = vector.outputBytes
            XCTAssertEqual(
                SHA3.shake256(vector.messageBytes, outputByteCount: expected.count),
                expected,
                vector.label
            )
        }
    }

    func testSHAKE256StreamingAcrossAbsorbAndSqueezeBoundaries() throws {
        let vectors = try loadVectors("shake_nist_vectors").filter { $0.outputBytes.count > 136 }
        for vector in vectors {
            var stream = SHAKE256Stream(vector.messageBytes)
            defer { stream.clear() }
            let expected = vector.outputBytes
            var actual = [UInt8]()
            // Includes zero reads and reads ending at / straddling a rate boundary.
            let sizes = [0, 1, 134, 0, 1, 1, 135, 0, 137, 1, 103]
            for size in sizes {
                actual += stream.read(count: min(size, expected.count - actual.count))
            }
            actual += stream.read(count: expected.count - actual.count)
            XCTAssertEqual(actual, expected, vector.label)
        }
    }

    func testSHAKE256CanReturnAnEmptyOutputAndClearTwice() {
        XCTAssertEqual(SHA3.shake256([], outputByteCount: 0), [])
        var stream = SHAKE256Stream([])
        XCTAssertEqual(stream.read(count: 0), [])
        XCTAssertEqual(stream.read(count: 32), SHA3.shake256([], outputByteCount: 32))
        stream.clear()
        stream.clear()
    }

    private struct Vector: Decodable {
        let label: String
        let message: String
        let output: String

        var messageBytes: [UInt8] { Self.decodeHex(message) }
        var outputBytes: [UInt8] { Self.decodeHex(output) }

        private static func decodeHex(_ string: String) -> [UInt8] {
            let characters = Array(string.utf8)
            precondition(characters.count % 2 == 0)
            return stride(from: 0, to: characters.count, by: 2).map {
                UInt8(String(decoding: characters[$0..<($0 + 2)], as: UTF8.self), radix: 16)!
            }
        }
    }

    private func loadVectors(_ name: String) throws -> [Vector] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    }
}
