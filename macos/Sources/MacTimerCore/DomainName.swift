import Foundation

/// Normalizes user-entered URLs/domains to the same registrable-domain keys
/// the Chrome extension stores (a deliberately small eTLD+1 heuristic).
public enum DomainName {
    private static let ccSecondLevels: Set<String> = [
        "co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go",
        "mil", "sch", "nhs", "mod", "police", "ltd", "plc", "asn", "me",
        "idv", "nom", "firm", "gen", "ind", "res", "gob", "govt", "school",
        "waw", "muni",
    ]

    /// Accepts `www.bilibili.com`, `https://www.bilibili.com/video/...`,
    /// `b23.tv/...` and returns `bilibili.com` / `b23.tv`. Returns nil when the
    /// input does not contain a usable host.
    public static func normalize(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            return nil
        }

        if !value.contains("://") {
            value = "https://" + value
        }

        guard let url = URL(string: value),
              var host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else { return nil }

        if host == "localhost" || host.hasPrefix("[") || isIPv4(host) {
            return host
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        if labels.count <= 2 { return host }

        let tld = labels[labels.count - 1]
        let secondLevel = labels[labels.count - 2]
        if tld.count == 2 && ccSecondLevels.contains(secondLevel) {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else {
                return false
            }
            return String(value) == String(part)
        }
    }
}
