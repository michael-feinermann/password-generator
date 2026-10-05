import XCTest
@testable import PasswordGeneratorCore

final class AESCTRTests: XCTestCase {
    func testNISTAndIndependentOpenSSLKnownAnswers() throws {
        for vector in try vectors() {
            let stream = try AES256CTRStream(key: hex(vector.key), initialCounter: hex(vector.counter))
            defer { stream.clear() }
            let plaintext = try hex(vector.plaintext)
            let keyStream = try stream.read(count: plaintext.count)
            XCTAssertEqual(zip(plaintext, keyStream).map(^), try hex(vector.ciphertext), vector.name)
        }
    }

    func testEverySplitRetainsUnusedBlockBytesAndZeroReadsDoNotAdvance() throws {
        for vector in try vectors() {
            let expected = try zip(hex(vector.plaintext), hex(vector.ciphertext)).map(^)
            for split in [0, 1, 15, 16, 17, 127, 128, 129, 135, 136, 137, 255, 256, 257]
                where split <= expected.count {
                let stream = try AES256CTRStream(key: hex(vector.key), initialCounter: hex(vector.counter))
                defer { stream.clear() }
                let first = try stream.read(count: split)
                XCTAssertEqual(try stream.read(count: 0), [])
                let rest = try stream.read(count: expected.count - split)
                XCTAssertEqual(first + rest, expected, "\(vector.name), split \(split)")
            }
            let bytewise = try AES256CTRStream(key: hex(vector.key), initialCounter: hex(vector.counter))
            defer { bytewise.clear() }
            var actual: [UInt8] = []
            for _ in expected.indices { actual += try bytewise.read(count: 1) }
            XCTAssertEqual(actual, expected, vector.name)
        }
    }

    func testDefaultCounterIsZero() throws {
        let vector = try XCTUnwrap(vectors().first { $0.name == "ascending-key-zero-counter" })
        let stream = try AES256CTRStream(key: hex(vector.key))
        defer { stream.clear() }
        XCTAssertEqual(try stream.read(count: 4_097), try hex(vector.ciphertext))
    }

    func testLastCounterTailIsAvailableButWrapFailsClosed() throws {
        let vector = try XCTUnwrap(vectors().first { $0.name == "final-two-counters" })
        let stream = try AES256CTRStream(key: hex(vector.key), initialCounter: hex(vector.counter))
        let first = try stream.read(count: 17)
        XCTAssertEqual(try stream.read(count: 0), [])
        let last = try stream.read(count: 15)
        XCTAssertEqual(first + last, try hex(vector.ciphertext))
        XCTAssertEqual(try stream.read(count: 0), [])
        XCTAssertThrowsError(try stream.read(count: 1)) {
            XCTAssertEqual($0 as? AES256CTRStreamError, .counterExhausted)
        }
        XCTAssertThrowsError(try stream.read(count: 0)) {
            XCTAssertEqual($0 as? AES256CTRStreamError, .cleared)
        }
    }

    func testRequestCrossingOverflowReturnsNoPartialOutputAndClears() throws {
        let stream = try AES256CTRStream(key: [UInt8](repeating: 0, count: 32),
                                        initialCounter: [UInt8](repeating: 0xff, count: 16))
        XCTAssertThrowsError(try stream.read(count: 17)) {
            XCTAssertEqual($0 as? AES256CTRStreamError, .counterExhausted)
        }
        XCTAssertThrowsError(try stream.read(count: 1)) {
            XCTAssertEqual($0 as? AES256CTRStreamError, .cleared)
        }
    }

    func testInvalidParametersDoNotSilentlyTruncateAndInvalidReadsDoNotAdvance() throws {
        for count in [0, 16, 24, 31, 33] {
            XCTAssertThrowsError(try AES256CTRStream(key: [UInt8](repeating: 0, count: count))) {
                XCTAssertEqual($0 as? AES256CTRStreamError, .invalidKeyByteCount(count))
            }
        }
        for count in [0, 15, 17] {
            XCTAssertThrowsError(try AES256CTRStream(key: [UInt8](repeating: 0, count: 32),
                                                  initialCounter: [UInt8](repeating: 0, count: count))) {
                XCTAssertEqual($0 as? AES256CTRStreamError, .invalidCounterByteCount(count))
            }
        }
        let vector = try XCTUnwrap(vectors().first { $0.name == "zero-key-zero-counter" })
        let stream = try AES256CTRStream(key: hex(vector.key))
        defer { stream.clear() }
        for count in [-1, 1_048_577, Int.max] {
            XCTAssertThrowsError(try stream.read(count: count)) {
                XCTAssertEqual($0 as? AES256CTRStreamError, .invalidByteCount(count))
            }
        }
        XCTAssertEqual(try stream.read(count: 257), try hex(vector.ciphertext))
    }

    func testClearIsIdempotentAndPreventsBufferedOutputReuse() throws {
        let stream = try AES256CTRStream(key: [UInt8](repeating: 0, count: 32))
        XCTAssertEqual(try stream.read(count: 1).count, 1)
        stream.clear()
        stream.clear()
        for label in ["counter", "block"] {
            let bytes = try XCTUnwrap(
                Mirror(reflecting: stream).children.first { $0.label == label }?.value as? [UInt8]
            )
            XCTAssertEqual(bytes, [UInt8](repeating: 0, count: 16))
        }
        for count in [0, 1, 16] {
            XCTAssertThrowsError(try stream.read(count: count)) {
                XCTAssertEqual($0 as? AES256CTRStreamError, .cleared)
            }
        }
    }

    private func vectors() throws -> [AESCTRVector] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "aes256ctr_vectors", withExtension: "json"))
        let result = try JSONDecoder().decode([AESCTRVector].self, from: Data(contentsOf: url))
        XCTAssertEqual(result.count, 5)
        return result
    }

    private func hex(_ string: String) throws -> [UInt8] {
        try stride(from: 0, to: string.count, by: 2).map { offset in
            let start = string.index(string.startIndex, offsetBy: offset)
            let end = string.index(start, offsetBy: 2)
            return try XCTUnwrap(UInt8(string[start..<end], radix: 16))
        }
    }
}

private struct AESCTRVector: Decodable {
    let name: String
    let key: String
    let counter: String
    let plaintext: String
    let ciphertext: String
}
