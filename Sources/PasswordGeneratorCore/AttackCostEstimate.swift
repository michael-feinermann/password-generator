import Foundation

/// Continuous estimates for an ideal, uniformly selected target in a 2^n space.
/// These are model comparisons, not measurements or guarantees about an attack.
public struct AttackCostEstimate: Equatable, Sendable {
    public struct SearchEstimate: Equatable, Sendable {
        /// Base-10 logarithms retain very large and very small modeled durations.
        public let log10Seconds: Double
        public let log10Years: Double
        /// The modeled search exceeds the assumed energy budget. Partial success
        /// can remain possible; this does not mean the target cannot be found.
        public let exceedsLandauerBudget: Bool
        /// The modeled duration exceeds the explicitly assumed comparison horizon.
        public let exceedsCosmicTimeHorizon: Bool
    }

    public struct Model: Sendable {
        public let classicalAttemptsPerSecond: Double = 1e18
        public let groverIterationsPerSecond: Double = 1e15
        public let temperatureKelvin: Double = 2.7
        public let boltzmannConstantJoulesPerKelvin: Double = 1.380649e-23
        public let energyBudgetJoules: Double = 3e71
        /// An extra model assumption, not a necessary cost of reversible Grover steps.
        public let erasedInformationBitsPerQuery: Double = 1
        /// An assumed comparison horizon, not a prediction of the universe's lifetime.
        public let cosmicTimeHorizonYears: Double = 1e106
        public let secondsPerYear: Double = 365.25 * 24 * 60 * 60

        fileprivate init() {}

        public var landauerEnergyPerQueryJoules: Double {
            boltzmannConstantJoulesPerKelvin * temperatureKelvin * log(2)
                * erasedInformationBitsPerQuery
        }

        public var classicalLandauerThresholdBits: Double {
            log2(energyBudgetJoules) - log2(landauerEnergyPerQueryJoules)
        }

        public var groverLandauerThresholdBits: Double {
            2 * (classicalLandauerThresholdBits - log2(Double.pi / 4))
        }

        public var classicalCosmicTimeThresholdBits: Double {
            log2(cosmicTimeHorizonYears) + log2(secondsPerYear)
                + log2(classicalAttemptsPerSecond)
        }

        public var groverCosmicTimeThresholdBits: Double {
            2 * (log2(cosmicTimeHorizonYears) + log2(secondsPerYear)
                + log2(groverIterationsPerSecond) - log2(Double.pi / 4))
        }
    }

    public static let standardModel = Model()

    public let nominalEntropyBits: Double
    public let classic: SearchEstimate
    public let grover: SearchEstimate
    /// Exact mean for a uniformly positioned target among N candidates searched
    /// without replacement: (N + 1) / (2 * attemptsPerSecond).
    public let classicalMeanLog10Seconds: Double

    /// Classical exhaustive search uses N attempts; this is not its mean time.
    /// Grover uses the continuous approximation (pi/4) * sqrt(N) for one target
    /// and near-unit success probability, without rounding iterations to integers.
    public init?(nominalEntropyBits: Double) {
        guard nominalEntropyBits.isFinite, nominalEntropyBits >= 0 else { return nil }
        self.nominalEntropyBits = nominalEntropyBits
        let model = Self.standardModel
        let secondsPerYearLog10 = log10(model.secondsPerYear)
        let classicLog10Seconds = nominalEntropyBits * log10(2)
            - log10(model.classicalAttemptsPerSecond)
        classicalMeanLog10Seconds = classicLog10Seconds
            + log10((1 + pow(2, -nominalEntropyBits)) / 2)
        let groverLog10Seconds = log10(Double.pi / 4)
            + (nominalEntropyBits / 2) * log10(2)
            - log10(model.groverIterationsPerSecond)
        classic = SearchEstimate(
            log10Seconds: classicLog10Seconds,
            log10Years: classicLog10Seconds - secondsPerYearLog10,
            exceedsLandauerBudget: nominalEntropyBits > model.classicalLandauerThresholdBits,
            exceedsCosmicTimeHorizon: nominalEntropyBits > model.classicalCosmicTimeThresholdBits
        )
        grover = SearchEstimate(
            log10Seconds: groverLog10Seconds,
            log10Years: groverLog10Seconds - secondsPerYearLog10,
            exceedsLandauerBudget: nominalEntropyBits > model.groverLandauerThresholdBits,
            exceedsCosmicTimeHorizon: nominalEntropyBits > model.groverCosmicTimeThresholdBits
        )
    }
}
