import Foundation

public struct NativeSyncPayload: Codable, Sendable {
    public var type: String
    public var sentAt: Int64?
    public var reset: Bool?
    public var current: CurrentSession?
    public var days: [String: [String: Int64]]?

    public init(
        type: String,
        sentAt: Int64? = nil,
        reset: Bool? = nil,
        current: CurrentSession? = nil,
        days: [String: [String: Int64]]? = nil
    ) {
        self.type = type
        self.sentAt = sentAt
        self.reset = reset
        self.current = current
        self.days = days
    }
}

public struct NativeSyncResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var updatedAt: Int64?
    public var days: Int?
    public var needFull: Bool?

    public init(
        ok: Bool,
        error: String? = nil,
        updatedAt: Int64? = nil,
        days: Int? = nil,
        needFull: Bool? = nil
    ) {
        self.ok = ok
        self.error = error
        self.updatedAt = updatedAt
        self.days = days
        self.needFull = needFull
    }
}
