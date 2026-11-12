import Foundation
import CryptoKit

// MARK: - FTP/SFTP şifreleri için yerel şifreli kasa (AES-GCM)
//
// macOS Keychain her binary değişiminde "anahtar zinciri parolası" popup'ı çıkardığı için
// parolalar uygulama dizininde (0600 izinli) AES-GCM (256-bit) ile şifrelenmiş olarak saklanır.
// Hiçbir zaman işletim sistemi parola diyaloğu çıkarmaz.

public struct CredentialStore {

    public let service: String
    private let fileURL: URL

    public init(service: String = "com.mcb.upload.ftp", baseDirectory: URL? = nil) {
        self.service = service
        let dir: URL
        if let baseDirectory {
            dir = baseDirectory
        } else if let custom = ProcessInfo.processInfo.environment["MCB_HOME"], !custom.isEmpty {
            dir = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            dir = MCBUploadPaths.sharedBaseDirectory
        }
        let safeName = service.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        self.fileURL = dir.appendingPathComponent("vault-\(safeName).enc")
    }

    private var symmetricKey: SymmetricKey {
        // Kullanıcı + servis bazlı deterministik 256-bit anahtar
        let seed = "MCBUpload.Vault.v1.\(MCBUploadPaths.realHomeDirectory).\(service)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private func loadAll() -> [String: String] {
        guard let raw = try? Data(contentsOf: fileURL), !raw.isEmpty else { return [:] }
        guard let box = try? AES.GCM.SealedBox(combined: raw),
              let decrypted = try? AES.GCM.open(box, using: symmetricKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: decrypted) else {
            return [:]
        }
        return dict
    }

    @discardableResult
    private func saveAll(_ dict: [String: String]) -> Bool {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(dict)
            let sealed = try AES.GCM.seal(data, using: symmetricKey)
            guard let combined = sealed.combined else { return false }
            try combined.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func setPassword(_ password: String, for account: String) -> Bool {
        var all = loadAll()
        all[account] = password
        return saveAll(all)
    }

    public func password(for account: String) -> String? {
        let all = loadAll()
        return all[account]
    }

    @discardableResult
    public func deletePassword(for account: String) -> Bool {
        var all = loadAll()
        all.removeValue(forKey: account)
        return saveAll(all)
    }
}
