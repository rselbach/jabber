import XCTest
@testable import Jabber

@MainActor
final class AppReadinessGateTests: XCTestCase {
    func testWaiterResumesWhenUIIsReady() async throws {
        let gate = AppReadinessGate()
        var didResume = false

        let waitTask = Task { @MainActor in
            await gate.waitForUIReady()
            didResume = true
        }

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(didResume)

        gate.markUIReady()
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(didResume)
        await waitTask.value
    }

    func testWaitReturnsImmediatelyAfterUIIsReady() async {
        let gate = AppReadinessGate()

        gate.markUIReady()
        await gate.waitForUIReady()
    }

    func testCancelledWaiterResumesWithoutMarkUIReady() async {
        let gate = AppReadinessGate()

        let waitTask = Task { @MainActor in
            await gate.waitForUIReady()
        }

        // Let the task park on its continuation.
        try? await Task.sleep(for: .milliseconds(50))

        waitTask.cancel()

        // The waiter must return promptly after cancellation, without markUIReady()
        // being called. Race the await against a timeout; if the bug is present the
        // continuation never resumes and the timeout wins.
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await waitTask.value
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            XCTAssertNotNil(
                result,
                "waitForUIReady did not return within 500ms after the awaiting task was cancelled"
            )
        }

        // A subsequent markUIReady() must not double-resume the (already-removed)
        // continuation or crash.
        gate.markUIReady()
    }
}
