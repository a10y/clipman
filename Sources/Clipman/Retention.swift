import Foundation

enum Retention {
    /// Decide which items to drop. `items` must be ordered newest-first.
    ///
    /// An item is evicted if it is older than `maxAge`, or if keeping it would
    /// push the cumulative size of everything newer than it past `maxBytes`.
    /// Once the size budget is exhausted, everything older is evicted too, so
    /// history is always a contiguous "most recent" window.
    static func evictions(
        in items: [ClipItem],
        now: Date = Date(),
        maxAge: TimeInterval,
        maxBytes: Int
    ) -> Set<UUID> {
        var evict = Set<UUID>()
        var total = 0
        var budgetExhausted = false

        for item in items {
            if budgetExhausted || now.timeIntervalSince(item.date) > maxAge {
                evict.insert(item.id)
                continue
            }
            if total + item.byteSize > maxBytes {
                evict.insert(item.id)
                // A single oversized item shouldn't wipe out older, smaller ones.
                if item.byteSize <= maxBytes { budgetExhausted = true }
                continue
            }
            total += item.byteSize
        }
        return evict
    }
}
