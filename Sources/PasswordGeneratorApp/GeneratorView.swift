import PasswordGeneratorCore
import SwiftUI

struct GeneratorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showIntegrityDetails = false
    @State private var showDiscardConfirmation = false
    @State private var showRevealConfirmation = false
    @State private var lengthText = ""

    var body: some View {
        ZStack {
            AppPalette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    securityStrip
                    configurationSection
                    mouseEntropySection
                    if model.phase == .generated {
                        resultSection
                    }
                    securityNote
                }
                .frame(maxWidth: 980)
                .padding(.horizontal, 30)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
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
                .frame(width: 58, height: 58)
                .background(AppPalette.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(tr("Seedphrasen, Wortpasswörter, ASCII, PINs und Hex. Lokal auf deinem Mac.", "Seed phrases, word passwords, ASCII, PINs, and hex. Locally on your Mac."))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            Spacer()
            LanguageSwitcher(selection: $model.language)
        }
    }

    private var securityStrip: some View {
        HStack(spacing: 10) {
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
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        TextField(tr("Länge", "Length"), text: $lengthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 78)
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
                            .font(.system(size: 12, design: .monospaced))
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
                    .font(.system(size: 11, design: .rounded))
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    TextField(tr("Kein Trennzeichen", "No separator"), text: $model.wordSeparator)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(width: 180)
                        .accessibilityLabel(tr("Trennzeichen beim Kopieren", "Separator when copying"))
                        .accessibilityHint(tr("Leer lassen, um die Wörter ohne Trennzeichen zu kopieren.", "Leave empty to copy words without a separator."))
                    Text(model.wordSeparator == " "
                         ? tr("Ein Leerzeichen", "One space")
                         : tr("Leer = ohne Trennzeichen", "Empty = no separator"))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppPalette.secondaryText)
                    Spacer(minLength: 0)
                }
                if model.selectedMode == .bip39 {
                    Text(tr(
                        "Für den Wallet-Import Leerzeichen verwenden. Ohne Trennzeichen gehen Wortgrenzen verloren. Das Trennzeichen ändert nur den kopierten Text.",
                        "Use spaces for wallet import. Without a separator, word boundaries are lost. The separator changes only the copied text."
                    ))
                    .font(.system(size: 11, design: .rounded))
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
                .font(.system(size: 11, design: .rounded))
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
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(model.remainingMouseEvents > 0
                         ? tr("Noch \(model.language.number(model.remainingMouseEvents))", "\(model.language.number(model.remainingMouseEvents)) remaining")
                         : tr("Pool gefüllt · Sammlung läuft weiter", "Pool filled · collection continues"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(model.remainingMouseEvents > 0 ? AppPalette.secondaryText : AppPalette.teal)
                }
                ProgressView(value: model.collectionProgress)
                    .tint(AppPalette.teal)
                    .accessibilityLabel(tr("Mauspool füllen", "Fill mouse pool"))
                Text(tr(
                    "Der Pool hält die letzten \(model.language.number(EntropyPool.capacity)) Bewegungen. Die Mausdaten erhalten keinen geschätzten Entropiewert.",
                    "The pool retains the most recent \(model.language.number(EntropyPool.capacity)) movements. Mouse data is not assigned an estimated entropy value."
                ))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AppPalette.secondaryText)

                Toggle(isOn: $model.userConfirmedSecureEnvironment) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Sichere Umgebung bestätigen", "Confirm a secure environment"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(tr(
                            "Mac offline · keine Aufnahme, Bildschirmfreigabe oder Fernwartung · vertrauenswürdiges System",
                            "Mac offline · no recording, screen sharing, or remote support · trusted system"
                        ))
                            .font(.system(size: 11, design: .rounded))
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
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppPalette.mutedText)
                    Spacer()
                    Button(action: model.generate) {
                        Label(
                            model.phase == .generated
                                ? tr("Passwort erzeugt", "Password generated")
                                : tr("Passwort erzeugen", "Generate password"),
                            systemImage: "sparkles"
                        )
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
                        .font(.system(size: 11, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(model.isMnemonicVisible ? AppPalette.amber : AppPalette.secondaryText)

                if model.generatedPassword?.mode.usesWords == true {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                            ForEach(Array(model.mnemonicWords.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", index + 1))
                                        .foregroundStyle(AppPalette.teal)
                                        .font(.system(size: 10, design: .monospaced))
                                    Text(model.isMnemonicVisible ? word : "••••••••")
                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
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
                    .frame(height: CGFloat(min((model.mnemonicWords.count + 2) / 3, 7) * 43))
                    .privacySensitive()
                } else {
                    ScrollView {
                        Text(model.isMnemonicVisible ? model.generatedText : "••••••••••••••••••••••••")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .tracking(0.7)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .accessibilityLabel(model.isMnemonicVisible ? model.generatedText : tr("Passwort verdeckt", "Password hidden"))
                    }
                    .frame(minHeight: 64, maxHeight: 190)
                    .background(AppPalette.wordChip, in: RoundedRectangle(cornerRadius: 12))
                    .privacySensitive()
                }
                HStack(spacing: 12) {
                    Text(model.isClipboardClearScheduled
                         ? tr("Löschung der Zwischenablage nach ca. 45 Sekunden vorgesehen.", "Clipboard clearing is scheduled after about 45 seconds.")
                         : tr("Universal Clipboard ist deaktiviert. Lokale Apps können die Kopie dennoch lesen.", "Universal Clipboard is disabled. Local apps may still read the copy."))
                        .font(.system(size: 11, design: .rounded))
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .buttonStyle(.plain)
            if showIntegrityDetails {
                Text(LocalizedMessage.randomGenerationExplanation.value(in: model.language))
                    .font(.system(size: 11, design: .rounded))
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
        .font(.system(size: 11.5, design: .rounded))
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
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.secondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formattedBits)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(tr("Bit", "bits"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppPalette.secondaryText)
                        if excludesChecksum, activeLevel != nil {
                            Text(tr("ohne Prüfsumme", "excluding checksum"))
                                .font(.system(size: 10, design: .rounded))
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
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(appearance.text)
                        .fixedSize(horizontal: false, vertical: true)
                    NominalSecurityInfoButton(title: title(for: activeLevel), language: language)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(appearance.chip, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(appearance.accent.opacity(0.72), lineWidth: 1))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("Einordnung des Auswahlraums", "Selection-space rating"))

            Text(explanation)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(AppPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if showsLegend { legend }

            Text(tr(
                "Nomineller Auswahlraum bei gleichverteilter Auswahl. Keine Messung der Zufallsquelle und keine Garantie für die Gesamtsicherheit.",
                "Nominal selection space with uniform sampling. No measurement of the random source and no guarantee of overall security."
            ))
            .font(.system(size: 10.5, design: .rounded))
            .foregroundStyle(AppPalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(appearance.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(appearance.accent.opacity(0.28), lineWidth: 1))
    }

    private var legend: some View {
        HStack(alignment: .top, spacing: 10) {
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.text)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(range(for: candidate))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.76))
                            HStack(alignment: .top, spacing: 3) {
                                Text(title(for: candidate))
                                    .font(.system(size: 9.5, design: .rounded))
                                    .foregroundStyle(AppPalette.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                NominalSecurityInfoButton(title: title(for: candidate), language: language)
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
            tr("Ein kleinerer Suchraum bietet weniger Reserve gegen vollständiges Durchprobieren. Einsatz und Ratebegrenzungen spielen ebenfalls eine Rolle.", "A smaller search space provides less reserve against exhaustive guessing. The use case and rate limits also matter.")
        case .atLeast128:
            tr("Im idealen Grover-Suchmodell benötigen N Möglichkeiten ungefähr √N Abfragen. Reale Quantenhardware wird hier nicht bewertet.", "In the ideal Grover search model, N possibilities require roughly √N queries. Real quantum hardware is not assessed here.")
        case .atLeast256:
            tr("Bei ideal gleichverteilter Auswahl ist vollständiges Durchprobieren sehr aufwendig. Andere Angriffswege bleiben möglich.", "With ideally uniform selection, exhaustive guessing has a very high cost. Other attack paths remain possible.")
        case .atLeast1024:
            tr("Ein extrem großer nomineller Suchraum. Diese Stufe ist kein thermodynamischer Nachweis und keine Garantie gegen Angriffe.", "An extremely large nominal search space. This level is not thermodynamic proof or a guarantee against attacks.")
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

private struct NominalSecurityInfoButton: View {
    let title: String
    let language: AppLanguage
    @State private var showsInformation = false

    private var explanation: String {
        language.text(
            "Die Einordnung bezieht sich auf das Erraten des Passworts durch Brute-Force bei gleichverteilter Zufallsauswahl. Sie beschreibt den nominellen Auswahlraum. Die Bezeichnungen sind vereinfachte Stufen, keine Garantie: Sie bewerten keine reale Quantenhardware und sind kein thermodynamischer Nachweis. Andere Angriffswege werden nicht erfasst.",
            "The classification refers to guessing the password by brute force with uniformly random selection. It describes the nominal selection space. The labels are simplified levels, not a guarantee: they do not assess real quantum hardware and are not thermodynamic proof. Other attack paths are not covered."
        )
    }

    var body: some View {
        Button {
            showsInformation = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppPalette.secondaryText)
                .frame(width: 20, height: 20)
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
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(explanation)
                    .font(.system(size: 12, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(language.text("Schließen", "Close")) {
                        showsInformation = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(18)
            .frame(width: 360)
            .preferredColorScheme(.dark)
        }
    }
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
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppPalette.teal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(AppPalette.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11.5, design: .rounded))
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
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.teal)
                .frame(width: 28, height: 28)
                .background(AppPalette.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(AppPalette.mutedText)
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
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
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
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.teal)
            Text(value)
                .font(.system(size: 9.5, design: .monospaced))
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
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .saturation(isEnabled ? 1 : 0.28)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.38)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
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
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
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
