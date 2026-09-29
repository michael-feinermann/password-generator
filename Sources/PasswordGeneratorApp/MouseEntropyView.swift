import AppKit
import SwiftUI

struct MouseEntropySample {
    let uptimeNanoseconds: UInt64
    let eventTimestamp: Double
    let x: Double
    let y: Double
    let deltaX: Double
    let deltaY: Double
    let canvasWidth: Double
    let canvasHeight: Double
    let modifierFlags: UInt64
    let pressedMouseButtons: UInt64
}

/// Observes the window's local event stream without intercepting controls or drags.
struct MouseEntropyView: NSViewRepresentable {
    let isEnabled: Bool
    let onMove: (MouseEntropySample) -> Void

    func makeNSView(context: Context) -> EntropyTrackingView {
        let view = EntropyTrackingView()
        view.onMove = onMove
        view.isCollectionEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: EntropyTrackingView, context: Context) {
        nsView.onMove = onMove
        nsView.isCollectionEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: EntropyTrackingView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class EntropyTrackingView: NSView {
    var onMove: ((MouseEntropySample) -> Void)?
    var isCollectionEnabled = true
    private var eventMonitor: Any?
    private var lastPoint: NSPoint?

    override var isOpaque: Bool { false }

    // This background observer must never win hit testing over actual UI controls.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.accept(event)
            }
            return event
        }
    }

    func stopMonitoring() {
        lastPoint = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    func accept(_ event: NSEvent) {
        guard isCollectionEnabled, let window, event.window === window else { return }
        let point = event.locationInWindow
        let windowBounds = NSRect(origin: .zero, size: window.frame.size)
        guard windowBounds.contains(point) else { return }
        let previousPoint = lastPoint
        lastPoint = point
        guard event.deltaX != 0 || event.deltaY != 0
                || previousPoint.map({ $0 != point }) == true else { return }
        onMove?(
            MouseEntropySample(
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                eventTimestamp: event.timestamp,
                x: Double(point.x),
                y: Double(point.y),
                deltaX: Double(event.deltaX),
                deltaY: Double(event.deltaY),
                canvasWidth: Double(windowBounds.width),
                canvasHeight: Double(windowBounds.height),
                modifierFlags: UInt64(event.modifierFlags.rawValue),
                pressedMouseButtons: UInt64(NSEvent.pressedMouseButtons)
            )
        )
    }
}
