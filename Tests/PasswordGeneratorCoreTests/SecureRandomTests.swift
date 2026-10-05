import Security
import XCTest
@testable import PasswordGeneratorCore

final class SecureRandomTests: XCTestCase {
    func testPartialProviderFailureErasesTheEntireStillOwnedBuffer() {
        var bytes = [UInt8](repeating: 0x7b, count: 64)
        var calls = 0
        XCTAssertThrowsError(try SecureRandom.fill(&bytes) { buffer in
            calls += 1
            for index in 0..<17 { buffer[index] = UInt8(index + 1) }
            return errSecNotAvailable
        }) { error in
            guard case let EntropyError.secureRandomFailure(status) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(status, errSecNotAvailable)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(bytes, [UInt8](repeating: 0, count: 64))
    }

    func testSuccessfulProviderOutputIsPreserved() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        try SecureRandom.fill(&bytes) { buffer in
            for index in buffer.indices { buffer[index] = UInt8(index) }
            return errSecSuccess
        }
        XCTAssertEqual(bytes, Array(UInt8(0)...UInt8(31)))
    }

    func testInvalidCountsAreRejectedAndZeroNeedsNoRandomBytes() throws {
        XCTAssertEqual(try SecureRandom.bytes(count: 0), [])
        for count in [-1, 1_048_577, Int.max] {
            XCTAssertThrowsError(try SecureRandom.bytes(count: count)) {
                XCTAssertEqual($0 as? EntropyPoolError, .invalidByteCount(count))
            }
        }
    }
}
