import Foundation
import XCTest
@testable import PasswordGeneratorApp

final class AppDisplayMetricsTests: XCTestCase {
    func testNormalWindowIsTheMinimumAndAllTextRemainsAtLeastFourteenPoints() {
        XCTAssertEqual(AppDisplayMetrics.minimumWindowSize, CGSize(width: 1_060, height: 840))
        let metrics = AppDisplayMetrics(viewportSize: AppDisplayMetrics.minimumWindowSize)
        XCTAssertEqual(metrics.fontSize(for: 14), 14)
        XCTAssertEqual(metrics.fontSize(for: 29), 29)
        let baseSizes: [CGFloat] = [0, 9, 13.5, -.infinity, .nan]
        for baseSize in baseSizes {
            XCTAssertGreaterThanOrEqual(metrics.fontSize(for: baseSize), 14)
        }
        let constrained = AppDisplayMetrics(viewportSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(constrained.fontSize(for: 14), 14)
    }

    func testLargerWindowsIncreaseTypographyWithoutAContentMaximum() {
        let normal = AppDisplayMetrics(viewportSize: AppDisplayMetrics.minimumWindowSize)
        let fullscreen = AppDisplayMetrics(viewportSize: CGSize(width: 1_920, height: 1_080))
        let doubleSize = AppDisplayMetrics(viewportSize: CGSize(width: 2_120, height: 1_680))
        XCTAssertGreaterThan(fullscreen.fontSize(for: 14), normal.fontSize(for: 14))
        XCTAssertGreaterThan(fullscreen.fontSize(for: 29), normal.fontSize(for: 29))
        XCTAssertEqual(doubleSize.fontSize(for: 14), 28, accuracy: 0.000_001)
        XCTAssertGreaterThan(doubleSize.popoverWidth, normal.popoverWidth)
    }

    func testReadablePopoversStayInsideSupportedWindows() {
        for size in [CGSize(width: 1_060, height: 840), CGSize(width: 1_920, height: 1_080), CGSize(width: 3_840, height: 2_160)] {
            let metrics = AppDisplayMetrics(viewportSize: size)
            XCTAssertGreaterThanOrEqual(metrics.popoverWidth, 680)
            XCTAssertLessThan(metrics.popoverWidth, size.width)
            XCTAssertLessThan(metrics.popoverScrollHeight + 150, size.height)
        }
    }
}
