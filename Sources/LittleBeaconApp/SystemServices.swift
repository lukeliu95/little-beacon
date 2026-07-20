import AppKit
import Foundation
import ServiceManagement
import UserNotifications

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
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            return "已设置登录时启动"
        } catch {
            return "自动启动需要在系统设置中确认：\(error.localizedDescription)"
        }
    }
}
