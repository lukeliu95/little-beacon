import Foundation
import Security

protocol ParentAuthorizing: Sendable {
    func authorizeQuit() async -> Bool
}

/// Asks macOS to verify an administrator password, the credential the family model already leaves
/// with the parent (ADR-0005). The system dialog owns the password, so the app never sees or stores it.
struct AdministratorPasswordAuthorizer: ParentAuthorizing {
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
