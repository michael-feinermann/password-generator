import Foundation
import XCTest
@testable import PasswordGeneratorCore

final class BIP39Tests: XCTestCase {
    private var bip39: BIP39!

    override func setUpWithError() throws {
        bip39 = try BIP39()
    }

    func testOfficialWordListIntegrity() {
        XCTAssertEqual(bip39.words.count, 2_048)
        XCTAssertEqual(bip39.wordListIntegrity, .expected)
    }

    func testTwelveWordZeroEntropyVector() throws {
        let words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 16))
        XCTAssertEqual(words, Array(repeating: "abandon", count: 11) + ["about"])
        XCTAssertEqual(try bip39.entropy(from: words), [UInt8](repeating: 0, count: 16))
    }

    func testEighteenWordZeroEntropyVector() throws {
        let words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 24))
        XCTAssertEqual(words, Array(repeating: "abandon", count: 17) + ["agent"])
        XCTAssertEqual(try bip39.entropy(from: words), [UInt8](repeating: 0, count: 24))
    }

    func testFifteenWordZeroEntropyVector() throws {
        let words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 20))
        XCTAssertEqual(words, Array(repeating: "abandon", count: 14) + ["address"])
        XCTAssertEqual(try bip39.entropy(from: words), [UInt8](repeating: 0, count: 20))
    }

    func testTwentyOneWordZeroEntropyVector() throws {
        let words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 28))
        XCTAssertEqual(words, Array(repeating: "abandon", count: 20) + ["admit"])
        XCTAssertEqual(try bip39.entropy(from: words), [UInt8](repeating: 0, count: 28))
    }

    func testTwentyFourWordZeroEntropyVector() throws {
        let words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 32))
        XCTAssertEqual(words, Array(repeating: "abandon", count: 23) + ["art"])
        XCTAssertEqual(try bip39.entropy(from: words), [UInt8](repeating: 0, count: 32))
    }

    func testRejectsChangedChecksumWord() throws {
        var words = try bip39.mnemonic(from: [UInt8](repeating: 0, count: 16))
        words[11] = "ability"
        XCTAssertThrowsError(try bip39.entropy(from: words)) { error in
            XCTAssertEqual(error as? BIP39Error, .invalidChecksum)
        }
    }

    func testAllApplicableOfficialTrezorVectors() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "trezor_english_vectors",
                withExtension: "json"
            )
        )
        let fixture = try JSONDecoder().decode(
            TrezorFixture.self,
            from: Data(contentsOf: url)
        )
        var testedCount = 0

        for vector in fixture.english {
            guard let entropy = bytes(fromHex: vector[0]) else {
                XCTFail("Ungültige Entropie im offiziellen Testvektor")
                continue
            }
            let expectedWords = vector[1].split(separator: " ").map(String.init)
            guard MnemonicWordCount(rawValue: expectedWords.count) != nil else { continue }

            XCTAssertEqual(
                try bip39.mnemonic(from: entropy),
                expectedWords,
                "Trezor-Vektor mit Entropie \(vector[0])"
            )
            XCTAssertEqual(try bip39.entropy(from: expectedWords), entropy)
            testedCount += 1
        }

        XCTAssertEqual(testedCount, 24)
    }

    private func bytes(fromHex hex: String) -> [UInt8]? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}

private struct TrezorFixture: Decodable {
    let english: [[String]]
}
