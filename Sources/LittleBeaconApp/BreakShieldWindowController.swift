import AppKit
import LittleBeaconCore
import SwiftUI

func pomodoroBreakMessage(for phase: PomodoroBreakPhase, at date: Date) -> String {
    switch phase {
    case .awaitingAcknowledgement:
        return "你已经连续使用 25 分钟。先确认，然后完整休息 5 分钟。"
    case let .requiredBreak(_, _, closeAvailableAt):
        let remaining = max(0, Int(ceil(closeAvailableAt.timeIntervalSince(date))))
        return "再休息 \(remaining / 60):\(String(format: "%02d", remaining % 60))。看看远处，喝口水，手先别急着找鼠标。"
    case .readyToClose:
        return "休息完成。准备好以后再开始下一轮。"
    case .counting:
        return ""
    }
}

private final class BreakShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        // Escape is deliberately inert while the required break is active.
    }
}

@MainActor
final class BreakShieldWindowController: NSObject, BreakShieldPresenting, NSWindowDelegate {
    private var panels: [BreakShieldPanel] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var phase: PomodoroBreakPhase?
    private var acknowledgeAction: (@MainActor () -> Void)?
    private var closeAction: (@MainActor () -> Void)?

    func present(
        phase: PomodoroBreakPhase,
        acknowledge: @escaping @MainActor () -> Void,
        close: @escaping @MainActor () -> Void
    ) {
        self.phase = phase
        acknowledgeAction = acknowledge
        closeAction = close
        installObserversIfNeeded()
        rebuildPanels()
        bringToFront()
    }

    func update(phase: PomodoroBreakPhase) {
        self.phase = phase
        updatePanelContents()
        bringToFront()
    }

    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        phase = nil
        acknowledgeAction = nil
        closeAction = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

#if DEBUG
    struct PanelContract: Equatable {
        var level: Int
        var isBorderless: Bool
        var hasCloseButton: Bool
        var joinsAllSpaces: Bool
        var supportsFullScreenAuxiliary: Bool
        var hidesOnDeactivate: Bool
    }

    var panelContractsForTesting: [PanelContract] {
        panels.map { panel in
            PanelContract(
                level: panel.level.rawValue,
                isBorderless: panel.styleMask.contains(.borderless),
                hasCloseButton: panel.standardWindowButton(.closeButton) != nil,
                joinsAllSpaces: panel.collectionBehavior.contains(.canJoinAllSpaces),
                supportsFullScreenAuxiliary: panel.collectionBehavior.contains(.fullScreenAuxiliary),
                hidesOnDeactivate: panel.hidesOnDeactivate
            )
        }
    }
#endif

    private func rebuildPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.enumerated().map { index, screen in
            let panel = BreakShieldPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.09, alpha: 1)
            panel.isOpaque = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.delegate = self
            panel.contentView = hostingView(isPrimary: index == 0)
            return panel
        }
    }

    private func updatePanelContents() {
        for (index, panel) in panels.enumerated() {
            panel.contentView = hostingView(isPrimary: index == 0)
        }
    }

    private func hostingView(isPrimary: Bool) -> NSView {
        let view = BreakShieldView(
            phase: phase ?? .counting(activeSeconds: 0, idleSeconds: 0),
            isPrimary: isPrimary,
            acknowledge: { [weak self] in self?.acknowledgeAction?() },
            close: { [weak self] in self?.closeAction?() }
        )
        return NSHostingView(rootView: view)
    }

    private func bringToFront() {
        guard !panels.isEmpty else { return }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        for (index, panel) in panels.enumerated() {
            if index == 0 {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let applicationCenter = NotificationCenter.default
        let applicationNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didUnhideNotification,
            NSApplication.didHideNotification,
            NSApplication.didChangeScreenParametersNotification,
        ]
        observers = applicationNotifications.map { name in
            let token = applicationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self, self.phase?.isActiveBreak == true else { return }
                    if notification.name == NSApplication.didChangeScreenParametersNotification {
                        self.rebuildPanels()
                    }
                    self.bringToFront()
                }
            }
            return (applicationCenter, token)
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase?.isActiveBreak == true else { return }
                    self.bringToFront()
                }
            }
            observers.append((workspaceCenter, token))
        }
    }
}

private struct BreakShieldView: View {
    let phase: PomodoroBreakPhase
    let isPrimary: Bool
    let acknowledge: () -> Void
    let close: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.14), Color(red: 0.13, green: 0.08, blue: 0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    Image(systemName: phaseSymbol)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.mint)
                    Text(title)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("pomodoro.break.title")
                    Text(pomodoroBreakMessage(for: phase, at: context.date))
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 580)
                        .accessibilityIdentifier("pomodoro.break.status")

                    if isPrimary {
                        actionButton
                    } else {
                        Text("请在主显示器上操作")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(44)
                .foregroundStyle(.white)
                .accessibilityElement(children: .contain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .awaitingAcknowledgement:
            Button("确认，我现在开始休息") { acknowledge() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("pomodoro.break.acknowledge")
        case .readyToClose:
            Button("关闭并开始下一轮") { close() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("pomodoro.break.close")
        case .requiredBreak:
            EmptyView()
        case .counting:
            EmptyView()
        }
    }

    private var title: String {
        switch phase {
        case .awaitingAcknowledgement: "该休息 5 分钟了"
        case .requiredBreak: "休息进行中"
        case .readyToClose: "5 分钟到了"
        case .counting: "小灯塔"
        }
    }

    private var phaseSymbol: String {
        switch phase {
        case .awaitingAcknowledgement: "bell.badge.fill"
        case .requiredBreak: "eye.fill"
        case .readyToClose: "checkmark.circle.fill"
        case .counting: "light.beacon.max.fill"
        }
    }

}
