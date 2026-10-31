import AppKit
import AVFoundation
import LittleBeaconCore
import SwiftUI

/// A short note in the corner. It never takes the keyboard or mouse from what the child is doing.
@MainActor
final class ChildToastController {
    private static let visibleSeconds = 8
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: ReminderMessage, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        hide()
        let content = NSHostingView(rootView: ChildToastView(
            message: message,
            actionTitle: actionTitle,
            action: { [weak self] in
                action?()
                self?.hide()
            }
        ))
        let panel = NSPanel(
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
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.minX + 20, y: frame.minY + 20))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

#if DEBUG
    var isShowingForTesting: Bool { panel != nil }
    var panelIsNonActivatingForTesting: Bool { panel?.styleMask.contains(.nonactivatingPanel) ?? false }
#endif
}

private struct ChildToastView: View {
    let message: ReminderMessage
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.title).font(.system(size: 14, weight: .semibold))
                Text(message.body).font(.system(size: 13)).opacity(0.8)
            }
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Darkens every screen while leaving it usable, so the child can still save before it ends.
@MainActor
final class ScreenDimController {
    private static let targetOpacity = 0.45
    private static let fadeSeconds = 20.0
    private var panels: [NSPanel] = []

    var isDimming: Bool { !panels.isEmpty }

    func show() {
        guard panels.isEmpty else { return }
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .floating
            panel.backgroundColor = .black
            panel.isOpaque = false
            panel.alphaValue = 0
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.orderFrontRegardless()
            return panel
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeSeconds
            panels.forEach { $0.animator().alphaValue = Self.targetOpacity }
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

#if DEBUG
    struct PanelContract: Equatable {
        var ignoresMouse: Bool
        var isNonActivating: Bool
        var joinsAllSpaces: Bool
    }

    var panelContractsForTesting: [PanelContract] {
        panels.map {
            PanelContract(
                ignoresMouse: $0.ignoresMouseEvents,
                isNonActivating: $0.styleMask.contains(.nonactivatingPanel),
                joinsAllSpaces: $0.collectionBehavior.contains(.canJoinAllSpaces)
            )
        }
    }
#endif
}

/// A full-screen message the child can close, unlike the enforced break shield.
@MainActor
final class ReminderShieldController {
    private var panels: [NSPanel] = []

    var isShowing: Bool { !panels.isEmpty }

    func show(_ message: ReminderMessage, dismiss: (@MainActor () -> Void)? = nil) {
        hide()
        panels = NSScreen.screens.enumerated().map { index, screen in
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .modalPanel
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: ReminderShieldView(
                message: message,
                isPrimary: index == 0,
                close: { [weak self] in
                    self?.hide()
                    dismiss?()
                }
            ))
            panel.orderFrontRegardless()
            return panel
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

private struct ReminderShieldView: View {
    let message: ReminderMessage
    let isPrimary: Bool
    let close: () -> Void

    var body: some View {
        ZStack {
            Color(white: 0.1).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(message.title).font(.system(size: 34, weight: .semibold))
                Text(message.body)
                    .font(.title3)
                    .opacity(0.8)
                    .multilineTextAlignment(.center)
                if isPrimary {
                    Button("知道了", action: close)
                        .buttonStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 22)
                        .frame(minHeight: 38)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("reminder.shield.close")
                }
            }
            .padding(44)
            .foregroundStyle(.white)
        }
    }
}

/// Speaks with a voice already on this Mac; nothing leaves the machine.
@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    static var hasChineseVoice: Bool {
        AVSpeechSynthesisVoice(language: "zh-CN") != nil
    }

    func say(_ text: String) {
        guard let voice = AVSpeechSynthesisVoice(language: "zh-CN") else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
}
