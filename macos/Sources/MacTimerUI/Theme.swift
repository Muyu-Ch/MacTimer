import SwiftUI

public enum Theme {
    public static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 57 / 255, green: 135 / 255, blue: 229 / 255)
            : Color(red: 42 / 255, green: 120 / 255, blue: 214 / 255)
    }

    public static func accentInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 134 / 255, green: 182 / 255, blue: 239 / 255)
            : Color(red: 28 / 255, green: 92 / 255, blue: 171 / 255)
    }

    public static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255)
            : Color(red: 249 / 255, green: 249 / 255, blue: 247 / 255)
    }

    public static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 26 / 255, green: 26 / 255, blue: 25 / 255)
            : Color(red: 252 / 255, green: 252 / 255, blue: 251 / 255)
    }

    public static func surface2(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 38 / 255, green: 38 / 255, blue: 37 / 255)
            : Color(red: 240 / 255, green: 239 / 255, blue: 236 / 255)
    }

    public static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 44 / 255, green: 44 / 255, blue: 42 / 255)
            : Color(red: 225 / 255, green: 224 / 255, blue: 217 / 255)
    }

    public static func gridline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
    }

    public static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    public static func hover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    public static func accentWash(_ scheme: ColorScheme) -> Color {
        accent(scheme).opacity(scheme == .dark ? 0.16 : 0.10)
    }

    public static func warningWash(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 208 / 255, green: 59 / 255, blue: 59 / 255).opacity(0.16)
            : Color(red: 208 / 255, green: 59 / 255, blue: 59 / 255).opacity(0.08)
    }

    public static func warningInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 255 / 255, green: 155 / 255, blue: 155 / 255)
            : Color(red: 156 / 255, green: 37 / 255, blue: 37 / 255)
    }

    /// Four-step sequential wash for the month calendar heatmap.
    public static func heatWash(_ level: Int, _ scheme: ColorScheme) -> Color {
        guard level > 0 else { return .clear }
        let light = [0.0, 0.06, 0.12, 0.19, 0.27]
        let dark = [0.0, 0.12, 0.20, 0.30, 0.42]
        let values = scheme == .dark ? dark : light
        let index = min(max(level, 0), values.count - 1)
        return accent(scheme).opacity(values[index])
    }
}

struct StayCard: ViewModifier {
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border(scheme), lineWidth: 1)
            )
    }
}

extension View {
    func stayCard(_ scheme: ColorScheme) -> some View {
        modifier(StayCard(scheme: scheme))
    }
}
