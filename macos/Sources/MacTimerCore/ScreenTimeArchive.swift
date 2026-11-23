import Foundation

/// App-owned persistence for Screen Time days. Apple's detail database keeps
/// only a few weeks, so the app merges successful reads into this archive.
public struct ScreenTimeArchive: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: Int64
    public var stream: String?
    public var days: [String: [String: Int64]]
    /// JSON uses string hour keys because Int-keyed dictionaries are awkward
    /// to exchange and inspect.
    public var hours: [String: [String: [String: Int64]]]

    public init(
        version: Int = 1,
        updatedAt: Int64,
        stream: String?,
        days: [String: [String: Int64]],
        hours: [String: [String: [String: Int64]]]
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.stream = stream
        self.days = days
        self.hours = hours
    }

    public init(
        days: [String: [String: Int64]],
        hoursByHour: [String: [Int: [String: Int64]]],
        stream: String?,
        updatedAt: Date
    ) {
        self.version = 1
        self.updatedAt = Int64(updatedAt.timeIntervalSince1970 * 1_000)
        self.stream = stream
        self.days = days
        var encodedHours: [String: [String: [String: Int64]]] = [:]
        for (day, buckets) in hoursByHour {
            var dayHours: [String: [String: Int64]] = [:]
            for (hour, values) in buckets {
                dayHours[String(hour)] = values
            }
            encodedHours[day] = dayHours
        }
        self.hours = encodedHours
    }

    public var updatedAtDate: Date {
        Date(timeIntervalSince1970: Double(updatedAt) / 1_000)
    }

    public func hourBuckets() -> [String: [Int: [String: Int64]]] {
        var decoded: [String: [Int: [String: Int64]]] = [:]
        for (day, buckets) in hours {
            var dayHours: [Int: [String: Int64]] = [:]
            for (hour, values) in buckets {
                guard let hourValue = Int(hour),
                      (0...23).contains(hourValue) else {
                    continue
                }
                dayHours[hourValue] = values
            }
            decoded[day] = dayHours
        }
        return decoded
    }

    public func usage(fetchedAt: Date? = nil) -> ScreenTimeUsage {
        ScreenTimeUsage(
            days: days,
            fetchedAt: fetchedAt ?? updatedAtDate,
            stream: stream,
            eventCount: 0,
            hours: hourBuckets()
        )
    }
}

public struct ScreenTimeArchiveStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.screenTimeArchiveURL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ScreenTimeArchive? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(ScreenTimeArchive.self, from: data)
    }

    public func save(_ archive: ScreenTimeArchive) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public enum ScreenTimeArchiveMerger {
    /// Newly read days replace the same days in the archive. Days that are
    /// absent from a read are preserved, because they may have fallen out of
    /// Apple's retention window (or a temporary read may have missed them).
    public static func merge(
        days: inout [String: [String: Int64]],
        hours: inout [String: [Int: [String: Int64]]],
        with usage: ScreenTimeUsage
    ) {
        for (day, bucket) in usage.days {
            days[day] = bucket
        }
        for day in usage.days.keys {
            hours[day] = usage.hours[day] ?? [:]
        }
        for (day, buckets) in usage.hours where usage.days[day] != nil {
            hours[day] = buckets
        }
    }
}
