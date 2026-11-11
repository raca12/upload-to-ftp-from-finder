import Foundation
import CryptoKit

// MARK: - Kilit politikası

public enum LockPolicy: String, Codable, CaseIterable, Sendable {
    case never          // hiç sorma
    case launch         // uygulama açılırken bir kez
    case everyUpload    // her yüklemeden önce
    case everyAction    // her işlemden önce (yükleme, sunucu düzenleme, klasör gezme)

    public var requiresUnlockOnLaunch: Bool {
        switch self {
        case .never, .everyUpload: return false
        case .launch, .everyAction: return true
        }
    }

    public var requiresUnlockBeforeUpload: Bool {
        switch self {
        case .never, .launch: return false
        case .everyUpload, .everyAction: return true
        }
    }

    public var requiresUnlockBeforeAction: Bool {
        self == .everyAction
    }
}

// MARK: - Ayarlar

public struct SecuritySettings: Codable, Sendable {
    /// PBKDF2 ile türetilmiş parola özeti (salt + hash, base64)
    public var passwordHash: String?
    public var iterations: Int
    public var policy: LockPolicy
    /// Pencere kapanınca kilitle
    public var lockOnWindowClose: Bool

    public init(passwordHash: String? = nil,
                iterations: Int = 120_000,
                policy: LockPolicy = .launch,
                lockOnWindowClose: Bool = true) {
        self.passwordHash = passwordHash
        self.iterations = iterations
        self.policy = policy
        self.lockOnWindowClose = lockOnWindowClose
    }

    public var hasPassword: Bool { !(passwordHash ?? "").isEmpty }
}

// MARK: - Parola deposu

public final class SecurityStore {
    public static let changedNotification = Notification.Name("com.mcb.upload.securityChanged")

    public let fileURL: URL

    public init(baseDirectory: URL? = nil) {
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else if let custom = ProcessInfo.processInfo.environment["MCB_HOME"], !custom.isEmpty {
            base = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = MCBUploadPaths.sharedBaseDirectory
        }
        self.fileURL = base.appendingPathComponent("security.json")
    }

    public func load() -> SecuritySettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(SecuritySettings.self, from: data) else {
            return SecuritySettings()
        }
        return settings
    }

    public func save(_ settings: SecuritySettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder.mcb.encode(settings)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    // MARK: Parola işlemleri

    public func setPassword(_ password: String, policy: LockPolicy? = nil) throws {
        var settings = load()
        if password.isEmpty {
            settings.passwordHash = nil
        } else {
            settings.passwordHash = PasswordHasher.hash(password, iterations: settings.iterations)
        }
        if let policy { settings.policy = policy }
        try save(settings)
    }

    public func removePassword() throws {
        var settings = load()
        settings.passwordHash = nil
        try save(settings)
    }

    public func verify(_ password: String) -> Bool {
        let settings = load()
        guard let stored = settings.passwordHash else { return false }
        return PasswordHasher.verify(password, encoded: stored, iterations: settings.iterations)
    }
}

// MARK: - PBKDF2-HMAC-SHA256 (CryptoKit ile)

public enum PasswordHasher {

    public static func hash(_ password: String, iterations: Int) -> String {
        let salt = randomSalt()
        let derived = pbkdf2(password: Data(password.utf8), salt: salt, iterations: iterations, keyLength: 32)
        var blob = salt
        blob.append(derived)
        return blob.base64EncodedString()
    }

    public static func verify(_ password: String, encoded: String, iterations: Int) -> Bool {
        guard let blob = Data(base64Encoded: encoded), blob.count > 16 else { return false }
        let salt = blob.prefix(16)
        let expected = blob.dropFirst(16)
        let derived = pbkdf2(password: Data(password.utf8), salt: Data(salt), iterations: iterations, keyLength: expected.count)
        return constantTimeEquals(Data(derived), Data(expected))
    }

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let key = SymmetricKey(data: password)
        var result = Data()
        var block: UInt32 = 1
        while result.count < keyLength {
            var message = salt
            message.append(contentsOf: withUnsafeBytes(of: block.bigEndian) { Data($0) })
            var u = Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for i in 0..<t.count { t[i] ^= u[i] }
                }
            }
            result.append(t)
            block += 1
        }
        return result.prefix(keyLength)
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count { diff |= lhs[i] ^ rhs[i] }
        return diff == 0
    }
}
