import Carbon
import CoreGraphics
import XCTest
@testable import Jabber

/// Tests for the pure flagsChanged → gesture-input mapping extracted out of
/// `HotkeyManager`'s event tap. The mapping (`ModifierOnlyGestureReducer.input`)
/// bridges OS semantics (cumulative per-family `CGEventFlags`) and reducer
/// semantics (`.modifierDown` / `.modifierUp`), using the gesture phase to tell
/// a configured-side release apart from a press when a sibling modifier keeps
/// the family flag high.
final class ModifierOnlyGestureMappingTests: XCTestCase {
    // MARK: - Pure mapping: flagsChanged event -> gesture Input

    func testFlagsChangedMappingTable() {
        let rightOption = UInt32(kVK_RightOption)
        let leftOption = UInt32(kVK_Option)
        let alternate = CGEventFlags.maskAlternate

        struct Case {
            let name: String
            let keyCode: UInt32
            let flags: CGEventFlags
            let gestureState: ModifierOnlyGestureReducer.State
            let shortcutKeyCode: UInt32
            let expected: ModifierOnlyGestureReducer.Input?
        }

        let tests: [Case] = [
            .init(
                name: "configured press from idle",
                keyCode: rightOption, flags: alternate,
                gestureState: .idle, shortcutKeyCode: rightOption,
                expected: .modifierDown
            ),
            // Sibling already held leaves the gesture idle (its events are
            // ignored), so the configured press still reads as a down.
            .init(
                name: "configured press with sibling already held",
                keyCode: rightOption, flags: alternate,
                gestureState: .idle, shortcutKeyCode: rightOption,
                expected: .modifierDown
            ),
            // THE BUG: configured key released while a sibling keeps the family
            // flag set must map to up, not a repeat down.
            .init(
                name: "configured release while sibling holds family (active)",
                keyCode: rightOption, flags: alternate,
                gestureState: .active, shortcutKeyCode: rightOption,
                expected: .modifierUp
            ),
            .init(
                name: "configured release while sibling holds family (pending)",
                keyCode: rightOption, flags: alternate,
                gestureState: .pending, shortcutKeyCode: rightOption,
                expected: .modifierUp
            ),
            // Family flag cleared (no sibling): the configured key is up.
            .init(
                name: "configured release family cleared (active)",
                keyCode: rightOption, flags: [],
                gestureState: .active, shortcutKeyCode: rightOption,
                expected: .modifierUp
            ),
            .init(
                name: "spurious configured release family cleared (idle)",
                keyCode: rightOption, flags: [],
                gestureState: .idle, shortcutKeyCode: rightOption,
                expected: .modifierUp
            ),
            // Sibling-modifier events never drive the gesture.
            .init(
                name: "sibling press ignored",
                keyCode: leftOption, flags: alternate,
                gestureState: .idle, shortcutKeyCode: rightOption,
                expected: nil
            ),
            .init(
                name: "sibling release ignored",
                keyCode: leftOption, flags: [],
                gestureState: .idle, shortcutKeyCode: rightOption,
                expected: nil
            ),
            .init(
                name: "sibling event ignored even when active",
                keyCode: leftOption, flags: alternate,
                gestureState: .active, shortcutKeyCode: rightOption,
                expected: nil
            ),
        ]

        for tc in tests {
            let got = ModifierOnlyGestureReducer.input(
                forFlagsChanged: tc.keyCode,
                flags: tc.flags,
                shortcutKeyCode: tc.shortcutKeyCode,
                gestureState: tc.gestureState
            )
            XCTAssertEqual(got, tc.expected, tc.name)
        }
    }

    // MARK: - Integration: mapping + reducer end-to-end

    func testNormalPressReleaseReturnsToIdle() {
        var g = ModifierOnlyGestureReducer()
        let keyCode = UInt32(kVK_RightOption)
        let alternate = CGEventFlags.maskAlternate

        XCTAssertEqual(g.state, .idle)

        // Press: family flag just went set, idle -> down -> pending.
        let down = ModifierOnlyGestureReducer.input(
            forFlagsChanged: keyCode, flags: alternate,
            shortcutKeyCode: keyCode, gestureState: g.state
        )
        XCTAssertEqual(down, .modifierDown)
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.state, .pending)

        // Debounce: pending -> active.
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.state, .active)

        // Release (no sibling): family cleared -> up -> idle.
        let up = ModifierOnlyGestureReducer.input(
            forFlagsChanged: keyCode, flags: [],
            shortcutKeyCode: keyCode, gestureState: g.state
        )
        XCTAssertEqual(up, .modifierUp)
        XCTAssertEqual(g.handle(.modifierUp), .fireUp)
        XCTAssertEqual(g.state, .idle)
    }

    func testSiblingHeldStuckScenarioReturnsToIdle() {
        // Reproduces the bug: configured = Right Option; user holds Left Option,
        // presses Right Option, releases Right Option while Left is still held.
        // Previously the release read as a repeat down (family flag still set)
        // and `.modifierUp` was never delivered, leaving the gesture stuck
        // `.active` and the next press ignored.
        var g = ModifierOnlyGestureReducer()
        let rightOption = UInt32(kVK_RightOption)
        let leftOption = UInt32(kVK_Option)
        let alternate = CGEventFlags.maskAlternate

        // Left Option pressed first: ignored, gesture stays idle.
        XCTAssertNil(ModifierOnlyGestureReducer.input(
            forFlagsChanged: leftOption, flags: alternate,
            shortcutKeyCode: rightOption, gestureState: g.state
        ))
        XCTAssertEqual(g.state, .idle)

        // Right Option pressed: down -> pending.
        let down = ModifierOnlyGestureReducer.input(
            forFlagsChanged: rightOption, flags: alternate,
            shortcutKeyCode: rightOption, gestureState: g.state
        )
        XCTAssertEqual(down, .modifierDown)
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.state, .pending)

        // Debounce fires: active.
        XCTAssertEqual(g.handle(.debounceElapsed), .fireDown)
        XCTAssertEqual(g.state, .active)

        // Right Option released while Left still held: family flag still set,
        // but state is active -> mapping must yield up (the fix). The gesture
        // must fire up and return to idle instead of sticking active.
        let up = ModifierOnlyGestureReducer.input(
            forFlagsChanged: rightOption, flags: alternate,
            shortcutKeyCode: rightOption, gestureState: g.state
        )
        XCTAssertEqual(up, .modifierUp)
        XCTAssertEqual(g.handle(.modifierUp), .fireUp)
        XCTAssertEqual(g.state, .idle)

        // Left Option release: ignored. Gesture is back to idle and ready.
        XCTAssertNil(ModifierOnlyGestureReducer.input(
            forFlagsChanged: leftOption, flags: [],
            shortcutKeyCode: rightOption, gestureState: g.state
        ))
        XCTAssertEqual(g.state, .idle)

        // A subsequent Right Option press re-arms (proving it is not stuck).
        let again = ModifierOnlyGestureReducer.input(
            forFlagsChanged: rightOption, flags: alternate,
            shortcutKeyCode: rightOption, gestureState: g.state
        )
        XCTAssertEqual(again, .modifierDown)
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.state, .pending)
    }

    func testBothSidesReleasedTogetherRegardlessOfOrder() {
        // Both Option keys held then released; the gesture must end idle and
        // fire down+up exactly once regardless of which side releases first.
        let rightOption = UInt32(kVK_RightOption)
        let leftOption = UInt32(kVK_Option)
        let alternate = CGEventFlags.maskAlternate

        let orders: [(String, [(UInt32, CGEventFlags)])] = [
            ("configured released first while sibling holds", [
                (leftOption, alternate), // sibling press (ignored)
                (rightOption, alternate), // configured press
                (rightOption, alternate), // configured release (sibling still holds)
                (leftOption, []), // sibling release
            ]),
            ("sibling released first", [
                (leftOption, alternate), // sibling press (ignored)
                (rightOption, alternate), // configured press
                (leftOption, alternate), // sibling release (ignored; family still set by Right)
                (rightOption, []), // configured release (family now cleared)
            ]),
        ]

        for (name, events) in orders {
            var g = ModifierOnlyGestureReducer()
            var actions: [ModifierOnlyGestureReducer.Action] = []
            for (kc, flags) in events {
                guard let input = ModifierOnlyGestureReducer.input(
                    forFlagsChanged: kc, flags: flags,
                    shortcutKeyCode: rightOption, gestureState: g.state
                ) else {
                    continue
                }
                actions.append(g.handle(input))
                // Mirror the live debounce timer: once pending, elapse it.
                if g.state == .pending {
                    actions.append(g.handle(.debounceElapsed))
                }
            }
            XCTAssertEqual(g.state, .idle, "\(name): gesture must return to idle")
            XCTAssertTrue(actions.contains(.fireDown), "\(name): gesture must fire down once")
            XCTAssertTrue(actions.contains(.fireUp), "\(name): gesture must fire up once")
        }
    }

    func testRepeatModifierDownIsSuppressed() {
        // The reducer must still ignore a repeat down (chatter / already
        // tracking) so a gesture never double-arms. The mapping feeds a single
        // down per physical press; this guards the reducer invariant directly.
        var g = ModifierOnlyGestureReducer()
        XCTAssertEqual(g.handle(.modifierDown), .scheduleStart)
        XCTAssertEqual(g.handle(.modifierDown), .none)
        XCTAssertEqual(g.state, .pending)
    }
}
