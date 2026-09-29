import Foundation

public struct MouseEntropyRecord: Sendable {
    public let uptimeNanoseconds: UInt64
    public let eventTimestamp: Double
    public let x: Double
    public let y: Double
    public let deltaX: Double
    public let deltaY: Double
    public let canvasWidth: Double
    public let canvasHeight: Double
    public let modifierFlags: UInt64
    public let pressedMouseButtons: UInt64

    public init(
        uptimeNanoseconds: UInt64,
        eventTimestamp: Double,
        x: Double,
        y: Double,
        deltaX: Double,
        deltaY: Double,
        canvasWidth: Double,
        canvasHeight: Double,
        modifierFlags: UInt64,
        pressedMouseButtons: UInt64
    ) {
        self.uptimeNanoseconds = uptimeNanoseconds
        self.eventTimestamp = eventTimestamp
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.modifierFlags = modifierFlags
        self.pressedMouseButtons = pressedMouseButtons
    }
}
