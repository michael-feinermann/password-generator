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
        for fixture in try pipelineFixtures() {
            let source = PipelineRandomSource(style: fixture.randomStyle)
            let pool = try EntropyPool(randomProvider: source.bytes(count:))
            for index in 0..<fixture.recordCount {
                pool.absorb(record(index))
                if fixture.shuffleAfterRecords.contains(index + 1) { try pool.shuffle() }
            }
            let stream = try pool.makeStream()
            defer { stream.clear() }
            XCTAssertEqual(pool.eventCount, 4_096, fixture.name)
            XCTAssertEqual(pool.absorbedEventCount, UInt64(fixture.recordCount), fixture.name)
            XCTAssertEqual(pool.shuffleCount, 2 + fixture.shuffleAfterRecords.count, fixture.name)
            XCTAssertEqual(source.requests, fixture.randomRequestByteCounts, fixture.name)

            // These cumulative positions cross both XOF block boundaries, including
            // positions 127/128/129 and 135/136/137. OS bytes advance independently.
            var output: [UInt8] = []
            for count in [0, 127, 1, 1, 6, 1, 1, 119, 128, 136, 137, 367] {
                output += try stream.bytes(count: count)
            }
            XCTAssertEqual(output, try hexBytes(fixture.output), fixture.name)
            XCTAssertEqual(source.outputOffset, 1_024, fixture.name)
        }
    }

    func testDigestBitShuffleAgainstIndependentIntermediateFixtures() throws {
        for fixture in try pipelineFixtures() {
            let source = PipelineRandomSource(style: fixture.randomStyle)
            source.shuffleBufferIndex = fixture.recordShuffleRandomRequests
            var digest = try hexBytes(fixture.digest)
            let originalPopcount = digest.reduce(0) { $0 + $1.nonzeroBitCount }
            try EntropyPool.shuffleDigestBits(&digest, randomProvider: source.bytes(count:))
            XCTAssertEqual(digest, try hexBytes(fixture.shuffledDigest), fixture.name)
            XCTAssertEqual(digest.reduce(0) { $0 + $1.nonzeroBitCount }, originalPopcount, fixture.name)
        }
    }

    func testDigestBitShuffleIdentitySameByteAndCrossByteSwaps() throws {
        var identity = (0..<192).map { UInt8(truncatingIfNeeded: $0 * 73 + 19) }
        let original = identity
        XCTAssertEqual(try shuffleWithSelections(&identity), [4_096, 4_096])
        XCTAssertEqual(identity, original)

        var sameByte = [UInt8](repeating: 0, count: 192)
        sameByte[0] = 1 << 2
        _ = try shuffleWithSelections(&sameByte, overrides: [7: 2])
        XCTAssertEqual(sameByte, [0x80] + [UInt8](repeating: 0, count: 191))

        var crossByte = [UInt8](repeating: 0, count: 192)
        crossByte[0] = 1
        _ = try shuffleWithSelections(&crossByte, overrides: [8: 0])
        XCTAssertEqual(crossByte, [0, 1] + [UInt8](repeating: 0, count: 190))
    }

    func testZeroShuffleWordsRotateTheEntire1536BitArray() throws {
        var bytes = (0..<192).map { UInt8(truncatingIfNeeded: $0 * 73 + 19) }
        let original = bytes
        let expected = original.indices.map { index in
            (original[index] >> 1) | ((original[(index + 1) % original.count] & 1) << 7)
        }
        try EntropyPool.shuffleDigestBits(&bytes) { [UInt8](repeating: 0, count: $0) }
        XCTAssertEqual(bytes, expected)
    }

    func testDigestBitShuffleRejectsIncompleteUInt32Bucket() throws {
        var bytes = [UInt8](repeating: 0, count: 192)
        bytes[191] = 0x80
        let original = bytes
        // At bound 1536, UInt32.max is in the incomplete final bucket. Rejecting
        // it then selecting the current index must preserve this final one-bit.
        _ = try shuffleWithSelections(&bytes, rejectedPrefix: [UInt32.max])
        XCTAssertEqual(bytes, original)
    }

    func testDigestBitShuffleFailsOnEitherRandomBufferAndBoundsStalledSource() {
        for failedRequest in [1, 2] {
            var requests = 0
            var bytes = [UInt8](repeating: 0x55, count: 192)
            XCTAssertThrowsError(try EntropyPool.shuffleDigestBits(&bytes) { count in
                requests += 1
                return [UInt8](repeating: 0, count: count - (requests == failedRequest ? 1 : 0))
            }) {
                XCTAssertEqual($0 as? EntropyPoolError, .incorrectRandomByteCount(expected: 4_096, actual: 4_095))
            }
            XCTAssertEqual(requests, failedRequest)
        }
        var requests = 0
        var bytes = [UInt8](repeating: 0x55, count: 192)
        XCTAssertThrowsError(try EntropyPool.shuffleDigestBits(&bytes) { count in
            requests += 1
            return [UInt8](repeating: 0xff, count: count)
        }) {
            XCTAssertEqual($0 as? EntropyPoolError, .randomSourceStalled)
        }
        XCTAssertEqual(requests, 4)
    }

    func testPoolAbortsWhenEitherDigestShuffleBufferFails() throws {
        // Zero candidates consume four record-shuffle buffers, then two digest
        // buffers. Failure must stop before the master or output mask is read.
        for failedRequest in [5, 6] {
            var requests: [Int] = []
            let pool = try EntropyPool { count in
                requests.append(count)
                return [UInt8](repeating: 0, count: count - (requests.count == failedRequest ? 1 : 0))
            }
            for index in 0..<4_096 { pool.absorb(record(index)) }
            XCTAssertThrowsError(try pool.makeStream()) {
                XCTAssertEqual($0 as? EntropyPoolError, .incorrectRandomByteCount(expected: 4_096, actual: 4_095))
            }
            XCTAssertEqual(requests, [Int](repeating: 4_096, count: failedRequest))
        }
    }

    func testByteStreamChunkingIsIndependentOfReadLengthsAtBothBlockBoundaries() throws {
        for fixture in try pipelineFixtures() {
            let expected = try hexBytes(fixture.output)
            let master = try hexBytes(fixture.master)
            for firstRead in [127, 128, 129, 135, 136, 137, 1_024] {
                let source = PipelineRandomSource(style: fixture.randomStyle)
                let stream = PasswordByteStream(master: master, randomProvider: source.outputBytes(count:))
                defer { stream.clear() }
                let first = try stream.bytes(count: firstRead)
                XCTAssertEqual(try stream.bytes(count: 0), [])
                let rest = try stream.bytes(count: expected.count - firstRead)
                XCTAssertEqual(first + rest, expected, "\(fixture.name), split at \(firstRead)")
                XCTAssertEqual(source.outputOffset, expected.count)
            }
        }
    }

    func testOutputRandomFailureAfterSuccessfulReadClearsEveryStream() throws {
        enum RandomFailure: Error { case unavailable }
        for malformedReturn in [false, true] {
            var calls = 0
            let stream = PasswordByteStream(master: [UInt8](repeating: 0x42, count: 192)) { count in
                calls += 1
                if calls == 2 {
                    if malformedReturn { return [UInt8](repeating: 0, count: count - 1) }
                    throw RandomFailure.unavailable
                }
                return [UInt8](repeating: 0, count: count)
            }
            XCTAssertEqual(try stream.bytes(count: 129).count, 129)
            XCTAssertThrowsError(try stream.bytes(count: 137))
            XCTAssertThrowsError(try stream.bytes(count: 1)) {
                XCTAssertEqual($0 as? EntropyPoolError, .cleared)
            }
            XCTAssertEqual(calls, 2)
        }
    }

    func testAllFormatsAgainstIndependentPipelineAndSamplingFixtures() throws {
        let generator = try PasswordGenerator()
        for fixture in try pipelineFixtures() {
            let master = try hexBytes(fixture.master)
            for expected in fixture.passwords {
                let mode = try XCTUnwrap(GeneratorMode(rawValue: expected.mode))
                let source = PipelineRandomSource(style: fixture.randomStyle)
                let stream = PasswordByteStream(master: master, randomProvider: source.outputBytes(count:))
                defer { stream.clear() }
                let configuration = GeneratorConfiguration(mode: mode, length: expected.length)
                let password = try generator.generate(configuration: configuration, randomProvider: stream.bytes(count:))
                XCTAssertEqual(password.text, expected.text, "\(fixture.name), \(expected.mode), \(expected.length)")
                XCTAssertEqual(password.components.count, expected.length)
                XCTAssertEqual(password.entropyBits, configuration.entropyBits)
                if mode == .bip39 { XCTAssertTrue(generator.bip39.validate(password.components)) }
            }
        }
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

    private func pipelineFixtures() throws -> [PipelineFixture] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "pipeline_expected", withExtension: "json"))
        let fixtures = try JSONDecoder().decode(PipelineFixtures.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.version, 2)
        XCTAssertEqual(fixtures.cases.count, 3)
        return fixtures.cases
    }

    private func hexBytes(_ text: String) throws -> [UInt8] {
        XCTAssertTrue(text.count.isMultiple(of: 2))
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(try XCTUnwrap(UInt8(text[index..<next], radix: 16)))
            index = next
        }
        return bytes
    }

    private func shuffleWithSelections(
        _ bytes: inout [UInt8],
        overrides: [Int: Int] = [:],
        rejectedPrefix: [UInt32] = []
    ) throws -> [Int] {
        let candidates = rejectedPrefix + stride(from: 1_535, through: 1, by: -1).map {
            UInt32(overrides[$0] ?? $0)
        }
        let encoded = candidates.flatMap { candidate in
            stride(from: 0, to: 32, by: 8).map { UInt8(truncatingIfNeeded: candidate >> $0) }
        }
        var cursor = 0
        var requests: [Int] = []
        try EntropyPool.shuffleDigestBits(&bytes) { count in
            requests.append(count)
            return (0..<count).map { _ in
                defer { cursor += 1 }
                return cursor < encoded.count ? encoded[cursor] : 0
            }
        }
        return requests
    }
}

private struct PipelineFixtures: Decodable {
    let version: Int
    let cases: [PipelineFixture]
}

private struct PipelineFixture: Decodable {
    let name: String
    let recordCount: Int
    let shuffleAfterRecords: [Int]
    let randomStyle: String
    let recordShuffleRandomRequests: Int
    let randomRequestByteCounts: [Int]
    let digest: String
    let shuffledDigest: String
    let master: String
    let output: String
    let passwords: [PipelinePasswordFixture]
}

private struct PipelinePasswordFixture: Decodable {
    let mode: String
    let length: Int
    let text: String
}

private final class PipelineRandomSource {
    let style: String
    var shuffleBufferIndex = 0
    private(set) var outputOffset = 0
    private(set) var requests: [Int] = []
    private var masterRead = false

    init(style: String) { self.style = style }

    func bytes(count: Int) -> [UInt8] {
        requests.append(count)
        if !masterRead {
            if count == 4_096 { return shuffleBuffer() }
            precondition(count == 192)
            masterRead = true
            return (0..<count).map { style == "zero" ? 0xa5 : UInt8(truncatingIfNeeded: $0 * 37 + 0xa5) }
        }
        return advanceOutput(count: count)
    }

    func outputBytes(count: Int) -> [UInt8] {
        requests.append(count)
        return advanceOutput(count: count)
    }

    private func advanceOutput(count: Int) -> [UInt8] {
        defer { outputOffset += count }
        return (0..<count).map { style == "zero" ? 0x5a : UInt8(truncatingIfNeeded: (outputOffset + $0) * 53 + 0x5a) }
    }

    private func shuffleBuffer() -> [UInt8] {
        defer { shuffleBufferIndex += 1 }
        guard style != "zero" else { return [UInt8](repeating: 0, count: 4_096) }
        return (0..<1_024).flatMap { index -> [UInt8] in
            let value: UInt32
            if index < 2 { value = UInt32.max }
            else if index == 2 { value = 0 }
            else {
                value = UInt32(truncatingIfNeeded: shuffleBufferIndex * 1_024 + index)
                    &* 0x9e3779b9 &+ 0x7f4a7c15
            }
            return stride(from: 0, to: 32, by: 8).map { UInt8(truncatingIfNeeded: value >> $0) }
        }
    }
}
