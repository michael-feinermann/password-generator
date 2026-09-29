import XCTest
@testable import PasswordGeneratorCore

final class EntropyPoolTests: XCTestCase {
    func testRequires4096ActualRecordsBeforeReadingRandomBytes() throws {
        var requests: [Int] = []
        let pool = try EntropyPool { count in
            requests.append(count)
            return [UInt8](repeating: 0, count: count)
        }
        XCTAssertEqual(pool.eventCount, 0)
        for index in 0..<4_095 { pool.absorb(record(index)) }
        XCTAssertThrowsError(try pool.makeStream()) {
            XCTAssertEqual($0 as? EntropyError, .insufficientMouseEvents(actual: 4_095, required: 4_096))
        }
        XCTAssertTrue(requests.isEmpty)
        pool.absorb(record(4_095))
        XCTAssertEqual(pool.eventCount, 4_096)
        let stream = try pool.makeStream()
        defer { stream.clear() }
        XCTAssertEqual(try stream.bytes(count: 32).count, 32)
        XCTAssertEqual(requests.suffix(2), [192, 32])
    }

    func testBoundedRecordsContinueCollectingAndShuffleOnlyUsesRandomness() throws {
        var requests: [Int] = []
        let pool = try EntropyPool { count in
            requests.append(count)
            return [UInt8](repeating: 0, count: count)
        }
        for index in 0..<8_192 { pool.absorb(record(index)) }
        XCTAssertEqual(pool.eventCount, 4_096)
        XCTAssertEqual(pool.absorbedEventCount, 8_192)
        XCTAssertTrue(requests.isEmpty)
        try pool.shuffle()
        XCTAssertEqual(pool.shuffleCount, 2)
        XCTAssertEqual(requests, [4_096, 4_096, 4_096, 4_096])
        XCTAssertEqual(pool.eventCount, 4_096)
    }

    func testPoolFailsClosedAtShuffleMasterAndOutputRandomFailures() throws {
        for failedCount in [4_096, 192, 32] {
            let pool = try EntropyPool { count in
                [UInt8](repeating: 0, count: count == failedCount ? count - 1 : count)
            }
            for index in 0..<4_096 { pool.absorb(record(index)) }
            if failedCount == 32 {
                let stream = try pool.makeStream()
                XCTAssertThrowsError(try stream.bytes(count: 32))
                XCTAssertThrowsError(try stream.bytes(count: 16)) {
                    XCTAssertEqual($0 as? EntropyPoolError, .cleared)
                }
            } else {
                XCTAssertThrowsError(try pool.makeStream()) {
                    XCTAssertEqual($0 as? EntropyPoolError,
                                   .incorrectRandomByteCount(expected: failedCount, actual: failedCount - 1))
                }
            }
        }
    }

    func testShuffleRejectsBiasedTailAndIncludesCurrentPosition() throws {
        var requests = 0
        let pool = try EntropyPool { count in
            requests += 1
            // All 0xff is accepted for bound 4096 but rejected for bound 4095.
            // The retry then accepts zero and completes the permutation.
            return [UInt8](repeating: requests == 1 ? 0xff : 0, count: count)
        }
        for index in 0..<4_096 { pool.absorb(record(index)) }
        try pool.shuffle()
        XCTAssertEqual(requests, 5)
        XCTAssertEqual(pool.shuffleCount, 2)
    }

    func testBrokenShuffleSourceTerminatesAndClearPreventsReuse() throws {
        let pool = try EntropyPool { [UInt8](repeating: 0xff, count: $0) }
        for index in 0..<4_096 { pool.absorb(record(index)) }
        XCTAssertThrowsError(try pool.shuffle()) {
            XCTAssertEqual($0 as? EntropyPoolError, .randomSourceStalled)
        }
        pool.clear()
        XCTAssertEqual(pool.eventCount, 0)
        pool.absorb(record(0))
        XCTAssertEqual(pool.eventCount, 0)
        XCTAssertThrowsError(try pool.makeStream()) {
            XCTAssertEqual($0 as? EntropyPoolError, .cleared)
        }
    }

    func testFullPipelineAgainstOfficialSkeinReferenceAndPythonHashlib() throws {
        // Reference calculation: official Skein v1.3 C, Python hashlib SHA3/SHAKE.
        // Zero shuffle words give order [1, 2, ..., 4095, 0]. OS masks A5 and 5A.
        let pool = try EntropyPool { count in
            [UInt8](repeating: count == 4_096 ? 0 : (count == 192 ? 0xa5 : 0x5a), count: count)
        }
        for index in 0..<4_096 { pool.absorb(record(index)) }
        let stream = try pool.makeStream()
        defer { stream.clear() }
        // Cross both a SHAKE block boundary and a separate OS-random request.
        let actual = try stream.bytes(count: 137) + stream.bytes(count: 23)
        let expected = "bc2bfebcf30e1116d31fae1a232d906e8db4d7a0dc26fd83b7de69516f50252e50801737742373e4b454aad7f30205f846ad95b404f9bbe788e7b0e549a5e931c4898d7381302ea8bbfc2ac452280bd83d8d8e9416d5c8c77df202c17bc327d293fda3a253fbb7eb196617e8c3a3a77a233b4dae60ba6356cd5a6dffd5260cdc996388950bf8db7cab541535da93f08a421525c1be128ca41cb8d4dc5a8fb918"
        XCTAssertEqual(actual.map { String(format: "%02x", $0) }.joined(), expected)
    }

    func testSystemSourceValidatesCounts() throws {
        XCTAssertEqual(try SecureRandom.bytes(count: 192).count, 192)
        XCTAssertEqual(try SecureRandom.bytes(count: 0), [])
        XCTAssertThrowsError(try SecureRandom.bytes(count: -1))
    }

    private func record(_ index: Int) -> MouseEntropyRecord {
        MouseEntropyRecord(uptimeNanoseconds: UInt64(index + 1), eventTimestamp: Double(index) / 120,
                           x: Double(index % 127), y: Double(index % 83), deltaX: 1.2, deltaY: -0.8,
                           canvasWidth: 800, canvasHeight: 600, modifierFlags: 0, pressedMouseButtons: 0)
    }
}
