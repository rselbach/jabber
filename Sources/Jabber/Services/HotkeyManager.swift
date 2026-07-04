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
    // Bounded backoff for re-enabling the tap after the system disables it
    // (.tapDisabledByTimeout / .tapDisabledByUserInput). Without a bound, a
    // revoked Accessibility grant turns the main run loop into a tight
    // disable→re-enable→disable loop (log spam + CPU burn). `recentTapDisables`
    // holds in-window disable timestamps (pure decision lives in
    // `EventTapReenablePolicy`); `eventTapDead` latches once we give up so a
    // stale in-flight callback cannot re-enter teardown. Held under `lock`.
    private var recentTapDisables: [Date] = []
    private var eventTapDead = false
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
            // Invalidate synchronously so an in-flight callback can no longer
            // re-enter this (already-deinit) object. Disabling the tap alone
            // does not synchronize with a callback already on the stack; the
            // `isDeinit()` guard in the callback dereferences `self` to read
            // the flag, which is itself a use-after-free. Invalidation is the
            // authoritative teardown that prevents further dispatch.
            CFMachPortInvalidate(tap)
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
        recentTapDisables = []
        eventTapDead = false
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
            // Invalidate synchronously so an in-flight callback can no longer
            // re-enter the manager after unregister. See deinit for rationale.
            CFMachPortInvalidate(tap)
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
        recentTapDisables = []
        eventTapDead = false
        modifierOnlyDebounce?.cancel()
        modifierOnlyDebounce = nil
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        lock.unlock()

        guard let source else {
            // The tap was created but its run-loop source could not be. Tear
            // the tap down so it can't linger, and surface a registration
            // failure through the existing path (matching the tapCreate
            // failure above). Passing nil to CFRunLoopAddSource would crash.
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            lock.lock()
            eventTap = nil
            runLoopSource = nil
            modifierOnlyShortcut = nil
            gesture.reset()
            recentTapDisables = []
            eventTapDead = true
            lock.unlock()
            logger.error("Failed to create run-loop source for event tap")
            dispatchRegistrationFailure(OSStatus(eventNotHandledErr))
            return OSStatus(eventNotHandledErr)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("CGEventTap enabled on main runloop for keyCode=\(shortcut.keyCode)")
        return noErr
    }

    /// Clear the rapid-disable history once a real event proves the tap is alive.
    private func resetTapDisableHistory() {
        lock.lock()
        recentTapDisables = []
        lock.unlock()
    }

    /// Handle a `.tapDisabledByTimeout` / `.tapDisabledByUserInput` with a
    /// bounded backoff. Re-enables are allowed while rapid re-disables stay
    /// under `EventTapReenablePolicy.maxReenables` within its window; once the
    /// bound is exceeded the tap is torn down, marked dead, and the failure is
    /// surfaced through the existing registration-failure path (typically:
    /// Accessibility permission was revoked).
    ///
    /// Pass-through invariant: always returns the incoming event unchanged.
    private func handleTapDisabled(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let now = Date()

        // Decide under the lock; do CG/CF and dispatch work after release to
        // keep the critical section free of reentrancy.
        var reenableTap: CFMachPort?
        var reenableCount = 0
        var teardownTap: CFMachPort?
        var teardownSource: CFRunLoopSource?
        var teardownDebounce: DispatchWorkItem?

        lock.lock()
        let (updated, shouldReenable) = EventTapReenablePolicy.shouldReenable(
            recentDisableTimes: recentTapDisables,
            newDisableTime: now
        )
        recentTapDisables = updated
        if shouldReenable {
            reenableTap = eventTap
            reenableCount = recentTapDisables.count
        } else if !eventTapDead {
            // Bound exceeded: give up and tear down the tap.
            eventTapDead = true
            teardownTap = eventTap
            teardownSource = runLoopSource
            teardownDebounce = modifierOnlyDebounce
            eventTap = nil
            runLoopSource = nil
            modifierOnlyShortcut = nil
            gesture.reset()
            recentTapDisables = []
            modifierOnlyDebounce = nil
        }
        lock.unlock()

        if let tap = reenableTap {
            logger.warning("CGEventTap disabled by system (\(String(describing: type))); re-enabling (\(reenableCount) recent disable(s)). If this repeats, Accessibility permission is likely missing.")
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if teardownTap != nil {
            if let tap = teardownTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                // Invalidate so the dead tap can't dispatch further callbacks.
                CFMachPortInvalidate(tap)
            }
            if let source = teardownSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            teardownDebounce?.cancel()
            logger.error("CGEventTap repeatedly disabled by system (\(String(describing: type))); giving up re-enable after \(EventTapReenablePolicy.maxReenables) rapid disables. Accessibility permission was likely revoked.")
            dispatchRegistrationFailure(OSStatus(eventNotHandledErr))
        }
        // `eventTapDead` already latched: the tap is gone, nothing left to do.

        return Unmanaged.passUnretained(event)
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
            return handleTapDisabled(type: type, event: event)
        }

        // The tap delivered a real event, so it is healthy: clear the
        // rapid-disable history so a later burst is evaluated from scratch.
        resetTapDisableHistory()

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
            // Translate the flag transition into a gesture input via the
            // reducer's pure mapping, then feed it. CGEventFlags are cumulative
            // per family (Left and Right Option share `.maskAlternate`), so the
            // configured key's release while a sibling stays held still reports
            // the family flag as set; the mapping disambiguates that release
            // from a press using the gesture phase. See
            // `ModifierOnlyGestureReducer.input(forFlagsChanged:)`.
            //
            // Direction is read from the event's own flags, not from
            // CGEventSource.keyState: the tap is a head-insert `.defaultTap`,
            // so this callback runs BEFORE the session key-state updates, and
            // keyState(.combinedSessionState) still reflects the pre-transition
            // state — a press would read as a release and be dropped, so the
            // gesture never fires. The event flags reflect state AFTER the
            // transition and are the reliable signal.
            lock.lock()
            let gestureState = gesture.state
            lock.unlock()
            guard let gestureInput = ModifierOnlyGestureReducer.input(
                forFlagsChanged: keyCode,
                flags: event.flags,
                shortcutKeyCode: shortcut.keyCode,
                gestureState: gestureState
            ) else {
                return Unmanaged.passUnretained(event)
            }
            logger.debug("Event tap flagsChanged keyCode=\(keyCode) gestureState=\(String(describing: gestureState)) input=\(String(describing: gestureInput))")
            feed(gestureInput)

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

    /// Hop to the main actor via the main dispatch queue, which is FIFO.
    ///
    /// Replaces the ad-hoc `Task { @MainActor in ... }` hops used for gesture
    /// delivery. Separate unstructured Tasks on the same actor have no formal
    /// ordering guarantee, so a fast press-release could deliver onKeyUp
    /// before onKeyDown — leaving the dictation coordinator with a stuck
    /// "recording" state or a no-op. The main dispatch queue is serial, so
    /// blocks submitted in order run in order; `assumeIsolated` runs the
    /// `@MainActor` closure synchronously on the main actor without re-queue.
    private static func deliverToMain(_ body: @escaping @Sendable @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }

    private func dispatchGesture(_ action: ModifierOnlyGestureReducer.Action) {
        switch action {
        case .fireDown:
            logger.info("Modifier-only gesture fired: onKeyDown")
            Self.deliverToMain { self.onKeyDown?() }
        case .fireUp:
            logger.info("Modifier-only gesture fired: onKeyUp")
            Self.deliverToMain { self.onKeyUp?() }
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
                    HotkeyManager.deliverToMain { manager.onKeyDown?() }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    HotkeyManager.deliverToMain { manager.onKeyUp?() }
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

    /// Map a `flagsChanged` event from the modifier-only event tap to the
    /// gesture input it represents, or `nil` when the event should be ignored.
    ///
    /// Pure and table-testable: the live tap callback passes the event's key
    /// code and flags, the configured shortcut's key code, and the reducer's
    /// current `state`, then feeds the result to `handle(_:)`.
    ///
    /// `CGEventFlags` masks are cumulative per family — Left and Right Option
    /// both report `.maskAlternate` — so a release of the configured key while
    /// its sibling stays held still shows the family flag as set. The press/
    /// release ambiguity is resolved with the gesture phase, since a key cannot
    /// transition down twice:
    ///
    /// - Family flag set and the configured key is NOT already tracked down
    ///   (`state == .idle`) → a press of the configured key → `.modifierDown`.
    /// - Family flag set and the configured key IS already tracked down
    ///   (`state` is `.pending`/`.active`) → the key was already down, so this
    ///   flagsChanged can only be the release of the configured side while a
    ///   sibling keeps the family flag high → `.modifierUp`.
    /// - Family flag cleared → the configured key (and any sibling) is up →
    ///   `.modifierUp`.
    /// - Event for any key code other than the configured one (e.g. a sibling
    ///   modifier) → `nil` (ignored).
    static func input(
        forFlagsChanged keyCode: UInt32,
        flags: CGEventFlags,
        shortcutKeyCode: UInt32,
        gestureState: State
    ) -> Input? {
        // Only the configured physical key drives the gesture; sibling-modifier
        // events (e.g. Left Option when Right Option is configured) are ignored.
        guard keyCode == shortcutKeyCode else { return nil }

        guard let familyFlag = HotkeyShortcut.cgEventFlag(forKeyCode: keyCode) else {
            return nil
        }

        let familyIsSet = flags.contains(familyFlag)
        let configuredKeyTrackedDown = (gestureState == .pending || gestureState == .active)

        if familyIsSet, !configuredKeyTrackedDown {
            return .modifierDown
        }
        // Either the family flag cleared (the configured key — and any sibling —
        // is up), or the family flag is still set while the configured key is
        // already tracked down: a key cannot press twice, so the latter is the
        // configured-side release with a sibling still holding the family flag.
        return .modifierUp
    }
}

/// Pure decision logic for the CGEventTap re-enable backoff.
///
/// When the system disables the modifier-only event tap
/// (`.tapDisabledByTimeout` / `.tapDisabledByUserInput`) the manager used to
/// re-enable it unconditionally. If Accessibility permission is revoked (or the
/// tap is otherwise unsatisfiable) that produces a tight
/// disable→re-enable→disable loop on the main run loop — log spam and CPU burn.
/// This policy bounds the loop: as long as rapid re-disables stay under
/// `maxReenables` within `rapidWindow`, re-enabling proceeds; once the bound is
/// exceeded within the window the manager tears the tap down and surfaces a
/// registration failure.
///
/// Pure and table-testable: the manager records disable timestamps and asks
/// this policy whether to continue. The window filter drops stale disables, so
/// "the tap stayed alive for a while" needs no timer; the manager additionally
/// clears the history whenever a real event is delivered (a second, event-driven
/// reset condition).
///
/// Semantics: `shouldReenable` returns `false` once `maxReenables` rapid
/// disables have accumulated within `rapidWindow` — i.e. up to `maxReenables`
/// re-enables are tolerated, and the disable that pushes the in-window count
/// past that bound trips give-up.
enum EventTapReenablePolicy: Sendable {
    /// Maximum in-window re-disables tolerated before give-up.
    static let maxReenables = 5
    /// Rolling window (seconds) within which rapid re-disables are counted.
    static let rapidWindow: TimeInterval = 5

    /// Decide whether to re-enable the tap after another disable.
    ///
    /// - Parameters:
    ///   - recentDisableTimes: Disable timestamps recorded so far (oldest
    ///     first), already filtered to the window by prior calls.
    ///   - newDisableTime: Timestamp of the disable currently being handled.
    ///   - maxReenables: Override of `maxReenables` (for tests).
    ///   - rapidWindow: Override of `rapidWindow` (for tests).
    /// - Returns: `updated` is the new in-window history (caller should store
    ///   it); `reenable` is `false` once the in-window count exceeds
    ///   `maxReenables`.
    static func shouldReenable(
        recentDisableTimes: [Date],
        newDisableTime: Date,
        maxReenables: Int = EventTapReenablePolicy.maxReenables,
        rapidWindow: TimeInterval = EventTapReenablePolicy.rapidWindow
    ) -> (updated: [Date], reenable: Bool) {
        let cutoff = newDisableTime.addingTimeInterval(-rapidWindow)
        let inWindow = recentDisableTimes.filter { $0 >= cutoff }
        let updated = inWindow + [newDisableTime]
        let reenable = updated.count <= maxReenables
        return (updated, reenable)
    }
}
