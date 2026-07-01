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

        try await Task.sleep(for: .milliseconds(20))
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
}
