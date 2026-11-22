import Foundation

/// A mapping between a registrable website domain and a macOS application
/// bundle. Multiple domains may point at the same app; their website time and
/// the app's Screen Time usage are merged into one row.
public struct DomainAppMapping: Codable, Identifiable, Equatable, Sendable {
    public var domain: String
    public var bundleID: String
    public var appName: String

    public var id: String { domain }

    public init(domain: String, bundleID: String, appName: String) {
        self.domain = DomainName.normalize(domain) ?? domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Common mappings bundled with the app. They are starting points, not
    /// claims about which apps are installed; a mapping only contributes
    /// Screen Time usage when that app appears in the local database.
    public static let builtIns: [DomainAppMapping] = [
        DomainAppMapping(
            domain: "bilibili.com",
            bundleID: "com.bilibili.bilibiliPC",
            appName: "哔哩哔哩"
        ),
        DomainAppMapping(
            domain: "steampowered.com",
            bundleID: "com.valvesoftware.steam",
            appName: "Steam"
        ),
        DomainAppMapping(
            domain: "spotify.com",
            bundleID: "com.spotify.client",
            appName: "Spotify"
        ),
        DomainAppMapping(
            domain: "netflix.com",
            bundleID: "com.netflix.Netflix",
            appName: "Netflix"
        ),
        DomainAppMapping(
            domain: "notion.so",
            bundleID: "notion.id",
            appName: "Notion"
        ),
        DomainAppMapping(
            domain: "slack.com",
            bundleID: "com.tinyspeck.slackmacgap",
            appName: "Slack"
        ),
        DomainAppMapping(
            domain: "discord.com",
            bundleID: "com.hnc.Discord",
            appName: "Discord"
        ),
        DomainAppMapping(
            domain: "figma.com",
            bundleID: "com.figma.Desktop",
            appName: "Figma"
        ),
        DomainAppMapping(
            domain: "chatgpt.com",
            bundleID: "com.openai.chat",
            appName: "ChatGPT"
        ),
        DomainAppMapping(
            domain: "zoom.us",
            bundleID: "us.zoom.xos",
            appName: "Zoom"
        ),
        DomainAppMapping(
            domain: "telegram.org",
            bundleID: "ru.keepcoder.Telegram",
            appName: "Telegram"
        ),
        DomainAppMapping(
            domain: "github.com",
            bundleID: "com.github.GitHubClient",
            appName: "GitHub Desktop"
        ),
    ]
}

/// Which Screen Time bundle IDs are shown, hidden, or unsuitable as mapping
/// targets.
public enum ScreenTimeFilter {
    /// Many Screen Time records are background/system UI rather than something
    /// the user would consider app usage. Chrome is special: its browsing time
    /// already comes from the extension, so including the Chrome app (and its
    /// web apps) would double count.
    private static let excludedExact: Set<String> = [
        "com.apple.finder",
        "com.apple.systemsettings",
        "com.apple.systempreferences",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.spotlight",
        "com.apple.screentimeagent",
    ]

    public static func isExcluded(_ bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !id.isEmpty else { return true }
        if id.hasPrefix("com.google.chrome") { return true }
        if id.hasPrefix("com.muyuchen.mactimer") { return true }
        return excludedExact.contains(id)
    }

    /// Chrome itself is excluded from normal app rows, but its Screen Time
    /// duration is used to calculate time the extension did not record.
    /// Chrome web apps/PWAs count as Chrome browsing too.
    private static let chromeMainBundleIDs: Set<String> = [
        "com.google.chrome",
        "com.google.chrome.beta",
        "com.google.chrome.dev",
        "com.google.chrome.canary",
    ]

    public static func isChromeUsage(_ bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !id.isEmpty else { return false }
        return chromeMainBundleIDs.contains(id)
            || id.hasPrefix("com.google.chrome.app.")
    }

    /// Browsers aggregate many different websites into one app. Mapping a
    /// domain to a browser would assign all browser time to that one site, so
    /// the settings UI refuses it.
    public static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if id.hasPrefix("com.google.chrome") { return true }
        if id.hasPrefix("com.apple.safari") { return true }
        return browserBundleIDs.contains(id)
    }

    private static let browserBundleIDs: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac",
        "company.thebrowser.browser",
        "com.brave.browser",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera",
        "org.chromium.chromium",
        "com.google.chrome.canary",
        "com.apple.safaritechnologypreview",
    ]
}
