import Carbon
import Foundation
import os

final class HotkeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "HotkeyManager")

    var onKeyDown: (@MainActor () -> Void)?
    var onKeyUp: (@MainActor () -> Void)?
    var onRegistrationFailure: (@MainActor (OSStatus) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        lock.lock()
        let ref = hotKeyRef
        let handler = eventHandlerRef
        lock.unlock()

        if let ref {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                logger.error("Failed to unregister hotkey with status: \(status)")
            }
        }
        if let handler {
            let status = RemoveEventHandler(handler)
            if status != noErr {
                logger.error("Failed to remove hotkey event handler with status: \(status)")
            }
        }
    }

    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> OSStatus {
        register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        unregister()

        guard let signature = OSType(fourCharCode: "JBBR") else {
            let status = OSStatus(paramErr)
            logger.error("Failed to create hotkey signature with status: \(status)")
            dispatchRegistrationFailure(status)
            return status
        }

        let hotKeyID = EventHotKeyID(
            signature: signature,
            id: 1
        )

        lock.lock()
        defer { lock.unlock() }

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
            dispatchRegistrationFailure(status)
        }
        return status
    }

    func unregister() {
        lock.lock()
        let ref = hotKeyRef
        hotKeyRef = nil
        lock.unlock()

        if let ref {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                logger.error("Failed to unregister hotkey with status: \(status)")
            }
        }
    }

    private func dispatchRegistrationFailure(_ status: OSStatus) {
        if let onRegistrationFailure {
            Task { @MainActor in
                onRegistrationFailure(status)
            }
        }
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, refcon) -> OSStatus in
                guard let refcon, let event else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let kind = GetEventKind(event)

                if kind == UInt32(kEventHotKeyPressed) {
                    Task { @MainActor in
                        manager.onKeyDown?()
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    Task { @MainActor in
                        manager.onKeyUp?()
                    }
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            refcon,
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("Failed to install hotkey event handler with status: \(status)")
            dispatchRegistrationFailure(status)
        }
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
