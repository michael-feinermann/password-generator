import XCTest
@testable import PasswordGeneratorCore

final class NominalSecurityLevelTests: XCTestCase {
    func testExactThresholdsAndAdjacentRepresentableValues() {
        let boundaries: [(Double, NominalSecurityLevel, NominalSecurityLevel)] = [
            (128, .below128, .atLeast128),
            (256, .atLeast128, .atLeast256),
            (1024, .atLeast256, .atLeast1024),
        ]
        for (threshold, before, atAndAfter) in boundaries {
            XCTAssertEqual(NominalSecurityLevel(nominalBits: threshold.nextDown), before)
            XCTAssertEqual(NominalSecurityLevel(nominalBits: threshold), atAndAfter)
            XCTAssertEqual(NominalSecurityLevel(nominalBits: threshold.nextUp), atAndAfter)
        }
    }

    func testZeroAndInvalidValuesReceiveLowestBand() {
        for bits in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(NominalSecurityLevel(nominalBits: bits), .below128)
        }
        let invalid = GeneratorConfiguration(mode: .hex, length: 513)
        XCTAssertEqual(invalid.entropyBits, 0)
        XCTAssertEqual(invalid.nominalSecurityLevel, .below128)
    }

    func testHexSelectionSpaceCrossesEveryBandAtExactLengths() {
        let cases: [(Int, NominalSecurityLevel)] = [
            (31, .below128), (32, .atLeast128),
            (63, .atLeast128), (64, .atLeast256),
            (255, .atLeast256), (256, .atLeast1024), (512, .atLeast1024),
        ]
        for (length, level) in cases {
            let configuration = GeneratorConfiguration(mode: .hex, length: length)
            XCTAssertEqual(configuration.nominalSecurityLevel, level)
        }
    }
}
