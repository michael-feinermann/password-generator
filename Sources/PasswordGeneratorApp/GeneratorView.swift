import PasswordGeneratorCore
import SwiftUI

struct GeneratorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showIntegrityDetails = false
    @State private var showDiscardConfirmation = false
    @State private var showRevealConfirmation = false
    @State private var lengthText = ""
    @State private var viewportSize = AppDisplayMetrics.minimumWindowSize

    private var displayMetrics: AppDisplayMetrics { AppDisplayMetrics(viewportSize: viewportSize) }

    var body: some View {
        GeometryReader { geometry in
            let metrics = AppDisplayMetrics(viewportSize: geometry.size)
            ZStack {
                AppPalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20 * metrics.scale) {
                        header
                        securityStrip
                        configurationSection
                        mouseEntropySection
                        if model.phase == .generated {
                            resultSection
                        }
                        securityNote
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, 28 * metrics.scale)
                }
            }
            .font(.system(size: metrics.fontSize(for: 14), design: .rounded))
            .controlSize(.large)
            .environment(\.appDisplayMetrics, metrics)
            .onChange(of: geometry.size, initial: true) { _, size in viewportSize = size }
        }
        .background(
            MouseEntropyView(isEnabled: model.canCollectMouseEvents, onMove: model.record)
                .accessibilityHidden(true)
        )
        .preferredColorScheme(.dark)
        .onAppear { lengthText = String(model.selectedLength) }
        .onChange(of: lengthText) { _, value in
            model.selectedLength = Int(value) ?? 0
        }
        .onChange(of: model.selectedLength) { _, value in
            // Preserve an empty/invalid draft while the user edits the field.
            if value != 0, Int(lengthText) != value { lengthText = String(value) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { model.secureContextDidChange() }
        }
        .alert(
            tr("Aktion fehlgeschlagen", "Action failed"),
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage?.value(in: model.language) ?? tr("Unbekannter Fehler", "Unknown error"))
        }
        .confirmationDialog(
            tr("Passwort wirklich verwerfen?", "Discard this password?"),
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(tr("Passwort verwerfen", "Discard password"), role: .destructive) { model.reset() }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) { }
        } message: {
            Text(tr(
                "Das Passwort wird nicht gespeichert und kann danach nicht wiederhergestellt werden. Für das nächste Passwort wird ein neuer Mauspool gesammelt.",
                "The password is not stored and cannot be recovered afterwards. A new mouse pool will be collected for the next password."
            ))
        }
        .confirmationDialog(
            tr("Geschützte Anzeige öffnen?", "Open protected display?"),
            isPresented: $showRevealConfirmation,
            titleVisibility: .visible
        ) {
            Button(tr(
                "Vorübergehend anzeigen (ca. \(AppModel.mnemonicRevealDurationSeconds) s)",
                "Reveal temporarily (about \(AppModel.mnemonicRevealDurationSeconds) sec)"
            )) { model.revealMnemonic() }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) { }
        } message: {
            Text(tr(
                "Beende vorher Bildschirmfreigaben, Aufnahmen und Fernwartung. macOS bietet Apps keinen garantierten Schutz gegen moderne Bildschirmaufnahme. Die Anzeige wird bei Deaktivierung bestmöglich und sonst zeitgesteuert wieder verdeckt.",
                "Stop screen sharing, recording, and remote support first. macOS gives apps no guaranteed protection against modern screen capture. The display is concealed on a best-effort basis when the app deactivates and otherwise hides again on a timer."
            ))
        }
    }

    private var brandLogo: NSImage {
        let url = Bundle.main.url(forResource: "PasswordGeneratorLogo", withExtension: "png")
            ?? Bundle.module.url(forResource: "PasswordGeneratorLogo", withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:)) ?? NSApplication.shared.applicationIconImage
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: brandLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 58 * displayMetrics.scale, height: 58 * displayMetrics.scale)
                .background(AppPalette.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.displayName)
                    .appFont(size: 29, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                Text(tr("Seedphrasen, Wortpasswörter, ASCII, PINs und Hex. Lokal auf deinem Mac.", "Seed phrases, word passwords, ASCII, PINs, and hex. Locally on your Mac."))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            Spacer()
            LanguageSwitcher(selection: $model.language)
        }
    }

    private var securityStrip: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: displayMetrics.viewportSize.width / displayMetrics.scale >= 1_200 ? 4 : 2),
            spacing: 12
        ) {
            SecurityBadge(icon: "apple.logo", title: "macOS CSPRNG", detail: "SecRandomCopyBytes")
            SecurityBadge(
                icon: "cursorarrow.motionlines",
                title: tr("Mauspool", "Mouse pool"),
                detail: tr("\(model.language.number(EntropyPool.capacity)) Bewegungen", "\(model.language.number(EntropyPool.capacity)) movements")
            )
            SecurityBadge(
                icon: "shuffle", title: "Fisher-Yates",
                detail: tr("Alle 6 s und vor Generierung", "Every 6 sec and before generation")
            )
            SecurityBadge(
                icon: model.runtimeSecurity.isEnforced ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                title: tr("Laufzeitschutz", "Runtime protection"),
                detail: model.runtimeSecurity.isEnforced
                    ? tr("Sandbox · HR · kein Debugger", "Sandbox · HR · no debugger")
                    : tr("Generierung gesperrt", "Generation blocked")
            )
        }
    }

    private var configurationSection: some View {
        SectionCard(step: "01", title: tr("Typ und Länge wählen", "Choose type and length"), subtitle: modeDescription) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(tr("Passworttyp", "Password type"), selection: $model.selectedMode) {
                    ForEach(GeneratorMode.allCases) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.phase == .generated)

                if model.selectedMode == .bip39 {
                    Picker(tr("Wortanzahl", "Word count"), selection: $model.selectedLength) {
                        ForEach(MnemonicWordCount.allCases) { count in
                            Text(tr("\(count.rawValue) Wörter", "\(count.rawValue) words")).tag(count.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.phase == .generated)
                } else {
                    HStack(spacing: 14) {
                        Text(model.selectedMode == .eff ? tr("Wörter", "Words") : tr("Zeichen", "Characters"))
                            .appFont(size: 14, weight: .semibold, design: .rounded)
                        TextField(tr("Länge", "Length"), text: $lengthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90 * displayMetrics.scale)
                            .accessibilityLabel(tr("Länge direkt eingeben", "Enter length directly"))
                        Stepper(tr("Länge anpassen", "Adjust length"), value: $model.selectedLength, in: model.lengthRange)
                            .labelsHidden()
                        Slider(
                            value: Binding(
                                get: { Double(min(max(model.selectedLength, model.lengthRange.lowerBound), model.lengthRange.upperBound)) },
                                set: { model.selectedLength = Int($0) }
                            ),
                            in: Double(model.lengthRange.lowerBound)...Double(model.lengthRange.upperBound),
                            step: 1
                        )
                        .tint(AppPalette.teal)
                        .accessibilityLabel(tr("Länge", "Length"))
                        Text("\(model.lengthRange.lowerBound)...\(model.lengthRange.upperBound)")
                            .appFont(size: 14, design: .monospaced)
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    .disabled(model.phase == .generated)
                }
                NominalSecurityIndicator(
                    entropyBits: model.selectedEntropyBits,
                    level: model.configuration?.nominalSecurityLevel,
                    language: model.language,
                    excludesChecksum: model.selectedMode == .bip39,
                    showsLegend: true
                )
                if model.selectedEntropyBits == nil {
                    Text(tr(
                        "Gib eine gültige Länge zwischen \(model.lengthRange.lowerBound) und \(model.lengthRange.upperBound) ein.",
                        "Enter a valid length between \(model.lengthRange.lowerBound) and \(model.lengthRange.upperBound)."
                    ))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)
                }
                exportOptions
            }
        }
    }

    @ViewBuilder
    private var exportOptions: some View {
        if model.selectedMode.usesWords {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Text(tr("Trennzeichen beim Kopieren", "Separator when copying"))
                        .appFont(size: 14, weight: .semibold, design: .rounded)
                    TextField(tr("Kein Trennzeichen", "No separator"), text: $model.wordSeparator)
                        .textFieldStyle(.roundedBorder)
                        .appFont(size: 14, design: .monospaced)
                        .frame(width: 180 * displayMetrics.scale)
                        .accessibilityLabel(tr("Trennzeichen beim Kopieren", "Separator when copying"))
                        .accessibilityHint(tr("Leer lassen, um die Wörter ohne Trennzeichen zu kopieren.", "Leave empty to copy words without a separator."))
                    Text(model.wordSeparator == " "
                         ? tr("Ein Leerzeichen", "One space")
                         : tr("Leer = ohne Trennzeichen", "Empty = no separator"))
                        .appFont(size: 14, design: .rounded)
                        .foregroundStyle(AppPalette.secondaryText)
                    Spacer(minLength: 0)
                }
                if model.selectedMode == .bip39 {
                    Text(tr(
                        "Für den Wallet-Import Leerzeichen verwenden. Ohne Trennzeichen gehen Wortgrenzen verloren. Das Trennzeichen ändert nur den kopierten Text.",
                        "Use spaces for wallet import. Without a separator, word boundaries are lost. The separator changes only the copied text."
                    ))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if model.selectedMode == .hex {
            VStack(alignment: .leading, spacing: 7) {
                Picker(tr("Hex-Ausgabe", "Hex output"), selection: $model.uppercaseHex) {
                    Text(tr("Kleinbuchstaben (a bis f)", "Lowercase (a to f)")).tag(false)
                    Text(tr("Großbuchstaben (A bis F)", "Uppercase (A to F)")).tag(true)
                }
                .pickerStyle(.segmented)
                Text(tr(
                    "Gilt für Anzeige und Kopieren. Ein Wechsel erzeugt keinen neuen Schlüssel und verändert seine Entropie nicht.",
                    "Applies to display and copying. Switching case does not generate a new key or change its entropy."
                ))
                .appFont(size: 14, design: .rounded)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mouseEntropySection: some View {
        SectionCard(
            step: "02",
            title: tr("Maus im ganzen Fenster bewegen", "Move the mouse anywhere in the window"),
            subtitle: tr(
                "Alle Bewegungen und Ziehbewegungen fließen ein, auch über Schaltflächen und nach der Generierung.",
                "All movements and drags are included, also over controls and after generation."
            )
        ) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(tr("\(model.language.number(model.mouseEventCount)) Bewegungen erfasst", "\(model.language.number(model.mouseEventCount)) movements collected"))
                        .appFont(size: 14, weight: .semibold, design: .rounded)
                        .monospacedDigit()
                    Spacer()
                    Text(model.remainingMouseEvents > 0
                         ? tr("Noch \(model.language.number(model.remainingMouseEvents))", "\(model.language.number(model.remainingMouseEvents)) remaining")
                         : tr("Pool gefüllt · Sammlung läuft weiter", "Pool filled · collection continues"))
                        .appFont(size: 14, design: .rounded)
                        .foregroundStyle(model.remainingMouseEvents > 0 ? AppPalette.secondaryText : AppPalette.teal)
                }
                ProgressView(value: model.collectionProgress)
                    .tint(AppPalette.teal)
                    .accessibilityLabel(tr("Mauspool füllen", "Fill mouse pool"))
                Text(tr(
                    "Der Pool hält die letzten \(model.language.number(EntropyPool.capacity)) Bewegungen. Die Mausdaten erhalten keinen geschätzten Entropiewert.",
                    "The pool retains the most recent \(model.language.number(EntropyPool.capacity)) movements. Mouse data is not assigned an estimated entropy value."
                ))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)

                Toggle(isOn: $model.userConfirmedSecureEnvironment) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Sichere Umgebung bestätigen", "Confirm a secure environment"))
                            .appFont(size: 14, weight: .bold, design: .rounded)
                        Text(tr(
                            "Mac offline · keine Aufnahme, Bildschirmfreigabe oder Fernwartung · vertrauenswürdiges System",
                            "Mac offline · no recording, screen sharing, or remote support · trusted system"
                        ))
                            .appFont(size: 14, design: .rounded)
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(model.phase == .generated)
                .accessibilityHint(tr(
                    "Diese Bestätigung wird bei App-Wechsel, Minimierung, Ruhezustand oder Sitzungswechsel zurückgesetzt.",
                    "This confirmation resets when switching apps, minimizing, sleeping, or changing sessions."
                ))
                HStack {
                    Text(tr("\(model.language.number(model.poolShuffleCount)) Mischvorgänge", "\(model.language.number(model.poolShuffleCount)) shuffles"))
                        .appFont(size: 14, design: .monospaced)
                        .foregroundStyle(AppPalette.mutedText)
                    Spacer()
                    Button(action: model.generate) {
                        Label(
                            model.phase == .generated
                                ? tr("Passwort erzeugt", "Password generated")
                                : tr("Passwort erzeugen", "Generate password"),
                            systemImage: "sparkles"
                        )
                        .appFont(size: 14, weight: .bold, design: .rounded)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canGenerate)
                }
                if !model.runtimeSecurity.isEnforced {
                    Label(tr(
                        "Die Generierung erfordert eine gültige Signatur, Hardened Runtime, minimale App-Sandbox, deaktivierte Core-Dumps und keinen Debugger.",
                        "Generation requires a valid signature, Hardened Runtime, a minimal App Sandbox, disabled core dumps, and no debugger."
                    ), systemImage: "exclamationmark.triangle.fill")
                        .appFont(size: 14, design: .rounded)
                        .foregroundStyle(AppPalette.amber)
                }
            }
        }
    }

    private var resultSection: some View {
        SectionCard(
            step: "03",
            title: tr("Dein Passwort", "Your password"),
            subtitle: modeTitle(model.generatedPassword?.mode ?? model.selectedMode)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                NominalSecurityIndicator(
                    entropyBits: model.generatedPassword?.entropyBits,
                    level: model.generatedPassword?.nominalSecurityLevel,
                    language: model.language,
                    excludesChecksum: model.generatedPassword?.mode == .bip39,
                    showsLegend: false
                )
                HStack {
                    Label(
                        model.isGeneratedMnemonicValid
                            ? tr("BIP39-Prüfsumme gültig", "BIP39 checksum valid")
                            : tr("Gleichverteilte Auswahl", "Uniform selection"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppPalette.teal)
                    Spacer()
                    Button {
                        if model.isMnemonicVisible { model.concealMnemonic() }
                        else { showRevealConfirmation = true }
                    } label: {
                        Label(
                            model.isMnemonicVisible ? tr("Verdecken", "Hide") : tr("Anzeigen", "Reveal"),
                            systemImage: model.isMnemonicVisible ? "eye.slash" : "eye"
                        )
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Text(model.isMnemonicVisible
                     ? tr("Anzeige für ca. 60 Sekunden oder bis zur Deaktivierung.", "Shown for about 60 seconds or until deactivation.")
                     : tr("Das Ergebnis bleibt bis zur bestätigten Anzeige verdeckt.", "The result stays hidden until reveal is confirmed."))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(model.isMnemonicVisible ? AppPalette.amber : AppPalette.secondaryText)

                if model.generatedPassword?.mode.usesWords == true {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                            ForEach(Array(model.mnemonicWords.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", index + 1))
                                        .foregroundStyle(AppPalette.teal)
                                        .appFont(size: 14, design: .monospaced)
                                    Text(model.isMnemonicVisible ? word : "••••••••")
                                        .appFont(size: 15, weight: .semibold, design: .monospaced)
                                    Spacer(minLength: 0)
                                }
                                .padding(11)
                                .background(AppPalette.wordChip, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(model.isMnemonicVisible
                                    ? tr("Wort \(index + 1), \(word)", "Word \(index + 1), \(word)")
                                    : tr("Wort \(index + 1), verdeckt", "Word \(index + 1), hidden"))
                            }
                        }
                    }
                    .frame(height: CGFloat(min((model.mnemonicWords.count + 2) / 3, 7) * 52) * displayMetrics.scale)
                    .privacySensitive()
                } else {
                    ScrollView {
                        Text(model.isMnemonicVisible ? model.generatedText : "••••••••••••••••••••••••")
                            .appFont(size: 18, weight: .semibold, design: .monospaced)
                            .tracking(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .accessibilityLabel(model.isMnemonicVisible ? model.generatedText : tr("Passwort verdeckt", "Password hidden"))
                    }
                    .frame(height: 240 * displayMetrics.scale)
                    .background(AppPalette.wordChip, in: RoundedRectangle(cornerRadius: 12))
                    .privacySensitive()
                }
                HStack(spacing: 12) {
                    Text(model.isClipboardClearScheduled
                         ? tr("Löschung der Zwischenablage nach ca. 45 Sekunden vorgesehen.", "Clipboard clearing is scheduled after about 45 seconds.")
                         : tr("Universal Clipboard ist deaktiviert. Lokale Apps können die Kopie dennoch lesen.", "Universal Clipboard is disabled. Local apps may still read the copy."))
                        .appFont(size: 14, design: .rounded)
                        .foregroundStyle(AppPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: model.copyMnemonic) {
                        Label(tr("Kopieren · 45 s", "Copy · 45 sec"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!model.isMnemonicVisible)
                    Button { showDiscardConfirmation = true } label: {
                        Label(tr("Verwerfen", "Discard"), systemImage: "trash")
                    }
                    .buttonStyle(DangerButtonStyle())
                }
                Divider().overlay(AppPalette.border)
                integrityProof
            }
        }
    }

    private var integrityProof: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showIntegrityDetails.toggle()
            } label: {
                Label(tr("Wortlisten und Zufallsverfahren", "Word lists and random generation"), systemImage: showIntegrityDetails ? "chevron.up" : "chevron.down")
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .buttonStyle(.plain)
            if showIntegrityDetails {
                Text(LocalizedMessage.randomGenerationExplanation.value(in: model.language))
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let integrity = model.wordListIntegrity {
                    HashRow(name: "BIP39 SHA-256", value: integrity.sha256)
                    HashRow(name: "BIP39 SHA3-512", value: integrity.sha3_512)
                }
                if let integrity = model.effWordListIntegrity {
                    HashRow(name: "EFF SHA-256", value: integrity.sha256)
                    HashRow(name: "EFF SHA3-512", value: integrity.sha3_512)
                }
            }
        }
    }

    private var securityNote: some View {
        Text(tr(
            "Die Entropieanzeige beschreibt den theoretischen Auswahlraum bei gleichverteilter Zufallsauswahl. Hashlängen und Mausereignisse werden nicht als zusätzliche Entropie gezählt. Nutze ein vertrauenswürdiges System. Seedphrasen gewähren Zugriff auf das zugehörige Wallet.",
            "The entropy display describes the theoretical selection space with uniform random sampling. Hash lengths and mouse events are not counted as additional entropy. Use a trusted system. Seed phrases grant access to the associated wallet."
        ))
        .appFont(size: 14, design: .rounded)
        .foregroundStyle(AppPalette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeDescription: String {
        switch model.selectedMode {
        case .bip39: tr("Englische BIP39-Wortliste mit Prüfsumme: 12, 15, 18, 21 oder 24 Wörter.", "English BIP39 word list with checksum: 12, 15, 18, 21, or 24 words.")
        case .eff: tr("EFF Large Wordlist: 7776 englische Wörter, 6 bis 128 Wörter pro Passwort.", "EFF Large Wordlist: 7776 English words, 6 to 128 words per password.")
        case .ascii: tr("94 druckbare ASCII-Zeichen ohne Leerzeichen (! bis ~), 8 bis 256 Zeichen.", "94 printable ASCII characters without spaces (! through ~), 8 to 256 characters.")
        case .pin: tr("Ziffern 0 bis 9, 3 bis 512 Zeichen. Führende Nullen bleiben erhalten.", "Digits 0 through 9, 3 to 512 characters. Leading zeroes are preserved.")
        case .hex: tr("Hexadezimale Zeichen 0 bis 9 und a bis f, 1 bis 512 Zeichen. Jedes Zeichen entspricht 4 Bit.", "Hexadecimal characters 0 through 9 and a through f, 1 to 512 characters. Each character represents 4 bits.")
        }
    }

    private func modeTitle(_ mode: GeneratorMode) -> String {
        switch mode {
        case .bip39: "BIP39"
        case .eff: "EFF"
        case .ascii: "ASCII-94"
        case .pin: "PIN"
        case .hex: "Hex"
        }
    }

    private func tr(_ german: String, _ english: String) -> String {
        model.language.text(german, english)
    }
}

private struct NominalSecurityIndicator: View {
    @Environment(\.appDisplayMetrics) private var metrics
    let entropyBits: Double?
    let level: NominalSecurityLevel?
    let language: AppLanguage
    let excludesChecksum: Bool
    let showsLegend: Bool

    private var activeLevel: NominalSecurityLevel? {
        guard let entropyBits, entropyBits.isFinite, entropyBits >= 0 else { return nil }
        return level
    }

    private var appearance: NominalLevelAppearance { NominalLevelAppearance(level: activeLevel) }

    private var formattedBits: String {
        guard activeLevel != nil, let entropyBits else { return "…" }
        return entropyBits.formatted(.number.precision(.fractionLength(1)).locale(language.locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Nominelle Entropie", "Nominal entropy"))
                        .appFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AppPalette.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formattedBits)
                            .appFont(size: 27, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(tr("Bit", "bits"))
                            .appFont(size: 14, weight: .medium, design: .rounded)
                            .foregroundStyle(AppPalette.secondaryText)
                        if excludesChecksum, activeLevel != nil {
                            Text(tr("ohne Prüfsumme", "excluding checksum"))
                                .appFont(size: 14, design: .rounded)
                                .foregroundStyle(AppPalette.secondaryText)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("Nominelle Entropie", "Nominal entropy"))
                .accessibilityValue(activeLevel == nil
                    ? title(for: nil)
                    : "\(formattedBits) \(tr("Bit", "bits"))\(excludesChecksum ? tr(", ohne Prüfsummenbits", ", excluding checksum bits") : "")")
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Label(title(for: activeLevel), systemImage: appearance.symbol)
                        .appFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundStyle(appearance.text)
                        .fixedSize(horizontal: false, vertical: true)
                    NominalSecurityInfoButton(
                        title: title(for: activeLevel), level: activeLevel,
                        entropyBits: activeLevel == nil ? nil : entropyBits, language: language
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(appearance.chip, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(appearance.accent.opacity(0.72), lineWidth: 1))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("Einordnung des Auswahlraums", "Selection-space rating"))

            AttackCostRows(entropyBits: activeLevel == nil ? nil : entropyBits, language: language)

            Text(explanation)
                .appFont(size: 14, design: .rounded)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showsLegend { legend }

            Text(tr(
                "Nomineller Auswahlraum bei gleichverteilter Auswahl. Keine Messung der Zufallsquelle und keine Garantie für die Gesamtsicherheit.",
                "Nominal selection space with uniform sampling. No measurement of the random source and no guarantee of overall security."
            ))
            .appFont(size: 14, design: .rounded)
            .foregroundStyle(AppPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(appearance.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(appearance.accent.opacity(0.28), lineWidth: 1))
    }

    private var legend: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: metrics.viewportSize.width / metrics.scale >= 1_400 ? 4 : 2),
            alignment: .leading, spacing: 14
        ) {
            ForEach(NominalSecurityLevel.allCases, id: \.rawValue) { candidate in
                let style = NominalLevelAppearance(level: candidate)
                let isSelected = activeLevel == candidate
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(style.accent.opacity(isSelected ? 1 : 0.44))
                        .frame(height: 5)
                        .accessibilityHidden(true)
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: style.symbol)
                            .appFont(size: 14, weight: .semibold)
                            .foregroundStyle(style.text)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(range(for: candidate))
                                .appFont(size: 14, weight: .bold, design: .rounded)
                                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.76))
                            HStack(alignment: .top, spacing: 3) {
                                Text(title(for: candidate))
                                    .appFont(size: 14, design: .rounded)
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                NominalSecurityInfoButton(
                                    title: title(for: candidate), level: candidate,
                                    entropyBits: isSelected ? entropyBits : nil, language: language
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(range(for: candidate)), \(title(for: candidate))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Vier Stufen des nominellen Auswahlraums", "Four levels of nominal selection space"))
    }

    private var explanation: String {
        switch activeLevel {
        case .below128:
            tr("Beide Laufzeiten gelten für die aktuelle Auswahl. Klassisch wird die vollständige Suche gezeigt, der Mittelwert ist ungefähr halb so groß. Die Stufe bedeutet nicht, dass jedes Passwort unter 128 Bit praktisch schnell erraten werden kann.", "Both times apply to the current selection. Classical time shows full search; the average is approximately half as long. This level does not mean that every password below 128 bits can be guessed quickly in practice.")
        case .atLeast128:
            tr("Bei 128 Bit dauert die ideale Grover-Suche im Petahertz-Modell etwa vier Stunden. Die benötigten Iterationen wachsen mit der Quadratwurzel des Auswahlraums. Reale Quantenhardware wird hier nicht bewertet.", "At 128 bits, ideal Grover search takes about four hours in the petahertz model. Required iterations grow with the square root of the selection space. Real quantum hardware is not assessed here.")
        case .atLeast256:
            tr("Schon bei 256 Bit benötigt die ideale Grover-Suche im Petahertz-Modell etwa 8,47 Billiarden Jahre. Die Einordnung gilt für die angenommene Suche; andere Angriffswege bleiben möglich.", "At 256 bits, ideal Grover search already takes about 8.47 quadrillion years in the petahertz model. This classification applies to the assumed search; other attack paths remain possible.")
        case .atLeast1024:
            tr("Ab 1.024 Bit erreicht Brute-Force im definierten Lösch- und Energiemodell keine nennenswerte Erfolgschance. Beide Suchzeiten überschreiten außerdem den angenommenen Horizont von 10^106 Jahren. Dies ist eine bedingte Modellrechnung, kein allgemeiner physikalischer Beweis.", "From 1,024 bits, brute force has no appreciable success probability in the defined erasure and energy model. Both search times also exceed the assumed 10^106-year horizon. This is a conditional model calculation, not a general physical proof.")
        case nil:
            tr("Die aktuelle Eingabe hat noch keine gültige Länge.", "The current input does not yet have a valid length.")
        }
    }

    private func title(for level: NominalSecurityLevel?) -> String {
        switch level {
        case .below128: tr("knackbar", "crackable")
        case .atLeast128: tr("nicht quantensicher", "not quantum-safe")
        case .atLeast256: tr("praktisch nicht angreifbar", "practically unattackable")
        case .atLeast1024: tr("thermodynamisch nicht angreifbar", "thermodynamically unattackable")
        case nil: tr("Noch keine Einordnung", "Not rated yet")
        }
    }

    private func range(for level: NominalSecurityLevel) -> String {
        switch level {
        case .below128: tr("< 128 Bit", "< 128 bits")
        case .atLeast128: tr("128 bis < 256 Bit", "128 to < 256 bits")
        case .atLeast256: tr("256 bis < 1.024 Bit", "256 to < 1,024 bits")
        case .atLeast1024: tr("≥ 1.024 Bit", "≥ 1,024 bits")
        }
    }

    private func tr(_ german: String, _ english: String) -> String {
        language.text(german, english)
    }
}

private struct AttackCostRows: View {
    let entropyBits: Double?
    let language: AppLanguage

    private var estimate: AttackCostEstimate? { entropyBits.flatMap(AttackCostEstimate.init(nominalEntropyBits:)) }
    private var presentation: AttackCostPresentation { AttackCostPresentation(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                name: tr("Exascale-Computer", "Exascale computer"), symbol: "desktopcomputer",
                estimate: estimate?.classic,
                detail: tr("Vollsuche · 10^18 Prüfungen/s", "Full search · 10^18 checks/s"),
                mean: estimate.map { presentation.duration(log10Seconds: $0.classicalMeanLog10Seconds) }
            )
            Divider().overlay(AppPalette.border)
            row(
                name: tr("Petahertz-Quantencomputer", "Petahertz quantum computer"), symbol: "atom",
                estimate: estimate?.grover,
                detail: tr("Grover · 10^15 vollständige Iterationen/s", "Grover · 10^15 complete iterations/s"),
                mean: nil
            )
            Text(tr("Hypothetische Modelle, keine gemessenen Angriffszeiten.", "Hypothetical models, not measured attack times."))
                .appFont(size: 14, design: .rounded)
                .foregroundStyle(AppPalette.secondaryText)
        }
        .padding(12)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }

    private func row(
        name: String, symbol: String, estimate: AttackCostEstimate.SearchEstimate?, detail: String, mean: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(name, systemImage: symbol)
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                Spacer(minLength: 4)
                Text(estimate.map { "≈ \(presentation.duration(log10Seconds: $0.log10Seconds))" } ?? "—")
                    .appFont(size: 14, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(detail)
                Spacer(minLength: 0)
                if let mean { Text(tr("im Mittel ≈ \(mean)", "on average ≈ \(mean)")) }
            }
            .appFont(size: 14, design: .rounded)
            .foregroundStyle(AppPalette.secondaryText)
            HStack(alignment: .top, spacing: 12) {
                modelStatus(
                    title: tr("Landauer-Budget", "Landauer budget"),
                    exceeds: estimate?.exceedsLandauerBudget,
                    within: tr("Suchaufwand im Budget", "search cost within budget"),
                    beyond: tr("Suchaufwand > Budget", "search cost > budget")
                )
                Spacer(minLength: 0)
                modelStatus(
                    title: tr("10^106-Jahre-Horizont", "10^106-year horizon"),
                    exceeds: estimate?.exceedsCosmicTimeHorizon,
                    within: tr("innerhalb", "within"), beyond: tr("überschritten", "exceeded")
                )
            }
            .appFont(size: 14, design: .rounded)
        }
        .accessibilityElement(children: .combine)
    }

    private func modelStatus(title: String, exceeds: Bool?, within: String, beyond: String) -> some View {
        Label(
            "\(title): \(exceeds.map { $0 ? beyond : within } ?? "—")",
            systemImage: exceeds == true ? "arrow.up.right.circle" : "circle.dotted"
        )
        .foregroundStyle(exceeds == true ? AppPalette.teal : AppPalette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tr(_ german: String, _ english: String) -> String { language.text(german, english) }
}

private struct NominalSecurityInfoButton: View {
    @Environment(\.appDisplayMetrics) private var metrics
    let title: String
    let level: NominalSecurityLevel?
    let entropyBits: Double?
    let language: AppLanguage
    @State private var showsInformation = false

    private var explanation: String {
        language.text(
            "Die Einordnung bezieht sich auf das Erraten des Passworts durch Brute-Force bei gleichverteilter Zufallsauswahl. Sie beschreibt den nominellen Auswahlraum. Die Bezeichnungen sind vereinfachte Stufen, keine Garantie: Sie bewerten keine reale Quantenhardware und sind kein thermodynamischer Nachweis. Andere Angriffswege werden nicht erfasst.",
            "The classification refers to guessing the password by brute force with uniformly random selection. It describes the nominal selection space. The labels are simplified levels, not a guarantee: they do not assess real quantum hardware and are not thermodynamic proof. Other attack paths are not covered."
        )
    }

    private var levelExplanation: String {
        switch level {
        case .below128:
            tr(
                "Unter 128 Bit: Der Exascale-Computer prüft im Modell 10^18 Passwörter pro Sekunde. Für N = 2^n Möglichkeiten dauert die vollständige Suche N / 10^18 Sekunden, im Mittel ungefähr halb so lange. Die aktuelle Modelllaufzeit steht unter dem Entropiewert. Die Bezeichnung bedeutet nicht, dass jedes Passwort dieser Stufe praktisch schnell erraten werden kann.",
                "Below 128 bits: the exascale computer checks 10^18 passwords per second in this model. For N = 2^n possibilities, a full search takes N / 10^18 seconds, and about half that on average. The current model time appears below the entropy value. The label does not mean that every password in this level can be guessed quickly in practice."
            )
        case .atLeast128:
            tr(
                "128 bis unter 256 Bit: Die ideale Grover-Suche benötigt ungefähr (π/4) · 2^(n/2) Iterationen für nahezu sicheren Erfolg. Der Petahertz-Quantencomputer führt im Modell 10^15 vollständige Iterationen pro Sekunde aus. Die daraus berechnete Zeit bewertet keine reale Quantenhardware; die Bezeichnung ist eine vereinfachte Stufe.",
                "128 to below 256 bits: ideal Grover search needs approximately (π/4) · 2^(n/2) iterations for near-certain success. The petahertz quantum computer performs 10^15 complete iterations per second in this model. The resulting time does not assess real quantum hardware; the label is a simplified level."
            )
        case .atLeast256:
            tr(
                "256 bis unter 1.024 Bit: Schon bei 256 Bit dauert die ideale Grover-Suche mit 10^15 vollständigen Iterationen pro Sekunde etwa 8,47 Billiarden Jahre. Klassisch wären es mit 10^18 Prüfungen pro Sekunde etwa 3,67 × 10^51 Jahre für die vollständige Suche. Diese Einordnung gilt für das angenommene Suchmodell, nicht für sämtliche Angriffsmöglichkeiten.",
                "256 to below 1,024 bits: at 256 bits, ideal Grover search at 10^15 complete iterations per second takes about 8.47 quadrillion years. Classical full search at 10^18 checks per second would take about 3.67 × 10^51 years. This classification applies to the assumed search model, not to every possible attack."
            )
        case .atLeast1024:
            tr(
                "Ab 1.024 Bit: Unter der zusätzlichen Annahme einer irreversiblen Löschung von mindestens einem Bit Information je Grover-Iteration bei 2,7 K erfordert die Suche bei 1.024 Bit mindestens etwa 2,72 × 10^131 J. Das sind rund 9,07 × 10^59 angenommene Energiebudgets von je 3 × 10^71 J. Innerhalb eines solchen Budgets beträgt die ideale Grover-Erfolgswahrscheinlichkeit bei 1.024 Bit nur ungefähr 3 × 10^-120: keine hohe Erfolgschance in diesem Modell. Die Grover-Laufzeit von etwa 3,34 × 10^131 Jahren übersteigt den angenommenen Horizont von 10^106 Jahren um den Faktor 3,34 × 10^25. Reversible Quantenrechnung erzwingt die Löschannahme nicht. Dies ist kein allgemeiner physikalischer Unmöglichkeitsbeweis.",
                "From 1,024 bits: with the additional assumption that each Grover iteration irreversibly erases at least one bit of information at 2.7 K, search at 1,024 bits requires at least about 2.72 × 10^131 J. This is roughly 9.07 × 10^59 assumed energy budgets of 3 × 10^71 J each. Within one such budget, ideal Grover success probability at 1,024 bits is only about 3 × 10^-120: no high success probability in this model. Grover time of about 3.34 × 10^131 years exceeds the assumed 10^106-year horizon by a factor of 3.34 × 10^25. Reversible quantum computation does not require the assumed erasure. This is not a general proof of physical impossibility."
            )
        case nil:
            tr("Gib eine gültige Länge ein, um die Modelllaufzeiten zu sehen.", "Enter a valid length to see the model times.")
        }
    }

    var body: some View {
        Button {
            showsInformation = true
        } label: {
            Image(systemName: "info.circle")
                .appFont(size: 14, weight: .medium)
                .foregroundStyle(AppPalette.secondaryText)
                .frame(width: 28 * metrics.scale, height: 28 * metrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help(explanation)
        .accessibilityLabel(language.text("Information zur Stufe: \(title)", "Information about the level: \(title)"))
        .accessibilityHint(language.text("Öffnet die Erklärung zur Einordnung.", "Opens an explanation of the classification."))
        .popover(isPresented: $showsInformation, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .appFont(size: 14, weight: .semibold, design: .rounded)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let entropyBits, AttackCostEstimate(nominalEntropyBits: entropyBits) != nil {
                            Text(tr(
                                "Aktuelle Auswahl: \(entropyBits.formatted(.number.precision(.fractionLength(1)).locale(language.locale))) Bit",
                                "Current selection: \(entropyBits.formatted(.number.precision(.fractionLength(1)).locale(language.locale))) bits"
                            ))
                            .appFont(size: 14, weight: .semibold, design: .rounded)
                            AttackCostRows(entropyBits: entropyBits, language: language)
                        }
                        infoSection(tr("Diese Stufe", "This level"), text: levelExplanation)
                        infoSection(tr("Gemeinsame Modellannahmen", "Shared model assumptions"), text: commonAssumptions)
                        infoSection(tr("Energie und Zeithorizont", "Energy and time horizon"), text: budgetAssumptions)
                        if level == .atLeast1024 {
                            infoSection(tr("Passwörter als Schlüsselquelle", "Passwords as a key source"), text: keySourceExplanation)
                        }
                        infoSection(tr("Geltungsbereich", "Scope"), text: explanation)
                        sourceLinks
                    }
                    .padding(.trailing, 8)
                }
                .frame(height: metrics.popoverScrollHeight)
                HStack {
                    Spacer()
                    Button(language.text("Schließen", "Close")) {
                        showsInformation = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(18)
            .frame(width: metrics.popoverWidth)
            .appFont(size: 14)
            .preferredColorScheme(.dark)
        }
    }

    private var commonAssumptions: String {
        tr(
            "Genau ein richtiges Passwort unter N = 2^n gleichwahrscheinlichen Möglichkeiten. n beschreibt den nominellen Auswahlraum, nicht die gemessene Entropie der Quelle. Klassisch werden Kandidaten ohne Wiederholung geprüft: volle Suche N Prüfungen, mittlerer Erfolg nach (N + 1)/2 Prüfungen. Grover wird als ideale serielle Suche für nahezu sicheren Erfolg modelliert. 10^18 klassische Prüfungen/s und 10^15 vollständige Grover-Iterationen/s sind angenommene Raten. Sie sind weder Hardwaremessungen noch universelle Geschwindigkeitsgrenzen. Eine vollständige Iteration umfasst die Passwortprüfung; Gatterkosten, Fehlerkorrektur und Parallelisierung werden nicht separat simuliert. Ein Jahr entspricht 365,25 Tagen.",
            "Exactly one correct password among N = 2^n equally likely possibilities. n describes nominal selection space, not measured source entropy. Classical candidates are checked without repetition: full search takes N checks, with success after (N + 1)/2 checks on average. Grover is modeled as ideal serial search for near-certain success. 10^18 classical checks/s and 10^15 complete Grover iterations/s are assumed rates, neither hardware measurements nor universal speed limits. A complete iteration includes password verification; gate costs, error correction and parallelization are not simulated separately. One year equals 365.25 days."
        )
    }

    private var budgetAssumptions: String {
        tr(
            "Landauer-Modell: 2,7 K, ein irreversibel gelöschtes Bit Information je Prüfung bzw. Iteration und ein angenommenes Gesamtbudget von 3 × 10^71 J. Die Mindestenergie je Löschung beträgt kBT ln(2). Die Löschannahme folgt nicht automatisch aus Grover oder reversibler Rechnung. Ein überschrittenes Budget bedeutet hier nur, dass die vollständige klassische bzw. nahezu sicher erfolgreiche Grover-Suche mehr erfordert. Erfolgreiche Teilsuchen sind dadurch nicht ausgeschlossen: Bei 626 Bit erreicht Grover mit dem angesetzten Budget noch etwa 96,8 % Erfolg.\n\nZeithorizont-Modell: 10^106 Jahre sind ein angenommener kosmologischer Vergleichshorizont. Das ist weder ein gesicherter Zeitpunkt maximaler Entropie noch eine universelle Frist für das Ende jeder Berechnung. Temperatur, verfügbares Budget und kosmologische Entwicklung sind zusätzliche Annahmen, kein allgemeiner physikalischer Sicherheitsbeweis.",
            "Landauer model: 2.7 K, one irreversibly erased bit of information per check or iteration, and an assumed total budget of 3 × 10^71 J. Minimum energy per erasure is kBT ln(2). The erasure assumption does not follow automatically from Grover or reversible computation. Exceeding this budget only means that complete classical search or near-certain Grover search needs more. It does not exclude successful partial searches: at 626 bits, Grover still achieves about 96.8% success with the assumed budget.\n\nTime-horizon model: 10^106 years is an assumed cosmological comparison horizon. It is neither an established time of maximum entropy nor a universal deadline for all computation to end. Temperature, available budget and cosmological evolution are additional assumptions, not a general physical security proof."
        )
    }

    private var keySourceExplanation: String {
        tr(
            "Ein Passwortauswahlraum dieser Größe kann für die Schlüsselversorgung von Threefish-1024 oder passend konstruierten Chiffrenkaskaden ausreichen. Das setzt voraus, dass die Zufallsquelle die benötigte Unvorhersagbarkeit tatsächlich liefert und eine geeignete KDF sie erhält sowie nötige Teilschlüssel korrekt trennt. Eine KDF erzeugt keine fehlende Entropie. Schlüsselbreite und Passwortsuchraum beweisen keine entsprechende Gesamtsicherheit einer Chiffre oder Kaskade; Angriffe auf deren Konstruktion und Implementierung bleiben gesondert zu bewerten.",
            "A password selection space of this size can be sufficient to supply keys for Threefish-1024 or appropriately constructed cipher cascades. This assumes that the random source actually provides the required unpredictability and that a suitable KDF preserves it and correctly separates any required subkeys. A KDF cannot create missing entropy. Key width and password search space do not prove corresponding overall security of a cipher or cascade; attacks on its construction and implementation require separate assessment."
        )
    }

    private func infoSection(_ heading: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading).appFont(size: 14, weight: .bold, design: .rounded)
            Text(text)
                .appFont(size: 14, design: .rounded)
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(tr("Quellen und Hintergrund", "Sources and background"))
                .appFont(size: 14, weight: .bold, design: .rounded)
            Link("Zalka: Grover’s quantum searching algorithm is optimal", destination: URL(string: "https://arxiv.org/abs/quant-ph/9711070")!)
            Link("Landauer: Irreversibility and Heat Generation in the Computing Process (PDF)", destination: URL(string: "https://www.dna.caltech.edu/courses/cs191/paperscs191/landauer1961.pdf")!)
            Link("Bennett: Logical Reversibility of Computation", destination: URL(string: "https://www.cs.princeton.edu/courses/archive/fall04/cos576/papers/bennett73.html")!)
            Link(tr("NIST: Boltzmann-Konstante", "NIST: Boltzmann constant"), destination: URL(string: "https://www.nist.gov/si-redefinition/kelvin/kelvin-boltzmann-constant")!)
            Link(tr("Adams & Laughlin: kosmologische Zukunftsszenarien", "Adams & Laughlin: cosmological future scenarios"), destination: URL(string: "https://arxiv.org/abs/astro-ph/9701131")!)
            if level == .atLeast1024 {
                Link("Threefish / Skein specification (PDF)", destination: URL(string: "https://www.schneier.com/wp-content/uploads/2015/01/skein.pdf")!)
                Link("NIST SP 800-132: Password-Based Key Derivation", destination: URL(string: "https://csrc.nist.gov/pubs/sp/800/132/final")!)
            }
        }
        .appFont(size: 14, design: .rounded)
        .tint(AppPalette.teal)
    }

    private func tr(_ german: String, _ english: String) -> String { language.text(german, english) }
}

private struct NominalLevelAppearance {
    let accent: Color
    let text: Color
    let chip: Color
    let symbol: String

    init(level: NominalSecurityLevel?) {
        switch level {
        case .below128:
            accent = Color(red: 0.95, green: 0.34, blue: 0.41)
            text = Color(red: 1.0, green: 0.73, blue: 0.77)
            chip = Color(red: 0.25, green: 0.09, blue: 0.12)
            symbol = "exclamationmark.triangle.fill"
        case .atLeast128:
            accent = Color(red: 0.97, green: 0.76, blue: 0.28)
            text = Color(red: 1.0, green: 0.88, blue: 0.58)
            chip = Color(red: 0.25, green: 0.20, blue: 0.08)
            symbol = "circle.lefthalf.filled"
        case .atLeast256:
            accent = Color(red: 0.71, green: 0.93, blue: 0.46)
            text = Color(red: 0.84, green: 1.0, blue: 0.67)
            chip = Color(red: 0.17, green: 0.24, blue: 0.09)
            symbol = "chart.bar.fill"
        case .atLeast1024:
            accent = Color(red: 0.18, green: 0.62, blue: 0.39)
            text = Color(red: 0.85, green: 1.0, blue: 0.91)
            chip = Color(red: 0.07, green: 0.28, blue: 0.18)
            symbol = "square.stack.3d.up.fill"
        case nil:
            accent = Color(red: 0.48, green: 0.56, blue: 0.66)
            text = Color(red: 0.78, green: 0.82, blue: 0.88)
            chip = AppPalette.panelStrong
            symbol = "questionmark.circle"
        }
    }
}

private struct SectionCard<Content: View>: View {
    let step: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                Text(step)
                    .appFont(size: 14, weight: .heavy, design: .monospaced)
                    .foregroundStyle(AppPalette.teal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AppPalette.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .appFont(size: 18, weight: .bold, design: .rounded)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .appFont(size: 14, design: .rounded)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
            }
            content
        }
        .padding(22)
        .background(AppPalette.panel, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
    }
}

private struct SecurityBadge: View {
    @Environment(\.appDisplayMetrics) private var metrics
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .appFont(size: 14, weight: .semibold)
                .foregroundStyle(AppPalette.teal)
                .frame(width: 28 * metrics.scale, height: 28 * metrics.scale)
                .background(AppPalette.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(size: 14, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .appFont(size: 14, design: .rounded)
                    .foregroundStyle(AppPalette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(AppPalette.panelStrong, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppPalette.border, lineWidth: 1))
    }
}

private struct LanguageSwitcher: View {
    @Binding var selection: AppLanguage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selection = language
                } label: {
                    Text(language.shortLabel)
                        .appFont(size: 14, weight: .bold, design: .rounded)
                        .foregroundStyle(
                            selection == language ? Color.white : AppPalette.mutedText
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            selection == language
                                ? AppPalette.teal.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.displayName)
                .accessibilityAddTraits(selection == language ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppPalette.panelStrong, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            selection.text("Sprache", "Language")
        )
    }
}

private struct HashRow: View {
    let name: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .appFont(size: 14, weight: .bold, design: .rounded)
                .foregroundStyle(AppPalette.teal)
            Text(value)
                .appFont(size: 14, design: .monospaced)
                .foregroundStyle(AppPalette.secondaryText)
                .textSelection(.enabled)
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [AppPalette.teal.opacity(0.92), AppPalette.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .shadow(color: AppPalette.teal.opacity(0.18), radius: 12, y: 5)
            .saturation(isEnabled ? 1 : 0.28)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.38)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 14, weight: .bold, design: .rounded)
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(AppPalette.panelStrong, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38)
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appFont(size: 14, weight: .bold, design: .rounded)
            .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.62))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.20), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private enum AppPalette {
    static let background = Color(red: 0.025, green: 0.042, blue: 0.070)
    static let panel = Color(red: 0.055, green: 0.078, blue: 0.112).opacity(0.96)
    static let panelStrong = Color(red: 0.075, green: 0.100, blue: 0.138)
    static let canvasTop = Color(red: 0.033, green: 0.065, blue: 0.092)
    static let canvasBottom = Color(red: 0.025, green: 0.045, blue: 0.073)
    static let wordChip = Color(red: 0.067, green: 0.096, blue: 0.130)
    static let teal = Color(red: 0.23, green: 0.88, blue: 0.77)
    static let blue = Color(red: 0.25, green: 0.48, blue: 0.95)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let secondaryText = Color.white.opacity(0.66)
    static let mutedText = Color.white.opacity(0.56)
    static let border = Color.white.opacity(0.085)
}
