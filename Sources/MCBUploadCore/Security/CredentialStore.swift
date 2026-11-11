import Foundation
import Security

// MARK: - FTP şifreleri için Keychain
//
// Sunucu profilleri JSON'da tutulur ama parolalar macOS Keychain'de saklanır.
// Hesap anahtarı sunucunun UUID'sidir.

public struct CredentialStore {

    public let service: String

    public init(service: String = "com.mcb.upload.ftp") {
        self.service = service
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    public func setPassword(_ password: String, for account: String) -> Bool {
        let data = Data(password.utf8)
        var attributes = query(account: account)
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)

        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let result = SecItemUpdate(attributes as CFDictionary, update as CFDictionary)
            if result != errSecSuccess { logFailure("güncelleme", result) }
            return result == errSecSuccess
        }

        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrLabel as String] = "Upload to FTP from Finder"
        let result = SecItemAdd(attributes as CFDictionary, nil)
        if result != errSecSuccess { logFailure("ekleme", result) }
        return result == errSecSuccess
    }

    private func logFailure(_ operation: String, _ status: OSStatus) {
        guard ProcessInfo.processInfo.environment["MCB_KEYCHAIN_DEBUG"] != nil else { return }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "bilinmeyen"
        FileHandle.standardError.write(Data("Keychain \(operation) hatası: \(status) \(message)\n".utf8))
    }

    public func password(for account: String) -> String? {
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    @discardableResult
    public func deletePassword(for account: String) -> Bool {
        SecItemDelete(query(account: account) as CFDictionary) == errSecSuccess
    }
}
