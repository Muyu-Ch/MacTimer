import AppKit
import Combine
import Foundation
import MacTimerCore

public enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    public var jumpLabel: String {
        switch self {
        case .day: "回到今天"
        case .week: "回到本周"
        case .month: "回到本月"
        case .year: "回到今年"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .day: "日视图"
        case .week: "周视图"
        case .month: "月视图"
        case .year: "年视图"
        }
    }

    public var previousHelp: String {
        switch self {
        case .day: "前一天"
        case .week: "上一周"
        case .month: "上个月"
        case .year: "上一年"
        }
    }

    public var nextHelp: String {
        switch self {
        case .day: "后一天"
        case .week: "下一周"
        case .month: "下个月"
        case .year: "下一年"
        }
    }
}

public struct HistoryBar: Identifiable, Equatable, Sendable {
    public var day: String
    public var date: Date
    public var milliseconds: Int64

    public var id: String { day }

    public var hours: Double {
        Double(milliseconds) / 3_600_000
    }

    public init(day: String, date: Date, milliseconds: Int64) {
        self.day = day
        self.date = date
        self.milliseconds = milliseconds
    }
}

public struct YearMonthSummary: Identifiable, Equatable, Sendable {
    public var key: String
    public var date: Date
    public var milliseconds: Int64
    public var isFuture: Bool

    public var id: String { key }

    public init(
        key: String,
        date: Date,
        milliseconds: Int64,
        isFuture: Bool
    ) {
        self.key = key
        self.date = date
        self.milliseconds = milliseconds
        self.isFuture = isFuture
    }
}

public enum ScreenTimeAccessState: Equatable, Sendable {
    case idle
    case loading
    case ready(dayCount: Int, updatedAt: Date)
    case needsPermission
    case unavailable(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public enum DayChartMode: String, CaseIterable, Identifiable, Sendable {
    case hourly
    case items

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hourly: "按小时"
        case .items: "按网站/App"
        }
    }
}

public struct DayHourBar: Identifiable, Equatable, Sendable {
    public var hour: Int
    public var milliseconds: Int64

    public var id: Int { hour }
    public var hours: Double { Double(milliseconds) / 3_600_000 }

    public init(hour: Int, milliseconds: Int64) {
        self.hour = hour
        self.milliseconds = milliseconds
    }
}

public struct DayItemBar: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var milliseconds: Int64
    public var isAggregate: Bool

    public var hours: Double { Double(milliseconds) / 3_600_000 }

    public init(
        id: String,
        name: String,
        milliseconds: Int64,
        isAggregate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.milliseconds = milliseconds
        self.isAggregate = isAggregate
    }
}

@MainActor
public final class DashboardModel: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var loadError: String?
    @Published public private(set) var selectedDay: String
    @Published public private(set) var viewMode: StatsRange = .day
    @Published public private(set) var followToday = true
    @Published public private(set) var screenTimeAccess: ScreenTimeAccessState = .idle
    @Published public private(set) var entityDisplays:
        [String: UsageEntityDisplay] = [:]
    @Published public private(set) var dayChartMode: DayChartMode = .hourly

    public let dataFileURL: URL

    private let store: UsageSnapshotStore
    private let autoRefresh: Bool
    private let mappingStore: MappingStore
    private let screenTimeReader: ScreenTimeReader
    private var chromeSnapshot: UsageSnapshot?
    private var screenTimeDays: [String: [String: Int64]] = [:]
    private var screenTimeHours: [String: [Int: [String: Int64]]] = [:]
    private var screenTimeStream: String?
    private var screenTimeFetchedAt: Date?
    private var screenTimeLoading = false
    private var screenTimeTask: Task<Void, Never>?
    private var screenTimeTimer: Timer?
    private var appNames: [String: String] = [:]
    private var mappingCancellable: AnyCancellable?
    private var timer: Timer?
    private var lastModificationDate: Date?

    public init(
        dataFileURL: URL = AppPaths.dataFileURL,
        initialSnapshot: UsageSnapshot? = nil,
        initialScreenTime: ScreenTimeUsage? = nil,
        initialScreenTimeAccess: ScreenTimeAccessState? = nil,
        mappingStore: MappingStore = .shared,
        autoRefresh: Bool = true
    ) {
        self.dataFileURL = dataFileURL
        self.store = UsageSnapshotStore(fileURL: dataFileURL)
        self.autoRefresh = autoRefresh
        self.mappingStore = mappingStore
        self.screenTimeReader = ScreenTimeReader()
        self.chromeSnapshot = initialSnapshot
        self.selectedDay = CalendarDay.today()

        if let initialScreenTime {
            self.screenTimeDays = initialScreenTime.days
            self.screenTimeHours = initialScreenTime.hours
            self.screenTimeStream = initialScreenTime.stream
            self.screenTimeFetchedAt = initialScreenTime.fetchedAt
            self.screenTimeAccess = .ready(
                dayCount: Self.activeAppDayCount(initialScreenTime.days),
                updatedAt: initialScreenTime.fetchedAt
            )
        }
        if let initialScreenTimeAccess {
            self.screenTimeAccess = initialScreenTimeAccess
        }

        rebuildUsage()
        mappingCancellable = mappingStore.objectWillChange.sink {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildUsage()
            }
        }
    }

    public func start() {
        guard autoRefresh else { return }
        load(force: true)

        if timer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.load(force: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        if screenTimeTimer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshScreenTimeFromTimer()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.screenTimeTimer = timer
        }

        refreshScreenTime(full: true)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        screenTimeTimer?.invalidate()
        screenTimeTimer = nil
        screenTimeTask?.cancel()
        screenTimeTask = nil
    }

    public func reload(force: Bool = true) {
        load(force: force)
        if autoRefresh {
            refreshScreenTime(full: true)
        }
    }

    private func load(force: Bool) {
        let today = CalendarDay.today()
        if followToday, selectedDay != today {
            selectedDay = today
        }
        if selectedDay > today {
            selectedDay = today
            followToday = true
        }

        guard autoRefresh || force else { return }

        let attributes = try? FileManager.default.attributesOfItem(
            atPath: dataFileURL.path
        )
        let modificationDate = attributes?[.modificationDate] as? Date
        if !force,
           let modificationDate,
           let lastModificationDate,
           modificationDate == lastModificationDate {
            return
        }
        lastModificationDate = modificationDate

        do {
            chromeSnapshot = try store.load()
            loadError = nil
            rebuildUsage()
        } catch {
            loadError = "数据文件无法读取：\(error.localizedDescription)"
        }
    }

    public var hasData: Bool { snapshot != nil }

    // MARK: - Screen Time

    public var usesScreenTimeData: Bool {
        Self.activeAppDayCount(screenTimeDays) > 0
    }

    public var screenTimeDatabasePath: String {
        screenTimeReader.databaseURL.path
    }

    public func retryScreenTime() {
        refreshScreenTime(full: true)
    }

    private func refreshScreenTimeFromTimer() {
        refreshScreenTime(full: !screenTimeAccess.isReady)
    }

    public func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    public func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func refreshScreenTime(full: Bool) {
        guard !screenTimeLoading else { return }
        screenTimeLoading = true
        if full {
            screenTimeAccess = .loading
        }

        let now = Date()
        let calendar = Calendar.current
        let since: Date
        if full {
            let startOfToday = calendar.startOfDay(for: now)
            since = calendar.date(
                byAdding: .day,
                value: -730,
                to: startOfToday
            ) ?? now.addingTimeInterval(-730 * 86_400)
        } else {
            let startOfToday = calendar.startOfDay(for: now)
            since = calendar.date(
                byAdding: .day,
                value: -1,
                to: startOfToday
            ) ?? now.addingTimeInterval(-86_400)
        }

        let reader = screenTimeReader
        let preferredStream = full ? nil : screenTimeStream
        let task = Task { [weak self] in
            let result: Result<ScreenTimeUsage, ScreenTimeReadError> =
                await Task.detached(priority: .utility) {
                    do {
                        return .success(
                            try reader.read(
                                since: since,
                                now: now,
                                preferredStream: preferredStream
                            )
                        )
                    } catch let error as ScreenTimeReadError {
                        return .failure(error)
                    } catch {
                        return .failure(
                            .readFailed(error.localizedDescription)
                        )
                    }
                }.value

            guard let self else { return }
            if Task.isCancelled {
                self.screenTimeLoading = false
                return
            }
            self.screenTimeLoading = false
            self.screenTimeTask = nil
            self.applyScreenTime(
                result,
                full: full,
                requestedAt: now
            )
        }
        screenTimeTask = task
    }

    private func applyScreenTime(
        _ result: Result<ScreenTimeUsage, ScreenTimeReadError>,
        full: Bool,
        requestedAt: Date
    ) {
        switch result {
        case .success(let usage):
            if full {
                screenTimeDays = usage.days
                screenTimeHours = usage.hours
            } else {
                let replaced = Set(
                    CalendarDay.lastDays(2, endingAt: requestedAt)
                )
                for day in replaced {
                    screenTimeDays.removeValue(forKey: day)
                    screenTimeHours.removeValue(forKey: day)
                }
                for (day, bucket) in usage.days {
                    screenTimeDays[day] = bucket
                }
                for (day, buckets) in usage.hours {
                    screenTimeHours[day] = buckets
                }
            }
            if let stream = usage.stream {
                screenTimeStream = stream
            }
            screenTimeFetchedAt = usage.fetchedAt
            screenTimeAccess = .ready(
                dayCount: Self.activeAppDayCount(screenTimeDays),
                updatedAt: usage.fetchedAt
            )
            rebuildUsage()
            writeScreenTimeStatus(
                state: "ready",
                usage: usage
            )
        case .failure(let error):
            let status: String
            switch error {
            case .permissionDenied:
                screenTimeAccess = .needsPermission
                status = "needsPermission"
            case .databaseNotFound, .schemaUnsupported, .readFailed:
                screenTimeAccess = .unavailable(
                    error.localizedDescription
                )
                status = "unavailable"
            }
            writeScreenTimeStatus(
                state: status,
                error: error.localizedDescription
            )
        }
    }

    /// A small local status file helps diagnose private-database/schema
    /// changes. It contains only counts and the error, never app durations.
    private func writeScreenTimeStatus(
        state: String,
        error: String? = nil,
        usage: ScreenTimeUsage? = nil
    ) {
        var payload: [String: Any] = [
            "checkedAt": ISO8601DateFormatter().string(from: Date()),
            "state": state,
            "database": screenTimeReader.databaseURL.path,
        ]
        if let usage {
            payload["stream"] = usage.stream ?? ""
            payload["lastReadEventCount"] = usage.eventCount
            payload["dayCount"] = Self.activeAppDayCount(screenTimeDays)
            payload["oldestDay"] = screenTimeDays.keys.min() ?? ""
            payload["newestDay"] = screenTimeDays.keys.max() ?? ""
        }
        if let error {
            payload["error"] = error
        }

        let folder = AppPaths.defaultSupportDirectory
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        try? data.write(
            to: folder.appendingPathComponent("screen-time-status.json"),
            options: [.atomic]
        )
    }

    private func rebuildUsage() {
        refreshAppNames()

        let usedAppBundles = Set(
            screenTimeDays.values.flatMap { $0.keys }
        )
        let mappings = mappingStore.effectiveMappings.filter { mapping in
            // A built-in mapping for an app that is neither installed nor in
            // the local Screen Time history should not rename its website.
            if mappingStore.customMapping(for: mapping.domain) != nil {
                return true
            }
            return appNames[mapping.bundleID] != nil
                || usedAppBundles.contains(mapping.bundleID)
        }

        let merged = UsageMerge.build(
            chromeDays: chromeSnapshot?.days ?? [:],
            screenTimeDays: screenTimeDays,
            mappings: mappings,
            appNames: appNames
        )
        entityDisplays = merged.displays

        guard chromeSnapshot != nil || !screenTimeDays.isEmpty else {
            snapshot = nil
            return
        }

        let screenTimeMilliseconds = screenTimeFetchedAt.map {
            Int64($0.timeIntervalSince1970 * 1_000)
        } ?? 0
        snapshot = UsageSnapshot(
            version: 1,
            updatedAt: max(chromeSnapshot?.updatedAt ?? 0, screenTimeMilliseconds),
            current: chromeSnapshot?.current,
            days: merged.days
        )
    }

    private func refreshAppNames() {
        var bundleIDs = Set(
            screenTimeDays.values.flatMap { $0.keys }
        )
        for mapping in mappingStore.effectiveMappings {
            bundleIDs.insert(mapping.bundleID)
        }
        for bundleID in bundleIDs {
            if let name = AppCatalog.shared.name(for: bundleID) {
                appNames[bundleID] = name
            }
        }
    }

    private static func activeAppDayCount(
        _ days: [String: [String: Int64]]
    ) -> Int {
        days.values.reduce(0) { count, bucket in
            count + (bucket.values.contains { $0 > 0 } ? 1 : 0)
        }
    }

    public func display(for entity: String) -> UsageEntityDisplay {
        entityDisplays[entity] ?? UsageEntityDisplay(name: entity)
    }

    // MARK: - Day chart

    public func setDayChartMode(_ mode: DayChartMode) {
        dayChartMode = mode
    }

    public var dayHasHourlyData: Bool {
        dayHourlyBars.contains { $0.milliseconds > 0 }
    }

    public var dayHourlyBars: [DayHourBar] {
        dayHourlyBars(for: selectedDay)
    }

    public func dayHourlyBars(for day: String) -> [DayHourBar] {
        let buckets = screenTimeHours[day] ?? [:]
        let allowed = allowedHourlyBundles
        return (0...23).map { hour in
            var total: Int64 = 0
            for (bundleID, milliseconds) in buckets[hour] ?? [:]
            where milliseconds > 0 {
                if ScreenTimeFilter.isChromeUsage(bundleID) {
                    total += milliseconds
                } else if ScreenTimeFilter.isExcluded(bundleID) {
                    continue
                } else if allowed.contains(bundleID) {
                    total += milliseconds
                }
            }
            return DayHourBar(hour: hour, milliseconds: total)
        }
    }

    private var allowedHourlyBundles: Set<String> {
        var allowed = Set(appNames.keys)
        for mapping in mappingStore.effectiveMappings
        where !ScreenTimeFilter.isExcluded(mapping.bundleID) {
            allowed.insert(mapping.bundleID)
        }
        return allowed
    }

    public var dayHourlyTotalMilliseconds: Int64 {
        dayHourlyBars.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    public var dayHourlyPeak: DayHourBar? {
        var peak: DayHourBar?
        for bar in dayHourlyBars where bar.milliseconds > 0 {
            if peak == nil || bar.milliseconds > peak!.milliseconds {
                peak = bar
            }
        }
        return peak
    }

    public var dayChartItems: [DayItemBar] {
        let all = entries
        guard !all.isEmpty else { return [] }
        let limit = 8
        var rows = all.prefix(limit).map { entry in
            DayItemBar(
                id: entry.site,
                name: display(for: entry.site).name,
                milliseconds: entry.milliseconds
            )
        }
        if all.count > limit {
            let rest = all.dropFirst(limit)
            let milliseconds = rest.reduce(Int64(0)) {
                $0 + $1.milliseconds
            }
            rows.append(
                DayItemBar(
                    id: "__other",
                    name: "其他 \(rest.count) 项",
                    milliseconds: milliseconds,
                    isAggregate: true
                )
            )
        }
        return rows
    }

    public var dayChartUsesFallback: Bool {
        dayChartMode == .hourly && !dayHasHourlyData && !entries.isEmpty
    }

    public var isTodaySelected: Bool {
        selectedDay == CalendarDay.today()
    }

    // MARK: - Selected period

    public var periodDays: [String] {
        switch viewMode {
        case .day:
            return [selectedDay]
        case .week:
            return CalendarDay.weekDayKeys(containing: selectedDay)
        case .month:
            return CalendarDay.monthDayKeys(containing: selectedDay)
        case .year:
            return CalendarDay.yearDayKeys(containing: selectedDay)
        }
    }

    public var periodEntries: [SiteEntry] {
        snapshot?.aggregatedEntries(over: periodDays) ?? []
    }

    public var periodTotalMilliseconds: Int64 {
        periodEntries.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    public var periodSiteCount: Int { periodEntries.count }

    public var periodActiveDays: Int {
        snapshot?.activeDayCount(over: periodDays) ?? 0
    }

    public var periodAverageMilliseconds: Int64 {
        guard periodActiveDays > 0 else { return 0 }
        return periodTotalMilliseconds / Int64(periodActiveDays)
    }

    public var periodTopEntry: SiteEntry? {
        periodEntries.first
    }

    public var periodBestDay: (day: String, milliseconds: Int64)? {
        snapshot?.bestDay(over: periodDays)
    }

    public var periodLabel: String {
        switch viewMode {
        case .day:
            return DateText.dayLabel(selectedDay)
        case .week:
            return DateText.weekRangeLabel(
                CalendarDay.weekDayKeys(containing: selectedDay)
            )
        case .month:
            return DateText.monthLabel(selectedDay)
        case .year:
            return DateText.yearLabel(selectedDay)
        }
    }

    public var periodTag: String? {
        switch viewMode {
        case .day:
            return DateText.relativeTag(selectedDay)
        case .week:
            return isCurrentPeriod ? "本周" : nil
        case .month:
            return isCurrentPeriod ? "本月" : nil
        case .year:
            return isCurrentPeriod ? "今年" : nil
        }
    }

    public var isCurrentPeriod: Bool {
        guard let selectedStart = periodStartKey(
            for: selectedDay,
            mode: viewMode
        ), let todayStart = periodStartKey(
            for: CalendarDay.today(),
            mode: viewMode
        ) else {
            return false
        }
        return selectedStart == todayStart
    }

    public var canShiftBack: Bool {
        guard let currentStart = periodStartKey(
            for: selectedDay,
            mode: viewMode
        ), let earliestStart = periodStartKey(
            for: earliestDay,
            mode: viewMode
        ) else {
            return false
        }
        return currentStart > earliestStart
    }

    public var canShiftForward: Bool {
        guard let currentStart = periodStartKey(
            for: selectedDay,
            mode: viewMode
        ), let todayStart = periodStartKey(
            for: CalendarDay.today(),
            mode: viewMode
        ) else {
            return false
        }
        return currentStart < todayStart
    }

    public func setViewMode(_ mode: StatsRange) {
        viewMode = mode
        if followToday {
            selectedDay = CalendarDay.today()
        }
    }

    public func goToCurrentPeriod() {
        selectedDay = CalendarDay.today()
        followToday = true
    }

    public func shiftPeriod(by delta: Int) {
        guard delta != 0 else { return }

        let today = CalendarDay.today()
        let target: String?
        switch viewMode {
        case .day:
            target = CalendarDay.shifting(selectedDay, by: delta)
        case .week:
            target = CalendarDay.shifting(selectedDay, by: delta * 7)
        case .month:
            target = CalendarDay.shiftingMonths(selectedDay, by: delta)
        case .year:
            target = CalendarDay.shiftingYears(selectedDay, by: delta)
        }

        guard let target,
              let targetStart = periodStartKey(
                  for: target,
                  mode: viewMode
              ),
              let todayStart = periodStartKey(
                  for: today,
                  mode: viewMode
              ) else {
            return
        }

        if delta > 0 {
            guard targetStart <= todayStart else { return }
        } else {
            guard let earliestStart = periodStartKey(
                for: earliestDay,
                mode: viewMode
            ), targetStart >= earliestStart else {
                return
            }
        }

        let isCurrent = targetStart == todayStart
        selectedDay = isCurrent ? today : target
        followToday = isCurrent
    }

    private func periodStartKey(
        for day: String,
        mode: StatsRange
    ) -> String? {
        switch mode {
        case .day:
            return day
        case .week:
            return CalendarDay.weekStartKey(containing: day)
        case .month:
            return CalendarDay.monthStartKey(containing: day)
        case .year:
            return CalendarDay.yearStartKey(containing: day)
        }
    }

    public func select(day: String) {
        guard CalendarDay.date(from: day) != nil else { return }
        let today = CalendarDay.today()
        if day > today {
            goToCurrentPeriod()
            return
        }
        selectedDay = day
        followToday = day == today
    }

    public func openDay(_ day: String) {
        guard CalendarDay.date(from: day) != nil,
              day <= CalendarDay.today() else {
            return
        }
        selectedDay = day
        viewMode = .day
        followToday = day == CalendarDay.today()
    }

    public func openMonth(_ monthStart: String) {
        guard CalendarDay.date(from: monthStart) != nil else { return }

        let today = CalendarDay.today()
        guard let currentMonthStart = CalendarDay.monthStartKey(
            containing: today
        ), monthStart <= currentMonthStart else {
            return
        }

        if today.hasPrefix(String(monthStart.prefix(7))) {
            selectedDay = today
        } else {
            selectedDay = monthStart
        }
        viewMode = .month
        followToday = isCurrentPeriod
    }

    // MARK: - Day detail

    public var syncText: String {
        if let chromeSnapshot {
            return "同步于 \(DateText.syncLabel(chromeSnapshot.updatedAt))"
        }
        if usesScreenTimeData {
            return "App 数据来自屏幕使用时间"
        }
        return "等待 Chrome 数据"
    }

    public var entries: [SiteEntry] {
        snapshot?.entries(for: selectedDay) ?? []
    }

    public var totalMilliseconds: Int64 {
        entries.reduce(Int64(0)) { $0 + $1.milliseconds }
    }

    public var siteCount: Int { entries.count }

    public var topEntry: SiteEntry? { entries.first }

    public var previousDayTotal: Int64 {
        guard let previous = CalendarDay.shifting(selectedDay, by: -1) else {
            return 0
        }
        return snapshot?.total(for: previous) ?? 0
    }

    public var previousDayLabel: String {
        guard let previous = CalendarDay.shifting(selectedDay, by: -1),
              let parts = CalendarDay.components(previous) else {
            return ""
        }
        return "\(parts.month)月\(parts.day)日"
    }

    public var earliestDay: String {
        let today = CalendarDay.today()
        guard let snapshot else { return today }
        let active = snapshot.days.compactMap { day, bucket in
            bucket.values.contains { $0 > 0 } ? day : nil
        }
        return active.min().map { min($0, today) } ?? today
    }

    public var selectedWeekDays: [HistoryBar] {
        makeBars(CalendarDay.weekDayKeys(containing: selectedDay))
    }

    public var selectedMonthPrefix: String {
        String(selectedDay.prefix(7))
    }

    public var selectedMonthGrid: [HistoryBar] {
        makeBars(CalendarDay.monthGridKeys(containing: selectedDay))
    }

    public var selectedMonthMaxMilliseconds: Int64 {
        let prefix = selectedMonthPrefix
        return selectedMonthGrid
            .filter { $0.day.hasPrefix(prefix) }
            .map(\.milliseconds)
            .max() ?? 0
    }

    public var selectedYearMonths: [YearMonthSummary] {
        let today = CalendarDay.today()
        guard let currentMonthStart = CalendarDay.monthStartKey(
            containing: today
        ) else {
            return []
        }

        return CalendarDay.yearMonthKeys(containing: selectedDay)
            .compactMap { monthStart in
                guard let date = CalendarDay.date(from: monthStart) else {
                    return nil
                }
                let monthDays = CalendarDay.monthDayKeys(
                    containing: monthStart
                )
                return YearMonthSummary(
                    key: monthStart,
                    date: date,
                    milliseconds: snapshot?.totalOver(monthDays) ?? 0,
                    isFuture: monthStart > currentMonthStart
                )
            }
    }

    private func makeBars(_ days: [String]) -> [HistoryBar] {
        days.compactMap { day in
            guard let date = CalendarDay.date(from: day) else { return nil }
            return HistoryBar(
                day: day,
                date: date,
                milliseconds: snapshot?.total(for: day) ?? 0
            )
        }
    }

    public func revealDataFolder() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dataFileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([dataFileURL])
        } else {
            let folder = dataFileURL.deletingLastPathComponent()
            try? fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(folder)
        }
    }
}
