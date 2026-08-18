import AppKit

@MainActor
final class InputController {
    var onInputActivityChanged: (() -> Void)?
    var onEscape: (() -> Void)?

    private var pressedKeyCodes = Set<UInt16>()
    private var eventMonitor: Any?
    private var mouseControlActive = false
    private var suppressMouseControlUntilModifiersReleased = false
    private var previousMouseLocation: NSPoint?

    var hasContinuousInput: Bool {
        !pressedKeyCodes.isEmpty || mouseControlActive
    }

    func start() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        releaseAllInput()
    }

    func currentState() -> InputState {
        InputState(
            forward: axis(positive: [.w, .upArrow], negative: [.s, .downArrow]),
            strafe: axis(positive: [.d, .rightArrow], negative: [.a, .leftArrow]),
            mouseDelta: consumeMouseDelta()
        )
    }

    func releaseMouseControl() {
        mouseControlActive = false
        suppressMouseControlUntilModifiersReleased = true
        previousMouseLocation = nil
        onInputActivityChanged?()
    }

    func releaseAllInput() {
        pressedKeyCodes.removeAll()
        mouseControlActive = false
        previousMouseLocation = nil
        onInputActivityChanged?()
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            if event.keyCode == Key.escape.rawValue {
                releaseMouseControl()
                onEscape?()
                return nil
            }
            guard Key.movementKeyCodes.contains(event.keyCode) else { return event }
            pressedKeyCodes.insert(event.keyCode)
            onInputActivityChanged?()
            return nil

        case .keyUp:
            guard Key.movementKeyCodes.contains(event.keyCode) else { return event }
            pressedKeyCodes.remove(event.keyCode)
            onInputActivityChanged?()
            return nil

        case .flagsChanged:
            let deviceIndependentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let requiredFlags: NSEvent.ModifierFlags = [.control, .option]
            let modifiersHeld = deviceIndependentFlags.contains(requiredFlags)

            if !modifiersHeld {
                suppressMouseControlUntilModifiersReleased = false
            }

            let shouldControl = modifiersHeld && !suppressMouseControlUntilModifiersReleased
            if mouseControlActive != shouldControl {
                mouseControlActive = shouldControl
                previousMouseLocation = shouldControl ? NSEvent.mouseLocation : nil
                onInputActivityChanged?()
            }
            return event

        default:
            return event
        }
    }

    private func axis(positive: [Key], negative: [Key]) -> Float {
        let positivePressed = positive.contains { pressedKeyCodes.contains($0.rawValue) }
        let negativePressed = negative.contains { pressedKeyCodes.contains($0.rawValue) }
        return Float((positivePressed ? 1 : 0) - (negativePressed ? 1 : 0))
    }

    private func consumeMouseDelta() -> SIMD2<Float> {
        guard mouseControlActive else { return .zero }

        let currentLocation = NSEvent.mouseLocation
        defer { previousMouseLocation = currentLocation }
        guard let previousMouseLocation else { return .zero }

        return SIMD2<Float>(
            Float(currentLocation.x - previousMouseLocation.x),
            Float(currentLocation.y - previousMouseLocation.y)
        )
    }
}

private enum Key: UInt16 {
    case a = 0
    case s = 1
    case d = 2
    case w = 13
    case escape = 53
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126

    static let movementKeyCodes: Set<UInt16> = [
        Key.a.rawValue,
        Key.s.rawValue,
        Key.d.rawValue,
        Key.w.rawValue,
        Key.leftArrow.rawValue,
        Key.rightArrow.rawValue,
        Key.downArrow.rawValue,
        Key.upArrow.rawValue,
    ]
}
