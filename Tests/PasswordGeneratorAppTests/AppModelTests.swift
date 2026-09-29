import AppKit
import XCTest
import PasswordGeneratorCore
@testable import PasswordGeneratorApp

@MainActor
final class AppModelTests: XCTestCase {
    func testLanguageSwitchKeepsMouseSessionAndLocalizesMessages() {
        let model = AppModel()
        defer { model.prepareForTermination() }
        collectMinimum(on: model)
        model.record(sample(index: AppModel.requiredMouseEventCount))

        XCTAssertEqual(model.mouseEventCount, AppModel.requiredMouseEventCount + 1)
        XCTAssertEqual(model.phase, .ready)
        model.language = .english
        XCTAssertEqual(model.mouseEventCount, AppModel.requiredMouseEventCount + 1)
        XCTAssertEqual(LocalizedMessage.clipboardFailed.value(in: model.language), "The password could not be copied to the clipboard.")
        model.language = .german
        XCTAssertEqual(LocalizedMessage.clipboardFailed.value(in: model.language), "Das Passwort konnte nicht in die Zwischenablage kopiert werden.")
    }

    func testCollectionContinuesBeyondPoolCapacityAndAfterGeneration() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        model.record(sample(index: AppModel.requiredMouseEventCount))
        let beforeGeneration = model.mouseEventCount
        model.generate()
        XCTAssertEqual(model.phase, .generated)
        let password = model.generatedText
        model.record(sample(index: beforeGeneration + 1))
        XCTAssertEqual(model.mouseEventCount, beforeGeneration + 1)
        XCTAssertTrue(model.canCollectMouseEvents)
        XCTAssertEqual(model.generatedText, password)
    }

    func testMinimumIs4096ActualMouseRecords() {
        XCTAssertEqual(AppModel.requiredMouseEventCount, 4_096)
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        for index in 0..<(AppModel.requiredMouseEventCount - 1) { model.record(sample(index: index)) }
        XCTAssertEqual(model.phase, .collecting)
        XCTAssertEqual(model.remainingMouseEvents, 1)
        XCTAssertFalse(model.canGenerate)
        model.generate()
        XCTAssertNil(model.generatedPassword)
        model.record(sample(index: AppModel.requiredMouseEventCount - 1))
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.collectionProgress, 1)
        XCTAssertTrue(model.canGenerate)
    }

    func testUnsignedTestHostCannotGenerateRealPassword() {
        let model = AppModel()
        defer { model.prepareForTermination() }
        collectMinimum(on: model)
        model.userConfirmedSecureEnvironment = true
        XCTAssertFalse(model.runtimeSecurity.isEnforced)
        XCTAssertFalse(model.canGenerate)
        model.generate()
        XCTAssertNil(model.generatedPassword)
        XCTAssertEqual(model.errorMessage, .secureRuntimeUnavailable)
    }

    func testEndToEndGenerationForEveryBIP39Length() throws {
        let validator = try BIP39()
        for wordCount in MnemonicWordCount.allCases {
            let model = secureModel()
            defer { model.prepareForTermination() }
            model.selectedWordCount = wordCount
            model.userConfirmedSecureEnvironment = true
            collectMinimum(on: model)
            let shuffleCount = model.poolShuffleCount
            model.generate()
            XCTAssertEqual(model.poolShuffleCount, shuffleCount + 1)
            XCTAssertEqual(model.phase, .generated)
            XCTAssertEqual(model.mnemonicWords.count, wordCount.rawValue)
            XCTAssertEqual(model.generatedPassword?.entropyBits, Double(wordCount.entropyBitCount))
            XCTAssertTrue(model.isGeneratedMnemonicValid)
            XCTAssertTrue(validator.validate(model.mnemonicWords))
            XCTAssertFalse(model.isMnemonicVisible)
            model.revealMnemonic()
            XCTAssertTrue(model.isMnemonicVisible)
            model.concealMnemonic()
            XCTAssertFalse(model.isMnemonicVisible)
            let original = model.generatedPassword
            model.language = .english
            XCTAssertEqual(model.generatedPassword, original)
        }
    }

    func testGenerationForOtherModesAtBothLengthBounds() {
        for mode in [GeneratorMode.eff, .ascii, .pin, .hex] {
            for length in [mode.lengthRange.lowerBound, mode.lengthRange.upperBound] {
                let model = secureModel()
                defer { model.prepareForTermination() }
                model.selectedMode = mode
                model.selectedLength = length
                model.userConfirmedSecureEnvironment = true
                collectMinimum(on: model)
                XCTAssertTrue(model.canGenerate)
                model.generate()
                XCTAssertEqual(model.generatedPassword?.mode, mode)
                XCTAssertEqual(model.generatedPassword?.components.count, length)
                XCTAssertEqual(model.generatedPassword?.entropyBits, Double(length) * log2(Double(mode.alphabetSize!)))
                XCTAssertFalse(model.isGeneratedMnemonicValid)
                XCTAssertFalse(model.isMnemonicVisible)
                if mode == .eff {
                    XCTAssertEqual(model.generatedText, model.mnemonicWords.joined(separator: "-"))
                    XCTAssertEqual(model.generatedPassword?.text.split(separator: " ").count, length)
                } else {
                    XCTAssertEqual(model.generatedText.count, length)
                    XCTAssertFalse(model.generatedText.contains(" "))
                }
            }
        }
    }

    func testWordSeparatorDefaultsAndPerModePreferencesSurviveModeChanges() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        XCTAssertEqual(model.selectedMode, .bip39)
        XCTAssertEqual(model.wordSeparator, " ")
        model.selectedMode = .eff
        XCTAssertEqual(model.wordSeparator, "-")
        model.wordSeparator = "::"
        model.selectedMode = .bip39
        XCTAssertEqual(model.wordSeparator, " ")
        model.wordSeparator = ""
        model.selectedMode = .ascii
        model.selectedMode = .eff
        XCTAssertEqual(model.wordSeparator, "::")
        model.selectedMode = .bip39
        XCTAssertEqual(model.wordSeparator, "")
        model.reset()
        XCTAssertEqual(model.wordSeparator, "")
        model.selectedMode = .eff
        XCTAssertEqual(model.wordSeparator, "::")
    }

    func testWordExportSeparatorsCanChangeAfterGenerationWithoutChangingSecret() throws {
        for mode in [GeneratorMode.bip39, .eff] {
            let assessment = secureRuntimeAssessment()
            let pasteboard = NSPasteboard.withUniqueName()
            var randomCalls = 0
            let model = AppModel(
                secureRuntimeCheck: { assessment },
                randomProvider: { count in
                    randomCalls += 1
                    return Array(repeating: UInt8(0), count: count)
                },
                shuffleInterval: .seconds(3600),
                pasteboard: pasteboard
            )
            defer { model.prepareForTermination() }
            model.selectedMode = mode
            XCTAssertEqual(model.wordSeparator, mode == .bip39 ? " " : "-")
            collectMinimum(on: model)
            model.userConfirmedSecureEnvironment = true
            model.generate()
            model.revealMnemonic()
            let original = try XCTUnwrap(model.generatedPassword)
            let originalRandomCalls = randomCalls
            let originalShuffleCount = model.poolShuffleCount
            XCTAssertEqual(original.text, original.components.joined(separator: " "))
            for separator in ["-", "", " ", "::", "🔐"] {
                model.wordSeparator = separator
                let expected = original.components.joined(separator: separator)
                XCTAssertEqual(model.generatedText, expected)
                model.copyMnemonic()
                XCTAssertEqual(pasteboard.string(forType: .string), expected)
                XCTAssertTrue(model.isClipboardClearScheduled)
                XCTAssertEqual(model.generatedPassword, original)
                XCTAssertEqual(model.generatedPassword?.entropyBits, original.entropyBits)
                XCTAssertEqual(model.phase, .generated)
                XCTAssertTrue(model.isMnemonicVisible)
                XCTAssertEqual(randomCalls, originalRandomCalls)
                XCTAssertEqual(model.poolShuffleCount, originalShuffleCount)
            }
            if mode == .bip39 {
                XCTAssertTrue(try BIP39().validate(model.mnemonicWords))
            }
            model.prepareForTermination()
            XCTAssertNil(pasteboard.string(forType: .string))
        }
    }

    func testHexCaseCanChangeAfterGenerationWithoutChangingSecret() throws {
        let assessment = secureRuntimeAssessment()
        let pasteboard = NSPasteboard.withUniqueName()
        var randomCalls = 0
        let model = AppModel(
            secureRuntimeCheck: { assessment },
            randomProvider: { count in
                randomCalls += 1
                return Array(repeating: UInt8(0), count: count)
            },
            shuffleInterval: .seconds(3600),
            pasteboard: pasteboard
        )
        defer { model.prepareForTermination() }
        model.selectedMode = .hex
        model.selectedLength = 448
        XCTAssertFalse(model.uppercaseHex)
        collectMinimum(on: model)
        model.userConfirmedSecureEnvironment = true
        model.generate()
        model.revealMnemonic()
        let original = try XCTUnwrap(model.generatedPassword)
        let originalRandomCalls = randomCalls
        let originalShuffleCount = model.poolShuffleCount
        XCTAssertEqual(original.text.count, 448)
        XCTAssertEqual(original.entropyBits, 1792)
        XCTAssertEqual(original.text, original.text.lowercased())
        for uppercase in [false, true, false] {
            model.uppercaseHex = uppercase
            model.wordSeparator = "IGNORED FOR HEX"
            let expected = uppercase ? original.text.uppercased() : original.text
            XCTAssertEqual(model.generatedText, expected)
            model.copyMnemonic()
            XCTAssertEqual(pasteboard.string(forType: .string), expected)
            XCTAssertEqual(model.generatedPassword, original)
            XCTAssertEqual(model.selectedEntropyBits, 1792)
            XCTAssertEqual(randomCalls, originalRandomCalls)
            XCTAssertEqual(model.poolShuffleCount, originalShuffleCount)
            XCTAssertTrue(model.isMnemonicVisible)
        }
        model.prepareForTermination()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testHexAllowsOddLengthsAndExportOptionsPersistAcrossReset() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.selectedMode = .hex
        XCTAssertEqual(model.lengthRange, 1...448)
        for length in [1, 3, 447, 448] {
            model.selectedLength = length
            XCTAssertNotNil(model.configuration)
            XCTAssertEqual(model.selectedEntropyBits, Double(length * 4))
        }
        model.effSeparator = "::"
        model.bip39Separator = ""
        model.uppercaseHex = true
        model.reset()
        XCTAssertEqual(model.effSeparator, "::")
        XCTAssertEqual(model.bip39Separator, "")
        XCTAssertTrue(model.uppercaseHex)
        XCTAssertEqual(model.selectedMode, .hex)
        XCTAssertEqual(model.selectedLength, 448)
    }

    func testInvalidLengthBlocksGenerationAndEntropyDisplay() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        for mode in GeneratorMode.allCases {
            model.selectedMode = mode
            for length in [0, mode.lengthRange.lowerBound - 1, mode.lengthRange.upperBound + 1] {
                model.selectedLength = length
                XCTAssertNil(model.configuration)
                XCTAssertNil(model.selectedEntropyBits)
                XCTAssertFalse(model.canGenerate)
                model.generate()
                XCTAssertNil(model.generatedPassword)
            }
        }
        model.selectedMode = .bip39
        model.selectedLength = 13
        XCTAssertFalse(model.canGenerate)
    }

    func testPeriodicShuffleRunsBeforeReadinessAndAfterGenerationThenStops() async throws {
        let model = secureModel(shuffleInterval: .milliseconds(15))
        defer { model.prepareForTermination() }
        model.record(sample(index: 0))
        model.record(sample(index: 1))
        let initialCount = model.poolShuffleCount
        try await waitForShuffle(on: model, after: initialCount)
        XCTAssertEqual(model.phase, .collecting)
        for index in 2..<AppModel.requiredMouseEventCount { model.record(sample(index: index)) }
        model.userConfirmedSecureEnvironment = true
        model.generate()
        XCTAssertEqual(model.phase, .generated)
        let generatedCount = model.poolShuffleCount
        try await waitForShuffle(on: model, after: generatedCount)
        XCTAssertEqual(model.phase, .generated)
        model.prepareForTermination()
        let finalCount = model.poolShuffleCount
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(model.poolShuffleCount, finalCount)
        XCTAssertFalse(model.canCollectMouseEvents)
        XCTAssertNil(model.generatedPassword)
    }

    func testRandomFailurePreventsGeneration() {
        let assessment = secureRuntimeAssessment()
        let model = AppModel(
            secureRuntimeCheck: { assessment },
            randomProvider: { _ in throw EntropyError.secureRandomFailure(-1) }
        )
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        model.generate()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.generatedPassword)
        XCTAssertEqual(model.errorMessage, .from(EntropyError.secureRandomFailure(-1)))
    }

    func testRuntimeSecurityIsRecheckedImmediatelyBeforeGeneration() {
        let box = RuntimeAssessmentBox(secureRuntimeAssessment())
        let model = AppModel(secureRuntimeCheck: { box.value })
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        XCTAssertTrue(model.canGenerate)
        box.value = secureRuntimeAssessment(debuggerAbsent: false)
        model.generate()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.generatedPassword)
        XCTAssertFalse(model.runtimeSecurity.isEnforced)
        XCTAssertEqual(model.errorMessage, .secureRuntimeUnavailable)
    }

    func testSecureContextChangeConcealsPasswordAndInvalidatesConfirmation() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        model.generate()
        model.revealMnemonic()
        XCTAssertTrue(model.isMnemonicVisible)
        model.secureContextDidChange()
        XCTAssertFalse(model.isMnemonicVisible)
        XCTAssertFalse(model.userConfirmedSecureEnvironment)
    }

    func testRuntimeFailureBeforeRevealDiscardsPasswordAndPool() {
        let box = RuntimeAssessmentBox(secureRuntimeAssessment())
        let model = AppModel(secureRuntimeCheck: { box.value })
        defer { model.prepareForTermination() }
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        model.generate()
        box.value = secureRuntimeAssessment(debuggerAbsent: false)
        model.revealMnemonic()
        XCTAssertEqual(model.phase, .collecting)
        XCTAssertEqual(model.mouseEventCount, 0)
        XCTAssertNil(model.generatedPassword)
        XCTAssertFalse(model.isMnemonicVisible)
        XCTAssertEqual(model.errorMessage, .secureRuntimeUnavailable)
    }

    func testResetRequiresFreshMousePoolAndPreservesFormat() {
        let model = secureModel()
        defer { model.prepareForTermination() }
        model.selectedMode = .ascii
        model.selectedLength = 256
        model.userConfirmedSecureEnvironment = true
        collectMinimum(on: model)
        model.generate()
        model.reset()
        XCTAssertEqual(model.phase, .collecting)
        XCTAssertEqual(model.mouseEventCount, 0)
        XCTAssertEqual(model.selectedMode, .ascii)
        XCTAssertEqual(model.selectedLength, 256)
        XCTAssertNil(model.generatedPassword)
        XCTAssertFalse(model.userConfirmedSecureEnvironment)
        XCTAssertTrue(model.canCollectMouseEvents)
    }

    func testWindowMouseObserverDoesNotInterceptControlsAndFiltersStationaryEvents() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let view = EntropyTrackingView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        window.contentView?.addSubview(view)
        defer { view.stopMonitoring(); view.removeFromSuperview() }
        var samples: [MouseEntropySample] = []
        view.onMove = { samples.append($0) }
        func event(_ type: NSEvent.EventType, x: CGFloat, windowNumber: Int? = nil) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 50), modifierFlags: [], timestamp: 1, windowNumber: windowNumber ?? window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        }
        XCTAssertNil(view.hitTest(NSPoint(x: 0.5, y: 0.5)))
        view.accept(try event(.mouseMoved, x: 50)) // Establish position; zero delta.
        view.accept(try event(.mouseMoved, x: 50)) // Stationary events contribute nothing.
        XCTAssertTrue(samples.isEmpty)
        view.accept(try event(.mouseMoved, x: 50.1)) // No artificial minimum distance.
        view.accept(try event(.leftMouseDragged, x: 51))
        view.accept(try event(.rightMouseDragged, x: 52))
        view.accept(try event(.otherMouseDragged, x: 53))
        XCTAssertEqual(samples.count, 4)
        XCTAssertGreaterThan(samples[0].x, Double(view.frame.width)) // Entire window, not observer bounds.
        view.accept(try event(.mouseMoved, x: 60, windowNumber: otherWindow.windowNumber))
        view.accept(try event(.mouseMoved, x: -1))
        XCTAssertEqual(samples.count, 4)
        view.isCollectionEnabled = false
        view.accept(try event(.mouseMoved, x: 61))
        XCTAssertEqual(samples.count, 4)
    }

    private func secureModel(shuffleInterval: Duration = .seconds(6)) -> AppModel {
        let assessment = secureRuntimeAssessment()
        return AppModel(secureRuntimeCheck: { assessment }, shuffleInterval: shuffleInterval)
    }

    private func collectMinimum(on model: AppModel) {
        for index in 0..<AppModel.requiredMouseEventCount { model.record(sample(index: index)) }
    }

    private func waitForShuffle(on model: AppModel, after count: Int) async throws {
        for _ in 0..<100 {
            if model.poolShuffleCount > count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Periodic pool shuffle did not run")
    }

    private func secureRuntimeAssessment(debuggerAbsent: Bool = true) -> SecureRuntimeAssessment {
        SecureRuntimeAssessment(appSandboxEnabled: true, entitlementsMinimized: true, codeSignatureValid: true, hardenedRuntimeEnabled: true, debuggerAbsent: debuggerAbsent, coreDumpsDisabled: true)
    }

    private func sample(index: Int) -> MouseEntropySample {
        MouseEntropySample(uptimeNanoseconds: UInt64(index + 1), eventTimestamp: Double(index) / 120, x: Double(index % 127), y: Double(index % 83), deltaX: 1.2, deltaY: -0.8, canvasWidth: 800, canvasHeight: 600, modifierFlags: 0, pressedMouseButtons: 0)
    }
}

@MainActor
private final class RuntimeAssessmentBox {
    var value: SecureRuntimeAssessment
    init(_ value: SecureRuntimeAssessment) { self.value = value }
}
