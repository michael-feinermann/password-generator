import AppKit
import Foundation
import PasswordGeneratorCore

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case collecting
        case ready
        case generated
    }

    @Published var language: AppLanguage = .german
    @Published var selectedMode: GeneratorMode = .bip39 {
        didSet {
            if selectedMode != oldValue {
                selectedLength = Self.defaultLength(for: selectedMode)
            }
        }
    }
    @Published var selectedLength = 12
    @Published var bip39Separator = " "
    @Published var effSeparator = "-"
    @Published var uppercaseHex = false
    @Published var userConfirmedSecureEnvironment = false
    @Published private(set) var phase: Phase = .collecting
    @Published private(set) var mouseEventCount = 0
    @Published private(set) var generatedPassword: GeneratedPassword?
    @Published private(set) var isMnemonicVisible = false
    @Published private(set) var wordListIntegrity: WordListIntegrity?
    @Published private(set) var effWordListIntegrity: WordListIntegrity?
    @Published private(set) var isClipboardClearScheduled = false
    @Published private(set) var errorMessage: LocalizedMessage?
    @Published private(set) var runtimeSecurity: SecureRuntimeAssessment
    @Published private(set) var poolShuffleCount = 0
    @Published private(set) var isPoolActive = false

    private var generator: PasswordGenerator?
    private var entropyPool: EntropyPool?
    private var clipboardChangeCount: Int?
    private var clipboardClearTask: Task<Void, Never>?
    private var mnemonicConcealTask: Task<Void, Never>?
    private var poolShuffleTask: Task<Void, Never>?
    private var isTerminated = false
    private let randomProvider: (Int) throws -> [UInt8]
    private let pasteboard: NSPasteboard
    private let secureRuntimeCheck: @MainActor () -> SecureRuntimeAssessment

    static let mnemonicRevealDurationSeconds = 60
    static let poolShuffleIntervalSeconds = 6
    static let requiredMouseEventCount = EntropyPool.requiredMouseEventCount

    init(
        secureRuntimeCheck: @escaping @MainActor () -> SecureRuntimeAssessment =
            SecureRuntimeAssessment.current,
        randomProvider: @escaping (Int) throws -> [UInt8] = SecureRandom.bytes,
        shuffleInterval: Duration = .seconds(poolShuffleIntervalSeconds),
        pasteboard: NSPasteboard = .general
    ) {
        self.secureRuntimeCheck = secureRuntimeCheck
        self.randomProvider = randomProvider
        self.pasteboard = pasteboard
        runtimeSecurity = secureRuntimeCheck()
        do {
            let implementation = try PasswordGenerator()
            generator = implementation
            wordListIntegrity = implementation.bip39.wordListIntegrity
            effWordListIntegrity = implementation.eff.wordListIntegrity
            try initializePool()
        } catch {
            errorMessage = .from(error)
        }
        // This schedule begins at launch, including while collecting and after generation.
        poolShuffleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: shuffleInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, self?.isTerminated == false else { return }
                self?.shufflePool()
            }
        }
    }

    var selectedWordCount: MnemonicWordCount {
        get { MnemonicWordCount(rawValue: selectedLength) ?? .twelve }
        set {
            selectedMode = .bip39
            selectedLength = newValue.rawValue
        }
    }

    var configuration: GeneratorConfiguration? {
        let value = GeneratorConfiguration(mode: selectedMode, length: selectedLength)
        guard (try? value.validate()) != nil else { return nil }
        return value
    }

    /// Keep independent preferences when switching formats or discarding a result.
    var wordSeparator: String {
        get {
            switch generatedPassword?.mode ?? selectedMode {
            case .bip39: bip39Separator
            case .eff: effSeparator
            default: ""
            }
        }
        set {
            switch generatedPassword?.mode ?? selectedMode {
            case .bip39: bip39Separator = newValue
            case .eff: effSeparator = newValue
            default: break
            }
        }
    }

    var selectedEntropyBits: Double? { configuration?.entropyBits }
    var mnemonicWords: [String] { generatedPassword?.components ?? [] }
    var generatedText: String {
        generatedPassword?.exportText(wordSeparator: wordSeparator, uppercaseHex: uppercaseHex) ?? ""
    }
    var isGeneratedMnemonicValid: Bool { generatedPassword?.mode == .bip39 }

    var lengthRange: ClosedRange<Int> { selectedMode.lengthRange }

    var collectionProgress: Double {
        min(Double(mouseEventCount) / Double(Self.requiredMouseEventCount), 1)
    }

    var remainingMouseEvents: Int {
        max(Self.requiredMouseEventCount - mouseEventCount, 0)
    }

    var canGenerate: Bool {
        phase == .ready
            && configuration != nil
            && generator != nil
            && isPoolActive
            && !isTerminated
            && runtimeSecurity.isEnforced
            && userConfirmedSecureEnvironment
    }

    var canCollectMouseEvents: Bool { isPoolActive && !isTerminated }

    func record(_ sample: MouseEntropySample) {
        guard canCollectMouseEvents, let entropyPool else { return }
        entropyPool.absorb(
            MouseEntropyRecord(
                uptimeNanoseconds: sample.uptimeNanoseconds,
                eventTimestamp: sample.eventTimestamp,
                x: sample.x,
                y: sample.y,
                deltaX: sample.deltaX,
                deltaY: sample.deltaY,
                canvasWidth: sample.canvasWidth,
                canvasHeight: sample.canvasHeight,
                modifierFlags: sample.modifierFlags,
                pressedMouseButtons: sample.pressedMouseButtons
            )
        )
        // The pool retains at most 4096 records, even as this lifetime count increases.
        if mouseEventCount < Int.max { mouseEventCount += 1 }
        if mouseEventCount >= Self.requiredMouseEventCount, phase == .collecting {
            phase = .ready
        }
    }

    func generate() {
        guard phase == .ready, !isTerminated,
              let generator, let entropyPool, let configuration else { return }
        guard userConfirmedSecureEnvironment else {
            errorMessage = .secureEnvironmentConfirmationRequired
            return
        }
        guard verifySecureRuntime(discardGeneratedSecretOnFailure: false) else { return }

        do {
            // makeStream shuffles immediately before deriving this generation's material.
            let stream = try entropyPool.makeStream()
            defer { stream.clear() }
            poolShuffleCount = entropyPool.shuffleCount
            let result = try generator.generate(
                configuration: configuration,
                randomProvider: stream.bytes(count:)
            )
            if result.mode == .bip39, !generator.bip39.validate(result.components) {
                throw BIP39Error.invalidChecksum
            }
            generatedPassword = result
            isMnemonicVisible = false
            phase = .generated
        } catch {
            errorMessage = .from(error)
        }
    }

    func copyMnemonic() {
        guard phase == .generated, isMnemonicVisible, !generatedText.isEmpty else { return }
        guard verifySecureRuntime(discardGeneratedSecretOnFailure: true) else { return }
        _ = pasteboard.prepareForNewContents(with: [.currentHostOnly])
        guard pasteboard.setString(generatedText, forType: .string) else {
            errorMessage = .clipboardFailed
            return
        }
        clipboardChangeCount = pasteboard.changeCount
        isClipboardClearScheduled = true
        clipboardClearTask?.cancel()
        clipboardClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.clearClipboardIfUnchanged()
        }
    }

    func concealMnemonic() {
        mnemonicConcealTask?.cancel()
        mnemonicConcealTask = nil
        isMnemonicVisible = false
    }

    func secureContextDidChange() {
        concealMnemonic()
        userConfirmedSecureEnvironment = false
    }

    func revealMnemonic() {
        guard phase == .generated, !generatedText.isEmpty else { return }
        guard verifySecureRuntime(discardGeneratedSecretOnFailure: true) else { return }
        isMnemonicVisible = true
        mnemonicConcealTask?.cancel()
        mnemonicConcealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.mnemonicRevealDurationSeconds))
            guard !Task.isCancelled else { return }
            self?.concealMnemonic()
        }
    }

    func reset() {
        discardSecret()
        entropyPool?.clear()
        entropyPool = nil
        isPoolActive = false
        mouseEventCount = 0
        poolShuffleCount = 0
        userConfirmedSecureEnvironment = false
        phase = .collecting
        guard !isTerminated else { return }
        do {
            try initializePool()
        } catch {
            errorMessage = .from(error)
        }
    }

    func prepareForTermination() {
        isTerminated = true
        poolShuffleTask?.cancel()
        poolShuffleTask = nil
        discardSecret()
        entropyPool?.clear()
        entropyPool = nil
        isPoolActive = false
        userConfirmedSecureEnvironment = false
        mouseEventCount = 0
        phase = .collecting
    }

    func dismissError() { errorMessage = nil }

    private func initializePool() throws {
        // EntropyPool owns its initial shuffle; later shuffles use macOS random bytes.
        let pool = try EntropyPool(randomProvider: randomProvider)
        entropyPool = pool
        poolShuffleCount = pool.shuffleCount
        isPoolActive = true
    }

    private func shufflePool() {
        guard !isTerminated, let entropyPool else { return }
        do {
            try entropyPool.shuffle()
            poolShuffleCount = entropyPool.shuffleCount
        } catch {
            errorMessage = .from(error)
        }
    }

    private func discardSecret() {
        clearClipboardIfUnchanged()
        clipboardClearTask?.cancel()
        clipboardClearTask = nil
        concealMnemonic()
        generatedPassword = nil
        isClipboardClearScheduled = false
    }

    private func verifySecureRuntime(discardGeneratedSecretOnFailure: Bool) -> Bool {
        runtimeSecurity = secureRuntimeCheck()
        guard runtimeSecurity.isEnforced else {
            if discardGeneratedSecretOnFailure { reset() }
            errorMessage = .secureRuntimeUnavailable
            return false
        }
        return true
    }

    private func clearClipboardIfUnchanged() {
        guard let expectedChangeCount = clipboardChangeCount else { return }
        if pasteboard.changeCount == expectedChangeCount { pasteboard.clearContents() }
        clipboardChangeCount = nil
        isClipboardClearScheduled = false
    }

    deinit {
        poolShuffleTask?.cancel()
        clipboardClearTask?.cancel()
        mnemonicConcealTask?.cancel()
    }

    private static func defaultLength(for mode: GeneratorMode) -> Int {
        switch mode {
        case .bip39: 12
        case .eff: 6
        case .ascii: 20
        case .pin: 6
        case .hex: 64
        }
    }
}
