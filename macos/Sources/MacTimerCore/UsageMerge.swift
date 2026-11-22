import Foundation

public struct UsageEntityDisplay: Equatable, Sendable {
    public var name: String
    public var detail: String?
    public var bundleID: String?
    public var isApp: Bool

    public init(
        name: String,
        detail: String? = nil,
        bundleID: String? = nil,
        isApp: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.bundleID = bundleID
        self.isApp = isApp
    }
}

public struct MergedUsage: Equatable, Sendable {
    public var days: [String: [String: Int64]]
    public var displays: [String: UsageEntityDisplay]

    public init(
        days: [String: [String: Int64]] = [:],
        displays: [String: UsageEntityDisplay] = [:]
    ) {
        self.days = days
        self.displays = displays
    }
}

/// Chrome is excluded from the normal app list because its web time is
/// recorded by the extension. The difference between Chrome's Screen Time
/// total and the sum of all extension domains is added back as one row when
/// it is large enough to indicate that the extension missed some browsing.
public enum ChromeGap {
    public static let minimumMilliseconds: Int64 = 3 * 60 * 1_000
    public static let entityKey = "__chrome_unaccounted"
    public static let display = UsageEntityDisplay(
        name: "Chrome（未记录）",
        detail: "插件未覆盖的浏览时间",
        bundleID: "com.google.Chrome",
        isApp: true
    )
}

/// Combines the extension's website buckets with Screen Time's app buckets.
/// Mapped domains and their app are collapsed into one entity, with the app's
/// duration added once even when several domains map to it.
public enum UsageMerge {
    public static func build(
        chromeDays: [String: [String: Int64]],
        screenTimeDays: [String: [String: Int64]],
        mappings: [DomainAppMapping],
        appNames: [String: String]
    ) -> MergedUsage {
        // Last mapping wins if a caller passes duplicates; the store already
        // keeps one mapping per domain.
        var mappingByDomain: [String: DomainAppMapping] = [:]
        for mapping in mappings {
            let domain = DomainName.normalize(mapping.domain) ?? mapping.domain
            mappingByDomain[domain] = mapping
        }

        var domainsByBundle: [String: Set<String>] = [:]
        var mappingNamesByBundle: [String: String] = [:]
        for mapping in mappingByDomain.values
        where !ScreenTimeFilter.isExcluded(mapping.bundleID) {
            domainsByBundle[mapping.bundleID, default: []].insert(mapping.domain)
            if let name = nonempty(mapping.appName) {
                mappingNamesByBundle[mapping.bundleID] = name
            }
        }

        var groupKeyByBundle: [String: String] = [:]
        var bundleByDomain: [String: String] = [:]
        var displays: [String: UsageEntityDisplay] = [:]

        for (bundleID, domains) in domainsByBundle {
            let sortedDomains = domains.sorted()
            guard let key = sortedDomains.first, !key.isEmpty else { continue }
            groupKeyByBundle[bundleID] = key
            for domain in sortedDomains {
                bundleByDomain[domain] = bundleID
            }

            let name = nonempty(appNames[bundleID])
                ?? nonempty(mappingNamesByBundle[bundleID])
                ?? key
            displays[key] = UsageEntityDisplay(
                name: name,
                detail: sortedDomains.joined(separator: " · "),
                bundleID: bundleID,
                isApp: true
            )
        }

        var days: [String: [String: Int64]] = [:]
        let allDays = Set(chromeDays.keys).union(screenTimeDays.keys)

        for day in allDays {
            var bucket: [String: Int64] = [:]

            for (site, milliseconds) in chromeDays[day] ?? [:]
            where milliseconds > 0 && !site.isEmpty {
                let key: String
                if let bundleID = bundleByDomain[site],
                   let groupKey = groupKeyByBundle[bundleID] {
                    key = groupKey
                } else {
                    key = site
                }
                bucket[key, default: 0] += milliseconds
                if displays[key] == nil {
                    displays[key] = UsageEntityDisplay(name: site)
                }
            }

            for (bundleID, milliseconds) in screenTimeDays[day] ?? [:]
            where milliseconds > 0 {
                if ScreenTimeFilter.isExcluded(bundleID) { continue }

                if let key = groupKeyByBundle[bundleID] {
                    bucket[key, default: 0] += milliseconds
                    continue
                }

                // Unmapped apps only appear when macOS can resolve a human
                // name; this filters out helpers, extensions and stale IDs.
                guard let name = nonempty(appNames[bundleID]) else { continue }
                let key = "app:" + bundleID
                bucket[key, default: 0] += milliseconds
                displays[key] = UsageEntityDisplay(
                    name: name,
                    detail: "App",
                    bundleID: bundleID,
                    isApp: true
                )
            }

            let chromeMilliseconds = (screenTimeDays[day] ?? [:])
                .reduce(Int64(0)) { partial, pair in
                    guard ScreenTimeFilter.isChromeUsage(pair.key) else {
                        return partial
                    }
                    return partial + max(0, pair.value)
                }
            let domainMilliseconds = (chromeDays[day] ?? [:])
                .values
                .reduce(Int64(0)) { $0 + max(0, $1) }
            let chromeUnaccounted = chromeMilliseconds - domainMilliseconds
            if chromeUnaccounted >= ChromeGap.minimumMilliseconds {
                bucket[ChromeGap.entityKey, default: 0] += chromeUnaccounted
                displays[ChromeGap.entityKey] = ChromeGap.display
            }

            if !bucket.isEmpty {
                days[day] = bucket
            }
        }

        return MergedUsage(days: days, displays: displays)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
