import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class AttackCostEstimateTests: XCTestCase {
    func testDurationsAgainstIndependentHighPrecisionGoldenValues() throws {
        // Independently calculated with Decimal precision 100 and a decimal pi.
        // Columns: bits, classical log10(s), classical log10(years),
        // Grover log10(s), Grover log10(years).
        let cases: [(Double, Double, Double, Double, Double)] = [
            (128, 20.531839444989593, 13.032735477904365,
             4.161009603860968, -3.3380943632242597),
            (256, 59.063678889979186, 51.56457492289396,
             23.426929326355764, 15.927825359270537),
            (1024, 290.25471555991674, 282.7556115928315,
             139.02244766132454, 131.52334369423932),
            (2048, 598.5094311198335, 591.0103271527483,
             293.1498054412829, 285.6507014741977),
        ]
        for (bits, classicSeconds, classicYears, groverSeconds, groverYears) in cases {
            let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: bits))
            XCTAssertEqual(estimate.classic.log10Seconds, classicSeconds, accuracy: 1e-12)
            XCTAssertEqual(estimate.classic.log10Years, classicYears, accuracy: 1e-12)
            XCTAssertEqual(estimate.grover.log10Seconds, groverSeconds, accuracy: 1e-12)
            XCTAssertEqual(estimate.grover.log10Years, groverYears, accuracy: 1e-12)
        }
    }

    func testEnergyAndTimeThresholdsAgainstIndependentGoldenValues() {
        let model = AttackCostEstimate.standardModel
        XCTAssertEqual(model.landauerEnergyPerQueryJoules, 2.5838809965708514e-23, accuracy: 1e-37)
        XCTAssertEqual(model.classicalLandauerThresholdBits, 312.47666379344914, accuracy: 1e-12)
        XCTAssertEqual(model.groverLandauerThresholdBits, 625.6503353279536, accuracy: 1e-12)
        XCTAssertEqual(model.classicalCosmicTimeThresholdBits, 436.8305679207746, accuracy: 1e-12)
        XCTAssertEqual(model.groverCosmicTimeThresholdBits, 854.4265750132804, accuracy: 1e-12)
        XCTAssertEqual(model.cosmicTimeHorizonYears, 1e106)
        XCTAssertEqual(model.secondsPerYear, 31_557_600)
    }

    func testAllThresholdsAreStrictAndUseFractionalBits() throws {
        let model = AttackCostEstimate.standardModel
        let boundaries: [(Double, KeyPath<AttackCostEstimate, Bool>)] = [
            (model.classicalLandauerThresholdBits, \.classic.exceedsLandauerBudget),
            (model.groverLandauerThresholdBits, \.grover.exceedsLandauerBudget),
            (model.classicalCosmicTimeThresholdBits, \.classic.exceedsCosmicTimeHorizon),
            (model.groverCosmicTimeThresholdBits, \.grover.exceedsCosmicTimeHorizon),
        ]
        for (threshold, flag) in boundaries {
            let before = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: threshold.nextDown))
            let at = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: threshold))
            let after = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: threshold.nextUp))
            XCTAssertFalse(before[keyPath: flag])
            XCTAssertFalse(at[keyPath: flag])
            XCTAssertTrue(after[keyPath: flag])
        }
    }

    func testIntegerTransitionsDistinguishEnergyBudgetFromTimeHorizon() throws {
        let cases: [(Double, Bool, Bool, Bool, Bool)] = [
            (312, false, false, false, false),
            (313, true, false, false, false),
            (436, true, false, false, false),
            (437, true, false, true, false),
            (625, true, false, true, false),
            (626, true, true, true, false),
            (854, true, true, true, false),
            (855, true, true, true, true),
            (2048, true, true, true, true),
        ]
        for (bits, classicEnergy, groverEnergy, classicTime, groverTime) in cases {
            let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: bits))
            XCTAssertEqual(estimate.classic.exceedsLandauerBudget, classicEnergy, "bits=\(bits)")
            XCTAssertEqual(estimate.grover.exceedsLandauerBudget, groverEnergy, "bits=\(bits)")
            XCTAssertEqual(estimate.classic.exceedsCosmicTimeHorizon, classicTime, "bits=\(bits)")
            XCTAssertEqual(estimate.grover.exceedsCosmicTimeHorizon, groverTime, "bits=\(bits)")
        }
    }

    func testSixDigitPINRetainsSubPicosecondModelTime() throws {
        let configuration = GeneratorConfiguration(mode: .pin, length: 6)
        let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: configuration.entropyBits))
        XCTAssertEqual(estimate.classic.log10Seconds, -12, accuracy: 1e-12)
        XCTAssertEqual(estimate.classicalMeanLog10Seconds, -12.301029561369716, accuracy: 1e-12)
        XCTAssertEqual(estimate.grover.log10Seconds, -12.104910118633829, accuracy: 1e-12)
        XCTAssertFalse(estimate.classic.exceedsLandauerBudget)
        XCTAssertFalse(estimate.grover.exceedsCosmicTimeHorizon)
    }

    func testOneHexCharacterMeanIncludesTheSuccessfulAttempt() throws {
        let configuration = GeneratorConfiguration(mode: .hex, length: 1)
        let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: configuration.entropyBits))
        // Sixteen candidates take an average of 8.5 attempts, not 8 attempts.
        // Decimal-precision reference: log10(8.5e-18 seconds).
        XCTAssertEqual(estimate.classicalMeanLog10Seconds, -17.070581074285707, accuracy: 1e-12)
    }

    func testInvalidInputsAreRejectedAndEveryFormatMaximumStaysFinite() throws {
        for bits in [-1, -Double.leastNonzeroMagnitude, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertNil(AttackCostEstimate(nominalEntropyBits: bits))
        }
        let zero = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: 0))
        XCTAssertEqual(zero.classic.log10Seconds, -18)
        XCTAssertEqual(zero.classicalMeanLog10Seconds, -18)
        for mode in GeneratorMode.allCases {
            let configuration = GeneratorConfiguration(mode: mode, length: mode.lengthRange.upperBound)
            let estimate = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: configuration.entropyBits))
            XCTAssertTrue(estimate.classicalMeanLog10Seconds.isFinite)
            for cost in [estimate.classic, estimate.grover] {
                XCTAssertTrue(cost.log10Seconds.isFinite)
                XCTAssertTrue(cost.log10Years.isFinite)
            }
        }
        let largest = try XCTUnwrap(AttackCostEstimate(nominalEntropyBits: Double.greatestFiniteMagnitude))
        XCTAssertTrue(largest.classic.log10Seconds.isFinite)
        XCTAssertTrue(largest.grover.log10Seconds.isFinite)
        XCTAssertTrue(largest.classicalMeanLog10Seconds.isFinite)
    }
}
