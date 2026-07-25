import Foundation

extension Duration {
    /// whole milliseconds, truncated; for latency logging
    var wholeMilliseconds: Int64 {
        let components = components
        let millisecondsFromSeconds = components.seconds * 1_000
        let millisecondsFromAttoseconds = components.attoseconds / 1_000_000_000_000_000
        return millisecondsFromSeconds + millisecondsFromAttoseconds
    }
}
