import SwiftUI
import LittleBeaconCore

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.role {
            case .unconfigured:
                RoleSelectionView(model: model)
            case .parent:
                ParentShellView(model: model)
            case .child:
                ChildDashboardView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            if let error = model.lastError {
                ErrorToast(message: error)
                    .padding(20)
            }
        }
        .background(BackgroundLaunchWindowCloser(shouldClose: model.consumeBackgroundLaunch))
    }
}

/// macOS 14 has no scene option to skip the launch window, so a paired child Mac closes it
/// before it is ever seen.
private struct BackgroundLaunchWindowCloser: NSViewRepresentable {
    let shouldClose: () -> Bool

    func makeNSView(context: Context) -> NSView {
        CloserView(shouldClose: shouldClose)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CloserView: NSView {
        private let shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from a nib") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, shouldClose() else { return }
            window.alphaValue = 0
            DispatchQueue.main.async {
                window.close()
                window.alphaValue = 1
            }
        }
    }
}

private struct RoleSelectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.18), Color.cyan.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 28) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.indigo)
                VStack(spacing: 8) {
                    Text("小灯塔")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("先讲清规则，再安静地守住它。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    RoleCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "这是家长 Mac",
                        detail: "设置时段、审批申请、接收提醒",
                        tint: .indigo
                    ) { model.configure(role: .parent) }
                    RoleCard(
                        icon: "laptopcomputer",
                        title: "这是孩子 Mac",
                        detail: "显示规则、申请时间、执行提醒",
                        tint: .teal
                    ) { model.configure(role: .child) }
                }
                .frame(maxWidth: 700)
                Text("孩子端始终显示在菜单栏；小灯塔不记录屏幕、按键或聊天内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(48)
        }
    }
}

private struct RoleCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(tint)
                Text(title).font(.title3.bold())
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Label("继续", systemImage: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(detail)
    }
}

func formatUsageDuration(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0 ? "\(hours) 小时 \(minutes) 分" : "\(minutes) 分"
}

private struct ErrorToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout)
            .padding(12)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
    }
}
