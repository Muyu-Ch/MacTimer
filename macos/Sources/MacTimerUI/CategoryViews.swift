import SwiftUI
import MacTimerCore

enum CategoryVisuals {
    static func color(_ hex: String, scheme: ColorScheme) -> Color {
        Color(hex: hex) ?? Theme.accent(scheme)
    }

    static func percent(_ milliseconds: Int64, total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let value = Double(milliseconds) / Double(total) * 100
        if value > 0, value < 1 {
            return "<1%"
        }
        return String(format: "%.0f%%", value)
    }
}

/// A compact, wrapping legend used under the day, week, month and year
/// charts. The colored dot carries identity; all text stays in normal ink.
struct CategoryLegend: View {
    let usages: [CategoryUsage]
    var showPercent = true
    var minimumColumnWidth: CGFloat = 150
    @Environment(\.colorScheme) private var scheme

    private var total: Int64 {
        usages.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    var body: some View {
        let sum = total
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumColumnWidth),
                    spacing: 12
                ),
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(usages) { usage in
                HStack(spacing: 6) {
                    Circle()
                        .fill(CategoryVisuals.color(usage.colorHex, scheme: scheme))
                        .frame(width: 7, height: 7)

                    Text(usage.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(
                        DurationText.string(milliseconds: usage.milliseconds)
                    )
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)

                    if showPercent {
                        Text(
                            CategoryVisuals.percent(
                                usage.milliseconds,
                                total: sum
                            )
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Vertical stacked bar used by the week and year charts.
struct CategoryStackedBar: View {
    let usages: [CategoryUsage]
    var width: CGFloat = 18
    var height: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var total: Int64 {
        usages.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    var body: some View {
        let sum = total
        GeometryReader { geometry in
            let gap = CGFloat(max(0, usages.count - 1)) * 2
            let available = max(0, geometry.size.height - gap)

            VStack(spacing: 2) {
                ForEach(Array(usages.reversed())) { usage in
                    Rectangle()
                        .fill(
                            CategoryVisuals.color(
                                usage.colorHex,
                                scheme: scheme
                            )
                        )
                        .frame(
                            height: sum > 0
                                ? available * CGFloat(usage.milliseconds)
                                    / CGFloat(sum)
                                : 0
                        )
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .bottom
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Horizontal stacked bar used inside the month card, where each day is a
/// heat cell rather than a column.
struct CategoryCompositionBar: View {
    let usages: [CategoryUsage]
    var height: CGFloat = 9
    @Environment(\.colorScheme) private var scheme

    private var total: Int64 {
        usages.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    var body: some View {
        let sum = total
        GeometryReader { geometry in
            let gap = CGFloat(max(0, usages.count - 1)) * 2
            let available = max(0, geometry.size.width - gap)

            HStack(spacing: 2) {
                ForEach(usages) { usage in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            CategoryVisuals.color(
                                usage.colorHex,
                                scheme: scheme
                            )
                        )
                        .frame(
                            width: sum > 0
                                ? available * CGFloat(usage.milliseconds)
                                    / CGFloat(sum)
                                : 0
                        )
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .leading
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
