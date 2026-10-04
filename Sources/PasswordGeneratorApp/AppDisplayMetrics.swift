import SwiftUI

struct AppDisplayMetrics: Equatable, Sendable {
    static let minimumWindowSize = CGSize(width: 1_060, height: 840)
    static let minimumFontSize: CGFloat = 14

    let viewportSize: CGSize

    var scale: CGFloat {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else { return 1 }
        let widthRatio = max(1, viewportSize.width / Self.minimumWindowSize.width)
        let heightRatio = max(1, viewportSize.height / Self.minimumWindowSize.height)
        return sqrt(widthRatio) * sqrt(heightRatio)
    }

    func fontSize(for baseSize: CGFloat) -> CGFloat {
        max(Self.minimumFontSize, baseSize.isFinite ? baseSize : Self.minimumFontSize) * scale
    }

    var horizontalPadding: CGFloat { 30 * scale }
    var popoverWidth: CGFloat { min(viewportSize.width - 80, 680 * scale) }
    var popoverScrollHeight: CGFloat { min(viewportSize.height - 180, 500 * scale) }
}

private struct AppDisplayMetricsKey: EnvironmentKey {
    static let defaultValue = AppDisplayMetrics(viewportSize: AppDisplayMetrics.minimumWindowSize)
}

extension EnvironmentValues {
    var appDisplayMetrics: AppDisplayMetrics {
        get { self[AppDisplayMetricsKey.self] }
        set { self[AppDisplayMetricsKey.self] = newValue }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.appDisplayMetrics) private var metrics
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: metrics.fontSize(for: size), weight: weight, design: design))
    }
}

extension View {
    func appFont(size: CGFloat = 14, weight: Font.Weight = .regular, design: Font.Design = .rounded) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }
}
