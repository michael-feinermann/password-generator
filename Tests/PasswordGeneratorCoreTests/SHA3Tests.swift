import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class SHA3Tests: XCTestCase {
    func testSHA3512EmptyStringFIPS202Vector() {
        let expected = "a69f73cca23a9ac5c8b567dc185a756e9"
            + "7c982164fe25859e0d1dcc1475c80a61"
            + "5b2123af1f5f94c11e3e9402c3ac558f"
            + "500199d95b6d3e301758586281dcd26"

        XCTAssertEqual(hex(SHA3.hash512(Data())), expected)
    }

    func testSHA3512ABCVector() {
        let expected = "b751850b1a57168a5693cd924b6b096e"
            + "08f621827444f70d884f5d0240d2712e"
            + "10e116e9192af3c91a7ec57647e39340"
            + "57340b4cf408d5a56592f8274eec53f0"

        XCTAssertEqual(hex(SHA3.hash512(Data("abc".utf8))), expected)
    }

    func testSHA3512AcrossRateBoundariesAgainstOpenSSLVectors() {
        let vectors: [(Int, String)] = [
            (71, "3ccc850d53a1287af7b4560b2ef0d43eb5d9a80d62a0e9cf1dbc040135921104d4395168e90bfc871773ebb34bca1bd67056e1cc7dc7a48ff7c3167d389f117c"),
            (72, "5d63f2bbe971a983ac6847480106e4e1264ee3a0befd79954914e1d86e795b2e18238f12fc5e46cb9cc78efdec610a93647cc04e1c23d8caaa6a58c21dd26c07"),
            (73, "921d9b7b2b0f3066a1646dbb058c979cb3925dec0f8c269faaa7f9648e73465ae55ec527257d5d5e1cfdbf5d6799bea1004b6186f5108c74e3b92fe924166558"),
            (143, "eb9748309c6b70ffe82820052ad26ea99f43968d2af359adc804b2a76741a62ea8d710f018ea113c2259d0bd6687e3838602ae6c1dff727ae985f059141c7217"),
            (144, "e1951b8bcb58ca75a34af80a7a2b765cad4257fe383a79b55bf21f180b75f6e5b08f09598851eeea7d13486387618d6c6bf88cf23c0088a3f783f59a06d60493"),
            (145, "1abec62dce93a6775cd2ec0098d7264676a21e644c7c1b80580c305cfde31b7d5848c63af4d0e7cfeda2e5076a32dbd632665fbb1e7f06651b2ed4d7341ac844"),
            (1_024, "b052fd4a09f988bbe4112d9a3eca8ccc517e56da866c1609504c37871146da80731bb681674a2000a41bcb78230b3d9069eb42820293ce23cba294550a1d4d3b"),
        ]

        for (length, expected) in vectors {
            let message = Data((0..<length).map { UInt8(truncatingIfNeeded: $0) })
            XCTAssertEqual(hex(SHA3.hash512(message)), expected, "length \(length)")
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
