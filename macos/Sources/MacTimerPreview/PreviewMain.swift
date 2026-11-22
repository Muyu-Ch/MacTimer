import AppKit
import SwiftUI
import MacTimerCore
import MacTimerUI

@main
@MainActor
struct MacTimerPreview {
    static func main() throws {
        var output = "/tmp/mactimer-preview.png"
        var dark = false
        var empty = false
        var compact = false
        var noApps = false
        var permission = false
        var showSettings = false
        var itemsChart = false
        var inputFile: String?
        var selectedDay: String?
        var mode: StatsRange?

        let arguments = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--dark":
                dark = true
            case "--empty":
                empty = true
            case "--compact":
                compact = true
            case "--no-apps":
                noApps = true
            case "--permission":
                permission = true
            case "--settings":
                showSettings = true
            case "--items-chart":
                itemsChart = true
            case "--file":
                if index + 1 < arguments.count {
                    index += 1
                    inputFile = arguments[index]
                }
            case "--day":
                if index + 1 < arguments.count {
                    index += 1
                    selectedDay = arguments[index]
                }
            case "--mode":
                if index + 1 < arguments.count {
                    index += 1
                    mode = StatsRange(rawValue: arguments[index])
                }
            default:
                output = argument
            }
            index += 1
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let snapshot: UsageSnapshot?
        if empty {
            snapshot = nil
        } else if let inputFile {
            snapshot = try UsageSnapshotStore(
                fileURL: URL(fileURLWithPath: inputFile)
            ).load()
        } else {
            snapshot = makeSampleSnapshot()
        }

        let screenTime: ScreenTimeUsage? = empty || noApps
            ? nil
            : makeSampleScreenTime(chromeDays: snapshot?.days ?? [:])
        let mappingStore = MappingStore(loadCustom: false)
        if showSettings {
            _ = try? mappingStore.addMapping(
                domainInput: "b23.tv",
                bundleID: "com.bilibili.bilibiliPC",
                appName: "哔哩哔哩"
            )
        }
        let model = DashboardModel(
            initialSnapshot: snapshot,
            initialScreenTime: screenTime,
            initialScreenTimeAccess: permission ? .needsPermission : nil,
            mappingStore: mappingStore,
            autoRefresh: false
        )
        if let selectedDay {
            model.select(day: selectedDay)
        }
        if let mode {
            model.setViewMode(mode)
        }
        if itemsChart {
            model.setDayChartMode(.items)
        }

        let content: AnyView
        if showSettings {
            content = AnyView(
                MacTimerSettingsView(
                    model: model,
                    store: mappingStore,
                    previewMode: true
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 700, height: 1_120)
            )
        } else {
            content = AnyView(
                DashboardView(
                    model: model,
                    autoStart: false,
                    previewMode: true
                )
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: compact ? 880 : 1040, height: 720)
            )
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let png = Self.sRGBPNG(from: image) else {
            throw PreviewError.renderFailed
        }

        try png.write(to: URL(fileURLWithPath: output))
        print(output)
    }

    /// App icons can make ImageRenderer emit a wide-gamut/HDR PNG. Redraw into
    /// an 8-bit sRGB context so screenshots are easy to inspect consistently.
    private static func sRGBPNG(from image: NSImage) -> Data? {
        guard let source = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let context = CGContext(
               data: nil,
               width: source.width,
               height: source.height,
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(
                x: 0,
                y: 0,
                width: source.width,
                height: source.height
            )
        )
        guard let output = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: output).representation(
            using: .png,
            properties: [:]
        )
    }

    private static func makeSampleSnapshot() -> UsageSnapshot {
        let now = Date()
        let today = CalendarDay.today(now)
        let sites = [
            "youtube.com",
            "github.com",
            "google.com",
            "x.com",
            "ycombinator.com",
            "figma.com",
            "stackoverflow.com",
            "notion.so",
            "linear.app",
            "reddit.com",
            "openai.com",
            "cloudflare.com",
            "bilibili.com",
            "steampowered.com",
        ]

        var days: [String: [String: Int64]] = [:]
        for (index, day) in CalendarDay.lastDays(420, endingAt: now).enumerated() {
            let pattern = [5, 3, 4, 0, 6, 2, 3][index % 7]
            var bucket: [String: Int64] = [:]
            for slot in 0..<pattern {
                let site = sites[(index * 3 + slot) % sites.count]
                let minutes = 22 + ((index * 37 + slot * 53) % 160)
                bucket[site] = Int64(minutes * 60_000)
            }
            days[day] = bucket
        }

        days[today] = [
            "youtube.com": Int64((2 * 60 + 14) * 60_000),
            "github.com": Int64(48 * 60_000),
            "google.com": Int64(21 * 60_000),
            "x.com": Int64(12 * 60_000),
            "ycombinator.com": Int64(6 * 60_000),
            "bilibili.com": Int64(35 * 60_000),
            "steampowered.com": Int64(22 * 60_000),
        ]

        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
        return UsageSnapshot(
            version: 1,
            updatedAt: nowMilliseconds,
            current: CurrentSession(
                site: "youtube.com",
                since: nowMilliseconds - 90_000
            ),
            days: days
        )
    }

    private static func makeSampleScreenTime(
        chromeDays: [String: [String: Int64]]
    ) -> ScreenTimeUsage {
        let now = Date()
        let today = CalendarDay.today(now)
        let apps: [(bundleID: String, minutes: Int)] = [
            ("com.bilibili.bilibiliPC", 55),
            ("com.valvesoftware.steam", 50),
            ("com.tencent.xinWeChat", 26),
            ("com.apple.Music", 18),
        ]

        var days: [String: [String: Int64]] = [:]
        var hours: [String: [Int: [String: Int64]]] = [:]

        for (index, day) in CalendarDay.lastDays(420, endingAt: now)
            .enumerated() {
            var bucket: [String: Int64] = [:]
            for (slot, app) in apps.enumerated()
            where (index + slot) % 4 != 0 {
                let variation = (index * 13 + slot * 29) % 45
                let minutes = max(6, app.minutes + variation - 20)
                let milliseconds = Int64(minutes * 60_000)
                bucket[app.bundleID] = milliseconds
                distributeSample(
                    milliseconds,
                    bundleID: app.bundleID,
                    slot: slot + 1,
                    index: index,
                    day: day,
                    hours: &hours
                )
            }

            let domainTotal = (chromeDays[day] ?? [:]).values
                .reduce(Int64(0)) { $0 + max(0, $1) }
            let gapMinutes: Int64 = domainTotal > 0
                ? (index % 6 == 0 ? 8 : 1)
                : 0
            let chromeMilliseconds = domainTotal + gapMinutes * 60_000
            if chromeMilliseconds > 0 {
                bucket["com.google.Chrome"] = chromeMilliseconds
                distributeSample(
                    chromeMilliseconds,
                    bundleID: "com.google.Chrome",
                    slot: 0,
                    index: index,
                    day: day,
                    hours: &hours
                )
            }

            days[day] = bucket
        }

        var todayBucket: [String: Int64] = [
            "com.bilibili.bilibiliPC": Int64(42 * 60_000),
            "com.valvesoftware.steam": Int64(70 * 60_000),
            "com.tencent.xinWeChat": Int64(18 * 60_000),
            "com.apple.Music": Int64(25 * 60_000),
        ]
        let todayDomainTotal = (chromeDays[today] ?? [:]).values
            .reduce(Int64(0)) { $0 + max(0, $1) }
        todayBucket["com.google.Chrome"] = todayDomainTotal + 8 * 60_000
        days[today] = todayBucket

        hours[today] = [:]
        for (slot, app) in apps.enumerated() {
            if let milliseconds = todayBucket[app.bundleID] {
                distributeSample(
                    milliseconds,
                    bundleID: app.bundleID,
                    slot: slot + 1,
                    index: 0,
                    day: today,
                    hours: &hours
                )
            }
        }
        if let chromeMilliseconds = todayBucket["com.google.Chrome"] {
            distributeSample(
                chromeMilliseconds,
                bundleID: "com.google.Chrome",
                slot: 0,
                index: 0,
                day: today,
                hours: &hours
            )
        }

        return ScreenTimeUsage(
            days: days,
            fetchedAt: now,
            stream: "/app/usage",
            eventCount: 0,
            hours: hours
        )
    }

    private static func distributeSample(
        _ milliseconds: Int64,
        bundleID: String,
        slot: Int,
        index: Int,
        day: String,
        hours: inout [String: [Int: [String: Int64]]]
    ) {
        guard milliseconds > 0 else { return }
        let totalMinutes = Int(milliseconds / 60_000)
        let chunks = max(
            1,
            min(8, Int(ceil(Double(totalMinutes) / 45.0)))
        )
        let start = 8 + ((index * 2 + slot * 3) % 12)
        let available = min(chunks, 24 - start)
        guard available > 0 else { return }

        let perChunk = milliseconds / Int64(available)
        var allocated: Int64 = 0
        for offset in 0..<available {
            let portion = offset == available - 1
                ? milliseconds - allocated
                : perChunk
            allocated += portion

            var dayHours = hours[day] ?? [:]
            var bundles = dayHours[start + offset] ?? [:]
            bundles[bundleID, default: 0] += portion
            dayHours[start + offset] = bundles
            hours[day] = dayHours
        }
    }
}

private enum PreviewError: Error {
    case renderFailed
}
