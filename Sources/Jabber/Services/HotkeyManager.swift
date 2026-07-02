import Carbon
import CoreGraphics
import Foundation
@preconcurrency import ApplicationServices
import os

final class HotkeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isDeinitialized = false
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "HotkeyManager")

    // Modifier-only shortcuts (e.g. Right Option on its own) cannot be
    // registered with Carbon — a bare modifier produces no key-down event and
    // Carbon modifier flags do not encode the physical side. We observe flag
    // transitions (and key-downs, to detect Option+key typing) with a
    // CGEventTap, using the event's key code + physical key state to
    // distinguish left/right.
    //
    // The tap uses `.defaultTap` (not `.listenOnly`) so a lone modifier can be
    // observed with only Accessibility permission — `.listenOnly` would prompt
    // for Input Monitoring. Because `.defaultTap` can swallow/alter input, the
    // callback MUST always pass the event through unmodified; we never drop or
    // synthesize events, we only read them. See `handleEventTapEvent`.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierOnlyShortcut: HotkeyShortcut?
    // Pure decision logic for the gesture (debounce/cancel rules). Held under
    // `lock`; mutated only from the event tap callback and the debounce timer.
    private var gesture = ModifierOnlyGestureReducer()
    private var modifierOnlyDebounce: DispatchWorkItem?

    var onKeyDown: (@MainActor () -> Void)?
    var onKeyUp: (@MainActor () -> Void)?
    var onRegistrationFailure: (@MainActor (OSStatus) -> Void)?

    init() {
        installEventHandler()
    }

    deinit {
        lock.lock()
        isDeinitialized = true
        let ref = hotKeyRef
        let handler = eventHandlerRef
        let tap = eventTap
        let source = runLoopSource
        let debounce = modifierOnlyDebounce
        modifierOnlyDebounce = nil
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
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        debounce?.cancel()
    }

    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> OSStatus {
        unregister()

        if shortcut.isModifierOnly {
            return registerModifierOnly(shortcut)
        }
        return registerCarbon(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        register(HotkeyShortcut(keyCode: keyCode, modifiers: modifiers))
    }

    func unregister() {
        lock.lock()
        let ref = hotKeyRef
        hotKeyRef = nil
        let tap = eventTap
        eventTap = nil
        let source = runLoopSource
        runLoopSource = nil
        modifierOnlyShortcut = nil
        gesture.reset()
        let debounce = modifierOnlyDebounce
        modifierOnlyDebounce = nil
        lock.unlock()

        if let ref {
            let status = UnregisterEventHotKey(ref)
            if status != noErr {
                logger.error("Failed to unregister hotkey with status: \(status)")
            }
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        debounce?.cancel()
    }

    private func dispatchRegistrationFailure(_ status: OSStatus) {
        if let onRegistrationFailure {
            Task { @MainActor in
                onRegistrationFailure(status)
            }
        }
    }

    private func isDeinit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isDeinitialized
    }

    @discardableResult
    private func registerCarbon(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
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

    @discardableResult
    private func registerModifierOnly(_ shortcut: HotkeyShortcut) -> OSStatus {
        guard HotkeyShortcut.carbonModifier(forKeyCode: shortcut.keyCode) != nil else {
            let status = OSStatus(paramErr)
            logger.error("Modifier-only shortcut has unmapped key code: \(shortcut.keyCode)")
            dispatchRegistrationFailure(status)
            return status
        }

        // A `.defaultTap` CGEventTap that observes flagsChanged + keyDown
        // needs only Accessibility permission (the `.listenOnly` option would
        // additionally require Input Monitoring to observe key-downs). We
        // preflight Accessibility here — there is a clean API — and fail loudly
        // with a precise message when it is missing. If the grant is missing at
        // runtime the tap fails to create (handled below) or delivers no events.
        guard AXIsProcessTrusted() else {
            let status = OSStatus(eventNotHandledErr)
            logger.error("Modifier-only shortcut requires Accessibility permission; not granted")
            dispatchRegistrationFailure(status)
            return status
        }

        logger.info("Creating CGEventTap for modifier-only shortcut keyCode=\(shortcut.keyCode)")

        // We need key-down in addition to flags-changed so we can detect
        // Option+key (and other combo) typing while the modifier is held and
        // cancel the pending start before it fires. We use `.defaultTap` (not
        // `.listenOnly`) so a lone modifier works with Accessibility alone and
        // never triggers the Input Monitoring prompt. The callback is read-only
        // in effect: it always returns the event unchanged — see the invariant
        // note on `handleEventTapEvent`.
        let eventMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HotkeyManager.eventTapCallback,
            userInfo: refcon
        ) else {
            // tapCreate returns nil when permission is missing. With
            // `.defaultTap` the only grant required is Accessibility (already
            // preflighted above); reaching here usually means the grant was
            // revoked between the check and creation.
            let status = OSStatus(eventNotHandledErr)
            logger.error("Failed to create event tap for modifier-only shortcut (grant Accessibility in System Settings)")
            dispatchRegistrationFailure(status)
            return status
        }

        lock.lock()
        modifierOnlyShortcut = shortcut
        gesture.reset()
        modifierOnlyDebounce?.cancel()
        modifierOnlyDebounce = nil
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        lock.unlock()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("CGEventTap enabled on main runloop for keyCode=\(shortcut.keyCode)")
        return noErr
    }

    private func currentEventTap() -> CFMachPort? {
        lock.lock()
        defer { lock.unlock() }
        return eventTap
    }

    /// Handle an event from the modifier-only CGEventTap.
    ///
    /// INVARIANT: this must always return the incoming event unchanged
    /// (`Unmanaged.passUnretained(event)`). The tap is created with
    /// `.defaultTap` so a lone modifier can be observed under Accessibility
    /// alone (no Input Monitoring prompt); `.defaultTap` can swallow input, so
    /// dropping or returning `nil` here would eat the user's keystrokes. Every
    /// branch below — including the disabled-by-system and no-shortcut guards —
    /// must pass the event through.
    private func handleEventTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("CGEventTap disabled by system (\(String(describing: type))); re-enabling. If this repeats, Accessibility permission is likely missing.")
            if let tap = currentEventTap() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let shortcut = modifierOnlyShortcut
        lock.unlock()

        // Only the modifier-only path uses the event tap; if there is none
        // configured the tap should already be torn down, but guard anyway.
        guard let shortcut else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .flagsChanged:
            // Ignore flag changes for any modifier other than the configured
            // physical key (e.g. Left Option when Right Option is configured).
            guard keyCode == shortcut.keyCode else {
                return Unmanaged.passUnretained(event)
            }
            // Determine down/up from the event's own modifier flags, NOT from
            // CGEventSource.keyState. The tap is a head-insert `.defaultTap`,
            // so this callback runs BEFORE the session key-state is updated;
            // keyState(.combinedSessionState) therefore still reflects the
            // pre-transition state and would invert the gesture — a press reads
            // as a release (keyState==false) and is silently dropped, so the
            // gesture never fires. The event flags reflect state AFTER the
            // transition and are the reliable signal. keyState is kept only as a
            // last-resort fallback for key codes we can't map to a flag family.
            //
            // The flags are cumulative per family (e.g. .maskAlternate is set if
            // EITHER Option key is down), so a release of the configured key
            // while its sibling stays held is only observed once the whole
            // family clears — matching FluidVoice's modifier-only semantics.
            let isDown: Bool
            if let familyFlag = HotkeyShortcut.cgEventFlag(forKeyCode: keyCode) {
                isDown = event.flags.contains(familyFlag)
            } else {
                isDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
            }
            logger.debug("Event tap flagsChanged keyCode=\(keyCode) isDown=\(isDown)")
            feed(isDown ? .modifierDown : .modifierUp)

        case .keyDown:
            // Modifier keys surface as flagsChanged, not keyDown; any other
            // key-down while the modifier is held means the user is typing a
            // combo (e.g. Option+E), so we cancel the pending start.
            guard !HotkeyShortcut.modifierOnlyKeyCodes.contains(keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            logger.debug("Event tap keyDown keyCode=\(keyCode) (combo typing; cancelling pending modifier-only start)")
            feed(.otherKeyDown)

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    /// Feed a gesture input to the reducer and translate the resulting action
    /// into debounce scheduling/cancellation and `onKeyDown`/`onKeyUp` delivery.
    private func feed(_ input: ModifierOnlyGestureReducer.Input) {
        var action: ModifierOnlyGestureReducer.Action = .none
        lock.lock()
        action = gesture.handle(input)
        switch action {
        case .scheduleStart:
            // Cancel any stale timer first to be safe, then arm a fresh one.
            modifierOnlyDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.handleDebounceTick()
            }
            modifierOnlyDebounce = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + ModifierOnlyGestureReducer.debounceInterval,
                execute: work
            )
        case .cancelStart:
            modifierOnlyDebounce?.cancel()
            modifierOnlyDebounce = nil
        default:
            break
        }
        lock.unlock()

        dispatchGesture(action)
    }

    private func handleDebounceTick() {
        var action: ModifierOnlyGestureReducer.Action = .none
        lock.lock()
        modifierOnlyDebounce = nil
        action = gesture.handle(.debounceElapsed)
        lock.unlock()
        dispatchGesture(action)
    }

    private func dispatchGesture(_ action: ModifierOnlyGestureReducer.Action) {
        switch action {
        case .fireDown:
            logger.info("Modifier-only gesture fired: onKeyDown")
            Task { @MainActor in
                self.onKeyDown?()
            }
        case .fireUp:
            logger.info("Modifier-only gesture fired: onKeyUp")
            Task { @MainActor in
                self.onKeyUp?()
            }
        case .scheduleStart, .cancelStart, .none:
            break
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        guard !manager.isDeinit() else { return Unmanaged.passUnretained(event) }
        return manager.handleEventTapEvent(type: type, event: event)
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, refcon -> OSStatus in
                guard let refcon, let event else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                guard !manager.isDeinit() else { return OSStatus(eventNotHandledErr) }

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

/// Pure decision logic for the modifier-only (e.g. Right Option) gesture.
///
/// Extracted from `HotkeyManager` so the debounce/cancel rules are unit
/// testable without simulating real OS input. The manager feeds it inputs from
/// the CGEventTap and the debounce timer, and maps the returned `Action` to the
/// existing `onKeyDown`/`onKeyUp` callbacks.
///
/// `state` reflects whether the configured modifier is physically held and
/// tracked (`.pending`) and has fired (`active`); it does not flip back to idle
/// just because a combo key was typed. `otherKeyPressedDuringModifier` records
/// that interference and gates the debounce.
///
/// Behaviour:
/// - Pressing the configured modifier enters `.pending` and asks the caller to
///   schedule a debounce timer (`scheduleStart`); nothing fires yet.
/// - If the timer elapses while still pending and no other key was pressed, the
///   gesture goes `.active` and asks the caller to fire `onKeyDown` (`fireDown`).
/// - If any non-modifier key is pressed while pending (combo typing, e.g.
///   Option+E), the start is cancelled (`cancelStart`) and remembered; nothing
///   fires. The modifier is still physically held, so the eventual release
///   tears the gesture down.
/// - If the modifier is released while pending, the start is cancelled
///   (`cancelStart`, or `.none` if another key already cancelled it); nothing
///   fires.
/// - Once active, a non-modifier key press is ignored (no re-fire); releasing
///   the modifier still asks the caller to fire `onKeyUp` (`fireUp`) so the
///   existing activation modes (hold / automatic push-to-talk) keep working.
struct ModifierOnlyGestureReducer: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case idle
        case pending
        case active
    }

    enum Action: Sendable, Equatable {
        case none
        case scheduleStart
        case cancelStart
        case fireDown
        case fireUp
    }

    enum Input: Sendable, Equatable {
        case modifierDown
        case modifierUp
        case otherKeyDown
        case debounceElapsed
    }

    /// Debounce applied before `onKeyDown` fires. Matches the FluidVoice
    /// approach (~150ms): long enough to reject Option+key typing and chatter,
    /// short enough to feel instantaneous for an intentional hold.
    static let debounceInterval: TimeInterval = 0.15

    private(set) var state: State = .idle
    /// `true` once a non-modifier key was pressed during the current hold.
    /// Guards the debounce tick so dictation can never start after the user
    /// typed a combo (e.g. Option+E). Reset whenever the gesture returns to
    /// idle.
    private(set) var otherKeyPressedDuringModifier = false

    mutating func reset() {
        state = .idle
        otherKeyPressedDuringModifier = false
    }

    mutating func handle(_ input: Input) -> Action {
        switch input {
        case .modifierDown:
            switch state {
            case .idle:
                state = .pending
                otherKeyPressedDuringModifier = false
                return .scheduleStart
            case .pending, .active:
                // Repeat down event (chatter / already tracking); ignore.
                return .none
            }

        case .modifierUp:
            switch state {
            case .idle:
                otherKeyPressedDuringModifier = false
                return .none
            case .pending:
                // Released before fire. If a combo key already cancelled the
                // start (and the timer), there is nothing left to cancel.
                let alreadyCancelled = otherKeyPressedDuringModifier
                state = .idle
                otherKeyPressedDuringModifier = false
                return alreadyCancelled ? .none : .cancelStart
            case .active:
                // onKeyDown already fired; stop the hold so existing activation
                // modes (hold / automatic push-to-talk) behave as expected.
                state = .idle
                otherKeyPressedDuringModifier = false
                return .fireUp
            }

        case .otherKeyDown:
            switch state {
            case .pending:
                // Combo typing (e.g. Option+E): remember it and cancel the
                // pending start. The modifier is still physically held, so the
                // release tears the gesture down; the flag guards any stray
                // debounce tick.
                otherKeyPressedDuringModifier = true
                return .cancelStart
            case .active:
                // Already recording: ignore (no re-fire).
                otherKeyPressedDuringModifier = true
                return .none
            case .idle:
                return .none
            }

        case .debounceElapsed:
            // Only start if still pending and no other key intervened.
            guard state == .pending, !otherKeyPressedDuringModifier else {
                return .none
            }
            state = .active
            return .fireDown
        }
    }
}
