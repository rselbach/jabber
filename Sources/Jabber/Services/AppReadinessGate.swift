import Foundation

@MainActor
final class AppReadinessGate {
    static let shared = AppReadinessGate()

    private var isUIReady = false
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    func markUIReady() {
        guard !isUIReady else { return }

        isUIReady = true
        let waiters = continuations
        continuations.removeAll()

        for continuation in waiters.values {
            continuation.resume()
        }
    }

    func waitForUIReady() async {
        guard !isUIReady else { return }

        // Each waiter gets a unique id so its own cancellation handler can remove
        // (and resume) exactly that continuation. Both markUIReady() and the
        // cancellation hop below run on @MainActor, so removeValue(forKey:) gives
        // us atomic check-and-remove: every continuation is resumed at most once.
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuations[id] = continuation
            }
        } onCancel: {
            Task { @MainActor in
                guard let continuation = self.continuations.removeValue(forKey: id) else { return }
                continuation.resume()
            }
        }
    }
}
