import Foundation
import SQLite3
import XCTest
@testable import MacTimerCore

final class MacTimerCoreTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testCalendarDayRoundTrip() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 23
        components.hour = 14
        let date = try XCTUnwrap(calendar.date(from: components))

        let key = CalendarDay.key(for: date, calendar: calendar)
        XCTAssertEqual(key, "2026-11-23")
        XCTAssertNotNil(CalendarDay.date(from: key, calendar: calendar))
        XCTAssertEqual(CalendarDay.shifting(key, by: 1, calendar: calendar), "2026-11-24")
        XCTAssertEqual(CalendarDay.shifting(key, by: -30, calendar: calendar), "2026-10-24")
        XCTAssertNil(CalendarDay.date(from: "2026-02-30", calendar: calendar))
        XCTAssertNil(CalendarDay.date(from: "not-a-day", calendar: calendar))
    }

    func testLastDaysAreAscending() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 23
        let date = try XCTUnwrap(calendar.date(from: components))

        let days = CalendarDay.lastDays(4, endingAt: date, calendar: calendar)
        XCTAssertEqual(days, [
            "2026-11-20",
            "2026-11-21",
            "2026-11-22",
            "2026-11-23",
        ])
    }

    func testSnapshotTotalsAndSorting() {
        let snapshot = UsageSnapshot(days: [
            "2026-11-22": [
                "a.com": 1_000,
                "b.com": 5_000,
                "zero.com": 0,
                "negative.com": -10,
            ],
        ])

        let entries = snapshot.entries(for: "2026-11-22")
        XCTAssertEqual(entries.map(\.site), ["b.com", "a.com"])
        XCTAssertEqual(snapshot.total(for: "2026-11-22"), 6_000)
        XCTAssertEqual(snapshot.total(for: "2026-11-21"), 0)
    }

    func testMergeDeltaReplacesDayAndKeepsOtherDays() {
        let existing = UsageSnapshot(
            updatedAt: 1,
            days: [
                "2026-11-21": ["a.com": 1_000],
                "2026-11-22": ["a.com": 2_000],
            ]
        )
        let payload = NativeSyncPayload(
            type: "sync",
            sentAt: 2,
            reset: false,
            current: CurrentSession(site: "b.com", since: 3),
            days: [
                "2026-11-22": ["b.com": 4_000],
                "2026-11-23": ["c.com": 5_000, "zero.com": 0],
            ]
        )

        let merged = UsageMerger.merge(
            existing: existing,
            payload: payload,
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(merged.days["2026-11-21"], ["a.com": 1_000])
        XCTAssertEqual(merged.days["2026-11-22"], ["b.com": 4_000])
        XCTAssertEqual(merged.days["2026-11-23"], ["c.com": 5_000])
        XCTAssertEqual(merged.current, CurrentSession(site: "b.com", since: 3))
        XCTAssertEqual(merged.updatedAt, 1_700_000_000_000)
    }

    func testFullMergeResetsHistory() {
        let existing = UsageSnapshot(days: [
            "2026-11-21": ["a.com": 1_000],
        ])
        let payload = NativeSyncPayload(
            type: "sync",
            sentAt: 2,
            reset: true,
            current: nil,
            days: [
                "2026-11-22": ["b.com": 2_000],
                "not-a-day": ["bad.com": 9_000],
            ]
        )

        let merged = UsageMerger.merge(existing: existing, payload: payload)
        XCTAssertEqual(merged.days, ["2026-11-22": ["b.com": 2_000]])
        XCTAssertNil(merged.current)
    }

    func testStoreRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = UsageSnapshotStore(
            fileURL: folder.appendingPathComponent("usage.json")
        )
        let snapshot = UsageSnapshot(
            updatedAt: 123,
            current: CurrentSession(site: "a.com", since: 100),
            days: [
                "2026-11-22": ["a.com": 1_500],
                "2026-11-23": ["b.com": 2_500],
            ]
        )

        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
    }

    func testDecodesHostJSONWithoutCurrent() throws {
        let json = #"""
        {
          "days" : {
            "2026-11-23" : { "a.com" : 1200 }
          },
          "updatedAt" : 1795364615376,
          "version" : 1
        }
        """#
        let snapshot = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(snapshot.current)
        XCTAssertEqual(snapshot.total(for: "2026-11-23"), 1200)
    }

    func testMondayFirstWeekBoundaries() {
        let calendar = utcCalendar()
        XCTAssertEqual(
            CalendarDay.weekStartKey(
                containing: "2026-11-23",
                calendar: calendar
            ),
            "2026-11-23"
        )
        XCTAssertEqual(
            CalendarDay.weekDayKeys(
                containing: "2026-11-22",
                calendar: calendar
            ),
            [
                "2026-11-16",
                "2026-11-17",
                "2026-11-18",
                "2026-11-19",
                "2026-11-20",
                "2026-11-21",
                "2026-11-22",
            ]
        )
        XCTAssertEqual(
            CalendarDay.weekStartKey(
                containing: "2026-11-01",
                calendar: calendar
            ),
            "2026-10-26"
        )
    }

    func testMonthGridAndYearKeys() {
        let calendar = utcCalendar()

        let monthDays = CalendarDay.monthDayKeys(
            containing: "2026-11-15",
            calendar: calendar
        )
        XCTAssertEqual(monthDays.count, 30)
        XCTAssertEqual(monthDays.first, "2026-11-01")
        XCTAssertEqual(monthDays.last, "2026-11-30")

        let grid = CalendarDay.monthGridKeys(
            containing: "2026-11-15",
            calendar: calendar
        )
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(grid.first, "2026-10-26")
        XCTAssertEqual(grid.last, "2026-12-06")

        let months = CalendarDay.yearMonthKeys(
            containing: "2026-11-15",
            calendar: calendar
        )
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, "2026-01-01")
        XCTAssertEqual(months.last, "2026-12-01")

        let days = CalendarDay.yearDayKeys(
            containing: "2026-11-15",
            calendar: calendar
        )
        XCTAssertEqual(days.count, 365)
        XCTAssertEqual(days.first, "2026-01-01")
        XCTAssertEqual(days.last, "2026-12-31")

        XCTAssertEqual(
            CalendarDay.yearDayKeys(
                containing: "2024-06-01",
                calendar: calendar
            ).count,
            366
        )
    }

    func testPeriodShifting() {
        let calendar = utcCalendar()
        XCTAssertEqual(
            CalendarDay.shiftingMonths(
                "2026-11-23",
                by: 1,
                calendar: calendar
            ),
            "2026-12-23"
        )
        XCTAssertEqual(
            CalendarDay.shiftingMonths(
                "2026-01-31",
                by: 1,
                calendar: calendar
            ),
            "2026-02-28"
        )
        XCTAssertEqual(
            CalendarDay.shiftingYears(
                "2026-11-23",
                by: -1,
                calendar: calendar
            ),
            "2025-11-23"
        )
    }

    func testAggregationOverMultipleDays() {
        let snapshot = UsageSnapshot(days: [
            "2026-11-21": ["a.com": 1_000],
            "2026-11-22": ["a.com": 2_000, "b.com": 3_000],
            "2026-11-23": ["b.com": 1_000],
        ])
        let days = ["2026-11-21", "2026-11-22", "2026-11-23"]

        XCTAssertEqual(
            snapshot.aggregatedEntries(over: days),
            [
                SiteEntry(site: "b.com", milliseconds: 4_000),
                SiteEntry(site: "a.com", milliseconds: 3_000),
            ]
        )
        XCTAssertEqual(snapshot.totalOver(days), 7_000)
        XCTAssertEqual(snapshot.activeDayCount(over: days), 3)
        XCTAssertEqual(snapshot.bestDay(over: days)?.day, "2026-11-22")
        XCTAssertEqual(snapshot.bestDay(over: days)?.milliseconds, 5_000)
    }

    func testCompactDuration() {
        XCTAssertEqual(DurationText.compact(milliseconds: 0), "0")
        XCTAssertEqual(DurationText.compact(milliseconds: 30_000), "<1m")
        XCTAssertEqual(DurationText.compact(milliseconds: 60_000), "1m")
        XCTAssertEqual(DurationText.compact(milliseconds: 3_600_000), "1h")
        XCTAssertEqual(
            DurationText.compact(milliseconds: (2 * 60 + 14) * 60_000),
            "2h14"
        )
        XCTAssertEqual(
            DurationText.compact(milliseconds: (10 * 60 + 5) * 60_000),
            "10h"
        )
    }

    func testFormatting() {
        XCTAssertEqual(DurationText.string(milliseconds: 0), "0 秒")
        XCTAssertEqual(DurationText.string(milliseconds: 59_900), "59 秒")
        XCTAssertEqual(DurationText.string(milliseconds: 60_000), "1 分钟")
        XCTAssertEqual(DurationText.string(milliseconds: 3_600_000), "1 小时")
        XCTAssertEqual(DurationText.string(milliseconds: 3_660_000), "1 小时 1 分")
        XCTAssertEqual(DurationText.axisLabel(hours: 0), "0")
        XCTAssertEqual(DurationText.axisLabel(hours: 0.25 / 60), "15s")
        XCTAssertEqual(DurationText.axisLabel(hours: 0.5), "30m")
        XCTAssertEqual(DurationText.axisLabel(hours: 2), "2h")
    }

    // MARK: - Domain normalization and mappings

    func testDomainNormalizationMatchesExtensionGrouping() {
        XCTAssertEqual(
            DomainName.normalize("www.bilibili.com"),
            "bilibili.com"
        )
        XCTAssertEqual(
            DomainName.normalize("https://music.youtube.com/watch?v=1"),
            "youtube.com"
        )
        XCTAssertEqual(
            DomainName.normalize("https://mail.google.com/mail/u/0"),
            "google.com"
        )
        XCTAssertEqual(
            DomainName.normalize("example.co.uk/path"),
            "example.co.uk"
        )
        XCTAssertEqual(
            DomainName.normalize("http://localhost:3000/path"),
            "localhost"
        )
        XCTAssertEqual(DomainName.normalize("127.0.0.1"), "127.0.0.1")
        XCTAssertEqual(DomainName.normalize("bilibili.com/path"), "bilibili.com")
        XCTAssertNil(DomainName.normalize("  "))
        XCTAssertNil(DomainName.normalize("not a domain"))
    }

    func testBuiltInAndBrowserFilters() {
        XCTAssertTrue(
            DomainAppMapping.builtIns.contains {
                $0.domain == "bilibili.com"
                    && $0.bundleID == "com.bilibili.bilibiliPC"
            }
        )
        XCTAssertTrue(ScreenTimeFilter.isExcluded("com.google.Chrome"))
        XCTAssertTrue(
            ScreenTimeFilter.isExcluded(
                "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml"
            )
        )
        XCTAssertTrue(
            ScreenTimeFilter.isExcluded("com.muyuchen.mactimer")
        )
        XCTAssertTrue(ScreenTimeFilter.isExcluded("com.apple.finder"))
        XCTAssertFalse(ScreenTimeFilter.isExcluded("com.tencent.xinWeChat"))
        XCTAssertTrue(ScreenTimeFilter.isBrowser("com.apple.Safari"))
        XCTAssertFalse(ScreenTimeFilter.isBrowser("com.tencent.xinWeChat"))
        XCTAssertTrue(ScreenTimeFilter.isChromeUsage("com.google.Chrome"))
        XCTAssertTrue(
            ScreenTimeFilter.isChromeUsage(
                "com.google.Chrome.app.agimnkijcaahngcdmfeangaknmldooml"
            )
        )
        XCTAssertFalse(ScreenTimeFilter.isChromeUsage("com.google.Chrome.helper"))
        XCTAssertFalse(ScreenTimeFilter.isChromeUsage("com.apple.Safari"))
    }

    func testMergeCombinesDomainsAndAppsWithoutDoubleCounting() {
        let bilibili = DomainAppMapping(
            domain: "bilibili.com",
            bundleID: "com.bilibili.bilibiliPC",
            appName: "B站"
        )
        let bilibiliShort = DomainAppMapping(
            domain: "b23.tv",
            bundleID: "com.bilibili.bilibiliPC",
            appName: "B站"
        )
        let steam = DomainAppMapping(
            domain: "steampowered.com",
            bundleID: "com.valvesoftware.steam",
            appName: "Steam"
        )
        let chromeMapping = DomainAppMapping(
            domain: "example.com",
            bundleID: "com.google.Chrome",
            appName: "Chrome"
        )

        let merged = UsageMerge.build(
            chromeDays: [
                "2026-11-20": [
                    "bilibili.com": 10 * 60_000,
                    "b23.tv": 1 * 60_000,
                    "steampowered.com": 5 * 60_000,
                    "example.com": 3 * 60_000,
                    "github.com": 2 * 60_000,
                ],
            ],
            screenTimeDays: [
                "2026-11-20": [
                    "com.bilibili.bilibiliPC": 20 * 60_000,
                    "com.valvesoftware.steam": 15 * 60_000,
                    "com.tencent.xinWeChat": 7 * 60_000,
                    "com.google.Chrome": 22 * 60_000,
                    "unknown.helper": 5 * 60_000,
                ],
            ],
            mappings: [bilibili, bilibiliShort, steam, chromeMapping],
            appNames: [
                "com.bilibili.bilibiliPC": "哔哩哔哩",
                "com.valvesoftware.steam": "Steam",
                "com.tencent.xinWeChat": "微信",
                "com.google.Chrome": "Google Chrome",
            ]
        )

        let expectedDay: [String: Int64] = [
            "b23.tv": 31 * 60_000,
            "steampowered.com": 20 * 60_000,
            "example.com": 3 * 60_000,
            "github.com": 2 * 60_000,
            "app:com.tencent.xinWeChat": 7 * 60_000,
        ]
        XCTAssertEqual(merged.days["2026-11-20"], expectedDay)

        let expectedBilibili = UsageEntityDisplay(
            name: "哔哩哔哩",
            detail: "b23.tv · bilibili.com",
            bundleID: "com.bilibili.bilibiliPC",
            isApp: true
        )
        XCTAssertEqual(merged.displays["b23.tv"], expectedBilibili)
        XCTAssertEqual(
            merged.displays["steampowered.com"]?.detail,
            "steampowered.com"
        )

        let expectedWeChat = UsageEntityDisplay(
            name: "微信",
            detail: "App",
            bundleID: "com.tencent.xinWeChat",
            isApp: true
        )
        XCTAssertEqual(
            merged.displays["app:com.tencent.xinWeChat"],
            expectedWeChat
        )
        XCTAssertNil(merged.displays["com.google.Chrome"])
        XCTAssertEqual(merged.displays["example.com"]?.isApp, false)
    }

    func testMergeKeepsAppOnlyMappedDomainAndSkipsExcludedMapping() {
        let netflix = DomainAppMapping(
            domain: "netflix.com",
            bundleID: "com.netflix.Netflix",
            appName: "Netflix"
        )
        let merged = UsageMerge.build(
            chromeDays: [
                "2026-11-20": ["example.com": 3_000],
            ],
            screenTimeDays: [
                "2026-11-20": [
                    "com.netflix.Netflix": 9_000,
                    "com.google.Chrome": 50_000,
                ],
            ],
            mappings: [
                netflix,
                DomainAppMapping(
                    domain: "example.com",
                    bundleID: "com.google.Chrome",
                    appName: "Chrome"
                ),
            ],
            appNames: ["com.netflix.Netflix": "Netflix"]
        )

        XCTAssertEqual(merged.days["2026-11-20"]?["netflix.com"], 9_000)
        XCTAssertEqual(merged.days["2026-11-20"]?["example.com"], 3_000)
        XCTAssertEqual(merged.days["2026-11-20"]?.count, 2)
        XCTAssertEqual(merged.displays["example.com"]?.name, "example.com")
        XCTAssertEqual(merged.displays["netflix.com"]?.name, "Netflix")
    }

    func testChromeGapUsesThreeMinuteThresholdAndChromePWA() {
        let day = "2026-11-20"
        let merged = UsageMerge.build(
            chromeDays: [
                day: [
                    "a.com": 10 * 60_000,
                    "b.com": 5 * 60_000,
                ],
                "2026-11-21": [
                    "a.com": 10 * 60_000,
                ],
                "2026-11-22": [
                    "a.com": 10 * 60_000,
                ],
            ],
            screenTimeDays: [
                day: [
                    "com.google.Chrome": 23 * 60_000,
                    "com.google.Chrome.app.pwa": 2 * 60_000,
                    "com.tencent.xinWeChat": 7 * 60_000,
                ],
                "2026-11-21": [
                    "com.google.Chrome": 12 * 60_000,
                ],
                "2026-11-22": [
                    "com.google.Chrome": 13 * 60_000,
                ],
            ],
            mappings: [],
            appNames: ["com.tencent.xinWeChat": "微信"]
        )

        XCTAssertEqual(
            merged.days[day]?[ChromeGap.entityKey],
            10 * 60_000
        )
        XCTAssertEqual(
            merged.days["2026-11-21"]?[ChromeGap.entityKey],
            nil
        )
        XCTAssertEqual(
            merged.days["2026-11-22"]?[ChromeGap.entityKey],
            ChromeGap.minimumMilliseconds
        )
        XCTAssertEqual(
            merged.displays[ChromeGap.entityKey],
            ChromeGap.display
        )
        XCTAssertEqual(
            merged.days[day]?["app:com.tencent.xinWeChat"],
            7 * 60_000
        )
    }

    // MARK: - Screen Time reader

    func testScreenTimeReaderSplitsAcrossMidnightAndPrefersUsageStream()
        throws {
        let calendar = utcCalendar()
        let since = try XCTUnwrap(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 11,
                day: 20,
                hour: 0
            )
        ))
        let now = try XCTUnwrap(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 11,
                day: 21,
                hour: 20
            )
        ))
        let eventStart = try XCTUnwrap(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 11,
                day: 20,
                hour: 10
            )
        ))
        let eventEnd = eventStart.addingTimeInterval(3_600)
        let crossStart = try XCTUnwrap(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 11,
                day: 20,
                hour: 23,
                minute: 50
            )
        ))
        let crossEnd = crossStart.addingTimeInterval(20 * 60)
        let morningStart = try XCTUnwrap(calendar.date(
            from: DateComponents(
                year: 2026,
                month: 11,
                day: 21,
                hour: 9
            )
        ))
        let morningEnd = morningStart.addingTimeInterval(30 * 60)

        let url = try makeKnowledgeDB(events: [
            ("/app/inFocus", "com.infocus.only", crossStart, crossEnd),
            ("/app/usage", "com.example.a", eventStart, eventEnd),
            ("/app/usage", "com.example.b", crossStart, crossEnd),
            ("/app/usage", "com.example.a", morningStart, morningEnd),
        ])
        defer { try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        ) }

        let usage = try ScreenTimeReader(databaseURL: url).read(
            since: since,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(usage.stream, "/app/usage")
        XCTAssertEqual(usage.eventCount, 3)
        XCTAssertEqual(
            usage.days["2026-11-20"],
            [
                "com.example.a": 3_600_000,
                "com.example.b": 10 * 60_000,
            ]
        )
        XCTAssertEqual(
            usage.days["2026-11-21"],
            [
                "com.example.b": 10 * 60_000,
                "com.example.a": 30 * 60_000,
            ]
        )
        XCTAssertEqual(
            usage.hours["2026-11-20"]?[10]?["com.example.a"],
            60 * 60_000
        )
        XCTAssertEqual(
            usage.hours["2026-11-20"]?[23]?["com.example.b"],
            10 * 60_000
        )
        XCTAssertEqual(
            usage.hours["2026-11-21"]?[0]?["com.example.b"],
            10 * 60_000
        )
        XCTAssertEqual(
            usage.hours["2026-11-21"]?[9]?["com.example.a"],
            30 * 60_000
        )
    }

    func testScreenTimeReaderFallsBackToInFocus() throws {
        let calendar = utcCalendar()
        let since = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 20)
        ))
        let start = since.addingTimeInterval(12 * 3_600)
        let end = start.addingTimeInterval(15 * 60)
        let now = since.addingTimeInterval(24 * 3_600)

        let url = try makeKnowledgeDB(events: [
            ("/app/inFocus", "com.example.only", start, end),
        ])
        defer { try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        ) }

        let usage = try ScreenTimeReader(databaseURL: url).read(
            since: since,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(usage.stream, "/app/inFocus")
        XCTAssertEqual(
            usage.days["2026-11-20"]?["com.example.only"],
            15 * 60_000
        )
    }

    func testScreenTimeReaderHonorsPreferredStream() throws {
        let calendar = utcCalendar()
        let since = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 20)
        ))
        let start = since.addingTimeInterval(10 * 3_600)
        let now = since.addingTimeInterval(24 * 3_600)
        let url = try makeKnowledgeDB(events: [
            ("/app/usage", "com.example.usage", start, start + 60),
            ("/app/inFocus", "com.example.focus", start, start + 120),
        ])
        defer { try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        ) }

        let usage = try ScreenTimeReader(databaseURL: url).read(
            since: since,
            now: now,
            preferredStream: "/app/inFocus",
            calendar: calendar
        )

        XCTAssertEqual(usage.stream, "/app/inFocus")
        XCTAssertEqual(usage.days["2026-11-20"]?["com.example.focus"], 120_000)
        XCTAssertNil(usage.days["2026-11-20"]?["com.example.usage"])
    }

    func testScreenTimeReaderMissingDatabaseAndSchema() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("knowledgeC.db")
        XCTAssertThrowsError(
            try ScreenTimeReader(databaseURL: missing).read(
                since: Date(timeIntervalSinceReferenceDate: 0),
                now: Date(timeIntervalSinceReferenceDate: 10)
            )
        ) { error in
            guard let readError = error as? ScreenTimeReadError,
                  case .databaseNotFound = readError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("knowledgeC.db")
        try executeSQL(
            at: url,
            sql: "CREATE TABLE ZOBJECT (ZSTREAMNAME TEXT);"
        )

        XCTAssertThrowsError(
            try ScreenTimeReader(databaseURL: url).read(
                since: Date(timeIntervalSinceReferenceDate: 0),
                now: Date(timeIntervalSinceReferenceDate: 10)
            )
        ) { error in
            guard let readError = error as? ScreenTimeReadError,
                  case .schemaUnsupported = readError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testScreenTimeArchiveRoundTripAndMerger() throws {
        let day = "2026-11-23"
        let olderDay = "2026-10-30"
        let days: [String: [String: Int64]] = [
            olderDay: ["com.example.old": 10 * 60_000],
            day: ["com.example.a": 20 * 60_000],
        ]
        let hours: [String: [Int: [String: Int64]]] = [
            olderDay: [9: ["com.example.old": 10 * 60_000]],
            day: [10: ["com.example.a": 20 * 60_000]],
        ]
        let archive = ScreenTimeArchive(
            days: days,
            hoursByHour: hours,
            stream: "/app/usage",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(archive.hourBuckets(), hours)
        XCTAssertEqual(archive.usage().days, days)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenTimeArchiveStore(
            fileURL: folder.appendingPathComponent("archive.json")
        )
        try store.save(archive)
        XCTAssertEqual(try store.load(), archive)

        var mergedDays = days
        var mergedHours = hours
        let usage = ScreenTimeUsage(
            days: [
                day: [
                    "com.example.a": 30 * 60_000,
                    "com.example.b": 5 * 60_000,
                ],
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_100),
            stream: "/app/usage",
            eventCount: 2,
            hours: [
                day: [
                    10: ["com.example.a": 30 * 60_000],
                    11: ["com.example.b": 5 * 60_000],
                ],
            ]
        )
        ScreenTimeArchiveMerger.merge(
            days: &mergedDays,
            hours: &mergedHours,
            with: usage
        )

        XCTAssertEqual(
            mergedDays[olderDay]?["com.example.old"],
            10 * 60_000
        )
        XCTAssertEqual(mergedDays[day]?["com.example.a"], 30 * 60_000)
        XCTAssertEqual(mergedDays[day]?["com.example.b"], 5 * 60_000)
        XCTAssertEqual(
            mergedHours[day]?[10]?["com.example.a"],
            30 * 60_000
        )
        XCTAssertEqual(
            mergedHours[day]?[11]?["com.example.b"],
            5 * 60_000
        )
    }

    func testCalendarDayTodayRespectsStartHour() throws {
        let calendar = utcCalendar()
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 24
        components.hour = 2
        let earlyMorning = try XCTUnwrap(
            calendar.date(from: components)
        )
        components.hour = 4
        let boundary = try XCTUnwrap(calendar.date(from: components))

        XCTAssertEqual(
            CalendarDay.today(
                earlyMorning,
                startHour: 0,
                calendar: calendar
            ),
            "2026-11-24"
        )
        XCTAssertEqual(
            CalendarDay.today(
                earlyMorning,
                startHour: 4,
                calendar: calendar
            ),
            "2026-11-23"
        )
        XCTAssertEqual(
            CalendarDay.today(
                boundary,
                startHour: 4,
                calendar: calendar
            ),
            "2026-11-24"
        )
    }

    func testDayBucketingMovesEarlyHoursToPreviousDay() {
        let hour: Int64 = 60 * 60_000
        let days: [String: [String: Int64]] = [
            "2026-11-23": ["a": 10 * hour, "b": hour],
            "2026-11-24": ["a": 2 * hour],
        ]
        let early: [String: [Int: [String: Int64]]] = [
            "2026-11-23": [
                0: ["a": hour],
                1: ["a": hour],
            ],
            "2026-11-24": [
                0: ["a": 30 * 60_000],
                2: ["b": 15 * 60_000],
            ],
        ]

        let shifted = DayBucketing.shiftedDays(
            days: days,
            earlyHourBuckets: early,
            startHour: 4
        )
        XCTAssertEqual(shifted["2026-11-23"]?["a"], 8 * hour + 30 * 60_000)
        XCTAssertEqual(shifted["2026-11-23"]?["b"], hour + 15 * 60_000)
        XCTAssertEqual(shifted["2026-11-24"]?["a"], hour + 30 * 60_000)
        XCTAssertNil(shifted["2026-11-24"]?["b"])
        XCTAssertEqual(
            DayBucketing.shiftedDays(
                days: days,
                earlyHourBuckets: early,
                startHour: 0
            ),
            days
        )
    }

    func testDayBucketingMovesHourBucketsToPreviousDay() {
        let hour: Int64 = 60 * 60_000
        let hours: [String: [Int: [String: Int64]]] = [
            "2026-11-23": [23: ["a": hour]],
            "2026-11-24": [
                0: ["a": 2 * hour],
                1: ["b": hour],
                4: ["a": 3 * hour],
            ],
        ]

        let shifted = DayBucketing.shiftedHours(
            hours: hours,
            startHour: 4
        )
        XCTAssertEqual(shifted["2026-11-23"]?[23]?["a"], hour)
        XCTAssertEqual(shifted["2026-11-23"]?[0]?["a"], 2 * hour)
        XCTAssertEqual(shifted["2026-11-23"]?[1]?["b"], hour)
        XCTAssertEqual(shifted["2026-11-24"]?[4]?["a"], 3 * hour)
        XCTAssertNil(shifted["2026-11-24"]?[0])
    }

    func testUsageMergerMergesAndResetsEarlyHours() {
        let day = "2026-11-23"
        let next = "2026-11-24"
        let first = UsageMerger.merge(
            existing: nil,
            payload: NativeSyncPayload(
                type: "sync",
                reset: true,
                days: [day: ["a": 60_000]],
                earlyHours: [
                    day: ["0": ["a": 10_000]],
                    next: ["1": ["b": 20_000]],
                ]
            ),
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(first.earlyHours?[day]?["0"]?["a"], 10_000)
        XCTAssertEqual(first.earlyHours?[next]?["1"]?["b"], 20_000)

        let delta = UsageMerger.merge(
            existing: first,
            payload: NativeSyncPayload(
                type: "sync",
                reset: false,
                days: [day: ["a": 120_000]],
                earlyHours: [day: ["0": ["a": 30_000]]]
            ),
            receivedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        XCTAssertEqual(delta.earlyHours?[day]?["0"]?["a"], 30_000)
        XCTAssertEqual(delta.earlyHours?[next]?["1"]?["b"], 20_000)

        let reset = UsageMerger.merge(
            existing: delta,
            payload: NativeSyncPayload(
                type: "sync",
                reset: true,
                days: [day: ["a": 60_000]]
            ),
            receivedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
        XCTAssertNil(reset.earlyHours)
    }

    private func makeKnowledgeDB(
        events: [(String, String, Date, Date)]
    ) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        let url = folder.appendingPathComponent("knowledgeC.db")

        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK,
              let database else {
            throw NSError(
                domain: "MacTimerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not open test DB"]
            )
        }
        defer { sqlite3_close(database) }

        try exec(
            "CREATE TABLE ZOBJECT ("
                + "ZSTREAMNAME TEXT, ZVALUESTRING TEXT, "
                + "ZSTARTDATE REAL, ZENDDATE REAL);",
            database: database
        )

        for (stream, bundleID, start, end) in events {
            var statement: OpaquePointer?
            let sql = "INSERT INTO ZOBJECT "
                + "(ZSTREAMNAME, ZVALUESTRING, ZSTARTDATE, ZENDDATE) "
                + "VALUES (?, ?, ?, ?)"
            guard sqlite3_prepare_v2(
                database,
                sql,
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else {
                throw NSError(
                    domain: "MacTimerTests",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            cString: sqlite3_errmsg(database)
                        ),
                    ]
                )
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(
                statement,
                1,
                stream,
                -1,
                testSQLiteTransient
            )
            sqlite3_bind_text(
                statement,
                2,
                bundleID,
                -1,
                testSQLiteTransient
            )
            sqlite3_bind_double(
                statement,
                3,
                start.timeIntervalSinceReferenceDate
            )
            sqlite3_bind_double(
                statement,
                4,
                end.timeIntervalSinceReferenceDate
            )
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NSError(
                    domain: "MacTimerTests",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            cString: sqlite3_errmsg(database)
                        ),
                    ]
                )
            }
        }

        return url
    }

    private func executeSQL(at url: URL, sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK,
              let database else {
            throw NSError(
                domain: "MacTimerTests",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not open test DB"]
            )
        }
        defer { sqlite3_close(database) }
        try exec(sql, database: database)
    }

    private func exec(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(
                domain: "MacTimerTests",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        cString: sqlite3_errmsg(database)
                    ),
                ]
            )
        }
    }
}

private let testSQLiteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
