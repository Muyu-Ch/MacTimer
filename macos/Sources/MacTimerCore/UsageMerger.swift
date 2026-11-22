import Foundation

public enum UsageMerger {
    /// A full sync (`reset == true`) replaces all history. A delta replaces only
    /// the day buckets it contains, which is safe because the extension always
    /// sends the complete bucket for a day.
    public static func merge(
        existing: UsageSnapshot?,
        payload: NativeSyncPayload,
        receivedAt: Date = Date()
    ) -> UsageSnapshot {
        var days: [String: [String: Int64]] = payload.reset == true
            ? [:]
            : (existing?.days ?? [:])

        if let incoming = payload.days {
            for (day, bucket) in incoming {
                guard CalendarDay.date(from: day) != nil else { continue }

                var clean: [String: Int64] = [:]
                for (site, milliseconds) in bucket
                where !site.isEmpty && milliseconds > 0 {
                    clean[site] = milliseconds
                }

                if clean.isEmpty {
                    days.removeValue(forKey: day)
                } else {
                    days[day] = clean
                }
            }
        }

        let updatedAt = Int64(receivedAt.timeIntervalSince1970 * 1000)
        return UsageSnapshot(
            version: 1,
            updatedAt: updatedAt,
            current: payload.current,
            days: days
        )
    }
}
