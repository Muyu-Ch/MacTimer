import Combine
import Foundation
import MacTimerCore

public enum MappingValidationError: LocalizedError, Equatable, Sendable {
    case invalidDomain
    case emptyApp
    case browserUnsupported
    case excludedApp

    public var errorDescription: String? {
        switch self {
        case .invalidDomain:
            return "请输入有效域名，例如 bilibili.com 或 www.bilibili.com。"
        case .emptyApp:
            return "请选择一个应用。"
        case .browserUnsupported:
            return "浏览器包含所有网站的使用时间，不能作为单个网站的映射目标。"
        case .excludedApp:
            return "系统界面或 MacTimer 本身不需要合并。"
        }
    }
}

@MainActor
public final class MappingStore: ObservableObject {
    @Published public private(set) var customMappings: [DomainAppMapping] = []

    public let builtIns: [DomainAppMapping]

    public static let shared = MappingStore()

    private let defaults: UserDefaults?
    private static let storageKey = "customDomainAppMappings.v1"

    public init(
        builtIns: [DomainAppMapping] = DomainAppMapping.builtIns,
        defaults: UserDefaults? = .standard,
        loadCustom: Bool = true
    ) {
        self.builtIns = builtIns
        self.defaults = defaults
        if loadCustom {
            load()
        }
    }

    public var effectiveMappings: [DomainAppMapping] {
        var byDomain: [String: DomainAppMapping] = [:]
        for mapping in builtIns {
            byDomain[mapping.domain] = mapping
        }
        for mapping in customMappings {
            byDomain[mapping.domain] = mapping
        }
        return byDomain.values.sorted { $0.domain < $1.domain }
    }

    public func customMapping(for domain: String) -> DomainAppMapping? {
        customMappings.first { $0.domain == domain }
    }

    public func builtInMapping(for domain: String) -> DomainAppMapping? {
        builtIns.first { $0.domain == domain }
    }

    public func isCustomized(domain: String) -> Bool {
        customMappings.contains { $0.domain == domain }
    }

    @discardableResult
    public func addMapping(
        domainInput: String,
        bundleID: String,
        appName: String
    ) throws -> DomainAppMapping {
        guard let domain = DomainName.normalize(domainInput) else {
            throw MappingValidationError.invalidDomain
        }
        let trimmedBundleID = bundleID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedBundleID.isEmpty else {
            throw MappingValidationError.emptyApp
        }
        if ScreenTimeFilter.isBrowser(trimmedBundleID) {
            throw MappingValidationError.browserUnsupported
        }
        if ScreenTimeFilter.isExcluded(trimmedBundleID) {
            throw MappingValidationError.excludedApp
        }

        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapping = DomainAppMapping(
            domain: domain,
            bundleID: trimmedBundleID,
            appName: trimmedName.isEmpty ? trimmedBundleID : trimmedName
        )

        var next = customMappings.filter { $0.domain != domain }
        next.append(mapping)
        customMappings = next.sorted { $0.domain < $1.domain }
        save()
        return mapping
    }

    public func removeMapping(domain: String) {
        let next = customMappings.filter { $0.domain != domain }
        guard next.count != customMappings.count else { return }
        customMappings = next
        save()
    }

    private func load() {
        var data = defaults?.data(forKey: Self.storageKey)

        // Carry custom mappings over from the pre-rename bundle when the
        // new app has not stored its own mappings yet. Only do this for the
        // real app domain, not test or preview UserDefaults suites.
        if data == nil, defaults === UserDefaults.standard {
            let legacyDefaults = UserDefaults(
                suiteName: "com.muyuchen.staytimer"
            )
            if let legacyData = legacyDefaults?.data(
                forKey: Self.storageKey
            ) {
                data = legacyData
                defaults?.set(legacyData, forKey: Self.storageKey)
            }
        }

        guard let data,
              !data.isEmpty,
              let decoded = try? JSONDecoder().decode(
                  [DomainAppMapping].self,
                  from: data
              ) else {
            return
        }

        // Re-normalize older data and keep one mapping per domain.
        var byDomain: [String: DomainAppMapping] = [:]
        for mapping in decoded {
            let normalized = DomainAppMapping(
                domain: mapping.domain,
                bundleID: mapping.bundleID,
                appName: mapping.appName
            )
            guard !normalized.domain.isEmpty,
                  !normalized.bundleID.isEmpty else {
                continue
            }
            byDomain[normalized.domain] = normalized
        }
        customMappings = byDomain.values.sorted { $0.domain < $1.domain }
    }

    private func save() {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(customMappings) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
