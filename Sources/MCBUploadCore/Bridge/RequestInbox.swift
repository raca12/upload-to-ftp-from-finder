import Foundation

// MARK: - Finder eklentisi → uygulama köprüsü
//
// Finder Sync extension ayrı bir süreç olduğu için yükleme isteğini diske yazar,
// uygulama da bu "gelen kutusu"nu okuyup işler.

public struct UploadRequest: Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case upload     // hemen yükle
        case queue      // pencereye ekle, kullanıcı klasörü kendi seçsin
    }

    public var id: UUID
    public var mode: Mode
    public var serverName: String?
    public var folder: String?
    public var files: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(),
                mode: Mode,
                serverName: String? = nil,
                folder: String? = nil,
                files: [String],
                createdAt: Date = Date()) {
        self.id = id
        self.mode = mode
        self.serverName = serverName
        self.folder = folder
        self.files = files
        self.createdAt = createdAt
    }
}

public struct RequestInbox {
    public static let notificationName = Notification.Name("com.mcb.upload.uploadRequest")

    public let directory: URL

    public init(baseDirectory: URL = ProfileStore().baseDirectory) {
        self.directory = baseDirectory.appendingPathComponent("inbox", isDirectory: true)
    }

    /// İsteği atomik olarak yazar; uygulama uyanık değilse bile kaybolmaz.
    public func submit(_ request: UploadRequest) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let target = directory.appendingPathComponent("\(request.id.uuidString).json")
        try data.write(to: target, options: .atomic)
    }

    /// Bekleyen istekleri döndürür ve kutuyu temizler.
    public func takeAll() throws -> [UploadRequest] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()

        // Tarih biçimi farklı yazılmış olabilir: iki stratejiyle de çözmeyi dene.
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        let plainDecoder = JSONDecoder()

        var requests: [UploadRequest] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url) {
                if let request = (try? isoDecoder.decode(UploadRequest.self, from: data))
                    ?? (try? plainDecoder.decode(UploadRequest.self, from: data)) {
                    requests.append(request)
                } else {
                    NSLog("Upload to FTP: istek okunamadı (%@)", name)
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
        return requests
    }

    /// Finder eklentisinden uygulamayı uyandırır (payload yok; istek diskte).
    public static func notifyApp() {
        DistributedNotificationCenter.default().post(name: notificationName, object: nil)
    }

    public static func observeApp(using handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in handler() }
    }
}
