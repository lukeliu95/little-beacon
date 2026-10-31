import AppKit
import LittleBeaconCore
import SwiftUI

private final class ChildAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Child alerts live in their own panel because the child app usually has no open window.
@MainActor
final class ChildAlertPanelController {
    private var panel: ChildAlertPanel?

    func show(
        _ alert: ChildAlert,
        dismiss: @escaping @MainActor () -> Void,
        extend: @escaping @MainActor (ActivityCategory) -> Void = { _ in },
        requestMore: @escaping @MainActor () -> Void = {}
    ) {
        hide()
        let content = NSHostingView(rootView: ChildAlertCard(
            alert: alert,
            dismiss: dismiss,
            extend: extend,
            requestMore: requestMore
        ))
        let panel = ChildAlertPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = content
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

#if DEBUG
    struct PanelContract: Equatable {
        var level: Int
        var isBorderless: Bool
        var isNonActivating: Bool
        var joinsAllSpaces: Bool
        var supportsFullScreenAuxiliary: Bool
        var hidesOnDeactivate: Bool
    }

    var panelContractForTesting: PanelContract? {
        panel.map { panel in
            PanelContract(
                level: panel.level.rawValue,
                isBorderless: panel.styleMask.contains(.borderless),
                isNonActivating: panel.styleMask.contains(.nonactivatingPanel),
                joinsAllSpaces: panel.collectionBehavior.contains(.canJoinAllSpaces),
                supportsFullScreenAuxiliary: panel.collectionBehavior.contains(.fullScreenAuxiliary),
                hidesOnDeactivate: panel.hidesOnDeactivate
            )
        }
    }
#endif
}

private struct ChildAlertCard: View {
    let alert: ChildAlert
    let dismiss: () -> Void
    let extend: (ActivityCategory) -> Void
    let requestMore: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(tint)
            Text(alert.title).font(.title.bold())
            Text(alert.message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let category = alert.extensionCategory {
                    Button("再玩 \(ReminderStrategy.extensionMinutes) 分钟") { extend(category) }
                        .buttonStyle(BeaconButtonStyle())
                }
                if alert.offersRequest {
                    Button("申请多玩") { requestMore() }
                        .buttonStyle(BeaconButtonStyle())
                }
                Button("知道了") { dismiss() }
                    .buttonStyle(BeaconButtonStyle(kind: .primary))
            }
        }
        .padding(40)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var icon: String {
        alert.tone == .gentle ? "eye" : "exclamationmark.triangle.fill"
    }
    private var tint: Color {
        alert.tone == .gentle ? .teal : .orange
    }
}
