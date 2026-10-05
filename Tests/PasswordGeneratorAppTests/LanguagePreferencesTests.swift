import AppKit
import XCTest
import PasswordGeneratorCore
@testable import PasswordGeneratorApp

@MainActor
final class LanguagePreferencesTests: XCTestCase {
    func testFreshLaunchUsesEnglishFirstWithoutWritingAnyPreference() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let model = makeModel(defaults: defaults)
            defer { model.prepareForTermination() }
            XCTAssertEqual(AppLanguage.allCases, [.english, .german])
            XCTAssertEqual(model.language, .english)
            XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)
        }
    }

    func testBothLanguageChoicesSurviveRelaunch() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let first = makeModel(defaults: defaults)
            defer { first.prepareForTermination() }
            first.language = .german
            XCTAssertEqual(defaults.string(forKey: UserDefaultsLanguagePreferences.languageKey), "de")
            first.prepareForTermination()

            let secondDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let second = makeModel(defaults: secondDefaults)
            defer { second.prepareForTermination() }
            XCTAssertEqual(second.language, .german)
            second.language = .english
            XCTAssertEqual(secondDefaults.string(forKey: UserDefaultsLanguagePreferences.languageKey), "en")
            second.prepareForTermination()

            let thirdDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let third = makeModel(defaults: thirdDefaults)
            defer { third.prepareForTermination() }
            XCTAssertEqual(third.language, .english)
            XCTAssertEqual(thirdDefaults.persistentDomain(forName: suiteName) as? [String: String], [UserDefaultsLanguagePreferences.languageKey: "en"])
        }
    }

    func testInvalidStoredValuesFallBackToEnglishAndValidChoiceReplacesThem() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let invalidValues: [Any] = ["", "fr", "DE", "german", "English", 17, true, ["en"], ["language": "de"]]
            for invalidValue in invalidValues {
                defaults.set(invalidValue, forKey: UserDefaultsLanguagePreferences.languageKey)
                let model = makeModel(defaults: defaults)
                defer { model.prepareForTermination() }
                XCTAssertEqual(model.language, .english)
                model.language = .german
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as? [String: String], [UserDefaultsLanguagePreferences.languageKey: "de"])
            }
        }
    }

    func testRelaunchRestoresOnlyLanguageAndResetsAllSessionState() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let first = makeModel(defaults: defaults)
            defer { first.prepareForTermination() }
            first.language = .german
            first.selectedMode = .hex
            first.selectedLength = 37
            first.bip39Separator = ""
            first.effSeparator = "TEST-SEPARATOR"
            first.uppercaseHex = true
            first.userConfirmedSecureEnvironment = true
            for index in 0..<AppModel.requiredMouseEventCount {
                first.record(MouseEntropySample(
                    uptimeNanoseconds: UInt64(index + 1), eventTimestamp: Double(index) / 120,
                    x: Double(index % 127), y: Double(index % 83), deltaX: 1, deltaY: 1,
                    canvasWidth: 1_060, canvasHeight: 840, modifierFlags: 0, pressedMouseButtons: 0
                ))
            }
            first.generate()
            XCTAssertEqual(first.phase, .generated)
            XCTAssertNotNil(first.generatedPassword)
            first.revealMnemonic()
            first.copyMnemonic()
            XCTAssertTrue(first.isMnemonicVisible)
            XCTAssertTrue(first.isClipboardClearScheduled)
            first.prepareForTermination()

            XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as? [String: String], [UserDefaultsLanguagePreferences.languageKey: "de"])
            let second = makeModel(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
            defer { second.prepareForTermination() }
            XCTAssertEqual(second.language, .german)
            XCTAssertEqual(second.selectedMode, .bip39)
            XCTAssertEqual(second.selectedLength, GeneratorMode.bip39.defaultLength)
            XCTAssertEqual(second.bip39Separator, " ")
            XCTAssertEqual(second.effSeparator, "-")
            XCTAssertFalse(second.uppercaseHex)
            XCTAssertFalse(second.userConfirmedSecureEnvironment)
            XCTAssertEqual(second.phase, .collecting)
            XCTAssertEqual(second.mouseEventCount, 0)
            XCTAssertNil(second.generatedPassword)
            XCTAssertTrue(second.generatedText.isEmpty)
            XCTAssertFalse(second.isMnemonicVisible)
            XCTAssertFalse(second.isClipboardClearScheduled)
            XCTAssertNil(second.errorMessage)
            XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as? [String: String], [UserDefaultsLanguagePreferences.languageKey: "de"])
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suiteName = "local.passwordgenerator.tests.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }

    private func makeModel(defaults: UserDefaults) -> AppModel {
        AppModel(
            secureRuntimeCheck: {
                SecureRuntimeAssessment(
                    appSandboxEnabled: true, entitlementsMinimized: true, codeSignatureValid: true,
                    hardenedRuntimeEnabled: true, debuggerAbsent: true, coreDumpsDisabled: true
                )
            },
            randomProvider: { [UInt8](repeating: 0, count: $0) },
            shuffleInterval: .seconds(3_600),
            pasteboard: .withUniqueName(),
            languagePreferences: UserDefaultsLanguagePreferences(defaults: defaults)
        )
    }
}
