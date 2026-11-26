import CommonCrypto
import Foundation
import Security

/// The password a parent sets for closing the child app (issue #19). Only a salted PBKDF2 digest
/// travels with the rules, so the child Mac can check it offline without ever holding the text.
public struct ExitPassword: Codable, Equatable, Sendable {
    public static let minimumLength = 4
    public static let defaultIterations = 200_000

    public var salt: String
    public var digest: String
    public var iterations: Int

    public init(salt: String, digest: String, iterations: Int) {
        self.salt = salt
        self.digest = digest
        self.iterations = iterations
    }

    /// `nil` when the text is too short to protect anything.
    public static func make(
        from password: String,
        iterations: Int = defaultIterations,
        salt: Data = randomSalt()
    ) -> ExitPassword? {
        guard password.count >= minimumLength,
              let digest = derive(password, salt: salt, iterations: iterations) else { return nil }
        return ExitPassword(
            salt: salt.base64EncodedString(),
            digest: digest.base64EncodedString(),
            iterations: iterations
        )
    }

    public func matches(_ password: String) -> Bool {
        guard let salt = Data(base64Encoded: salt),
              let expected = Data(base64Encoded: digest),
              let actual = Self.derive(password, salt: salt, iterations: iterations) else { return false }
        return Self.constantTimeEqual(actual, expected)
    }

    public static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func derive(_ password: String, salt: Data, iterations: Int) -> Data? {
        guard iterations > 0, !salt.isEmpty else { return nil }
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBuffer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.map { CChar(bitPattern: $0) },
                passwordBytes.count,
                saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived,
                derived.count
            )
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// Five wrong answers in a row lock the box for a minute, so guessing at the keyboard is slow.
public struct ExitPasswordAttempts: Equatable, Sendable {
    public static let allowedFailures = 5
    public static let lockSeconds: TimeInterval = 60

    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public init() {}

    public func isLocked(at date: Date) -> Bool {
        guard let lockedUntil else { return false }
        return date < lockedUntil
    }

    public func secondsLeft(at date: Date) -> Int {
        guard let lockedUntil, date < lockedUntil else { return 0 }
        return Int(lockedUntil.timeIntervalSince(date).rounded(.up))
    }

    public mutating func record(success: Bool, at date: Date) {
        if success {
            self = ExitPasswordAttempts()
            return
        }
        if let lockedUntil, date >= lockedUntil {
            self.lockedUntil = nil
            failures = 0
        }
        failures += 1
        if failures >= Self.allowedFailures {
            lockedUntil = date.addingTimeInterval(Self.lockSeconds)
        }
    }
}
