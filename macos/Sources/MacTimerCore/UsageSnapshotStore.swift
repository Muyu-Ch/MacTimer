import Foundation

public struct UsageSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.dataFileURL) {
        self.fileURL = fileURL
    }

    public func load() throws -> UsageSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
