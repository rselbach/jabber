import Foundation

@MainActor
final class AppReadinessGate {
    static let shared = AppReadinessGate()

    private var isUIReady = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func markUIReady() {
        guard !isUIReady else { return }

        isUIReady = true
        let waiters = continuations
        continuations.removeAll()

        for continuation in waiters {
            continuation.resume()
        }
    }

    func waitForUIReady() async {
        guard !isUIReady else { return }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
