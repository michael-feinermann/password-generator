/// Display bands for the log2 size of the generator's nominal selection space.
/// These bands do not measure source entropy or guarantee resistance to attacks.
public enum NominalSecurityLevel: String, CaseIterable, Sendable {
    /// Below 128 nominal bits; displayed in red.
    case below128
    /// At least 128 and below 256 nominal bits; displayed in yellow.
    case atLeast128
    /// At least 256 and below 1024 nominal bits; displayed in light green.
    case atLeast256
    /// At least 1024 nominal bits; displayed in dark green.
    case atLeast1024

    /// Invalid, non-finite values receive the lowest band.
    public init(nominalBits: Double) {
        guard nominalBits.isFinite else {
            self = .below128
            return
        }
        switch nominalBits {
        case ..<128: self = .below128
        case ..<256: self = .atLeast128
        case ..<1024: self = .atLeast256
        default: self = .atLeast1024
        }
    }
}
