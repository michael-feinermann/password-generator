import Foundation
import XCTest
import PasswordGeneratorCore
@testable import PasswordGeneratorApp

final class AttackCostPresentationTests: XCTestCase {
    func testTimeUnitBoundariesRemainReadable() {
        let presentation = AttackCostPresentation(language: .english)
        let examples: [(Double, String)] = [
            (-12, "1 ps"), (-9, "1 ns"), (-6, "1 µs"), (-3, "1 ms"),
            (0, "1 s"), (log10(60), "1 min"), (log10(3_600), "1 h"),
            (log10(86_400), "1 day"), (log10(31_557_600), "1 year")
        ]
        for (logarithm, expected) in examples {
            XCTAssertEqual(presentation.duration(log10Seconds: logarithm), expected)
        }
        XCTAssertEqual(presentation.duration(log10Seconds: -15), "1 × 10^-3 ps")
        XCTAssertEqual(presentation.duration(log10Seconds: log10(90)), "1.5 min")
        let german = AttackCostPresentation(language: .german)
        XCTAssertEqual(german.duration(log10Seconds: log10(86_400)), "1 Tag")
        XCTAssertEqual(german.duration(log10Seconds: log10(31_557_600)), "1 Jahr")
    }

    func testDefaultPINFullSearchDisplaysOnePicosecond() throws {
        let configuration = GeneratorConfiguration(mode: .pin, length: GeneratorMode.pin.defaultLength)
        let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: configuration.entropyBits))
        XCTAssertEqual(configuration.length, 6)
        XCTAssertEqual(AttackCostPresentation(language: .german).duration(log10Seconds: estimate.classic.log10Seconds), "1 ps")
    }

    func testPublished256BitExamplesUseLocalizedDecimalSeparators() throws {
        let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: 256))
        let german = AttackCostPresentation(language: .german)
        let english = AttackCostPresentation(language: .english)
        XCTAssertEqual(german.duration(log10Seconds: estimate.classic.log10Seconds), "3,67 × 10^51 Jahre")
        XCTAssertEqual(english.duration(log10Seconds: estimate.classic.log10Seconds), "3.67 × 10^51 years")
        XCTAssertEqual(german.duration(log10Seconds: estimate.grover.log10Seconds), "8,47 × 10^15 Jahre")
        XCTAssertEqual(english.duration(log10Seconds: estimate.grover.log10Seconds), "8.47 × 10^15 years")
    }

    func testMaximumHexEntropyFormatsWithoutOverflow() throws {
        let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: 2_048))
        let presentation = AttackCostPresentation(language: .english)
        XCTAssertEqual(presentation.duration(log10Seconds: estimate.classic.log10Seconds), "1.02 × 10^591 years")
        XCTAssertEqual(presentation.duration(log10Seconds: estimate.grover.log10Seconds), "4.47 × 10^285 years")
    }

    func testMissingOrNonfiniteDurationsUseNeutralDash() {
        for language in AppLanguage.allCases {
            let presentation = AttackCostPresentation(language: language)
            let values: [Double?] = [nil, .nan, .infinity, -.infinity]
            for value in values {
                XCTAssertEqual(presentation.duration(log10Seconds: value), "—")
            }
        }
    }

    func testRoundingScientificMantissaCarriesIntoExponent() {
        let presentation = AttackCostPresentation(language: .english)
        XCTAssertEqual(presentation.number(logarithm: log10(9.999) + 51), "1 × 10^52")
    }
}
