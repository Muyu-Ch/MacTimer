import AppKit
import SwiftUI
import MacTimerUI

final class MacTimerAppDelegate: NSObject, NSApplicationDelegate {
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

    @StateObject private var model = DashboardModel()

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
        }

        Settings {
            MacTimerSettingsView(
                model: model,
                store: MappingStore.shared
            )
        }
    }
}
