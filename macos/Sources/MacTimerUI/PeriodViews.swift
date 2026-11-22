import SwiftUI
import MacTimerCore

struct WeekOverviewCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    private var days: [HistoryBar] { model.selectedWeekDays }

    private var maxMilliseconds: Int64 {
        max(1, days.map(\.milliseconds).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("每日使用")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("点击某天查看当天明细")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    weekColumn(day)
                }
            }
        }
        .padding(20)
        .stayCard(scheme)
    }

    private func weekColumn(_ day: HistoryBar) -> some View {
        let isSelected = day.day == model.selectedDay
        let isFuture = day.day > CalendarDay.today()
        let isToday = day.day == CalendarDay.today()
        let weekdayIndex = CalendarDay.mondayIndex(for: day.day) ?? 0
        let fraction = Double(day.milliseconds) / Double(maxMilliseconds)
        let barHeight = max(day.milliseconds > 0 ? 3 : 0, 92 * fraction)

        return Button {
            model.openDay(day.day)
        } label: {
            VStack(spacing: 5) {
                Text(
                    day.milliseconds > 0
                        ? DurationText.compact(
                            milliseconds: day.milliseconds
                        )
                        : "—"
                )
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(
                    isSelected ? Color.primary : Color.secondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accent(scheme))
                        .frame(width: 18, height: barHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 92)

                Text(DateText.mondayFirstWeekdays[weekdayIndex])
                    .font(
                        .system(
                            size: 9.5,
                            weight: isToday ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(
                        isToday
                            ? Theme.accentInk(scheme)
                            : Color.secondary
                    )

                Text(DateText.monthDayNumeric(day.day))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Theme.surface2(scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .opacity(isFuture ? 0.35 : 1)
        .help(
            isFuture
                ? "未来日期"
                : "查看 \(DateText.shortDateLabel(day.day))"
        )
        .accessibilityLabel(
            "\(DateText.shortDateLabel(day.day))，\(day.milliseconds > 0 ? DurationText.string(milliseconds: day.milliseconds) : "无记录")"
        )
    }
}

struct MonthCalendarCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    private var grid: [HistoryBar] { model.selectedMonthGrid }
    private var prefix: String { model.selectedMonthPrefix }
    private var today: String { CalendarDay.today() }
    private var maxMilliseconds: Int64 {
        max(1, model.selectedMonthMaxMilliseconds)
    }

    private var monthIsEmpty: Bool {
        grid
            .filter { $0.day.hasPrefix(prefix) && $0.day <= today }
            .allSatisfy { $0.milliseconds == 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("日历")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                HeatLegend(scheme: scheme)
            }

            HStack(spacing: 4) {
                ForEach(DateText.mondayFirstWeekdays, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(grid) { day in
                    monthDayButton(day)
                }
            }

            HStack(spacing: 8) {
                Text("点击日期查看当天明细")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if monthIsEmpty {
                    Text("本月还没有记录")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .stayCard(scheme)
    }

    private func monthDayButton(_ day: HistoryBar) -> some View {
        let inMonth = day.day.hasPrefix(prefix)
        let isFuture = day.day > today
        let isSelected = day.day == model.selectedDay
        let isToday = day.day == today
        let level = heatLevel(day, inMonth: inMonth, isFuture: isFuture)
        let enabled = inMonth && !isFuture

        return Button {
            model.openDay(day.day)
        } label: {
            dayCell(
                day,
                inMonth: inMonth,
                isFuture: isFuture,
                isSelected: isSelected,
                isToday: isToday,
                level: level
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(inMonth ? (isFuture ? 0.42 : 1) : 0.28)
        .help(
            enabled
                ? "查看 \(DateText.shortDateLabel(day.day))"
                : (isFuture ? "未来日期" : "相邻月份")
        )
        .accessibilityLabel(
            "\(DateText.shortDateLabel(day.day))，\(day.milliseconds > 0 ? DurationText.string(milliseconds: day.milliseconds) : "无记录")"
        )
    }

    private func dayCell(
        _ day: HistoryBar,
        inMonth: Bool,
        isFuture: Bool,
        isSelected: Bool,
        isToday: Bool,
        level: Int
    ) -> some View {
        let dayNumber = DateText.dayNumber(day.day) ?? 0
        let showTotal = inMonth && !isFuture

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text("\(dayNumber)")
                    .font(
                        .system(
                            size: 10.5,
                            weight: isSelected ? .bold : (isToday ? .semibold : .regular)
                        )
                    )
                    .foregroundStyle(
                        inMonth && !isFuture ? Color.primary : Color.secondary
                    )

                if isToday {
                    Circle()
                        .fill(Theme.accent(scheme))
                        .frame(width: 3.5, height: 3.5)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            if showTotal {
                Text(
                    day.milliseconds > 0
                        ? DurationText.compact(
                            milliseconds: day.milliseconds
                        )
                        : "—"
                )
                .font(.system(size: 9))
                .foregroundStyle(
                    day.milliseconds > 0
                        ? Color.secondary
                        : Color.secondary.opacity(0.55)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 46)
        .background(
            Theme.heatWash(level, scheme),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Theme.accent(scheme)
                        : Theme.border(scheme).opacity(inMonth ? 0.9 : 0.35),
                    lineWidth: isSelected ? 1.6 : 1
                )
        )
        .contentShape(Rectangle())
    }

    private func heatLevel(
        _ day: HistoryBar,
        inMonth: Bool,
        isFuture: Bool
    ) -> Int {
        guard inMonth, !isFuture, day.milliseconds > 0 else { return 0 }
        let fraction = Double(day.milliseconds) / Double(maxMilliseconds)
        return min(4, max(1, Int(ceil(fraction * 4))))
    }
}

struct YearOverviewCard: View {
    @ObservedObject var model: DashboardModel
    @Environment(\.colorScheme) private var scheme

    private var months: [YearMonthSummary] {
        model.selectedYearMonths
    }

    private var maxMilliseconds: Int64 {
        max(1, months.map(\.milliseconds).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("每月使用")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("点击月份查看月视图")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(months) { month in
                    yearColumn(month)
                }
            }
        }
        .padding(20)
        .stayCard(scheme)
    }

    private func yearColumn(_ month: YearMonthSummary) -> some View {
        let isSelected = month.key.hasPrefix(model.selectedMonthPrefix)
        let fraction = Double(month.milliseconds) / Double(maxMilliseconds)
        let barHeight = max(month.milliseconds > 0 ? 3 : 0, 100 * fraction)

        return Button {
            model.openMonth(month.key)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accent(scheme))
                        .frame(width: 16, height: barHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)

                Text(DateText.monthShortLabel(month.key))
                    .font(
                        .system(
                            size: 9.5,
                            weight: isSelected ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(
                        month.isFuture ? Color.secondary : Color.primary.opacity(0.82)
                    )

                Text(
                    month.milliseconds > 0
                        ? DurationText.compact(
                            milliseconds: month.milliseconds
                        )
                        : "—"
                )
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? Theme.surface2(scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(month.isFuture)
        .opacity(month.isFuture ? 0.38 : 1)
        .help(
            month.isFuture
                ? "未来月份"
                : "查看 \(DateText.monthLabel(month.key))"
        )
        .accessibilityLabel(
            "\(DateText.monthLabel(month.key))，\(month.milliseconds > 0 ? DurationText.string(milliseconds: month.milliseconds) : "无记录")"
        )
    }
}

private struct HeatLegend: View {
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 3) {
            Text("少")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            ForEach(1...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.heatWash(level, scheme))
                    .frame(width: 9, height: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                Theme.border(scheme),
                                lineWidth: 0.5
                            )
                    )
            }

            Text("多")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel("颜色越深表示停留时间越长")
    }
}
