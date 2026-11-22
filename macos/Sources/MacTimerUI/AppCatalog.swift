import AppKit
import Foundation

/// Resolves Screen Time bundle identifiers to localized names and app icons.
@MainActor
public final class AppCatalog {
    public static let shared = AppCatalog()

    private var nameCache: [String: String] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var missing: Set<String> = []

    private init() {}

    public func name(for bundleID: String) -> String? {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !missing.contains(id) else { return nil }
        if let cached = nameCache[id] { return cached }

        guard let url = applicationURL(for: id) else {
            missing.insert(id)
            return nil
        }
        let name = Self.displayName(for: url)
        nameCache[id] = name
        return name
    }

    public func icon(for bundleID: String) -> NSImage? {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        if let cached = iconCache[id] { return cached }
        guard let url = applicationURL(for: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = icon
        return icon
    }

    /// Reads the bundle identifier and visible name of an application selected
    /// in an open panel and warms both caches for it.
    public func appInfo(at url: URL) -> (bundleID: String, name: String)? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty else {
            return nil
        }
        let name = Self.displayName(for: url)
        nameCache[bundleID] = name
        iconCache[bundleID] = NSWorkspace.shared.icon(forFile: url.path)
        missing.remove(bundleID)
        return (bundleID, name)
    }

    private func applicationURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url) {
            let candidates: [String?] = [
                bundle.localizedInfoDictionary?["CFBundleDisplayName"]
                    as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                    as? String,
                bundle.localizedInfoDictionary?["CFBundleName"] as? String,
                bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            ]
            if let name = candidates.compactMap({ $0 })
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return name
            }
        }

        let display = FileManager.default.displayName(atPath: url.path)
        if display.lowercased().hasSuffix(".app") {
            return String(display.dropLast(4))
        }
        return display
    }
}
