import Foundation
import XCTest
@testable import MacTimerCore
@testable import MacTimerUI

@MainActor
final class MacTimerUITests: XCTestCase {
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
}
