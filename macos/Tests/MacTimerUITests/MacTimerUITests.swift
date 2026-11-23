import AppKit
import Foundation
import XCTest
@testable import MacTimerCore
@testable import MacTimerUI

@MainActor
final class MacTimerUITests: XCTestCase {
    func testAppearanceAppliesDarkLightAndResetsToSystem() {
        AppearanceMode.apply(.dark)
        XCTAssertEqual(
            NSApplication.shared.appearance?.name,
            NSAppearance.Name.darkAqua
        )

        AppearanceMode.apply(.light)
        XCTAssertEqual(
            NSApplication.shared.appearance?.name,
            NSAppearance.Name.aqua
        )

        AppearanceMode.apply(.system)
        XCTAssertNil(NSApplication.shared.appearance)
    }

    func testMappingStoreOverridesBuiltInAndPersists() throws {
        let suite = "MacTimerUITests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MappingStore(defaults: defaults)
        XCTAssertTrue(store.customMappings.isEmpty)

        let mapping = try store.addMapping(
            domainInput: "https://www.bilibili.com/video/BV1",
            bundleID: "com.example.demo",
            appName: "Demo"
        )
        XCTAssertEqual(mapping.domain, "bilibili.com")
        XCTAssertEqual(
            store.effectiveMappings.first {
                $0.domain == "bilibili.com"
            }?.bundleID,
            "com.example.demo"
        )
        XCTAssertTrue(store.isCustomized(domain: "bilibili.com"))

        let reloaded = MappingStore(defaults: defaults)
        XCTAssertEqual(reloaded.customMappings, [mapping])

        reloaded.removeMapping(domain: "bilibili.com")
        XCTAssertNil(reloaded.customMapping(for: "bilibili.com"))
        XCTAssertEqual(
            reloaded.builtInMapping(for: "bilibili.com")?.bundleID,
            "com.bilibili.bilibiliPC"
        )

        let reloadedAgain = MappingStore(defaults: defaults)
        XCTAssertTrue(reloadedAgain.customMappings.isEmpty)
    }

    func testMappingStoreRejectsInvalidInputAndBrowsers() {
        let store = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )

        XCTAssertThrowsError(
            try store.addMapping(
                domainInput: "bilibili.com",
                bundleID: "com.google.Chrome",
                appName: "Chrome"
            )
        ) { error in
            XCTAssertEqual(
                error as? MappingValidationError,
                .browserUnsupported
            )
        }

        XCTAssertThrowsError(
            try store.addMapping(
                domainInput: "not a domain",
                bundleID: "com.example.demo",
                appName: "Demo"
            )
        ) { error in
            XCTAssertEqual(
                error as? MappingValidationError,
                .invalidDomain
            )
        }

        XCTAssertTrue(store.customMappings.isEmpty)
    }

    func testHourlyChartIncludesChromeAndMappedAppsOnly() throws {
        let store = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try store.addMapping(
            domainInput: "example.com",
            bundleID: "com.example.mapped",
            appName: "Mapped"
        )

        let day = CalendarDay.today()
        let screenTime = ScreenTimeUsage(
            days: [
                day: [
                    "com.example.mapped": 20 * 60_000,
                    "com.google.Chrome": 30 * 60_000,
                    "com.apple.finder": 5 * 60_000,
                    "com.unknown.helper": 7 * 60_000,
                ],
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            stream: "/app/usage",
            eventCount: 4,
            hours: [
                day: [
                    9: [
                        "com.example.mapped": 10 * 60_000,
                        "com.google.Chrome": 5 * 60_000,
                        "com.apple.finder": 5 * 60_000,
                        "com.unknown.helper": 7 * 60_000,
                    ],
                    10: [
                        "com.example.mapped": 10 * 60_000,
                        "com.google.Chrome": 25 * 60_000,
                    ],
                ],
            ]
        )
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [day: ["example.com": 5 * 60_000]]
            ),
            initialScreenTime: screenTime,
            mappingStore: store,
            categoryStore: CategoryStore(defaults: nil, load: false),
            autoRefresh: false
        )

        XCTAssertEqual(model.dayHourlyBars.count, 24)
        XCTAssertEqual(model.dayHourlyBars[9].milliseconds, 15 * 60_000)
        XCTAssertEqual(model.dayHourlyBars[10].milliseconds, 35 * 60_000)
        XCTAssertTrue(model.dayHasHourlyData)
        XCTAssertEqual(model.dayHourlyPeak?.hour, 10)
        XCTAssertEqual(
            model.dayHourlyTotalMilliseconds,
            50 * 60_000
        )
        XCTAssertTrue(
            model.dayChartItems.contains {
                $0.name == "Chrome（未记录）"
            }
        )
        XCTAssertEqual(model.dayChartMode, .hourly)
        model.setDayChartMode(.items)
        XCTAssertEqual(model.dayChartMode, .items)

        model.setDayChartMode(.category)
        XCTAssertEqual(model.dayChartMode, .category)
        XCTAssertEqual(model.dayCategoryUsages.count, 1)
        XCTAssertEqual(
            model.dayCategoryUsages.first?.name,
            CategoryStore.uncategorizedName
        )
        XCTAssertEqual(
            model.dayCategoryUsages.first?.milliseconds,
            50 * 60_000
        )
    }

    func testDayChartFallsBackToItemsWithoutHourlyData() {
        let day = CalendarDay.today()
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [day: ["example.com": 5 * 60_000]]
            ),
            mappingStore: MappingStore(
                builtIns: [],
                defaults: nil,
                loadCustom: false
            ),
            categoryStore: CategoryStore(defaults: nil, load: false),
            autoRefresh: false
        )

        XCTAssertEqual(model.dayChartMode, .hourly)
        XCTAssertFalse(model.dayHasHourlyData)
        XCTAssertTrue(model.dayChartUsesFallback)
        XCTAssertEqual(model.dayChartItems.count, 1)
        XCTAssertEqual(model.dayChartItems.first?.name, "example.com")
    }

    func testDashboardModelMergesMappedWebsiteAndAppUsage() throws {
        let store = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try store.addMapping(
            domainInput: "bilibili.com",
            bundleID: "com.example.demo",
            appName: "Demo App"
        )

        let day = CalendarDay.today()
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [
                    day: [
                        "bilibili.com": 1_000,
                        "example.com": 500,
                    ],
                ]
            ),
            initialScreenTime: ScreenTimeUsage(
                days: [
                    day: [
                        "com.example.demo": 2_000,
                        "com.google.Chrome": 9_999,
                    ],
                ],
                fetchedAt: fetchedAt,
                stream: "/app/usage",
                eventCount: 2
            ),
            mappingStore: store,
            categoryStore: CategoryStore(defaults: nil, load: false),
            autoRefresh: false
        )

        XCTAssertEqual(model.snapshot?.total(for: day), 3_500)
        XCTAssertEqual(
            model.snapshot?.days[day]?["bilibili.com"],
            3_000
        )
        XCTAssertEqual(model.snapshot?.days[day]?["example.com"], 500)
        XCTAssertNil(model.snapshot?.days[day]?["com.google.Chrome"])

        let display = model.display(for: "bilibili.com")
        XCTAssertEqual(display.name, "Demo App")
        XCTAssertEqual(display.detail, "bilibili.com")
        XCTAssertEqual(display.bundleID, "com.example.demo")
        XCTAssertTrue(display.isApp)
        XCTAssertTrue(model.usesScreenTimeData)
        XCTAssertEqual(
            model.screenTimeAccess,
            .ready(dayCount: 1, updatedAt: fetchedAt)
        )
    }

    func testCategoryStoreCRUDRulesAndPersistence() throws {
        let suite = "MacTimerUITests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CategoryStore(defaults: defaults)
        XCTAssertEqual(
            store.categories.map(\.name),
            ["学习", "工作", "娱乐"]
        )
        XCTAssertTrue(store.rules.isEmpty)

        let reading = try store.addCategory(
            name: "阅读",
            colorHex: "#123456"
        )
        store.renameCategory(id: reading.id, name: "深度阅读")
        store.setColor(id: reading.id, colorHex: "#654321")
        XCTAssertEqual(store.category(id: reading.id)?.name, "深度阅读")
        XCTAssertEqual(store.category(id: reading.id)?.colorHex, "#654321")

        try store.addAppRule(
            bundleID: "com.example.reader",
            appName: "Reader",
            categoryID: reading.id
        )
        try store.addDomainRule(
            domainInput: "https://www.example.com/article",
            categoryID: "study"
        )
        XCTAssertEqual(
            store.category(forDomain: "example.com")?.id,
            "study"
        )
        XCTAssertEqual(
            store.resolve(
                bundleID: "com.example.reader",
                domain: "example.com"
            )?.id,
            reading.id
        )

        // Adding the same domain again replaces the old rule.
        try store.addDomainRule(
            domainInput: "example.com",
            categoryID: "work"
        )
        XCTAssertEqual(
            store.rules.filter {
                $0.kind == .domain && $0.identifier == "example.com"
            }.count,
            1
        )
        XCTAssertEqual(
            store.category(forDomain: "example.com")?.id,
            "work"
        )

        let reloaded = CategoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.categories.count, 4)
        XCTAssertEqual(reloaded.rules.count, 2)
        XCTAssertEqual(
            reloaded.category(id: reading.id)?.colorHex,
            "#654321"
        )
        XCTAssertEqual(
            reloaded.category(forBundleID: "com.example.reader")?.id,
            reading.id
        )

        reloaded.removeCategory(id: reading.id)
        XCTAssertNil(reloaded.category(id: reading.id))
        XCTAssertNil(reloaded.category(forBundleID: "com.example.reader"))

        let reloadedAgain = CategoryStore(defaults: defaults)
        XCTAssertEqual(reloadedAgain.categories.count, 3)
        XCTAssertEqual(reloadedAgain.rules.count, 1)

        reloadedAgain.removeRule(
            kind: .domain,
            identifier: "example.com"
        )
        XCTAssertNil(reloadedAgain.category(forDomain: "example.com"))
        XCTAssertTrue(
            CategoryStore(defaults: defaults).rules.isEmpty
        )
    }

    func testCategoryUsagesGroupAppAndDomainRulesWithUncategorizedLast() throws {
        let mappingStore = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try mappingStore.addMapping(
            domainInput: "bilibili.com",
            bundleID: "com.example.video",
            appName: "Video"
        )

        let categoryStore = CategoryStore(defaults: nil, load: false)
        try categoryStore.addDomainRule(
            domainInput: "bilibili.com",
            categoryID: "entertainment"
        )
        try categoryStore.addDomainRule(
            domainInput: "github.com",
            categoryID: "study"
        )
        try categoryStore.addAppRule(
            bundleID: "com.example.video",
            appName: "Video",
            categoryID: "work"
        )

        let day = CalendarDay.today()
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [
                    day: [
                        "bilibili.com": 5 * 60_000,
                        "github.com": 10 * 60_000,
                        "example.com": 30 * 60_000,
                    ],
                ]
            ),
            initialScreenTime: ScreenTimeUsage(
                days: [day: ["com.example.video": 20 * 60_000]],
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                stream: "/app/usage",
                eventCount: 1
            ),
            mappingStore: mappingStore,
            categoryStore: categoryStore,
            autoRefresh: false
        )

        let usages = model.categoryUsages(for: model.entries)
        XCTAssertEqual(
            usages.map(\.name),
            ["工作", "学习", "未分类"]
        )
        XCTAssertEqual(usages[0].milliseconds, 25 * 60_000)
        XCTAssertEqual(usages[1].milliseconds, 10 * 60_000)
        XCTAssertEqual(usages[2].milliseconds, 30 * 60_000)
        XCTAssertTrue(usages[2].isUncategorized)
        XCTAssertEqual(
            usages.reduce(Int64(0)) { $0 + $1.milliseconds },
            65 * 60_000
        )
    }

    func testHourlyCategorySlicesSplitAppsAndChromeByCategory() throws {
        let mappingStore = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try mappingStore.addMapping(
            domainInput: "example.com",
            bundleID: "com.example.mapped",
            appName: "Mapped"
        )

        let categoryStore = CategoryStore(defaults: nil, load: false)
        try categoryStore.addAppRule(
            bundleID: "com.example.mapped",
            appName: "Mapped",
            categoryID: "study"
        )
        try categoryStore.addDomainRule(
            domainInput: "other.com",
            categoryID: "work"
        )

        let day = CalendarDay.today()
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [
                    day: [
                        "example.com": 5 * 60_000,
                        "other.com": 10 * 60_000,
                    ],
                ]
            ),
            initialScreenTime: ScreenTimeUsage(
                days: [
                    day: [
                        "com.example.mapped": 20 * 60_000,
                        "com.google.Chrome": 30 * 60_000,
                    ],
                ],
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                stream: "/app/usage",
                eventCount: 2,
                hours: [
                    day: [
                        9: [
                            "com.example.mapped": 10 * 60_000,
                            "com.google.Chrome": 5 * 60_000,
                        ],
                        10: [
                            "com.example.mapped": 10 * 60_000,
                            "com.google.Chrome": 25 * 60_000,
                        ],
                    ],
                ]
            ),
            mappingStore: mappingStore,
            categoryStore: categoryStore,
            autoRefresh: false
        )

        let slices = model.dayHourlyCategorySlices
        XCTAssertEqual(
            slices.reduce(Int64(0)) { $0 + $1.milliseconds },
            50 * 60_000
        )

        var totals: [String: Int64] = [:]
        for slice in slices {
            totals[slice.categoryID, default: 0] += slice.milliseconds
        }
        XCTAssertEqual(totals["study"], 25 * 60_000)
        XCTAssertEqual(totals["work"], 10 * 60_000)
        XCTAssertEqual(
            totals[CategoryStore.uncategorizedID],
            15 * 60_000
        )
        XCTAssertEqual(Set(slices.map(\.hour)), [9, 10])
        XCTAssertEqual(
            slices.filter { $0.hour == 9 }
                .reduce(Int64(0)) { $0 + $1.milliseconds },
            15 * 60_000
        )
        XCTAssertEqual(
            slices.filter { $0.hour == 10 }
                .reduce(Int64(0)) { $0 + $1.milliseconds },
            35 * 60_000
        )
    }

    func testDayStartHourShiftsChromeAndScreenTimeHistory() throws {
        let mappingStore = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try mappingStore.addMapping(
            domainInput: "example.com",
            bundleID: "com.example.app",
            appName: "App"
        )

        let day = "2026-11-23"
        let next = "2026-11-24"
        let hour: Int64 = 60 * 60_000
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [
                    day: ["example.com": 5 * hour],
                    next: ["example.com": hour],
                ],
                earlyHours: [
                    day: ["0": ["example.com": hour]],
                    next: ["0": ["example.com": 30 * 60_000]],
                ]
            ),
            initialScreenTime: ScreenTimeUsage(
                days: [
                    day: ["com.example.app": 4 * hour],
                    next: ["com.example.app": 2 * hour],
                ],
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                stream: "/app/usage",
                eventCount: 2,
                hours: [
                    day: [
                        0: ["com.example.app": hour],
                        10: ["com.example.app": 3 * hour],
                    ],
                    next: [
                        0: ["com.example.app": 2 * hour],
                    ],
                ]
            ),
            mappingStore: mappingStore,
            categoryStore: CategoryStore(defaults: nil, load: false),
            dayStartHour: 4,
            autoRefresh: false
        )

        XCTAssertEqual(model.dayStartHour, 4)
        XCTAssertEqual(
            model.snapshot?.days[day]?["example.com"],
            9 * hour + 30 * 60_000
        )
        XCTAssertEqual(
            model.snapshot?.days[next]?["example.com"],
            30 * 60_000
        )
        let dayBars = model.dayHourlyBars(for: day)
        XCTAssertEqual(
            dayBars.reduce(Int64(0)) { $0 + $1.milliseconds },
            5 * hour
        )
        XCTAssertEqual(model.clockHour(forAxisIndex: 0), 4)
        XCTAssertEqual(model.clockHour(forAxisIndex: 20), 0)
        XCTAssertEqual(dayBars[6].hour, 10)
        XCTAssertEqual(dayBars[6].axisIndex, 6)
        XCTAssertEqual(dayBars[6].milliseconds, 3 * hour)
        XCTAssertEqual(dayBars[20].hour, 0)
        XCTAssertEqual(dayBars[20].axisIndex, 20)
        XCTAssertEqual(dayBars[20].milliseconds, 2 * hour)
        XCTAssertEqual(
            model.dayHourlyBars(for: next)
                .reduce(Int64(0)) { $0 + $1.milliseconds },
            0
        )

        let slices = model.dayHourlyCategorySlices(for: day)
        XCTAssertEqual(slices.map(\.axisIndex), [6, 20])
        XCTAssertEqual(slices.map(\.hour), [10, 0])
    }

    func testCategoryRuleTargetsUseAllRecordedDomainsAndApps() throws {
        let mappingStore = MappingStore(
            builtIns: [],
            defaults: nil,
            loadCustom: false
        )
        try mappingStore.addMapping(
            domainInput: "bilibili.com",
            bundleID: "com.example.video",
            appName: "Video"
        )

        let today = CalendarDay.today()
        let older = CalendarDay.lastDays(2).first ?? today
        let model = DashboardModel(
            initialSnapshot: UsageSnapshot(
                updatedAt: 1,
                days: [
                    today: [
                        "bilibili.com": 5 * 60_000,
                        "github.com": 10 * 60_000,
                    ],
                    older: ["old.example": 4 * 60_000],
                ]
            ),
            initialScreenTime: ScreenTimeUsage(
                days: [today: ["com.example.video": 20 * 60_000]],
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                stream: "/app/usage",
                eventCount: 1
            ),
            mappingStore: mappingStore,
            categoryStore: CategoryStore(defaults: nil, load: false),
            autoRefresh: false
        )

        let targets = model.categoryRuleTargets
        XCTAssertEqual(targets.count, 3)

        let app = try XCTUnwrap(targets.first { $0.kind == .app })
        XCTAssertEqual(app.identifier, "com.example.video")
        XCTAssertEqual(app.name, "Video")
        XCTAssertEqual(app.detail, "bilibili.com")
        XCTAssertEqual(app.milliseconds, 25 * 60_000)

        XCTAssertNotNil(
            targets.first {
                $0.kind == .domain && $0.identifier == "github.com"
            }
        )
        XCTAssertNotNil(
            targets.first {
                $0.kind == .domain && $0.identifier == "old.example"
            }
        )
    }
}
