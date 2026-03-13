import Carbon.HIToolbox
import CoreGraphics

class HotkeyManager {
    enum Mode {
        case toggle
        case holdToTalk
    }

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    var mode: Mode = .toggle
    var keyCode: CGKeyCode = CGKeyCode(kVK_Space)
    var modifierFlags: CGEventFlags = .maskAlternate // Option key

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false

    func start() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRecording = false
    }

    fileprivate func handleKeyEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags

        let modifierMatch = eventFlags.contains(modifierFlags)
        let keyMatch = eventKeyCode == keyCode

        guard modifierMatch && keyMatch else { return false }

        switch mode {
        case .toggle:
            if type == .keyDown {
                if isRecording {
                    isRecording = false
                    onRecordStop?()
                } else {
                    isRecording = true
                    onRecordStart?()
                }
                return true
            }
        case .holdToTalk:
            if type == .keyDown && !isRecording {
                isRecording = true
                onRecordStart?()
                return true
            } else if type == .keyUp && isRecording {
                isRecording = false
                onRecordStop?()
                return true
            }
        }

        return false
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if manager.handleKeyEvent(event, type: type) {
        return nil
    }

    return Unmanaged.passRetained(event)
}
