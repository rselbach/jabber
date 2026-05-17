import Foundation

struct TranscriptionActivityTracker: Equatable {
    private(set) var activeID: UUID?

    var isActive: Bool {
        activeID != nil
    }

    mutating func start(_ id: UUID) -> Bool {
        guard activeID == nil else { return false }
        activeID = id
        return true
    }

    @discardableResult
    mutating func complete(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}
