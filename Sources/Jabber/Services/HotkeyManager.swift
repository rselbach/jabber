import Carbon
import Foundation
import os

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "HotkeyManager")

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onRegistrationFailure: ((OSStatus) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        let hotKeyID = EventHotKeyID(
            signature: OSType(fourCharCode: "JBBR")!,
            id: 1
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            logger.error("Failed to register hotkey with status: \(status)")
            onRegistrationFailure?(status)
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, refcon) -> OSStatus in
                guard let refcon, let event else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let kind = GetEventKind(event)

                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onKeyDown?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    manager.onKeyUp?()
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            refcon,
            &eventHandlerRef
        )
    }
}

private extension OSType {
    init?(fourCharCode: String) {
        guard fourCharCode.utf8.count == 4 else {
            return nil
        }
        var result: OSType = 0
        for char in fourCharCode.utf8 {
            result = (result << 8) + OSType(char)
        }
        self = result
    }
}
