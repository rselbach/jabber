import XCTest
@testable import Jabber

/// Tests for `ModifierOnlyRegistrationRetryPolicy`, the pure decision behind
/// re-registering a lone-modifier shortcut once Accessibility is granted.
///
/// A failed modifier-only registration starts a pending episode. Only the
/// first failure of an episode notifies the user, and a retry fires only when
/// Accessibility trust is observed going from untrusted to trusted, so a tap
/// that died while trusted cannot loop.
final class ModifierOnlyRegistrationRetryPolicyTests: XCTestCase {
    private enum Step {
        case failure(modifierOnly: Bool, trusted: Bool)
        case trustCheck(trusted: Bool)
        case reset
    }

    func testRetryDecisionTable() {
        // `want` holds one decision per step: for `.failure`, whether to notify
        // the user; for `.trustCheck`, whether to re-register. `.reset` has no
        // decision and records false.
        let tests: [String: (steps: [Step], want: [Bool], wantPending: Bool)] = [
            "lone modifier fails without accessibility: notify and stay pending": (
                steps: [.failure(modifierOnly: true, trusted: false)],
                want: [true],
                wantPending: true
            ),
            "carbon failure: notify, nothing to retry": (
                steps: [
                    .failure(modifierOnly: false, trusted: false),
                    .trustCheck(trusted: true)
                ],
                want: [true, false],
                wantPending: false
            ),
            "carbon failure ends a pending modifier-only episode": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .failure(modifierOnly: false, trusted: false),
                    .trustCheck(trusted: true)
                ],
                want: [true, true, false],
                wantPending: false
            ),
            "accessibility still missing: keep waiting": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .trustCheck(trusted: false),
                    .trustCheck(trusted: false)
                ],
                want: [true, false, false],
                wantPending: true
            ),
            "accessibility granted: re-register once": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .trustCheck(trusted: false),
                    .trustCheck(trusted: true),
                    .trustCheck(trusted: true)
                ],
                want: [true, false, true, false],
                wantPending: true
            ),
            "automatic retry fails again: no second notification": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .trustCheck(trusted: true),
                    .failure(modifierOnly: true, trusted: true),
                    .trustCheck(trusted: true)
                ],
                want: [true, true, false, false],
                wantPending: true
            ),
            "tap died while trusted: no retry until accessibility is toggled": (
                steps: [
                    .failure(modifierOnly: true, trusted: true),
                    .trustCheck(trusted: true),
                    .trustCheck(trusted: true),
                    .trustCheck(trusted: false),
                    .trustCheck(trusted: true)
                ],
                want: [true, false, false, false, true],
                wantPending: true
            ),
            "trust check with nothing pending: no retry": (
                steps: [.trustCheck(trusted: true)],
                want: [false],
                wantPending: false
            ),
            "reset after a successful retry stops polling": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .trustCheck(trusted: true),
                    .reset
                ],
                want: [true, true, false],
                wantPending: false
            ),
            "reset ends the episode: the next failure notifies again": (
                steps: [
                    .failure(modifierOnly: true, trusted: false),
                    .reset,
                    .trustCheck(trusted: true),
                    .failure(modifierOnly: true, trusted: false)
                ],
                want: [true, false, false, true],
                wantPending: true
            )
        ]

        for (name, tc) in tests {
            var policy = ModifierOnlyRegistrationRetryPolicy()
            var got: [Bool] = []
            for step in tc.steps {
                switch step {
                case let .failure(modifierOnly, trusted):
                    got.append(policy.recordFailure(isModifierOnly: modifierOnly, isTrusted: trusted))
                case let .trustCheck(trusted):
                    got.append(policy.recordTrust(trusted))
                case .reset:
                    policy.reset()
                    got.append(false)
                }
            }
            XCTAssertEqual(got, tc.want, name)
            XCTAssertEqual(policy.isPending, tc.wantPending, name)
        }
    }
}
