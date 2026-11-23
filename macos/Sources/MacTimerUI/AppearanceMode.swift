import AppKit
import SwiftUI

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "appearanceMode"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "明亮"
        case .dark: "黑暗"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Apply the appearance to the whole app so the window titlebars and
    /// SwiftUI content change together. `nil` makes AppKit follow the system.
    @MainActor
    public static func apply(_ mode: AppearanceMode) {
        let application = NSApplication.shared
        let appearance = mode.appKitAppearance
        application.appearance = appearance
        for window in application.windows {
            window.appearance = appearance
        }
    }

    @MainActor
    public static func applyStored() {
        let raw = UserDefaults.standard.string(
            forKey: storageKey
        ) ?? AppearanceMode.system.rawValue
        apply(AppearanceMode(rawValue: raw) ?? .system)
    }

    private var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
