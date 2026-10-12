namespace PasswordGenerator.Core;

public enum NominalSecurityLevel { Below128, AtLeast128, AtLeast256, AtLeast1024 }
public static class NominalSecurityLevelExtensions
{
    public static NominalSecurityLevel FromBits(double bits) => !double.IsFinite(bits) || bits < 128 ? NominalSecurityLevel.Below128
        : bits < 256 ? NominalSecurityLevel.AtLeast128 : bits < 1024 ? NominalSecurityLevel.AtLeast256 : NominalSecurityLevel.AtLeast1024;
}

/// <summary>Model comparison for an ideal uniform target; no measured entropy or attack guarantee.</summary>
public sealed record AttackCostEstimate
{
    public sealed record SearchEstimate(double Log10Seconds, double Log10Years, bool ExceedsLandauerBudget, bool ExceedsCosmicTimeHorizon);
    public sealed class Model
    {
        public double ClassicalAttemptsPerSecond => 1e18;
        public double GroverIterationsPerSecond => 1e15;
        public double TemperatureKelvin => 2.7;
        public double BoltzmannConstantJoulesPerKelvin => 1.380649e-23;
        public double EnergyBudgetJoules => 3e71;
        public double ErasedInformationBitsPerQuery => 1;
        public double CosmicTimeHorizonYears => 1e106;
        public double SecondsPerYear => 365.25 * 24 * 60 * 60;
        public double LandauerEnergyPerQueryJoules => BoltzmannConstantJoulesPerKelvin * TemperatureKelvin * Math.Log(2) * ErasedInformationBitsPerQuery;
        public double ClassicalLandauerThresholdBits => Math.Log2(EnergyBudgetJoules) - Math.Log2(LandauerEnergyPerQueryJoules);
        public double GroverLandauerThresholdBits => 2 * (ClassicalLandauerThresholdBits - Math.Log2(Math.PI / 4));
        public double ClassicalCosmicTimeThresholdBits => Math.Log2(CosmicTimeHorizonYears) + Math.Log2(SecondsPerYear) + Math.Log2(ClassicalAttemptsPerSecond);
        public double GroverCosmicTimeThresholdBits => 2 * (Math.Log2(CosmicTimeHorizonYears) + Math.Log2(SecondsPerYear) + Math.Log2(GroverIterationsPerSecond) - Math.Log2(Math.PI / 4));
    }
    public static Model StandardModel { get; } = new();
    public double NominalEntropyBits { get; }
    public SearchEstimate Classic { get; }
    public SearchEstimate Grover { get; }
    public double ClassicalMeanLog10Seconds { get; }
    public AttackCostEstimate(double nominalEntropyBits)
    {
        if (!double.IsFinite(nominalEntropyBits) || nominalEntropyBits < 0) throw new ArgumentOutOfRangeException(nameof(nominalEntropyBits));
        NominalEntropyBits = nominalEntropyBits;
        var model = StandardModel;
        double yearLog = Math.Log10(model.SecondsPerYear);
        double classicLog = nominalEntropyBits * Math.Log10(2) - Math.Log10(model.ClassicalAttemptsPerSecond);
        double groverLog = Math.Log10(Math.PI / 4) + nominalEntropyBits / 2 * Math.Log10(2) - Math.Log10(model.GroverIterationsPerSecond);
        ClassicalMeanLog10Seconds = classicLog + Math.Log10((1 + Math.Pow(2, -nominalEntropyBits)) / 2);
        Classic = new(classicLog, classicLog - yearLog, nominalEntropyBits > model.ClassicalLandauerThresholdBits, nominalEntropyBits > model.ClassicalCosmicTimeThresholdBits);
        Grover = new(groverLog, groverLog - yearLog, nominalEntropyBits > model.GroverLandauerThresholdBits, nominalEntropyBits > model.GroverCosmicTimeThresholdBits);
    }
}
