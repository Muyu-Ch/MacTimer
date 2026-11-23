import AppKit
import Combine
import SwiftUI
import MacTimerCore

public enum CategoryPalette {
    public static let presetColors = [
        "#3B82F6", "#6366F1", "#8B5CF6", "#D946EF", "#EC4899",
        "#EF4444", "#F97316", "#D97706", "#10B981", "#14B8A6",
        "#06B6D4", "#64748B",
    ]
}

public struct UsageCategory: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public enum CategoryRuleKind: String, Codable, Equatable, Sendable {
    case app
    case domain

    public var label: String {
        switch self {
        case .app: "App"
        case .domain: "网站"
        }
    }
}

public struct CategoryRule: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: CategoryRuleKind
    public var identifier: String
    public var displayName: String
    public var categoryID: String

    public init(
        id: String = UUID().uuidString,
        kind: CategoryRuleKind,
        identifier: String,
        displayName: String,
        categoryID: String
    ) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.categoryID = categoryID
    }
}

public enum CategoryStoreError: LocalizedError, Equatable, Sendable {
    case invalidName
    case invalidDomain
    case emptyApp
    case missingCategory

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "分类名称不能为空。"
        case .invalidDomain:
            return "请输入有效域名，例如 bilibili.com。"
        case .emptyApp:
            return "请选择一个应用。"
        case .missingCategory:
            return "请先创建并选择一个分类。"
        }
    }
}

public struct CategoryUsage: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var milliseconds: Int64
    public var isUncategorized: Bool

    public var hours: Double {
        Double(milliseconds) / 3_600_000
    }

    public init(
        id: String,
        name: String,
        colorHex: String,
        milliseconds: Int64,
        isUncategorized: Bool
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.milliseconds = milliseconds
        self.isUncategorized = isUncategorized
    }
}

public struct CategoryRuleTarget: Identifiable, Equatable, Sendable {
    public var kind: CategoryRuleKind
    public var identifier: String
    public var name: String
    public var detail: String?
    public var milliseconds: Int64

    public var id: String {
        "\(kind.rawValue):\(identifier)"
    }

    public init(
        kind: CategoryRuleKind,
        identifier: String,
        name: String,
        detail: String?,
        milliseconds: Int64
    ) {
        self.kind = kind
        self.identifier = identifier
        self.name = name
        self.detail = detail
        self.milliseconds = milliseconds
    }
}

@MainActor
public final class CategoryStore: ObservableObject {
    public static let uncategorizedID = "__uncategorized"
    public static let uncategorizedName = "未分类"
    public static let uncategorizedColorHex = "#9CA3AF"

    public static let defaultCategories: [UsageCategory] = [
        UsageCategory(id: "study", name: "学习", colorHex: "#3B82F6"),
        UsageCategory(id: "work", name: "工作", colorHex: "#D97706"),
        UsageCategory(id: "entertainment", name: "娱乐", colorHex: "#EC4899"),
    ]

    @Published public private(set) var categories: [UsageCategory]
    @Published public private(set) var rules: [CategoryRule]

    public static let shared = CategoryStore()

    private let defaults: UserDefaults?
    private static let storageKey = "usageCategories.v1"

    private struct Configuration: Codable {
        var categories: [UsageCategory]
        var rules: [CategoryRule]
    }

    public init(defaults: UserDefaults? = .standard, load: Bool = true) {
        self.defaults = defaults
        self.categories = Self.defaultCategories
        self.rules = []

        if load, let data = defaults?.data(forKey: Self.storageKey),
           !data.isEmpty,
           let config = try? JSONDecoder().decode(
               Configuration.self,
               from: data
           ) {
            self.categories = config.categories
            self.rules = config.rules
        }
    }

    public func category(id: String) -> UsageCategory? {
        categories.first { $0.id == id }
    }

    @discardableResult
    public func addCategory(
        name: String,
        colorHex: String
    ) throws -> UsageCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CategoryStoreError.invalidName
        }
        let category = UsageCategory(
            name: trimmed,
            colorHex: normalizedColorHex(colorHex)
        )
        categories.append(category)
        save()
        return category
    }

    public func renameCategory(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = categories.firstIndex(where: { $0.id == id }) else {
            return
        }
        categories[index].name = trimmed
        save()
    }

    public func setColor(id: String, colorHex: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else {
            return
        }
        categories[index].colorHex = normalizedColorHex(colorHex)
        save()
    }

    public func removeCategory(id: String) {
        categories.removeAll { $0.id == id }
        rules.removeAll { $0.categoryID == id }
        save()
    }

    public func addAppRule(
        bundleID: String,
        appName: String,
        categoryID: String
    ) throws {
        let trimmedID = bundleID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedID.isEmpty else {
            throw CategoryStoreError.emptyApp
        }
        guard category(id: categoryID) != nil else {
            throw CategoryStoreError.missingCategory
        }
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        replaceRule(
            CategoryRule(
                kind: .app,
                identifier: trimmedID,
                displayName: name.isEmpty ? trimmedID : name,
                categoryID: categoryID
            )
        )
    }

    public func addDomainRule(
        domainInput: String,
        categoryID: String
    ) throws {
        guard let domain = DomainName.normalize(domainInput) else {
            throw CategoryStoreError.invalidDomain
        }
        guard category(id: categoryID) != nil else {
            throw CategoryStoreError.missingCategory
        }
        replaceRule(
            CategoryRule(
                kind: .domain,
                identifier: domain,
                displayName: domain,
                categoryID: categoryID
            )
        )
    }

    public func removeRule(id: String) {
        rules.removeAll { $0.id == id }
        save()
    }

    public func removeRule(
        kind: CategoryRuleKind,
        identifier: String
    ) {
        rules.removeAll {
            $0.kind == kind && $0.identifier == identifier
        }
        save()
    }

    public func category(forBundleID bundleID: String) -> UsageCategory? {
        guard let rule = rules.first(where: {
            $0.kind == .app && $0.identifier == bundleID
        }) else {
            return nil
        }
        return category(id: rule.categoryID)
    }

    public func category(forDomain domain: String) -> UsageCategory? {
        let normalized = DomainName.normalize(domain) ?? domain
        guard let rule = rules.first(where: {
            $0.kind == .domain && $0.identifier == normalized
        }) else {
            return nil
        }
        return category(id: rule.categoryID)
    }

    public func resolve(
        bundleID: String?,
        domain: String?
    ) -> UsageCategory? {
        if let bundleID,
           let appCategory = category(forBundleID: bundleID) {
            return appCategory
        }
        if let domain,
           let domainCategory = category(forDomain: domain) {
            return domainCategory
        }
        return nil
    }

    private func replaceRule(_ rule: CategoryRule) {
        rules.removeAll {
            $0.kind == rule.kind && $0.identifier == rule.identifier
        }
        rules.append(rule)
        save()
    }

    private func normalizedColorHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#3B82F6" : trimmed
    }

    private func save() {
        guard let defaults else { return }
        let config = Configuration(categories: categories, rules: rules)
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension Color {
    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              let number = UInt64(value, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    public var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(
            format: "#%02X%02X%02X",
            min(255, max(0, red)),
            min(255, max(0, green)),
            min(255, max(0, blue))
        )
    }
}
