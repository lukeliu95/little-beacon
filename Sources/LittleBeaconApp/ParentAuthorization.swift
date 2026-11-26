import AppKit
import Foundation
import LittleBeaconCore
import Security

protocol ParentAuthorizing: Sendable {
    func authorizeQuit(with credential: QuitCredential) async -> Bool
}

/// Picks the dialog that matches what the parent has to prove.
struct FamilyQuitAuthorizer: ParentAuthorizing {
    func authorizeQuit(with credential: QuitCredential) async -> Bool {
        switch credential {
        case .administrator:
            await AdministratorPasswordAuthorizer().authorizeQuit()
        case let .exitPassword(password):
            await ExitPasswordPrompt.ask(for: password)
        }
    }
}

/// The child types the password the parent set in the parent app. Only its digest is on this Mac.
@MainActor
enum ExitPasswordPrompt {
    private static var attempts = ExitPasswordAttempts()

    static func ask(for password: ExitPassword) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        var note = "输入家长设置的退出密码。退出后，下次登录这台 Mac 时小灯塔会自动启动。"
        while true {
            let now = Date()
            if attempts.isLocked(at: now) {
                inform(
                    title: "输错太多次了",
                    message: "请 \(attempts.secondsLeft(at: now)) 秒后再试。小灯塔会继续运行。"
                )
                return false
            }
            let alert = NSAlert()
            alert.messageText = "退出小灯塔"
            alert.informativeText = note
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "取消")
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.placeholderString = "退出密码"
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            let matches = password.matches(field.stringValue)
            attempts.record(success: matches, at: Date())
            if matches { return true }
            note = "密码不对，请再试一次。"
        }
    }

    static func explainMissingPassword() {
        NSApp.activate(ignoringOtherApps: true)
        inform(
            title: "现在不能退出小灯塔",
            message: "家长还没有设置退出密码。家长可以在家长端的“设备”页设置。"
        )
    }

    private static func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

/// Asks macOS to verify an administrator password, the credential the family model already leaves
/// with the parent (ADR-0005). The system dialog owns the password, so the app never sees or stores it.
struct AdministratorPasswordAuthorizer {
    func authorizeQuit() async -> Bool {
        await withCheckedContinuation { continuation in
            // AuthorizationCopyRights blocks until the dialog closes; rule checks must keep running.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.verifyAdministratorPassword())
            }
        }
    }

    private static func verifyAdministratorPassword() -> Bool {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess,
              let authorization else {
            return false
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let promptText = "输入家长的管理员密码，才能退出小灯塔。"
        return "system.privilege.admin".withCString { rightName in
            "prompt".withCString { promptName in
                promptText.withCString { promptValue in
                    var right = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                    var prompt = AuthorizationItem(
                        name: promptName,
                        valueLength: strlen(promptValue),
                        value: UnsafeMutableRawPointer(mutating: promptValue),
                        flags: 0
                    )
                    return withUnsafeMutablePointer(to: &right) { rightPointer in
                        withUnsafeMutablePointer(to: &prompt) { promptPointer in
                            var rights = AuthorizationRights(count: 1, items: rightPointer)
                            var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                            return AuthorizationCopyRights(
                                authorization,
                                &rights,
                                &environment,
                                [.interactionAllowed, .extendRights],
                                nil
                            ) == errAuthorizationSuccess
                        }
                    }
                }
            }
        }
    }
}
