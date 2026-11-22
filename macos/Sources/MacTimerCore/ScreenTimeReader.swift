import Foundation
import SQLite3

public struct ScreenTimeUsage: Equatable, Sendable {
    public var days: [String: [String: Int64]]
    /// day -> hour (0...23) -> bundle id -> milliseconds. Used by the day
    /// view's hourly chart; it is not included in the native data mirror.
    public var hours: [String: [Int: [String: Int64]]]
    public var fetchedAt: Date
    public var stream: String?
    public var eventCount: Int

    public init(
        days: [String: [String: Int64]] = [:],
        fetchedAt: Date = Date(),
        stream: String? = nil,
        eventCount: Int = 0,
        hours: [String: [Int: [String: Int64]]] = [:]
    ) {
        self.days = days
        self.fetchedAt = fetchedAt
        self.stream = stream
        self.eventCount = eventCount
        self.hours = hours
    }

    public var hasData: Bool {
        days.values.contains { bucket in
            bucket.values.contains { $0 > 0 }
        }
    }
}

public enum ScreenTimeReadError: LocalizedError, Equatable, Sendable {
    case databaseNotFound(String)
    case permissionDenied
    case schemaUnsupported(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "未找到屏幕使用时间数据库。请确认已在系统中启用屏幕使用时间；如果已启用，请在「完全磁盘访问权限」中添加 MacTimer。"
        case .permissionDenied:
            return "需要「完全磁盘访问权限」才能读取 Apple 屏幕使用时间。"
        case .schemaUnsupported(let detail):
            return "当前系统的屏幕使用时间数据格式不受支持：\(detail)"
        case .readFailed(let detail):
            return "读取屏幕使用时间失败：\(detail)"
        }
    }
}

/// Reads app foreground durations from the local database behind Apple's
/// Screen Time. This is a private, undocumented Apple store; access requires
/// Full Disk Access. The file is opened read-only and nothing leaves the Mac.
public struct ScreenTimeReader: Sendable {
    public static let supportedStreams = ["/app/usage", "/app/inFocus"]

    public let databaseURL: URL

    public init(databaseURL: URL = AppPaths.screenTimeDatabaseURL) {
        self.databaseURL = databaseURL
    }

    /// Reads app events that end at or after `since`, clipped at `now`, and
    /// splits them at local midnights into `YYYY-MM-DD` buckets.
    ///
    /// `preferredStream` lets an incremental refresh reuse the stream chosen
    /// by the initial full read, so the cached days do not mix sources.
    public func read(
        since: Date,
        now: Date = Date(),
        preferredStream: String? = nil,
        calendar: Calendar = .current
    ) throws -> ScreenTimeUsage {
        guard now > since else {
            return ScreenTimeUsage(fetchedAt: now)
        }

        let path = databaseURL.path
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            throw ScreenTimeReadError.databaseNotFound(path)
        }

        var handle: OpaquePointer?
        let openCode = sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard openCode == SQLITE_OK, let database = handle else {
            let message = handle.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "SQLite error \(openCode)"
            if let handle {
                sqlite3_close(handle)
            }
            throw mapOpenError(code: openCode, message: message, path: path)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 3_000)

        let columns = try tableColumns(database: database, table: "ZOBJECT")
        let required = [
            "zstreamname", "zvaluestring", "zstartdate", "zenddate",
        ]
        guard Set(required).isSubset(of: columns) else {
            let missing = required.filter { !columns.contains($0) }
            throw ScreenTimeReadError.schemaUnsupported(
                "ZOBJECT 缺少字段 \(missing.joined(separator: ", "))"
            )
        }

        let cutoff = max(0, since.timeIntervalSinceReferenceDate)
        let stream = try preferredStream ?? chooseStream(
            database: database,
            cutoff: cutoff
        )

        guard let stream else {
            return ScreenTimeUsage(fetchedAt: now)
        }

        let events = try readEvents(
            database: database,
            stream: stream,
            cutoff: cutoff
        )

        var days: [String: [String: Int64]] = [:]
        var hours: [String: [Int: [String: Int64]]] = [:]
        for event in events {
            var start = Date(timeIntervalSinceReferenceDate: event.start)
            var end = Date(timeIntervalSinceReferenceDate: event.end)
            if start < since { start = since }
            if end > now { end = now }
            guard end > start else { continue }
            add(
                bundleID: event.bundleID,
                from: start,
                to: end,
                calendar: calendar,
                into: &days,
                hours: &hours
            )
        }

        return ScreenTimeUsage(
            days: days,
            fetchedAt: now,
            stream: stream,
            eventCount: events.count,
            hours: hours
        )
    }

    // MARK: - SQLite

    private struct Event {
        var bundleID: String
        var start: Double
        var end: Double
    }

    private func mapOpenError(
        code: Int32,
        message: String,
        path: String
    ) -> ScreenTimeReadError {
        let lower = message.lowercased()
        if code == SQLITE_AUTH
            || code == SQLITE_PERM
            || lower.contains("authorization denied")
            || lower.contains("not authorized")
            || lower.contains("operation not permitted") {
            return .permissionDenied
        }
        if code == SQLITE_CANTOPEN {
            if FileManager.default.fileExists(atPath: path) {
                return .permissionDenied
            }
            return .databaseNotFound(path)
        }
        return .readFailed(message)
    }

    private func tableColumns(
        database: OpaquePointer,
        table: String
    ) throws -> Set<String> {
        var statement: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw readError(database: database)
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let text = sqlite3_column_text(statement, 1) {
                    columns.insert(String(cString: text).lowercased())
                }
            case SQLITE_DONE:
                return columns
            default:
                throw readError(database: database)
            }
        }
    }

    private func chooseStream(
        database: OpaquePointer,
        cutoff: Double
    ) throws -> String? {
        let placeholders = Self.supportedStreams.map { _ in "?" }
            .joined(separator: ", ")
        let sql = """
            SELECT ZSTREAMNAME, COUNT(*)
            FROM ZOBJECT
            WHERE ZSTREAMNAME IN (\(placeholders))
              AND ZSTARTDATE IS NOT NULL
              AND ZENDDATE IS NOT NULL
              AND ZENDDATE > ZSTARTDATE
              AND ZENDDATE >= ?
            GROUP BY ZSTREAMNAME
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw readError(database: database)
        }
        defer { sqlite3_finalize(statement) }

        for (index, stream) in Self.supportedStreams.enumerated() {
            sqlite3_bind_text(
                statement,
                Int32(index + 1),
                stream,
                -1,
                sqliteTransient
            )
        }
        sqlite3_bind_double(
            statement,
            Int32(Self.supportedStreams.count + 1),
            cutoff
        )

        var counts: [String: Int] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let nameText = sqlite3_column_text(statement, 0) else {
                    continue
                }
                let name = String(cString: nameText)
                counts[name] = Int(sqlite3_column_int64(statement, 1))
            case SQLITE_DONE:
                for stream in Self.supportedStreams
                where (counts[stream] ?? 0) > 0 {
                    return stream
                }
                return nil
            default:
                throw readError(database: database)
            }
        }
    }

    private func readEvents(
        database: OpaquePointer,
        stream: String,
        cutoff: Double
    ) throws -> [Event] {
        let sql = """
            SELECT ZVALUESTRING, ZSTARTDATE, ZENDDATE
            FROM ZOBJECT
            WHERE ZSTREAMNAME = ?
              AND ZVALUESTRING IS NOT NULL
              AND ZVALUESTRING <> ''
              AND ZSTARTDATE IS NOT NULL
              AND ZENDDATE IS NOT NULL
              AND ZENDDATE > ZSTARTDATE
              AND ZENDDATE >= ?
            ORDER BY ZSTARTDATE
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw readError(database: database)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, stream, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, cutoff)

        var events: [Event] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let text = sqlite3_column_text(statement, 0) else {
                    continue
                }
                let bundleID = String(cString: text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleID.isEmpty else { continue }
                let start = sqlite3_column_double(statement, 1)
                let end = sqlite3_column_double(statement, 2)
                guard end > start else { continue }
                events.append(
                    Event(bundleID: bundleID, start: start, end: end)
                )
            case SQLITE_DONE:
                return events
            default:
                throw readError(database: database)
            }
        }
    }

    private func readError(database: OpaquePointer) -> ScreenTimeReadError {
        let code = sqlite3_errcode(database)
        let message = String(cString: sqlite3_errmsg(database))
        let lower = message.lowercased()
        if code == SQLITE_AUTH
            || code == SQLITE_PERM
            || lower.contains("authorization denied")
            || lower.contains("not authorized")
            || lower.contains("operation not permitted") {
            return .permissionDenied
        }
        return .readFailed(message)
    }

    // MARK: - Day buckets

    private func add(
        bundleID: String,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        into days: inout [String: [String: Int64]],
        hours: inout [String: [Int: [String: Int64]]]
    ) {
        var cursor = start
        var steps = 0
        while cursor < end && steps < 4_000 {
            let hourEnd = calendar.dateInterval(
                of: .hour,
                for: cursor
            )?.end ?? calendar.date(
                byAdding: .hour,
                value: 1,
                to: cursor
            )
            guard let hourEnd, hourEnd > cursor else { break }
            let segmentEnd = min(end, hourEnd)
            guard segmentEnd > cursor else { break }

            let day = CalendarDay.key(for: cursor, calendar: calendar)
            let hour = calendar.component(.hour, from: cursor)
            let milliseconds = Int64(
                (segmentEnd.timeIntervalSince(cursor) * 1_000).rounded()
            )
            if milliseconds > 0 {
                var dayBucket = days[day] ?? [:]
                dayBucket[bundleID, default: 0] += milliseconds
                days[day] = dayBucket

                var hourBucket = hours[day] ?? [:]
                var bundleBucket = hourBucket[hour] ?? [:]
                bundleBucket[bundleID, default: 0] += milliseconds
                hourBucket[hour] = bundleBucket
                hours[day] = hourBucket
            }

            cursor = segmentEnd
            steps += 1
        }
    }
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
