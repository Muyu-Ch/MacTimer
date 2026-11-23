import Foundation

public struct CurrentSession: Codable, Equatable, Sendable {
    public var site: String
    public var since: Int64

    public init(site: String, since: Int64) {
        self.site = site
        self.since = since
    }
}

public struct SiteEntry: Identifiable, Equatable, Sendable {
    public var site: String
    public var milliseconds: Int64

    public var id: String { site }

    public init(site: String, milliseconds: Int64) {
        self.site = site
        self.milliseconds = milliseconds
    }
}

/// The on-disk snapshot written by the native host and read by the app.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Int64
    public var current: CurrentSession?
    public var days: [String: [String: Int64]]
    /// Calendar day -> clock hour ("0"..."3") -> site -> milliseconds.
    /// Recorded by the extension so a custom day-start hour can move the
    /// early-morning part of a calendar day onto the previous logical day.
    public var earlyHours: [String: [String: [String: Int64]]]?

    public init(
        version: Int = 1,
        updatedAt: Int64 = 0,
        current: CurrentSession? = nil,
        days: [String: [String: Int64]] = [:],
        earlyHours: [String: [String: [String: Int64]]]? = nil
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.current = current
        self.days = days
        self.earlyHours = earlyHours
    }

    public func entries(for day: String) -> [SiteEntry] {
        guard let bucket = days[day] else { return [] }
        return bucket.compactMap { site, milliseconds in
            guard milliseconds > 0, !site.isEmpty else { return nil }
            return SiteEntry(site: site, milliseconds: milliseconds)
        }
        .sorted { left, right in
            if left.milliseconds == right.milliseconds {
                return left.site < right.site
            }
            return left.milliseconds > right.milliseconds
        }
    }

    public func total(for day: String) -> Int64 {
        (days[day] ?? [:]).values.reduce(Int64(0)) { partial, milliseconds in
            partial + max(0, milliseconds)
        }
    }

    public func aggregatedEntries(over dayKeys: [String]) -> [SiteEntry] {
        var totals: [String: Int64] = [:]
        for day in dayKeys {
            for (site, milliseconds) in days[day] ?? [:]
            where milliseconds > 0 && !site.isEmpty {
                totals[site, default: 0] += milliseconds
            }
        }
        return totals.map {
            SiteEntry(site: $0.key, milliseconds: $0.value)
        }
        .sorted { left, right in
            if left.milliseconds == right.milliseconds {
                return left.site < right.site
            }
            return left.milliseconds > right.milliseconds
        }
    }

    public func totalOver(_ dayKeys: [String]) -> Int64 {
        dayKeys.reduce(Int64(0)) { $0 + total(for: $1) }
    }

    public func activeDayCount(over dayKeys: [String]) -> Int {
        dayKeys.reduce(0) { count, day in
            count + (total(for: day) > 0 ? 1 : 0)
        }
    }

    public func bestDay(
        over dayKeys: [String]
    ) -> (day: String, milliseconds: Int64)? {
        var best: (day: String, milliseconds: Int64)?
        for day in dayKeys {
            let milliseconds = total(for: day)
            guard milliseconds > 0 else { continue }
            if best == nil || milliseconds > best!.milliseconds {
                best = (day, milliseconds)
            }
        }
        return best
    }

    public var activeDays: [String] {
        days.filter { _, bucket in
            bucket.values.contains { $0 > 0 }
        }
        .keys
        .sorted()
    }
}
