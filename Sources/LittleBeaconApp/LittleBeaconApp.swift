import AppKit
import SwiftUI
import LittleBeaconCore

private let mainWindowID = "main"

private var visibleMainWindow: NSWindow? {
    NSApp.windows.first { $0.canBecomeMain && $0.isVisible }
}

@MainActor
func showMainWindow(_ openWindow: OpenWindowAction) {
    if visibleMainWindow == nil {
        openWindow(id: mainWindowID)
    }
    NSApp.activate(ignoringOtherApps: true)
    // A background app is not raised on its own, and a new window arrives on the next run-loop turn.
    DispatchQueue.main.async {
        visibleMainWindow?.makeKeyAndOrderFront(nil)
    }
}

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

        MenuBarExtra {
            MenuPanelRoot(model: model, updates: updates)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuPanelRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch model.role {
        case .parent:
            ParentMenuPanel(model: model)
        case .child:
            ChildMenuPanel(model: model, updates: updates)
        case .unconfigured:
            VStack(alignment: .leading, spacing: 8) {
                Text("小灯塔还没有设置")
                    .font(.system(size: 15, weight: .semibold))
                MenuPanelRow(title: "打开小灯塔") { showMainWindow(openWindow) }
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

/// The lamp, plus the countdown during the last stretch. This view lives as long as the app, so
/// it is also what brings the window forward when an alert asks for it.
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "light.beacon.max.fill")
            if let countdown = model.menuBarCountdownText {
                Text(countdown).monospacedDigit()
            }
        }
        .accessibilityLabel(model.menuBarCountdownText ?? "小灯塔")
        .onChange(of: model.mainWindowRequest) { _, _ in
            showMainWindow(openWindow)
        }
    }
}
