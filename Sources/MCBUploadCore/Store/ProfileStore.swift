import Foundation

// MARK: - Yollar
// Sandbox'lı süreçlerde FileManager ev dizinini container'a çevirir;
// uygulama ile Finder eklentisinin aynı dosyayı görmesi için gerçek ev dizinini passwd'dan okuyoruz.

public enum MCBUploadPaths {
    public static var realHomeDirectory: String {
        String(cString: getpwuid(getuid())!.pointee.pw_dir)
    }

    /// Eski adla (Rightload) kullanılan ayar klasörü — bir kereliğine taşınır.
    private static var legacyBaseDirectory: URL {
        URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/RightloadMac", isDirectory: true)
    }

    public static var sharedBaseDirectory: URL {
        let base = URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/MCBUpload", isDirectory: true)
        migrateLegacyDataIfNeeded(to: base)
        return base
    }

    private static var migrationChecked = false

    private static func migrateLegacyDataIfNeeded(to destination: URL) {
        guard !migrationChecked else { return }
        migrationChecked = true
        let fm = FileManager.default
        let legacy = legacyBaseDirectory
        guard !fm.fileExists(atPath: destination.path),
              fm.fileExists(atPath: legacy.path) else { return }
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in (try? fm.contentsOfDirectory(atPath: legacy.path)) ?? [] {
                try? fm.copyItem(at: legacy.appendingPathComponent(name),
                                 to: destination.appendingPathComponent(name))
            }
            NSLog("MCB Upload: eski ayarlar taşındı")
        } catch {
            NSLog("MCB Upload: ayar taşıma hatası \(error.localizedDescription)")
        }
    }
}

// MARK: - Sunucu profilleri deposu
//
// Konum: MCB_HOME > ~/Library/Application Support/MCBUpload/servers.json

public final class ProfileStore {
    public let baseDirectory: URL
    public let credentials: CredentialStore

    public var fileURL: URL { baseDirectory.appendingPathComponent("servers.json") }

    public init(baseDirectory: URL? = nil, credentials: CredentialStore = CredentialStore()) {
        self.credentials = credentials
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let custom = ProcessInfo.processInfo.environment["MCB_HOME"], !custom.isEmpty {
            self.baseDirectory = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            self.baseDirectory = MCBUploadPaths.sharedBaseDirectory
        }
    }

    // MARK: - Okuma / yazma

    /// Sunucuları okur. `resolvePasswords` false ise Keychain'e hiç dokunulmaz
    /// (Finder eklentisi yalnızca isimleri okur).
    public func load(resolvePasswords: Bool = true) throws -> [ServerProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        var servers = try JSONDecoder.mcb.decode(ServerDocument.self, from: data).servers
        guard resolvePasswords else { return servers }

        // Eski sürümden kalan düz metin parolaları Keychain'e taşı
        var migrated = false
        for index in servers.indices where !servers[index].password.isEmpty {
            // Yalnızca Keychain'e yazılabildiyse JSON'dan sil (aksi halde parola kaybolur)
            if credentials.setPassword(servers[index].password, for: servers[index].id.uuidString) {
                servers[index].password = ""
                migrated = true
            }
        }
        if migrated { try? writeDocument(servers) }

        for index in servers.indices {
            if let password = credentials.password(for: servers[index].id.uuidString) {
                servers[index].password = password
            }
        }
        return servers
    }

    /// Parolalar Keychain'e, geri kalan her şey JSON'a yazılır.
    public func save(_ servers: [ServerProfile]) throws {
        var stored = servers
        for index in stored.indices {
            let account = stored[index].id.uuidString
            if stored[index].password.isEmpty {
                credentials.deletePassword(for: account)
            } else if !credentials.setPassword(stored[index].password, for: account) {
                // Keychain'e yazılamadıysa parolayı JSON'da tut (veri kaybı olmasın)
                continue
            } else {
                stored[index].password = ""
            }
        }
        try writeDocument(stored)
    }

    private func writeDocument(_ servers: [ServerProfile]) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let document = ServerDocument(version: 1, servers: servers)
        let data = try JSONEncoder.mcb.encode(document)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Tek bir sunucunun parolasını Keychain'den okur (parola zaten doluysa dokunmaz).
    public func password(for server: ServerProfile) -> String {
        if !server.password.isEmpty { return server.password }
        return credentials.password(for: server.id.uuidString) ?? ""
    }

    public func upsert(_ server: ServerProfile) throws {
        var servers = try load()
        if let index = servers.firstIndex(where: { $0.id == server.id || $0.name == server.name }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        try save(servers)
    }

    public func delete(id: UUID) throws {
        var servers = try load()
        servers.removeAll { $0.id == id }
        try save(servers)
    }

    public func find(_ nameOrID: String) throws -> ServerProfile {        let servers = try load()
        let needle = nameOrID.lowercased()
        if let match = servers.first(where: { $0.name.lowercased() == needle }) { return match }
        if let uuid = UUID(uuidString: nameOrID),
           let match = servers.first(where: { $0.id == uuid }) { return match }
        if let match = servers.first(where: { $0.name.lowercased().hasPrefix(needle) }) { return match }
        throw MCBUploadError.serverNotFound(nameOrID)
    }

    /// İlk çalıştırmada örnek profilleri yazar.
    @discardableResult
    public func ensureSeeded() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        try save(ServerProfile.examples)
        return true
    }
}

public struct ServerDocument: Codable {
    public var version: Int
    public var servers: [ServerProfile]

    public init(version: Int = 1, servers: [ServerProfile]) {
        self.version = version
        self.servers = servers
    }
}

// MARK: - JSON kodlayıcılar

public extension JSONEncoder {
    static var mcb: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var mcb: JSONDecoder {
        JSONDecoder()
    }
}

// MARK: - Örnek profiller

public extension ServerProfile {
    static var examples: [ServerProfile] {
        [
            ServerProfile(
                name: "Yerel test sunucusu",
                proto: .http,
                host: "127.0.0.1",
                port: 8099,
                remotePath: "/",
                publicBaseURL: "http://127.0.0.1:8099/files",
                http: HTTPUploadConfig(
                    actionURL: "http://127.0.0.1:8099/upload",
                    fileField: "file",
                    fields: ["klasor": "genel"],
                    fileURLRegex: #""url"\s*:\s*"([^"]+)""#
                )
            ),
            ServerProfile(
                name: "FTP Örneği",
                proto: .ftp,
                host: "ftp.ornek.com",
                username: "kullanici",
                password: "sifre",
                remotePath: "/public_html/resimler",
                publicBaseURL: "https://ornek.com/resimler",
                autoSort: AutoSortConfig(enabled: true, template: "{yyyy}/{MM}")
            ),
        ]
    }
}
