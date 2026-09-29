import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class PasswordGeneratorTests: XCTestCase {
    private var generator: PasswordGenerator!

    override func setUpWithError() throws {
        generator = try PasswordGenerator()
    }

    func testEFFOfficialListAndIntegrity() {
        XCTAssertEqual(generator.eff.words.count, 7_776)
        XCTAssertEqual(Set(generator.eff.words).count, 7_776)
        XCTAssertEqual(generator.eff.words.first, "abacus")
        XCTAssertEqual(generator.eff.words.last, "zoom")
        XCTAssertEqual(generator.eff.wordListIntegrity, EFF.expectedIntegrity)
    }

    func testEFFRejectsAlteredResource() {
        XCTAssertThrowsError(try EFF(verifiedWordListData: Data("11111\tabacus\n".utf8))) {
            XCTAssertEqual($0 as? EFFError, .wordListIntegrityFailure)
        }
    }

    func testAllAllowedBIP39LengthsAndEntropy() throws {
        for (words, bits) in [(12, 128), (15, 160), (18, 192), (21, 224), (24, 256)] {
            let configuration = GeneratorConfiguration(mode: .bip39, length: words)
            var requested: [Int] = []
            let password = try generator.generate(configuration: configuration) { count in
                requested.append(count)
                return [UInt8](repeating: 0, count: count)
            }
            XCTAssertEqual(requested, [bits / 8])
            XCTAssertEqual(password.components.count, words)
            XCTAssertEqual(password.entropyBits, Double(bits))
            XCTAssertEqual(password.text, password.components.joined(separator: " "))
            XCTAssertTrue(generator.bip39.validate(password.components))
        }
    }

    func testBoundaryLengthsAndExactAlphabets() throws {
        for mode in [GeneratorMode.eff, .ascii, .pin, .hex] {
            for length in [mode.lengthRange.lowerBound, mode.lengthRange.upperBound] {
                let password = try generator.generate(
                    configuration: GeneratorConfiguration(mode: mode, length: length),
                    randomProvider: { [UInt8](repeating: 0, count: $0) }
                )
                XCTAssertEqual(password.components.count, length)
                XCTAssertEqual(password.mode, mode)
                XCTAssertEqual(password.entropyBits, Double(length) * log2(Double(mode.alphabetSize!)))
                if mode == .eff {
                    XCTAssertEqual(password.text, Array(repeating: "abacus", count: length).joined(separator: " "))
                } else {
                    XCTAssertEqual(password.text.count, length)
                }
            }
        }
        XCTAssertEqual(PasswordGenerator.asciiAlphabet.count, 94)
        XCTAssertEqual(PasswordGenerator.asciiAlphabet.first, "!")
        XCTAssertEqual(PasswordGenerator.asciiAlphabet.last, "~")
        XCTAssertEqual(PasswordGenerator.asciiAlphabet.joined().utf8.map(Int.init), Array(33...126))
        XCTAssertEqual(PasswordGenerator.pinAlphabet.joined(), "0123456789")
        XCTAssertEqual(PasswordGenerator.hexAlphabet.joined(), "0123456789abcdef")
    }

    func testLeadingZeroesAndRepetitionsArePreserved() throws {
        let password = try generator.generate(
            configuration: GeneratorConfiguration(mode: .pin, length: 3),
            randomProvider: { [UInt8](repeating: 0, count: $0) }
        )
        XCTAssertEqual(password.text, "000")
        XCTAssertEqual(password.entropyBits, 3 * log2(10), accuracy: 1e-12)
    }

    func testInvalidLengthsNeverReadRandomSource() {
        for (mode, lengths) in [
            (GeneratorMode.bip39, [0, 11, 13, 14, 16, 17, 19, 20, 22, 23, 25]),
            (.eff, [-1, 0, 5, 61]),
            (.ascii, [0, 7, 257]),
            (.pin, [0, 2, 257]),
            (.hex, [-1, 0, 449, Int.max]),
        ] {
            for length in lengths {
                let configuration = GeneratorConfiguration(mode: mode, length: length)
                XCTAssertEqual(configuration.entropyBits, 0)
                XCTAssertThrowsError(try generator.generate(configuration: configuration) { _ in
                    XCTFail("Invalid configuration must not consume random bytes")
                    return []
                }) {
                    XCTAssertEqual($0 as? PasswordGeneratorError, .invalidLength(mode: mode, length: length))
                }
            }
        }
    }

    func testAllModesRejectShortAndLongRandomReads() {
        for mode in GeneratorMode.allCases {
            for delta in [-1, 1] {
                var expectedCount = 0
                XCTAssertThrowsError(try generator.generate(
                    configuration: GeneratorConfiguration(mode: mode, length: mode.defaultLength)
                ) { count in
                    expectedCount = count
                    return [UInt8](repeating: 0, count: count + delta)
                }) {
                    XCTAssertEqual(
                        $0 as? PasswordGeneratorError,
                        .invalidRandomByteCount(expected: expectedCount, actual: expectedCount + delta)
                    )
                }
            }
        }
    }

    func testRejectionUsesFreshBytesForNonPowerOfTwoAlphabets() throws {
        for mode in [GeneratorMode.eff, .ascii, .pin] {
            var calls = 0
            let password = try generator.generate(
                configuration: GeneratorConfiguration(mode: mode, length: mode.lengthRange.lowerBound)
            ) { count in
                calls += 1
                return [UInt8](repeating: calls == 1 ? 255 : 0, count: count)
            }
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(password.components.count, mode.lengthRange.lowerBound)
        }
    }

    func testCompleteByteDomainHasEqualAcceptedMultiplicity() throws {
        for alphabetSize in [10, 16, 94] {
            let acceptedCount = 256 - 256 % alphabetSize
            var supplied = false
            let indices = try PasswordGenerator.uniformIndices(count: 256, upperBound: alphabetSize) { count in
                if !supplied {
                    supplied = true
                    XCTAssertEqual(count, 256)
                    return Array(UInt8.min...UInt8.max)
                }
                // The rejected tail is replaced with valid zeroes, identifiable below.
                XCTAssertEqual(count, 256 - acceptedCount)
                return [UInt8](repeating: 0, count: count)
            }
            var multiplicities = [Int](repeating: 0, count: alphabetSize)
            for index in indices.prefix(acceptedCount) { multiplicities[index] += 1 }
            XCTAssertEqual(Set(multiplicities), [256 / alphabetSize])
        }
    }

    func testEFFCompleteTwoByteDomainHasEqualAcceptedMultiplicity() throws {
        let acceptedCount = 65_536 - 65_536 % EFF.wordCount
        var supplied = false
        let indices = try PasswordGenerator.uniformIndices(count: 65_536, upperBound: EFF.wordCount) { count in
            if !supplied {
                supplied = true
                XCTAssertEqual(count, 131_072)
                // Interleave both ends so this full-domain check does not look like
                // a failed source with thousands of consecutive rejected values.
                return (0..<32_768).flatMap { value in
                    [value, 65_535 - value].flatMap {
                        [UInt8($0 >> 8), UInt8(truncatingIfNeeded: $0)]
                    }
                }
            }
            return [UInt8](repeating: 0, count: count)
        }
        var multiplicities = [Int](repeating: 0, count: EFF.wordCount)
        for index in indices.prefix(acceptedCount) { multiplicities[index] += 1 }
        XCTAssertEqual(Set(multiplicities), [8])
    }

    func testPermanentlyUnusableRandomSourceFailsBoundedly() {
        var suppliedBytes = 0
        XCTAssertThrowsError(try generator.generate(
            configuration: GeneratorConfiguration(mode: .pin, length: 3)
        ) { count in
            suppliedBytes += count
            return [UInt8](repeating: 255, count: count)
        }) {
            XCTAssertEqual($0 as? PasswordGeneratorError, .rejectionLimitExceeded)
        }
        XCTAssertLessThanOrEqual(suppliedBytes, 1_026)
    }

    func testRandomProviderErrorPropagates() {
        enum TestError: Error { case unavailable }
        for mode in GeneratorMode.allCases {
            XCTAssertThrowsError(try generator.generate(
                configuration: GeneratorConfiguration(mode: mode, length: mode.defaultLength),
                randomProvider: { _ in throw TestError.unavailable }
            )) {
                XCTAssertTrue($0 is TestError)
            }
        }
    }

    func testHexOddLengthsRetainLeadingZeroAndExactEntropy() throws {
        for length in [1, 3, 63, 447, 448] {
            var requests: [Int] = []
            let password = try generator.generate(
                configuration: GeneratorConfiguration(mode: .hex, length: length)
            ) { count in
                requests.append(count)
                return (0..<count).map { UInt8(truncatingIfNeeded: $0) }
            }
            XCTAssertEqual(requests, [length])
            XCTAssertEqual(password.text.count, length)
            XCTAssertEqual(password.components.count, length)
            XCTAssertEqual(password.text.first, "0")
            XCTAssertTrue(password.text.allSatisfy { "0123456789abcdef".contains($0) })
            XCTAssertEqual(password.entropyBits, Double(length * 4))
            if length == 3 { XCTAssertEqual(password.text, "012") }
        }
    }

    func testHexAcceptsEveryByteValueWithoutRejection() throws {
        var requests = 0
        let password = try generator.generate(
            configuration: GeneratorConfiguration(mode: .hex, length: 256)
        ) { count in
            requests += 1
            XCTAssertEqual(count, 256)
            return Array(UInt8.min...UInt8.max)
        }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(password.text, String(repeating: "0123456789abcdef", count: 16))
        XCTAssertEqual(password.entropyBits, 1_024)
    }

    func testWordExportsPreserveCanonicalMnemonicAndEntropy() throws {
        for mode in [GeneratorMode.bip39, .eff] {
            let password = try generator.generate(
                configuration: GeneratorConfiguration(mode: mode, length: mode.defaultLength),
                randomProvider: { [UInt8](repeating: 0, count: $0) }
            )
            let original = password
            let defaultSeparator = mode == .bip39 ? " " : "-"
            XCTAssertEqual(password.exportText(), password.components.joined(separator: defaultSeparator))
            XCTAssertEqual(password.exportText(wordSeparator: nil), password.exportText())
            for separator in ["", " ", "-", "::", "💡", "\t", "\n", "abandon"] {
                XCTAssertEqual(
                    password.exportText(wordSeparator: separator, uppercaseHex: true),
                    password.components.joined(separator: separator)
                )
            }
            XCTAssertEqual(password, original)
            XCTAssertEqual(password.text, password.components.joined(separator: " "))
            if mode == .bip39 {
                XCTAssertTrue(generator.bip39.validate(password.components))
            }
        }
    }

    func testExportLetterCaseAppliesOnlyToHexWithoutChangingResult() throws {
        for mode in [GeneratorMode.hex, .ascii, .pin] {
            let password = try generator.generate(
                configuration: GeneratorConfiguration(mode: mode, length: mode.defaultLength),
                randomProvider: { [UInt8](repeating: 0xaf, count: $0) }
            )
            let original = password
            XCTAssertEqual(password.exportText(), password.text)
            XCTAssertEqual(password.exportText(wordSeparator: "separator"), password.text)
            XCTAssertEqual(
                password.exportText(wordSeparator: "", uppercaseHex: true),
                mode == .hex ? password.text.uppercased() : password.text
            )
            if mode == .hex {
                XCTAssertEqual(password.text, String(repeating: "f", count: mode.defaultLength))
                XCTAssertEqual(password.exportText(uppercaseHex: true), String(repeating: "F", count: mode.defaultLength))
            }
            XCTAssertEqual(password, original)
        }
    }
}
