import Foundation

public enum DayStartSetting {
    public static let storageKey = "dayStartHour"
    public static let allowedHours = 0...4

    public static func clamp(_ hour: Int) -> Int {
        min(allowedHours.upperBound, max(allowedHours.lowerBound, hour))
    }

    public static func load(defaults: UserDefaults = .standard) -> Int {
        clamp(defaults.integer(forKey: storageKey))
    }

    public static func save(
        _ hour: Int,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(clamp(hour), forKey: storageKey)
    }
}

/// Rebuckets calendar-day/hour data into logical days that start at a custom
/// hour. Only the first four hours of a calendar day can move backwards, so
/// callers record/supply at most hours 0...3 of "early" data.
public enum DayBucketing {
    /// `days` are calendar-day totals. `earlyHourBuckets` contains per-hour
    /// totals for hours that may need to move to the previous logical day.
    public static func shiftedDays(
        days: [String: [String: Int64]],
        earlyHourBuckets: [String: [Int: [String: Int64]]],
        startHour: Int
    ) -> [String: [String: Int64]] {
        let hour = DayStartSetting.clamp(startHour)
        guard hour > 0, !earlyHourBuckets.isEmpty else { return days }

        var result = days
        for (day, hourBuckets) in earlyHourBuckets {
            guard let previous = CalendarDay.shifting(day, by: -1) else {
                continue
            }

            for earlyHour in 0..<hour {
                guard let bucket = hourBuckets[earlyHour] else { continue }
                for (site, milliseconds) in bucket where milliseconds > 0 {
                    subtract(
                        site: site,
                        milliseconds: milliseconds,
                        from: day,
                        in: &result
                    )
                    add(
                        site: site,
                        milliseconds: milliseconds,
                        to: previous,
                        in: &result
                    )
                }
            }
        }

        return result.filter { !$0.value.isEmpty }
    }

    /// Moves recorded clock-hour buckets (0...23) belonging to the early
    /// hours onto the previous logical day. Hour keys stay as clock hours so
    /// the existing day chart can render them without a second calendar.
    public static func shiftedHours(
        hours: [String: [Int: [String: Int64]]],
        startHour: Int
    ) -> [String: [Int: [String: Int64]]] {
        let hour = DayStartSetting.clamp(startHour)
        guard hour > 0 else { return hours }

        var result: [String: [Int: [String: Int64]]] = [:]
        for (day, hourBuckets) in hours {
            for (clockHour, bucket) in hourBuckets {
                let targetDay: String
                if clockHour < hour {
                    targetDay = CalendarDay.shifting(day, by: -1) ?? day
                } else {
                    targetDay = day
                }
                for (site, milliseconds) in bucket where milliseconds > 0 {
                    var dayBucket = result[targetDay] ?? [:]
                    var siteBucket = dayBucket[clockHour] ?? [:]
                    siteBucket[site, default: 0] += milliseconds
                    dayBucket[clockHour] = siteBucket
                    result[targetDay] = dayBucket
                }
            }
        }
        return result
    }

    /// Extracts just the early-hour portion of full hour buckets.
    public static func earlyHourBuckets(
        from hours: [String: [Int: [String: Int64]]],
        startHour: Int
    ) -> [String: [Int: [String: Int64]]] {
        let hour = DayStartSetting.clamp(startHour)
        guard hour > 0 else { return [:] }

        var result: [String: [Int: [String: Int64]]] = [:]
        for (day, hourBuckets) in hours {
            for earlyHour in 0..<hour {
                guard let bucket = hourBuckets[earlyHour],
                      !bucket.isEmpty else {
                    continue
                }
                result[day, default: [:]][earlyHour] = bucket
            }
        }
        return result
    }

    private static func subtract(
        site: String,
        milliseconds: Int64,
        from day: String,
        in result: inout [String: [String: Int64]]
    ) {
        guard var bucket = result[day] else { return }
        let current = bucket[site] ?? 0
        let remaining = current - min(current, milliseconds)
        if remaining > 0 {
            bucket[site] = remaining
        } else {
            bucket.removeValue(forKey: site)
        }
        if bucket.isEmpty {
            result.removeValue(forKey: day)
        } else {
            result[day] = bucket
        }
    }

    private static func add(
        site: String,
        milliseconds: Int64,
        to day: String,
        in result: inout [String: [String: Int64]]
    ) {
        var bucket = result[day] ?? [:]
        bucket[site, default: 0] += milliseconds
        result[day] = bucket
    }
}
