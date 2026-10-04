import Foundation
import PasswordGeneratorCore

/// Formats logarithmic model estimates without converting enormous durations to seconds.
struct AttackCostPresentation {
    let language: AppLanguage

    func duration(log10Seconds: Double?) -> String {
        guard let logarithm = log10Seconds, logarithm.isFinite else { return "—" }
        let unit: (scale: Double, symbol: String)
        switch logarithm {
        case ..<(-9): unit = (-12, "ps")
        case ..<(-6): unit = (-9, "ns")
        case ..<(-3): unit = (-6, "µs")
        case ..<0: unit = (-3, "ms")
        case ..<log10(60): unit = (0, "s")
        case ..<log10(3_600): unit = (log10(60), "min")
        case ..<log10(86_400): unit = (log10(3_600), "h")
        case ..<log10(AttackCostEstimate.standardModel.secondsPerYear):
            unit = (log10(86_400), language.text("Tage", "days"))
        default:
            unit = (log10(AttackCostEstimate.standardModel.secondsPerYear), language.text("Jahre", "years"))
        }
        let value = number(logarithm: logarithm - unit.scale)
        let singularUnits = ["days": "day", "years": "year", "Tage": "Tag", "Jahre": "Jahr"]
        let symbol = value == "1" ? singularUnits[unit.symbol] ?? unit.symbol : unit.symbol
        return "\(value) \(symbol)"
    }

    func number(logarithm: Double) -> String {
        guard logarithm.isFinite else { return "—" }
        if (-2..<6).contains(logarithm) { return decimal(pow(10, logarithm)) }
        var exponent = floor(logarithm)
        var mantissa = pow(10, logarithm - exponent)
        // Keep a rounded mantissa in [1, 10), including at unit boundaries.
        if mantissa >= 9.995 { mantissa = 1; exponent += 1 }
        let exponentFormatter = NumberFormatter()
        exponentFormatter.locale = Locale(identifier: "en_US_POSIX")
        exponentFormatter.numberStyle = .decimal
        exponentFormatter.usesGroupingSeparator = false
        exponentFormatter.maximumFractionDigits = 0
        let exponentText = exponentFormatter.string(from: NSNumber(value: exponent)) ?? "?"
        // Regular baseline digits keep every exponent at the surrounding text size.
        return "\(decimal(mantissa)) × 10^\(exponentText)"
    }

    private func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}
