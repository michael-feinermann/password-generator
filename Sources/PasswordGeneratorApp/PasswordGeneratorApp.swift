import AppKit
import SwiftUI

enum AppIdentity {
    static let displayName = "Password Generator \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.3.5")"
}

@main
struct PasswordGeneratorApplication: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(AppIdentity.displayName) {
            GeneratorView()
                .environmentObject(model)
                .background(
                    PrivacyWindowConfigurator(
                        onResignKey: model.secureContextDidChange,
                        onMiniaturize: model.secureContextDidChange,
                        onClose: model.reset
                    )
                )
                .onAppear {
                    appDelegate.onConceal = model.secureContextDidChange
                    appDelegate.onTerminate = model.prepareForTermination
                }
                .frame(
                    minWidth: AppDisplayMetrics.minimumWindowSize.width,
                    minHeight: AppDisplayMetrics.minimumWindowSize.height
                )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: AppDisplayMetrics.minimumWindowSize.width,
            height: AppDisplayMetrics.minimumWindowSize.height
        )
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(AppIdentity.displayName) {
                Button(
                    model.language.text(
                        "Passwort verdecken",
                        "Hide password"
                    )
                ) {
                    model.concealMnemonic()
                }
                .font(.system(size: 14))
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model.phase != .generated || !model.isMnemonicVisible)
            }
        }
    }
}

private struct PrivacyWindowConfigurator: NSViewRepresentable {
    let onResignKey: () -> Void
    let onMiniaturize: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onResignKey: onResignKey,
            onMiniaturize: onMiniaturize,
            onClose: onClose
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateCallbacks(
            onResignKey: onResignKey,
            onMiniaturize: onMiniaturize,
            onClose: onClose
        )
        DispatchQueue.main.async {
            configure(nsView.window)
            context.coordinator.attach(to: nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.sharingType = .none
        window.hidesOnDeactivate = true
        window.isRestorable = false
        window.disableSnapshotRestoration()
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(
            calibratedRed: 0.025,
            green: 0.045,
            blue: 0.075,
            alpha: 1
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var observedWindow: NSWindow?
        private var onResignKey: () -> Void
        private var onMiniaturize: () -> Void
        private var onClose: () -> Void

        init(
            onResignKey: @escaping () -> Void,
            onMiniaturize: @escaping () -> Void,
            onClose: @escaping () -> Void
        ) {
            self.onResignKey = onResignKey
            self.onMiniaturize = onMiniaturize
            self.onClose = onClose
        }

        func updateCallbacks(
            onResignKey: @escaping () -> Void,
            onMiniaturize: @escaping () -> Void,
            onClose: @escaping () -> Void
        ) {
            self.onResignKey = onResignKey
            self.onMiniaturize = onMiniaturize
            self.onClose = onClose
        }

        func attach(to window: NSWindow?) {
            guard observedWindow !== window else { return }
            NotificationCenter.default.removeObserver(self)
            observedWindow = window
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillMiniaturize),
                name: NSWindow.willMiniaturizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        @objc private func windowDidResignKey() {
            onResignKey()
        }

        @objc private func windowWillMiniaturize() {
            onMiniaturize()
        }

        @objc private func windowWillClose() {
            onClose()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

@MainActor
private final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var onConceal: (() -> Void)?
    var onTerminate: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            workspaceNotifications.addObserver(
                self,
                selector: #selector(workspaceRequiresConcealment),
                name: name,
                object: nil
            )
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        onConceal?()
    }

    func applicationWillHide(_ notification: Notification) {
        onConceal?()
    }

    func applicationWillTerminate(_ notification: Notification) {
        onConceal?()
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func workspaceRequiresConcealment() {
        onConceal?()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
