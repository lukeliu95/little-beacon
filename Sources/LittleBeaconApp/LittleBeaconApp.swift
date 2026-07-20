import SwiftUI
import LittleBeaconCore

@main
struct LittleBeaconApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()

    var body: some Scene {
        WindowGroup("小灯塔") {
            RootView(model: model)
                .environmentObject(updates)
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
        }

        MenuBarExtra("小灯塔", systemImage: "light.beacon.max.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Label("小灯塔正在运行", systemImage: "checkmark.shield")
                    .font(.headline)
                if model.role == .child {
                    Text("当前：\(model.currentActivity.category.displayName)")
                    if let warning = model.warningMessage {
                        Text(warning).foregroundStyle(.orange)
                    }
                } else if model.role == .parent {
                    Text(model.connectionMessage)
                } else {
                    Text("请打开主窗口完成设置")
                }
                Divider()
                Button("立即同步") { Task { await model.syncNow() } }
                Button("检查更新…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
            .padding(10)
            .frame(width: 280)
        }
    }
}
