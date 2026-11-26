import AppKit
import AVFoundation
import Foundation
import ServiceManagement
import UserNotifications

enum BreakAlarmError: LocalizedError {
    case resourceUnavailable(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case let .resourceUnavailable(name):
            "找不到内置番茄钟声音：\(name)"
        case let .playbackFailed(name):
            "番茄钟声音播放失败：\(name)"
        }
    }
}

enum SoundService {
    /// Plays an attention-getting sound for on-screen alerts (warnings, break reminders,
    /// daily-usage nudges). Additive to `NotificationService.post`, which already plays the
    /// default notification sound but is easy to miss when the app isn't focused.
    static func playAlert() {
        let sound = NSSound(named: "Sosumi") ?? NSSound(named: "Glass")
        if let sound {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    static func playDistanceAlarm() {
        for delay in [0.0, 0.45, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let sound = NSSound(named: "Sosumi") ?? NSSound(named: "Glass")
                if let sound {
                    sound.play()
                } else {
                    NSSound.beep()
                }
            }
        }
    }
}

/// Owns the bundled strong-break players for the full lifetime of the break and stops the
/// repeating alarm immediately after acknowledgement.
@MainActor
final class BreakAlarmController: BreakAlarmPlaying {
    var onPlaybackError: ((Error) -> Void)?

    static var hasBundledResources: Bool {
        Bundle.module.url(forResource: "pomodoro-alarm", withExtension: "wav") != nil
            && Bundle.module.url(forResource: "pomodoro-complete", withExtension: "wav") != nil
    }

    private var attentionPlayer: AVAudioPlayer?
    private var completionPlayer: AVAudioPlayer?
    private var playersAreLoaded = false
    private var repeatTimer: Timer?

    init() {
        // Opening the sound system can stall for about a minute right after launchd starts the
        // app. Loading the players here, during AppModel.init, froze the whole app before its menu
        // bar icon appeared, so they load in the background and a beep covers the gap (issue #19).
        Task.detached(priority: .utility) { [weak self] in
            let players = LoadedPlayers(
                attention: Self.makePlayer(named: "pomodoro-alarm"),
                completion: Self.makePlayer(named: "pomodoro-complete")
            )
            await self?.receive(players)
        }
    }

    private func receive(_ players: LoadedPlayers) {
        attentionPlayer = players.attention
        completionPlayer = players.completion
        playersAreLoaded = true
    }

    func startWaitingAlarm() {
        stopWaitingAlarm()
        play(attentionPlayer, named: "pomodoro-alarm")

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.play(self.attentionPlayer, named: "pomodoro-alarm")
            }
        }
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopWaitingAlarm() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        attentionPlayer?.stop()
        attentionPlayer?.currentTime = 0
    }

    func playCompletion() {
        play(completionPlayer, named: "pomodoro-complete")
    }

    private func play(_ player: AVAudioPlayer?, named name: String) {
        guard let player else {
            NSSound.beep()
            // Still loading is not a fault; a missing resource after loading is.
            if playersAreLoaded { onPlaybackError?(BreakAlarmError.resourceUnavailable(name)) }
            return
        }
        player.stop()
        player.currentTime = 0
        if !player.play() {
            NSSound.beep()
            onPlaybackError?(BreakAlarmError.playbackFailed(name))
        }
    }

    private nonisolated static func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return nil
        }
        player.prepareToPlay()
        return player
    }
}

enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum AutoStartManager {
    static func registerIfPossible() -> String {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            return "开发模式：打包后启用自动启动"
        }
        do {
            // With the LaunchAgent installed, launchd starts the app at login. A login item as
            // well would start a second copy that the single-instance guard has to kill.
            if readAutoRecoveryState() != .missing {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                return "已由后台服务设置登录时启动"
            }
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            return "已设置登录时启动"
        } catch {
            return "自动启动需要在系统设置中确认：\(error.localizedDescription)"
        }
    }
}

/// Carries the players from the loading task to the main actor; nothing touches them in between.
private struct LoadedPlayers: @unchecked Sendable {
    let attention: AVAudioPlayer?
    let completion: AVAudioPlayer?
}
