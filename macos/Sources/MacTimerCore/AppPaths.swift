import Foundation

public enum AppPaths {
    private static var applicationSupportBase: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    public static var defaultSupportDirectory: URL {
        applicationSupportBase.appendingPathComponent(
            "MacTimer",
            isDirectory: true
        )
    }

    /// The pre-rename app used this folder. Its data file is copied once when
    /// the new app starts, so upgrading users keep their history.
    private static var legacySupportDirectory: URL {
        applicationSupportBase.appendingPathComponent(
            "StayTimer",
            isDirectory: true
        )
    }

    /// Set `MACTIMER_DATA_FILE` to point both the host and the app at a test file.
    public static var dataFileURL: URL {
        if let path = ProcessInfo.processInfo.environment["MACTIMER_DATA_FILE"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let url = defaultSupportDirectory.appendingPathComponent("usage.json")
        migrateLegacyUsageIfNeeded(to: url)
        return url
    }

    private static func migrateLegacyUsageIfNeeded(to url: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return }
        let legacy = legacySupportDirectory.appendingPathComponent(
            "usage.json"
        )
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.copyItem(at: legacy, to: url)
    }

    /// App-owned history of Screen Time data. Apple's detail database only
    /// keeps about four weeks, so successful reads are merged here and kept
    /// beyond that window.
    public static var screenTimeArchiveURL: URL {
        if let path = ProcessInfo.processInfo.environment[
            "MACTIMER_SCREEN_TIME_ARCHIVE"
        ], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultSupportDirectory.appendingPathComponent(
            "screen-time-archive.json"
        )
    }

    /// The private database behind Apple Screen Time. Reading it requires
    /// Full Disk Access; `MACTIMER_KNOWLEDGE_DB` overrides it for tests.
    public static var screenTimeDatabaseURL: URL {
        if let path = ProcessInfo.processInfo.environment["MACTIMER_KNOWLEDGE_DB"],
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge", isDirectory: true)
            .appendingPathComponent("knowledgeC.db")
    }
}
