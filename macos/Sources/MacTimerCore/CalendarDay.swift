import Foundation

/// Local-calendar day keys shared with the Chrome extension (`YYYY-MM-DD`).
public enum CalendarDay {
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else {
            return nil
        }

        guard let date = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return nil
        }

        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else {
            return nil
        }
        return date
    }

    public static func components(
        _ key: String,
        calendar: Calendar = .current
    ) -> (year: Int, month: Int, day: Int)? {
        guard let date = date(from: key, calendar: calendar) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return (year, month, day)
    }

    /// The logical day containing `now`. With `startHour = 4`, the period
    /// 00:00–04:00 still belongs to the previous day.
    public static func today(
        _ now: Date = Date(),
        startHour: Int = 0,
        calendar: Calendar = .current
    ) -> String {
        let hour = DayStartSetting.clamp(startHour)
        guard hour > 0 else {
            return key(for: now, calendar: calendar)
        }
        let shifted = calendar.date(
            byAdding: .hour,
            value: -hour,
            to: now
        ) ?? now
        return key(for: shifted, calendar: calendar)
    }

    public static func shifting(
        _ key: String,
        by days: Int,
        calendar: Calendar = .current
    ) -> String? {
        guard let date = date(from: key, calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            return nil
        }
        return self.key(for: shifted, calendar: calendar)
    }

    /// Ascending (oldest first) list of day keys ending on the given day.
    public static func lastDays(
        _ count: Int,
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        guard count > 0 else { return [] }
        let end = calendar.startOfDay(for: endDate)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end)
                .map { key(for: $0, calendar: calendar) }
        }
    }

    /// 0 = Sunday, 1 = Monday, ... 6 = Saturday.
    public static func weekday(_ key: String, calendar: Calendar = .current) -> Int? {
        guard let date = date(from: key, calendar: calendar) else { return nil }
        return calendar.component(.weekday, from: date) - 1
    }

    /// 0 = Monday, 1 = Tuesday, ... 6 = Sunday.
    public static func mondayIndex(
        for key: String,
        calendar: Calendar = .current
    ) -> Int? {
        guard let weekday = weekday(key, calendar: calendar) else { return nil }
        return (weekday + 6) % 7
    }

    public static func periodCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static func weekStartKey(
        containing key: String,
        calendar base: Calendar = .current
    ) -> String? {
        let calendar = periodCalendar(base)
        guard let date = date(from: key, calendar: calendar) else { return nil }
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(
            byAdding: .day,
            value: -offset,
            to: startOfDay
        ) else {
            return nil
        }
        return self.key(for: start, calendar: calendar)
    }

    public static func weekDayKeys(
        containing key: String,
        calendar: Calendar = .current
    ) -> [String] {
        guard let start = weekStartKey(
            containing: key,
            calendar: calendar
        ) else {
            return []
        }
        return (0..<7).compactMap {
            shifting(start, by: $0, calendar: calendar)
        }
    }

    public static func monthStartKey(
        containing key: String,
        calendar base: Calendar = .current
    ) -> String? {
        let calendar = periodCalendar(base)
        guard let date = date(from: key, calendar: calendar),
              let interval = calendar.dateInterval(of: .month, for: date) else {
            return nil
        }
        return self.key(for: interval.start, calendar: calendar)
    }

    public static func monthDayKeys(
        containing key: String,
        calendar: Calendar = .current
    ) -> [String] {
        guard let start = monthStartKey(
            containing: key,
            calendar: calendar
        ), let startDate = date(from: start, calendar: calendar),
           let range = calendar.range(of: .day, in: .month, for: startDate) else {
            return []
        }
        return range.compactMap {
            shifting(start, by: $0 - 1, calendar: calendar)
        }
    }

    /// Six Monday-first weeks covering the selected month, including the
    /// leading/trailing days from adjacent months.
    public static func monthGridKeys(
        containing key: String,
        calendar: Calendar = .current
    ) -> [String] {
        guard let monthStart = monthStartKey(
            containing: key,
            calendar: calendar
        ), let gridStart = weekStartKey(
            containing: monthStart,
            calendar: calendar
        ) else {
            return []
        }
        return (0..<42).compactMap {
            shifting(gridStart, by: $0, calendar: calendar)
        }
    }

    public static func yearStartKey(
        containing key: String,
        calendar base: Calendar = .current
    ) -> String? {
        let calendar = periodCalendar(base)
        guard let date = date(from: key, calendar: calendar),
              let interval = calendar.dateInterval(of: .year, for: date) else {
            return nil
        }
        return self.key(for: interval.start, calendar: calendar)
    }

    public static func yearDayKeys(
        containing key: String,
        calendar base: Calendar = .current
    ) -> [String] {
        let calendar = periodCalendar(base)
        guard let startKey = yearStartKey(
            containing: key,
            calendar: calendar
        ), let start = date(from: startKey, calendar: calendar),
           let nextYear = calendar.date(
               byAdding: .year,
               value: 1,
               to: start
           ) else {
            return []
        }

        var keys: [String] = []
        var cursor = start
        while cursor < nextYear {
            keys.append(self.key(for: cursor, calendar: calendar))
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: cursor
            ) else {
                break
            }
            cursor = next
        }
        return keys
    }

    public static func yearMonthKeys(
        containing key: String,
        calendar base: Calendar = .current
    ) -> [String] {
        let calendar = periodCalendar(base)
        guard let startKey = yearStartKey(
            containing: key,
            calendar: calendar
        ), let start = date(from: startKey, calendar: calendar) else {
            return []
        }
        return (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: start)
                .map { self.key(for: $0, calendar: calendar) }
        }
    }

    public static func shiftingMonths(
        _ key: String,
        by months: Int,
        calendar: Calendar = .current
    ) -> String? {
        guard let date = date(from: key, calendar: calendar),
              let shifted = calendar.date(
                  byAdding: .month,
                  value: months,
                  to: date
              ) else {
            return nil
        }
        return self.key(for: shifted, calendar: calendar)
    }

    public static func shiftingYears(
        _ key: String,
        by years: Int,
        calendar: Calendar = .current
    ) -> String? {
        guard let date = date(from: key, calendar: calendar),
              let shifted = calendar.date(
                  byAdding: .year,
                  value: years,
                  to: date
              ) else {
            return nil
        }
        return self.key(for: shifted, calendar: calendar)
    }
}
