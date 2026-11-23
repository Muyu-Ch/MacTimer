import AppKit
import SwiftUI
import MacTimerCore
import MacTimerUI

final class MacTimerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.applyStored()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

@main
struct MacTimerApp: App {
    @NSApplicationDelegateAdaptor(MacTimerAppDelegate.self)
    private var appDelegate

    @StateObject private var model = DashboardModel(
        dayStartHour: DayStartSetting.load()
    )
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("MacTimer") {
            DashboardView(model: model)
                .frame(minWidth: 880, minHeight: 620)
        }
        .defaultSize(width: 1000, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新读取数据") {
                    model.reload(force: true)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 MacTimer") {
                    openWindow(id: "about")
                }
            }
        }

        Settings {
            MacTimerSettingsView(
                model: model,
                store: MappingStore.shared,
                categoryStore: model.categoryStore
            )
        }

        Window("关于 MacTimer", id: "about") {
            MacTimerAboutView()
        }
        .defaultSize(width: 680, height: 760)
        .windowResizability(.contentSize)
    }
}
