import XCTest
import Darwin
@testable import PasswordGeneratorCore

final class SensitiveMemoryTests: XCTestCase {
    func testOwnedBufferIsOverwrittenWhileStillAllocatedAndAllAliasesObserveIt() {
        for count in [0, 6, 256, 364_544] {
            let buffer = SensitiveBytes(count: count)
            let alias = buffer
            buffer.withUnsafeMutableBytes { bytes in
                for index in bytes.indices { bytes[index] = 0xa5 }
            }
            XCTAssertFalse(buffer.isCleared)
            buffer.withUnsafeBytes { bytes in
                XCTAssertEqual(Int(bitPattern: bytes.baseAddress!) % Int(getpagesize()), 0)
            }
            buffer.clear()
            XCTAssertTrue(alias.isCleared)
            alias.withUnsafeBytes { XCTAssertTrue($0.allSatisfy { $0 == 0 }) }
            XCTAssertNil(alias.withLiveBytes { _ in true })
            alias.clear()
            buffer.withUnsafeBytes { XCTAssertTrue($0.allSatisfy { $0 == 0 }) }
        }
    }

    func testMasterIsOverwrittenBeforeStreamIsReturnedAndDerivedStreamRemainsUsable() throws {
        let master = SensitiveBytes(count: 256)
        master.withUnsafeMutableBytes { bytes in
            for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index) }
        }
        let stream = try PasswordByteStream(master: master) { [UInt8](repeating: 0, count: $0) }
        XCTAssertTrue(master.isCleared)
        master.withUnsafeBytes { XCTAssertTrue($0.allSatisfy { $0 == 0 }) }
        XCTAssertEqual(try stream.bytes(count: 97).count, 97)
        stream.clear()
        XCTAssertThrowsError(try stream.bytes(count: 1)) {
            XCTAssertEqual($0 as? EntropyPoolError, .cleared)
        }
    }

    func testClearingGeneratedPasswordInvalidatesEveryWrapperAndExportFormat() throws {
        let generator = try PasswordGenerator()
        for mode in GeneratorMode.allCases {
            let password = try generator.generate(
                configuration: GeneratorConfiguration(mode: mode, length: mode.defaultLength),
                randomProvider: { [UInt8](repeating: 0, count: $0) }
            )
            let alias = password
            XCTAssertEqual(password.componentCount, mode.defaultLength)
            XCTAssertFalse(alias.isCleared)
            XCTAssertFalse(password.text.isEmpty)
            password.clear()
            XCTAssertTrue(alias.isCleared)
            XCTAssertEqual(alias.componentCount, 0)
            XCTAssertEqual(alias.components, [])
            XCTAssertEqual(alias.text, "")
            XCTAssertEqual(alias.exportText(wordSeparator: "::", uppercaseHex: true), "")
            alias.clear()
            XCTAssertEqual(password.text, "")
        }
    }
}
