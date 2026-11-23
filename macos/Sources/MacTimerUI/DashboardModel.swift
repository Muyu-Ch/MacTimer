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
    case category

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hourly: "按小时"
        case .items: "按网站/App"
        case .category: "按分类"
        }
    }
}

public struct DayHourBar: Identifiable, Equatable, Sendable {
    /// Actual local clock hour (0...23).
    public var hour: Int
    /// Position within the logical day; the x-axis index.
    public var axisIndex: Int
    public var milliseconds: Int64

    public var id: Int { axisIndex }
    public var hours: Double { Double(milliseconds) / 3_600_000 }

    public init(
        hour: Int,
        milliseconds: Int64,
        axisIndex: Int? = nil
    ) {
        self.hour = hour
        self.axisIndex = axisIndex ?? hour
        self.milliseconds = milliseconds
    }
}

public struct DayHourCategorySlice: Identifiable, Equatable, Sendable {
    /// Actual local clock hour (0...23).
    public var hour: Int
    /// Position within the logical day; the x-axis index.
    public var axisIndex: Int
    public var categoryID: String
    public var categoryName: String
    public var colorHex: String
    public var milliseconds: Int64
    public var isUncategorized: Bool

    public var id: String { "\(axisIndex)-\(categoryID)" }
    public var hours: Double { Double(milliseconds) / 3_600_000 }

    public init(
        hour: Int,
        axisIndex: Int,
        categoryID: String,
        categoryName: String,
        colorHex: String,
        milliseconds: Int64,
        isUncategorized: Bool
    ) {
        self.hour = hour
        self.axisIndex = axisIndex
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.colorHex = colorHex
        self.milliseconds = milliseconds
        self.isUncategorized = isUncategorized
    }
}

public struct DayItemBar: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var milliseconds: Int64
    public var isAggregate: Bool
    public var categoryColorHex: String?

    public var hours: Double { Double(milliseconds) / 3_600_000 }

    public init(
        id: String,
        name: String,
        milliseconds: Int64,
        isAggregate: Bool = false,
        categoryColorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.milliseconds = milliseconds
        self.isAggregate = isAggregate
        self.categoryColorHex = categoryColorHex
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
    @Published public private(set) var dayStartHour: Int = 0

    public let dataFileURL: URL
    public let categoryStore: CategoryStore

    private let store: UsageSnapshotStore
    private let autoRefresh: Bool
    private let mappingStore: MappingStore
    private let screenTimeReader: ScreenTimeReader
    private let screenTimeArchiveStore: ScreenTimeArchiveStore
    private var chromeSnapshot: UsageSnapshot?
    /// Raw calendar-day Screen Time data, as read from Apple's database or
    /// restored from the archive. `screenTimeDays`/`screenTimeHours` are the
    /// logical-day views derived from these using `dayStartHour`.
    private var rawScreenTimeDays: [String: [String: Int64]] = [:]
    private var rawScreenTimeHours: [String: [Int: [String: Int64]]] = [:]
    private var screenTimeDays: [String: [String: Int64]] = [:]
    private var screenTimeHours: [String: [Int: [String: Int64]]] = [:]
    private var screenTimeStream: String?
    private var screenTimeFetchedAt: Date?
    private var screenTimeLoading = false
    private var screenTimeTask: Task<Void, Never>?
    private var screenTimeTimer: Timer?
    private var appNames: [String: String] = [:]
    private var mappingCancellable: AnyCancellable?
    private var categoryCancellable: AnyCancellable?
    private var timer: Timer?
    private var lastModificationDate: Date?

    public init(
        dataFileURL: URL = AppPaths.dataFileURL,
        initialSnapshot: UsageSnapshot? = nil,
        initialScreenTime: ScreenTimeUsage? = nil,
        initialScreenTimeAccess: ScreenTimeAccessState? = nil,
        mappingStore: MappingStore = .shared,
        categoryStore: CategoryStore = .shared,
        dayStartHour: Int = 0,
        autoRefresh: Bool = true
    ) {
        self.dataFileURL = dataFileURL
        self.store = UsageSnapshotStore(fileURL: dataFileURL)
        self.autoRefresh = autoRefresh
        self.mappingStore = mappingStore
        self.categoryStore = categoryStore
        self.screenTimeReader = ScreenTimeReader()
        self.screenTimeArchiveStore = ScreenTimeArchiveStore()
        self.chromeSnapshot = initialSnapshot
        let startHour = DayStartSetting.clamp(dayStartHour)
        self.dayStartHour = startHour
        self.selectedDay = CalendarDay.today(startHour: startHour)

        // The real app restores its own Screen Time history before the first
        // live read. Previews and tests pass initial data with autoRefresh
        // disabled and do not touch the user's archive.
        if autoRefresh {
            loadScreenTimeArchive()
        }

        if let initialScreenTime {
            self.rawScreenTimeDays = initialScreenTime.days
            self.rawScreenTimeHours = initialScreenTime.hours
            applyScreenTimeDayBoundary()
            self.screenTimeStream = initialScreenTime.stream
            self.screenTimeFetchedAt = initialScreenTime.fetchedAt
            self.screenTimeAccess = .ready(
                dayCount: Self.activeAppDayCount(screenTimeDays),
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
        categoryCancellable = categoryStore.objectWillChange.sink {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    private func loadScreenTimeArchive() {
        guard let archive = try? screenTimeArchiveStore.load(),
              !archive.days.isEmpty else {
            return
        }
        let updatedAt = archive.updatedAtDate
        rawScreenTimeDays = archive.days
        rawScreenTimeHours = archive.hourBuckets()
        applyScreenTimeDayBoundary()
        screenTimeStream = archive.stream
        screenTimeFetchedAt = updatedAt
        screenTimeAccess = .ready(
            dayCount: Self.activeAppDayCount(screenTimeDays),
            updatedAt: updatedAt
        )
    }

    private func saveScreenTimeArchive() {
        guard !rawScreenTimeDays.isEmpty else { return }
        let archive = ScreenTimeArchive(
            days: rawScreenTimeDays,
            hoursByHour: rawScreenTimeHours,
            stream: screenTimeStream,
            updatedAt: screenTimeFetchedAt ?? Date()
        )
        try? screenTimeArchiveStore.save(archive)
    }

    private func applyScreenTimeDayBoundary() {
        let early = DayBucketing.earlyHourBuckets(
            from: rawScreenTimeHours,
            startHour: dayStartHour
        )
        screenTimeDays = DayBucketing.shiftedDays(
            days: rawScreenTimeDays,
            earlyHourBuckets: early,
            startHour: dayStartHour
        )
        screenTimeHours = DayBucketing.shiftedHours(
            hours: rawScreenTimeHours,
            startHour: dayStartHour
        )
    }

    public func setDayStartHour(_ hour: Int) {
        let value = DayStartSetting.clamp(hour)
        guard value != dayStartHour else { return }

        dayStartHour = value
        DayStartSetting.save(value)
        applyScreenTimeDayBoundary()

        if case .ready(_, let updatedAt) = screenTimeAccess {
            screenTimeAccess = .ready(
                dayCount: Self.activeAppDayCount(screenTimeDays),
                updatedAt: updatedAt
            )
        }

        let today = todayKey
        if followToday || selectedDay > today {
            selectedDay = today
            followToday = true
        }
        rebuildUsage()
    }

    public var todayKey: String {
        CalendarDay.today(startHour: dayStartHour)
    }

    private var logicalChromeDays: [String: [String: Int64]] {
        guard let chromeSnapshot else { return [:] }
        let early = Self.chromeEarlyHourBuckets(
            from: chromeSnapshot.earlyHours,
            startHour: dayStartHour
        )
        return DayBucketing.shiftedDays(
            days: chromeSnapshot.days,
            earlyHourBuckets: early,
            startHour: dayStartHour
        )
    }

    private static func chromeEarlyHourBuckets(
        from earlyHours: [String: [String: [String: Int64]]]?,
        startHour: Int
    ) -> [String: [Int: [String: Int64]]] {
        let limit = DayStartSetting.clamp(startHour)
        guard limit > 0, let earlyHours else { return [:] }

        var result: [String: [Int: [String: Int64]]] = [:]
        for (day, hours) in earlyHours {
            for (rawHour, bucket) in hours {
                guard let hour = Int(rawHour),
                      hour >= 0, hour < limit,
                      !bucket.isEmpty else {
                    continue
                }
                result[day, default: [:]][hour] = bucket
            }
        }
        return result
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
        let today = todayKey
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
            self.applyScreenTime(result)
        }
        screenTimeTask = task
    }

    private func applyScreenTime(
        _ result: Result<ScreenTimeUsage, ScreenTimeReadError>
    ) {
        switch result {
        case .success(let usage):
            // Newly read days replace their matching days, while older days
            // already saved by the app survive Apple's retention window.
            ScreenTimeArchiveMerger.merge(
                days: &rawScreenTimeDays,
                hours: &rawScreenTimeHours,
                with: usage
            )
            applyScreenTimeDayBoundary()
            if let stream = usage.stream {
                screenTimeStream = stream
            }
            screenTimeFetchedAt = usage.fetchedAt
            screenTimeAccess = .ready(
                dayCount: Self.activeAppDayCount(screenTimeDays),
                updatedAt: usage.fetchedAt
            )
            rebuildUsage()
            saveScreenTimeArchive()
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
            chromeDays: logicalChromeDays,
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

    public func categoryUsages(for entries: [SiteEntry]) -> [CategoryUsage] {
        var totals: [String: Int64] = [:]
        for entry in entries where entry.milliseconds > 0 {
            let entity = display(for: entry.site)
            let category = categoryStore.resolve(
                bundleID: entity.bundleID,
                domain: entry.site
            )
            let id = category?.id ?? CategoryStore.uncategorizedID
            totals[id, default: 0] += entry.milliseconds
        }

        var usages: [CategoryUsage] = []
        for (id, milliseconds) in totals where milliseconds > 0 {
            if let category = categoryStore.category(id: id) {
                usages.append(
                    CategoryUsage(
                        id: category.id,
                        name: category.name,
                        colorHex: category.colorHex,
                        milliseconds: milliseconds,
                        isUncategorized: false
                    )
                )
            } else {
                usages.append(
                    CategoryUsage(
                        id: CategoryStore.uncategorizedID,
                        name: CategoryStore.uncategorizedName,
                        colorHex: CategoryStore.uncategorizedColorHex,
                        milliseconds: milliseconds,
                        isUncategorized: true
                    )
                )
            }
        }

        return usages.sorted { left, right in
            if left.isUncategorized != right.isUncategorized {
                return !left.isUncategorized
            }
            if left.milliseconds == right.milliseconds {
                return left.name < right.name
            }
            return left.milliseconds > right.milliseconds
        }
    }

    public var dayCategoryUsages: [CategoryUsage] {
        categoryUsages(for: entries)
    }

    public func categoryUsages(forDay day: String) -> [CategoryUsage] {
        categoryUsages(for: snapshot?.entries(for: day) ?? [])
    }

    public func categoryUsages(forDays days: [String]) -> [CategoryUsage] {
        categoryUsages(
            for: snapshot?.aggregatedEntries(over: days) ?? []
        )
    }

    public func categoryUsages(
        forMonthStart monthStart: String
    ) -> [CategoryUsage] {
        categoryUsages(
            forDays: CalendarDay.monthDayKeys(containing: monthStart)
        )
    }

    public var categoryRuleTargets: [CategoryRuleTarget] {
        guard let snapshot else { return [] }
        let entries = snapshot.aggregatedEntries(
            over: Array(snapshot.days.keys)
        )
        var targets: [String: CategoryRuleTarget] = [:]

        for entry in entries where entry.milliseconds > 0 {
            let entity = display(for: entry.site)
            let target: CategoryRuleTarget

            if let bundleID = entity.bundleID, !bundleID.isEmpty {
                target = CategoryRuleTarget(
                    kind: .app,
                    identifier: bundleID,
                    name: entity.name,
                    detail: entity.detail,
                    milliseconds: entry.milliseconds
                )
            } else {
                target = CategoryRuleTarget(
                    kind: .domain,
                    identifier: entry.site,
                    name: entry.site,
                    detail: "网站",
                    milliseconds: entry.milliseconds
                )
            }

            if var existing = targets[target.id] {
                existing.milliseconds += target.milliseconds
                if existing.detail == nil || existing.detail == "App" {
                    existing.detail = target.detail
                }
                targets[target.id] = existing
            } else {
                targets[target.id] = target
            }
        }

        return targets.values.sorted { left, right in
            if left.milliseconds == right.milliseconds {
                return left.name.localizedStandardCompare(right.name)
                    == .orderedAscending
            }
            return left.milliseconds > right.milliseconds
        }
    }

    // MARK: - Day chart

    public func setDayChartMode(_ mode: DayChartMode) {
        dayChartMode = mode
    }

    /// Maps an x-axis index (0 = the configured start of day) to the actual
    /// local clock hour shown on the hourly chart's axis.
    public func clockHour(forAxisIndex index: Int) -> Int {
        let offset = ((dayStartHour + index) % 24 + 24) % 24
        return offset
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
        return (0...23).map { axisIndex in
            let hour = clockHour(forAxisIndex: axisIndex)
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
            return DayHourBar(
                hour: hour,
                milliseconds: total,
                axisIndex: axisIndex
            )
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

    public var dayHourlyCategorySlices: [DayHourCategorySlice] {
        dayHourlyCategorySlices(for: selectedDay)
    }

    public func dayHourlyCategorySlices(
        for day: String
    ) -> [DayHourCategorySlice] {
        let buckets = screenTimeHours[day] ?? [:]
        guard !buckets.isEmpty else { return [] }

        let allowed = allowedHourlyBundles
        let chromeWeights = chromeCategoryWeights(for: day)
        var totals: [Int: [String: Int64]] = [:]

        for hour in 0...23 {
            for (bundleID, milliseconds) in buckets[hour] ?? [:]
            where milliseconds > 0 {
                if ScreenTimeFilter.isChromeUsage(bundleID) {
                    distributeChromeHour(
                        milliseconds,
                        weights: chromeWeights,
                        into: &totals[hour, default: [:]]
                    )
                } else if ScreenTimeFilter.isExcluded(bundleID) {
                    continue
                } else if allowed.contains(bundleID) {
                    totals[hour, default: [:]][
                        hourlyCategoryID(for: bundleID),
                        default: 0
                    ] += milliseconds
                }
            }
        }

        let orderedCategories = categoryUsages(forDay: day)
        let order = Dictionary(
            uniqueKeysWithValues: orderedCategories.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )

        var slices: [DayHourCategorySlice] = []
        for axisIndex in 0...23 {
            let hour = clockHour(forAxisIndex: axisIndex)
            for (categoryID, milliseconds) in totals[hour] ?? [:]
            where milliseconds > 0 {
                let meta = categoryMetadata(id: categoryID)
                slices.append(
                    DayHourCategorySlice(
                        hour: hour,
                        axisIndex: axisIndex,
                        categoryID: categoryID,
                        categoryName: meta.name,
                        colorHex: meta.colorHex,
                        milliseconds: milliseconds,
                        isUncategorized: meta.isUncategorized
                    )
                )
            }
        }

        return slices.sorted { left, right in
            if left.axisIndex != right.axisIndex {
                return left.axisIndex < right.axisIndex
            }
            let leftOrder = order[left.categoryID] ?? Int.max
            let rightOrder = order[right.categoryID] ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return left.categoryID < right.categoryID
        }
    }

    /// Maps an hourly app bundle to its category. A mapped app uses its app
    /// rule first, then a domain rule only when every mapped domain agrees.
    private func hourlyCategoryID(for bundleID: String) -> String {
        if let category = categoryStore.category(forBundleID: bundleID) {
            return category.id
        }
        let domainCategoryIDs = Set(
            mappingStore.effectiveMappings
                .filter { $0.bundleID == bundleID }
                .compactMap {
                    categoryStore.category(forDomain: $0.domain)?.id
                }
        )
        if domainCategoryIDs.count == 1,
           let categoryID = domainCategoryIDs.first {
            return categoryID
        }
        return CategoryStore.uncategorizedID
    }

    /// Screen Time only exposes Chrome as one aggregate bundle. Split each
    /// hourly Chrome slot using the categories of that day's recorded Chrome
    /// domains, plus the Chrome-unaccounted remainder.
    private func chromeCategoryWeights(
        for day: String
    ) -> [String: Int64] {
        var weights: [String: Int64] = [:]
        var domainTotal: Int64 = 0

        for (domain, milliseconds) in logicalChromeDays[day] ?? [:]
        where milliseconds > 0 {
            domainTotal += milliseconds
            let mappedBundleID = mappingStore.effectiveMappings.first {
                $0.domain == domain
            }?.bundleID
            let category = mappedBundleID.flatMap {
                categoryStore.category(forBundleID: $0)
            } ?? categoryStore.category(forDomain: domain)
            weights[
                category?.id ?? CategoryStore.uncategorizedID,
                default: 0
            ] += milliseconds
        }

        let chromeTotal = (screenTimeDays[day] ?? [:]).reduce(
            Int64(0)
        ) { partial, pair in
            guard ScreenTimeFilter.isChromeUsage(pair.key) else {
                return partial
            }
            return partial + max(0, pair.value)
        }
        let gap = chromeTotal - domainTotal
        if gap >= ChromeGap.minimumMilliseconds {
            let categoryID = categoryStore.category(
                forBundleID: "com.google.Chrome"
            )?.id ?? CategoryStore.uncategorizedID
            weights[categoryID, default: 0] += gap
        }

        if weights.isEmpty, chromeTotal > 0 {
            let categoryID = categoryStore.category(
                forBundleID: "com.google.Chrome"
            )?.id ?? CategoryStore.uncategorizedID
            weights[categoryID] = chromeTotal
        }
        return weights
    }

    private func distributeChromeHour(
        _ milliseconds: Int64,
        weights: [String: Int64],
        into totals: inout [String: Int64]
    ) {
        let entries = weights
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
        let totalWeight = entries.reduce(Int64(0)) { $0 + $1.value }

        guard totalWeight > 0 else {
            totals[CategoryStore.uncategorizedID, default: 0] += milliseconds
            return
        }

        var allocated: Int64 = 0
        for (index, entry) in entries.enumerated() {
            let portion: Int64
            if index == entries.count - 1 {
                portion = milliseconds - allocated
            } else {
                portion = Int64(
                    Double(milliseconds)
                        * Double(entry.value)
                        / Double(totalWeight)
                )
            }
            allocated += portion
            if portion > 0 {
                totals[entry.key, default: 0] += portion
            }
        }
    }

    private func categoryMetadata(
        id: String
    ) -> (name: String, colorHex: String, isUncategorized: Bool) {
        if let category = categoryStore.category(id: id) {
            return (category.name, category.colorHex, false)
        }
        return (
            CategoryStore.uncategorizedName,
            CategoryStore.uncategorizedColorHex,
            true
        )
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
            let entity = display(for: entry.site)
            let category = categoryStore.resolve(
                bundleID: entity.bundleID,
                domain: entry.site
            )
            return DayItemBar(
                id: entry.site,
                name: entity.name,
                milliseconds: entry.milliseconds,
                categoryColorHex: category?.colorHex
                    ?? CategoryStore.uncategorizedColorHex
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
        selectedDay == todayKey
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
            return DateText.dayLabel(
                selectedDay,
                startHour: dayStartHour
            )
        case .week:
            return DateText.weekRangeLabel(
                CalendarDay.weekDayKeys(containing: selectedDay),
                startHour: dayStartHour
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
            return DateText.relativeTag(
                selectedDay,
                startHour: dayStartHour
            )
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
            for: todayKey,
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
            for: todayKey,
            mode: viewMode
        ) else {
            return false
        }
        return currentStart < todayStart
    }

    public func setViewMode(_ mode: StatsRange) {
        viewMode = mode
        if followToday {
            selectedDay = todayKey
        }
    }

    public func goToCurrentPeriod() {
        selectedDay = todayKey
        followToday = true
    }

    public func shiftPeriod(by delta: Int) {
        guard delta != 0 else { return }

        let today = todayKey
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
        let today = todayKey
        if day > today {
            goToCurrentPeriod()
            return
        }
        selectedDay = day
        followToday = day == today
    }

    public func openDay(_ day: String) {
        guard CalendarDay.date(from: day) != nil,
              day <= todayKey else {
            return
        }
        selectedDay = day
        viewMode = .day
        followToday = day == todayKey
    }

    public func openMonth(_ monthStart: String) {
        guard CalendarDay.date(from: monthStart) != nil else { return }

        let today = todayKey
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
        let today = todayKey
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
        let today = todayKey
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
