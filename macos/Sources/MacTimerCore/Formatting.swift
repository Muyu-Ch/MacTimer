import Foundation

public enum DateText {
    public static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    public static let mondayFirstWeekdays = ["一", "二", "三", "四", "五", "六", "日"]

    public static func dayLabel(
        _ key: String,
        now: Date = Date(),
        startHour: Int = 0
    ) -> String {
        guard let parts = CalendarDay.components(key),
              let weekday = CalendarDay.weekday(key) else {
            return key
        }

        let currentYear = CalendarDay.components(
            CalendarDay.today(now, startHour: startHour)
        )?.year
        let year = parts.year == currentYear ? "" : "\(parts.year)年"
        return "\(year)\(parts.month)月\(parts.day)日 · 周\(weekdays[weekday])"
    }

    public static func relativeTag(
        _ key: String,
        now: Date = Date(),
        startHour: Int = 0
    ) -> String? {
        let today = CalendarDay.today(now, startHour: startHour)
        if key == today { return "今天" }
        if key == CalendarDay.shifting(today, by: -1) { return "昨天" }
        return nil
    }

    public static func rangeLabel(_ keys: [String]) -> String {
        guard let first = keys.first, let last = keys.last,
              let firstParts = CalendarDay.components(first),
              let lastParts = CalendarDay.components(last) else {
            return ""
        }

        let crossesYear = firstParts.year != lastParts.year
        let left = crossesYear
            ? "\(firstParts.year)/\(firstParts.month)/\(firstParts.day)"
            : "\(firstParts.month)/\(firstParts.day)"
        let right = crossesYear
            ? "\(lastParts.year)/\(lastParts.month)/\(lastParts.day)"
            : "\(lastParts.month)/\(lastParts.day)"
        return "\(left) – \(right)"
    }

    public static func syncLabel(_ timestamp: Int64, now: Date = Date()) -> String {
        guard timestamp > 0 else { return "尚未同步" }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let day = CalendarDay.key(for: date)
        let today = CalendarDay.today(now)

        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        let time = String(
            format: "%02d:%02d",
            timeComponents.hour ?? 0,
            timeComponents.minute ?? 0
        )

        if day == today { return "今天 \(time)" }
        if day == CalendarDay.shifting(today, by: -1) { return "昨天 \(time)" }

        guard let parts = CalendarDay.components(day) else { return time }
        return "\(parts.month)月\(parts.day)日 \(time)"
    }

    public static func chartDate(_ date: Date) -> String {
        guard let parts = CalendarDay.components(CalendarDay.key(for: date)) else {
            return ""
        }
        return "\(parts.month)/\(parts.day)"
    }

    public static func weekRangeLabel(
        _ keys: [String],
        now: Date = Date(),
        startHour: Int = 0
    ) -> String {
        guard let firstKey = keys.first,
              let lastKey = keys.last,
              let first = CalendarDay.components(firstKey),
              let last = CalendarDay.components(lastKey) else {
            return ""
        }

        let currentYear = CalendarDay.components(
            CalendarDay.today(now, startHour: startHour)
        )?.year
        if first.year == last.year {
            let prefix = first.year == currentYear ? "" : "\(first.year)年"
            return "\(prefix)\(first.month)月\(first.day)日 – \(last.month)月\(last.day)日"
        }
        return "\(first.year)年\(first.month)月\(first.day)日 – "
            + "\(last.year)年\(last.month)月\(last.day)日"
    }

    public static func monthLabel(_ key: String) -> String {
        guard let parts = CalendarDay.components(key) else { return key }
        return "\(parts.year)年\(parts.month)月"
    }

    public static func yearLabel(_ key: String) -> String {
        guard let parts = CalendarDay.components(key) else { return key }
        return "\(parts.year)年"
    }

    public static func monthShortLabel(_ key: String) -> String {
        guard let parts = CalendarDay.components(key) else { return key }
        return "\(parts.month)月"
    }

    public static func shortDateLabel(_ key: String) -> String {
        guard let parts = CalendarDay.components(key) else { return key }
        return "\(parts.month)月\(parts.day)日"
    }

    public static func monthDayNumeric(_ key: String) -> String {
        guard let parts = CalendarDay.components(key) else { return key }
        return "\(parts.month)/\(parts.day)"
    }

    public static func dayNumber(_ key: String) -> Int? {
        CalendarDay.components(key)?.day
    }
}

public enum DurationText {
    public static func string(milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1000)
        if seconds < 60 { return "\(seconds) 秒" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    /// Compact duration for calendar cells and chart labels: "2h14", "48m".
    public static func compact(milliseconds: Int64) -> String {
        let seconds = max(0, milliseconds / 1000)
        if seconds == 0 { return "0" }
        if seconds < 60 { return "<1m" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        let rest = minutes % 60
        if hours >= 10 {
            return "\(hours)h"
        }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h" + String(format: "%02d", rest)
    }

    public static func axisLabel(hours: Double) -> String {
        guard hours > 0 else { return "0" }

        let seconds = hours * 3600
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }

        let minutes = hours * 60
        if minutes < 10 {
            let rounded = (minutes * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))m"
            }
            return String(format: "%.1fm", rounded)
        }

        if hours < 1 {
            return "\(Int(minutes.rounded()))m"
        }

        let rounded = (hours * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))h"
        }
        return String(format: "%.1fh", rounded)
    }
}
