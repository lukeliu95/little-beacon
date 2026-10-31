import AppKit
import SwiftUI
import LittleBeaconCore

private let mainWindowID = "main"

@main
struct LittleBeaconApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleController.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()

    var body: some Scene {
        WindowGroup("小灯塔", id: mainWindowID) {
            RootView(model: model)
                .environmentObject(updates)
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
            CommandGroup(replacing: .appVisibility) {
                if model.role != .child {
                    Button("隐藏小灯塔") { NSApp.hide(nil) }
                        .keyboardShortcut("h")
                }
            }
            CommandGroup(replacing: .appTermination) {
                if model.role != .child {
                    Button("退出小灯塔") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
        }

        MenuBarExtra("小灯塔", systemImage: "light.beacon.max.fill") {
            MenuBarContent(model: model, updates: updates)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("小灯塔正在运行", systemImage: "checkmark.shield")
                .font(.headline)
            if model.role == .child {
                Text("当前：\(model.currentActivity.category.displayName)")
                if let warning = model.warningMessage {
                    Text(warning).foregroundStyle(.orange)
                }
                Button("打开小灯塔") { showMainWindow() }
            } else if model.role == .parent {
                Text(model.connectionMessage)
            } else {
                Text("请打开主窗口完成设置")
            }
            Divider()
            Button("立即同步") { Task { await model.syncNow() } }
            Button("检查更新…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
            if model.role == .child {
                Divider()
                Button("退出小灯塔…") { NSApp.terminate(nil) }
            }
        }
        .padding(10)
        .frame(width: 280)
    }

    private func showMainWindow() {
        if visibleMainWindow == nil {
            openWindow(id: mainWindowID)
        }
        NSApp.activate(ignoringOtherApps: true)
        // A background app is not raised on its own, and a new window arrives on the next run-loop turn.
        DispatchQueue.main.async {
            visibleMainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private var visibleMainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.isVisible }
    }
}
