import AppKit
import Charts
import SwiftUI
import MacTimerCore

public struct DashboardView: View {
    @ObservedObject private var model: DashboardModel
    private let autoStart: Bool
    private let previewMode: Bool
    @Environment(\.colorScheme) private var scheme

    public init(
        model: DashboardModel,
        autoStart: Bool = true,
        previewMode: Bool = false
    ) {
        self.model = model
        self.autoStart = autoStart
        self.previewMode = previewMode
    }

    @ViewBuilder
    private var visualCard: some View {
        switch model.viewMode {
        case .day:
            DayUsageChartCard(model: model)
        case .week:
            WeekOverviewCard(model: model)
        case .month:
            MonthCalendarCard(model: model)
        case .year:
            YearOverviewCard(model: model)
        }
    }

    private var dashboardContent: some View {
        let isDay = model.viewMode == .day
        let siteEntries = isDay ? model.entries : model.periodEntries
        let emptyTitle = isDay
            ? (model.isTodaySelected ? "今天还没有使用记录" : "这一天没有记录")
            : "本期没有记录"
        let emptyMessage = isDay
            ? "继续使用网站或 App，数据会在下一次刷新后出现；也可以切换到其他日期查看。"
            : "继续使用网站或 App，数据会在下一次刷新后出现；也可以切换到其他时间范围查看。"

        return VStack(alignment: .leading, spacing: 18) {
            if let error = model.loadError {
                ErrorBanner(message: error) {
                    model.reload(force: true)
                }
            }
            ScreenTimeAccessBanner(model: model)
            SummaryCard(model: model)
            HStack(alignment: .top, spacing: 18) {
                visualCard
                    .frame(maxWidth: .infinity, alignment: .top)
                SiteUsageCard(
                    model: model,
                    entries: siteEntries,
                    maxRows: isDay ? nil : 8,
                    emptyTitle: emptyTitle,
                    emptyMessage: emptyMessage
                )
                .frame(width: 400)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            Rectangle()
                .fill(Theme.hairline(scheme))
                .frame(height: 1)

            if model.snapshot == nil {
                VStack(spacing: 0) {
                    if let error = model.loadError {
                        ErrorBanner(message: error) {
                            model.reload(force: true)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                    }
                    ScreenTimeAccessBanner(model: model)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                    OnboardingView(model: model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if previewMode {
                dashboardContent
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else {
                ScrollView {
                    dashboardContent
                }
            }
        }
        .background(Theme.page(scheme).ignoresSafeArea())
        .tint(Theme.accent(scheme))
        .onAppear {
            if autoStart { model.start() }
        }
        .onDisappear {
            model.stop()
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            ModePicker(model: model)

            Rectangle()
                .fill(Theme.hairline(scheme))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 4)

            HeaderIconButton(
                systemName: "chevron.left",
                help: model.viewMode.previousHelp,
                disabled: !model.canShiftBack
            ) {
                model.shiftPeriod(by: -1)
            }

            HStack(spacing: 9) {
                Text(model.periodLabel)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let tag = model.periodTag {
                    Text(tag)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accentInk(scheme))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Theme.accentWash(scheme), in: Capsule())
                }
            }

            HeaderIconButton(
                systemName: "chevron.right",
                help: model.viewMode.nextHelp,
                disabled: !model.canShiftForward
            ) {
                model.shiftPeriod(by: 1)
            }

            if !model.isCurrentPeriod {
                Button(model.viewMode.jumpLabel) {
                    model.goToCurrentPeriod()
                }
                .buttonStyle(
                    CompactActionButtonStyle(
                        scheme: scheme,
                        emphasized: false,
                        large: true
                    )
                )
                .padding(.leading, 3)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Circle()
                    .fill(model.hasData ? Theme.accent(scheme) : Theme.hairline(scheme))
                    .frame(width: 6, height: 6)
                Text(model.syncText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.card(scheme), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Theme.border(scheme), lineWidth: 1)
            )

            HeaderIconButton(
                systemName: "arrow.clockwise",
                help: "重新读取本地数据"
            ) {
                model.reload(force: true)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15)
        .background(Theme.page(scheme))
    }
}

private struct ModePicker: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatsRange.allCases) { mode in
                Button {
                    model.setViewMode(mode)
                } label: {
                    Text(mode.shortLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            model.viewMode == mode
                                ? Color.primary
                                : Color.secondary
                        )
                        .frame(minWidth: 36)
                        .padding(.vertical, 6.5)
                        .padding(.horizontal, 5)
                        .background(
                            model.viewMode == mode
                                ? Theme.card(scheme)
                                : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: 8,
                                style: .continuous
                            )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.accessibilityLabel)
                .accessibilityAddTraits(
                    model.viewMode == mode ? [.isSelected] : []
                )
                .help(mode.accessibilityLabel)
            }
        }
        .padding(4)
        .background(
            Theme.surface2(scheme),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    var disabled = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(
                    hovering ? Theme.hover(scheme) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.28 : 0.82)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct SummaryCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isPeriod = model.viewMode != .day
        let total = isPeriod
            ? model.periodTotalMilliseconds
            : model.totalMilliseconds
        let subtitle = isPeriod
            ? "\(model.periodActiveDays) 个活跃日 · \(model.periodSiteCount) 项"
            : (model.siteCount == 0
                ? "暂无记录"
                : "共 \(model.siteCount) 项")

        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.usesScreenTimeData ? "屏幕使用" : "网页停留")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                Text(DurationText.string(milliseconds: total))
                    .font(.system(size: 38, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Divider()
                .frame(height: 62)
                .overlay(Theme.hairline(scheme))

            if isPeriod {
                StatBlock(
                    title: "活跃日均",
                    value: DurationText.string(
                        milliseconds: model.periodAverageMilliseconds
                    ),
                    detail: "\(model.periodActiveDays) 个活跃日",
                    alignment: .leading
                )
                .frame(minWidth: 150, alignment: .leading)

                Divider()
                    .frame(height: 62)
                    .overlay(Theme.hairline(scheme))

                StatBlock(
                    title: "单日最高",
                    value: model.periodBestDay.map {
                        DurationText.string(milliseconds: $0.milliseconds)
                    } ?? "—",
                    detail: model.periodBestDay.map {
                        DateText.shortDateLabel($0.day)
                    } ?? "",
                    alignment: .leading
                )
                .frame(minWidth: 130, alignment: .leading)
            } else {
                StatBlock(
                    title: "最常用",
                    value: model.topEntry.map {
                        model.display(for: $0.site).name
                    } ?? "—",
                    detail: model.topEntry.map {
                        DurationText.string(milliseconds: $0.milliseconds)
                    } ?? "",
                    alignment: .leading
                )
                .frame(minWidth: 150, alignment: .leading)

                Divider()
                    .frame(height: 62)
                    .overlay(Theme.hairline(scheme))

                StatBlock(
                    title: "前一天",
                    value: DurationText.string(
                        milliseconds: model.previousDayTotal
                    ),
                    detail: model.previousDayLabel,
                    alignment: .leading
                )
                .frame(minWidth: 130, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .stayCard(scheme)
    }
}

private struct StatBlock: View {
    let title: String
    let value: String
    let detail: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 14.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct DayUsageChartCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    private var showsHourly: Bool {
        model.dayChartMode == .hourly && model.dayHasHourlyData
    }

    private var hasContent: Bool {
        if model.dayChartMode == .hourly {
            return model.dayHasHourlyData || !model.entries.isEmpty
        }
        return !model.entries.isEmpty
    }

    private var subtitle: String {
        if model.dayChartMode == .hourly {
            if model.dayHasHourlyData {
                return "按小时 · 来自屏幕使用时间"
            }
            if !model.entries.isEmpty {
                return "无分时数据，显示网站/App"
            }
            return "暂无记录"
        }
        return "网页 + App"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当日使用")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                DayChartModePicker(model: model)
            }

            if !hasContent {
                VStack(spacing: 9) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accentInk(scheme))
                    Text("这一天没有记录")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else if showsHourly {
                hourlyChart
                footer
            } else {
                itemsChart
                footer
            }
        }
        .padding(20)
        .stayCard(scheme)
    }

    private var hourlyChart: some View {
        let bars = model.dayHourlyBars
        let maxHours = bars.map(\.hours).max() ?? 0
        let upper = max(1.0 / 60.0, maxHours * 1.12)

        return Chart(bars) { bar in
            BarMark(
                x: .value("小时", bar.hour),
                y: .value("小时", bar.hours)
            )
            .foregroundStyle(Theme.accent(scheme))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: -1...24)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                value in
                AxisGridLine()
                    .foregroundStyle(Theme.gridline(scheme))
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(DurationText.axisLabel(hours: hours))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 4, 8, 12, 16, 20]) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.gridline(scheme).opacity(0.65))
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(height: 210)
    }

    private var itemsChart: some View {
        let rows = model.dayChartItems
        let maxHours = rows.map(\.hours).max() ?? 0
        let upper = max(1.0 / 60.0, maxHours * 1.12)

        return Chart(rows) { row in
            BarMark(
                x: .value("项目", row.name),
                y: .value("小时", row.hours)
            )
            .foregroundStyle(Theme.accent(scheme))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...upper)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                value in
                AxisGridLine()
                    .foregroundStyle(Theme.gridline(scheme))
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(DurationText.axisLabel(hours: hours))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: rows.map(\.name)) { value in
                AxisTick()
                    .foregroundStyle(Theme.hairline(scheme))
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(shortItemLabel(name))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
            }
        }
        .frame(height: 210)
    }

    @ViewBuilder
    private var footer: some View {
        Divider()
            .overlay(Theme.hairline(scheme))

        if showsHourly {
            HStack(alignment: .top, spacing: 0) {
                StatBlock(
                    title: "峰值时段",
                    value: model.dayHourlyPeak.map {
                        peakLabel(for: $0.hour)
                    } ?? "—",
                    detail: model.dayHourlyPeak.map {
                        DurationText.string(milliseconds: $0.milliseconds)
                    } ?? ""
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 36)
                    .overlay(Theme.hairline(scheme))

                StatBlock(
                    title: "分时总计",
                    value: DurationText.string(
                        milliseconds: model.dayHourlyTotalMilliseconds
                    ),
                    detail: "来自屏幕使用时间"
                )
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                StatBlock(
                    title: "项数",
                    value: "\(model.entries.count) 项",
                    detail: "网页 + App"
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 36)
                    .overlay(Theme.hairline(scheme))

                StatBlock(
                    title: "最常用",
                    value: model.topEntry.map {
                        model.display(for: $0.site).name
                    } ?? "—",
                    detail: model.topEntry.map {
                        DurationText.string(milliseconds: $0.milliseconds)
                    } ?? ""
                )
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func peakLabel(for hour: Int) -> String {
        String(format: "%02d:00–%02d:00", hour, hour + 1)
    }

    private func shortItemLabel(_ name: String) -> String {
        guard name.count > 11 else { return name }
        return String(name.prefix(10)) + "…"
    }
}

private struct DayChartModePicker: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DayChartMode.allCases) { mode in
                Button {
                    model.setDayChartMode(mode)
                } label: {
                    Text(mode.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(
                            model.dayChartMode == mode
                                ? Color.primary
                                : Color.secondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5.5)
                        .background(
                            model.dayChartMode == mode
                                ? Theme.card(scheme)
                                : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: 6,
                                style: .continuous
                            )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    model.dayChartMode == mode ? [.isSelected] : []
                )
                .help(
                    mode == .hourly
                        ? "按小时查看屏幕使用时间"
                        : "按网站/App 查看当日排行"
                )
            }
        }
        .padding(3)
        .background(
            Theme.surface2(scheme),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
    }
}

private struct SiteUsageCard: View {
    @ObservedObject var model: DashboardModel
    let entries: [SiteEntry]
    let maxRows: Int?
    let emptyTitle: String
    let emptyMessage: String

    @Environment(\.colorScheme) private var scheme

    private struct DisplayRow: Identifiable {
        let id: String
        let site: String
        let milliseconds: Int64
        let isAggregate: Bool
        let count: Int
    }

    private var displayRows: [DisplayRow] {
        let limit = maxRows ?? entries.count
        let shown = Array(entries.prefix(limit))
        var rows = shown.map {
            DisplayRow(
                id: $0.site,
                site: $0.site,
                milliseconds: $0.milliseconds,
                isAggregate: false,
                count: 1
            )
        }

        if entries.count > limit {
            let rest = entries.dropFirst(limit)
            let milliseconds = rest.reduce(Int64(0)) {
                $0 + $1.milliseconds
            }
            rows.append(
                DisplayRow(
                    id: "__other",
                    site: "__other",
                    milliseconds: milliseconds,
                    isAggregate: true,
                    count: rest.count
                )
            )
        }
        return rows
    }

    var body: some View {
        let rows = displayRows
        let maxMilliseconds = max(1, entries.first?.milliseconds ?? 0)

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("网站与 App")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(entries.isEmpty ? "暂无记录" : "共 \(entries.count) 项")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                SettingsLink {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Theme.surface2(scheme),
                            in: RoundedRectangle(
                                cornerRadius: 7,
                                style: .continuous
                            )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("网站与 App 映射设置")
                .accessibilityLabel("网站与 App 映射设置")
            }
            .padding(.bottom, 7)

            if entries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "clock")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accentInk(scheme))
                        .frame(width: 42, height: 42)
                        .background(Theme.accentWash(scheme), in: Circle())

                    Text(emptyTitle)
                        .font(.system(size: 13, weight: .semibold))

                    Text(emptyMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) {
                        index,
                        row in
                        let display = model.display(for: row.site)
                        SiteRowView(
                            displayName: row.isAggregate
                                ? "其他 \(row.count) 项"
                                : display.name,
                            detail: row.isAggregate ? nil : display.detail,
                            bundleID: row.isAggregate
                                ? nil
                                : display.bundleID,
                            milliseconds: row.milliseconds,
                            maxMilliseconds: maxMilliseconds,
                            showBar: !row.isAggregate,
                            isAggregate: row.isAggregate
                        )

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Theme.hairline(scheme).opacity(0.65))
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(20)
        .stayCard(scheme)
    }
}

private struct SiteRowView: View {
    let displayName: String
    let detail: String?
    let bundleID: String?
    let milliseconds: Int64
    let maxMilliseconds: Int64
    var showBar = true
    var isAggregate = false

    @Environment(\.colorScheme) private var scheme

    private var fraction: CGFloat {
        guard maxMilliseconds > 0 else { return 0 }
        return CGFloat(milliseconds) / CGFloat(maxMilliseconds)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            appIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    Text(DurationText.string(milliseconds: milliseconds))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                if showBar {
                    GeometryReader { proxy in
                        RoundedRectangle(
                            cornerRadius: 2.5,
                            style: .continuous
                        )
                        .fill(Theme.accent(scheme))
                        .frame(
                            width: max(
                                3,
                                proxy.size.width * min(1, fraction)
                            ),
                            height: 4.5
                        )
                    }
                    .frame(height: 4.5)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, showBar ? 8 : 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(displayName)\(detail.map { "，\($0)" } ?? "")，"
                + DurationText.string(milliseconds: milliseconds)
        )
    }

    @ViewBuilder
    private var appIcon: some View {
        if !isAggregate,
           let bundleID,
           let image = AppCatalog.shared.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.surface2(scheme))
                if isAggregate {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
        }
    }
}

private struct ScreenTimeAccessBanner: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    var body: some View {
        switch model.screenTimeAccess {
        case .needsPermission:
            card(
                icon: "lock.shield",
                title: "合并 App 使用时间",
                message: "读取 Apple 屏幕使用时间需要「完全磁盘访问权限」。"
                    + "授权后，App 使用时长、日视图分时图和"
                    + " Chrome 未记录时间才会出现。",
                footnote: "系统设置 → 隐私与安全性 → 完全磁盘访问权限，"
                    + "添加 MacTimer.app。未授权时只显示网页数据；授权后如果仍不可用，请退出并重新打开 App。",
                emphasized: true
            )
        case .unavailable(let message):
            card(
                icon: "exclamationmark.triangle",
                title: "暂时无法读取屏幕使用时间",
                message: message,
                footnote: "网页数据仍会正常显示。你可以在「完全磁盘访问权限」中确认 MacTimer 已获授权，然后重新检查。",
                emphasized: false
            )
        default:
            EmptyView()
        }
    }

    private func card(
        icon: String,
        title: String,
        message: String,
        footnote: String,
        emphasized: Bool
    ) -> some View {
        let ink = emphasized
            ? Theme.accentInk(scheme)
            : Theme.warningInk(scheme)
        let wash = emphasized
            ? Theme.accentWash(scheme)
            : Theme.warningWash(scheme)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 38, height: 38)
                .background(wash, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))

                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(footnote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("打开系统设置") {
                        model.openFullDiskAccessSettings()
                    }
                    .buttonStyle(
                        CompactActionButtonStyle(
                            scheme: scheme,
                            emphasized: emphasized
                        )
                    )

                    Button("在 Finder 中显示 App") {
                        model.revealAppInFinder()
                    }
                    .buttonStyle(
                        CompactActionButtonStyle(
                            scheme: scheme,
                            emphasized: false
                        )
                    )

                    Button("重新检查") {
                        model.retryScreenTime()
                    }
                    .buttonStyle(
                        CompactActionButtonStyle(
                            scheme: scheme,
                            emphasized: !emphasized
                        )
                    )
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .stayCard(scheme)
    }
}

struct CompactActionButtonStyle: ButtonStyle {
    let scheme: ColorScheme
    var emphasized: Bool
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 11, weight: .semibold))
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .padding(.horizontal, large ? 15 : 11)
            .padding(.vertical, large ? 8 : 5.5)
            .background(
                emphasized
                    ? Theme.accent(scheme)
                        .opacity(configuration.isPressed ? 0.82 : 1)
                    : Theme.surface2(scheme),
                in: RoundedRectangle(
                    cornerRadius: large ? 9 : 7,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: large ? 9 : 7,
                    style: .continuous
                )
                .strokeBorder(
                    emphasized ? Color.clear : Theme.border(scheme),
                    lineWidth: 1
                )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 30)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(Theme.accentInk(scheme))
                .frame(width: 62, height: 62)
                .background(Theme.accentWash(scheme), in: Circle())

            VStack(spacing: 6) {
                Text("还没有收到使用数据")
                    .font(.system(size: 21, weight: .semibold))
                Text("网页数据来自 Chrome 扩展，App 数据来自 Apple 屏幕使用时间。数据只在本机。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 13) {
                StepRow(number: "1", text: "在 Chrome 中加载并启用「MacTimer」扩展。")
                StepRow(number: "2", text: "打开扩展弹窗，点击底部的「同步到 Mac」。")
                StepRow(number: "3", text: "如要合并 App 时间，在系统设置中给 MacTimer 授予完全磁盘访问权限。")
            }
            .padding(18)
            .frame(maxWidth: 430, alignment: .leading)
            .stayCard(scheme)

            HStack(spacing: 10) {
                Button("重新读取") {
                    model.reload(force: true)
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: true)
                )

                Button("打开数据文件夹") {
                    model.revealDataFolder()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )
            }

            Text("网页同步只写入本机文件；App 数据只从本机数据库读取，均不经过网络。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

private struct StepRow: View {
    let number: String
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text(number)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentInk(scheme))
                .frame(width: 19, height: 19)
                .background(Theme.accentWash(scheme), in: Circle())

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warningInk(scheme))

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.warningInk(scheme))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("重试", action: retry)
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.warningWash(scheme))
        )
    }
}
