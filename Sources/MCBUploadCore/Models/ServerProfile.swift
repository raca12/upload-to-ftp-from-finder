import Foundation

// MARK: - Protokoller

public enum TransferProtocol: String, Codable, CaseIterable, Sendable {
    case ftp          // düz FTP
    case ftps         // explicit TLS (AUTH TLS)
    case ftpsi        // implicit TLS (port 990)
    case sftp         // SSH File Transfer (Faz 2)
    case http         // multipart/form-data POST

    public var displayName: String {
        switch self {
        case .ftp: return "FTP"
        case .ftps: return "FTPS (explicit)"
        case .ftpsi: return "FTPS (implicit)"
        case .sftp: return "SFTP"
        case .http: return "HTTP POST"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .ftp, .ftps: return 21
        case .ftpsi: return 990
        case .sftp: return 22
        case .http: return 80
        }
    }
}

// MARK: - Alt ayarlar

public struct HTTPUploadConfig: Codable, Equatable, Sendable {
    /// Form gönderilecek adres, örn. https://ornek.com/upload.php
    public var actionURL: String
    /// Dosyanın gönderildiği form alanı adı
    public var fileField: String
    /// Ek form alanları (api_key, klasör, vb.)
    public var fields: [String: String]
    /// Ek HTTP başlıkları
    public var headers: [String: String]
    /// Sunucu cevabından dosya URL'sini çeken regex (ilk grup)
    public var fileURLRegex: String?
    /// Sunucu cevabından thumbnail URL'sini çeken regex (ilk grup)
    public var thumbURLRegex: String?
    /// Regex'te kullanılacak grup numarası
    public var matchGroup: Int

    public init(actionURL: String,
                fileField: String = "file",
                fields: [String: String] = [:],
                headers: [String: String] = [:],
                fileURLRegex: String? = nil,
                thumbURLRegex: String? = nil,
                matchGroup: Int = 1) {
        self.actionURL = actionURL
        self.fileField = fileField
        self.fields = fields
        self.headers = headers
        self.fileURLRegex = fileURLRegex
        self.thumbURLRegex = thumbURLRegex
        self.matchGroup = matchGroup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.actionURL = try c.decode(String.self, forKey: .actionURL)
        self.fileField = try c.decodeIfPresent(String.self, forKey: .fileField) ?? "file"
        self.fields = try c.decodeIfPresent([String: String].self, forKey: .fields) ?? [:]
        self.headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        self.fileURLRegex = try c.decodeIfPresent(String.self, forKey: .fileURLRegex)
        self.thumbURLRegex = try c.decodeIfPresent(String.self, forKey: .thumbURLRegex)
        self.matchGroup = try c.decodeIfPresent(Int.self, forKey: .matchGroup) ?? 1
    }
}

public struct ThumbnailConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Thumbnail de yüklensin mi?
    public var upload: Bool
    public var maxWidth: Int
    public var maxHeight: Int
    public var quality: Double
    /// Yüklenen dosya adına eklenecek sonek: resim_th.jpg
    public var suffix: String

    public init(enabled: Bool = true,
                upload: Bool = true,
                maxWidth: Int = 400,
                maxHeight: Int = 400,
                quality: Double = 0.8,
                suffix: String = "_th") {
        self.enabled = enabled
        self.upload = upload
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
        self.suffix = suffix
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.upload = try c.decodeIfPresent(Bool.self, forKey: .upload) ?? true
        self.maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth) ?? 400
        self.maxHeight = try c.decodeIfPresent(Int.self, forKey: .maxHeight) ?? 400
        self.quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.8
        self.suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? "_th"
    }
}

public struct ResizeConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var maxWidth: Int
    public var maxHeight: Int
    /// Yeniden boyutlandırılan görselin JPEG kalitesi (0...1)
    public var quality: Double

    public init(enabled: Bool = false, maxWidth: Int = 1920, maxHeight: Int = 1920, quality: Double = 0.9) {
        self.enabled = enabled
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.quality = quality
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth) ?? 1920
        self.maxHeight = try c.decodeIfPresent(Int.self, forKey: .maxHeight) ?? 1920
        self.quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.9
    }
}

/// MCB Upload'un "Auto-Sort" özelliği: uzak klasörü tarihe göre otomatik açar.
public struct AutoSortConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// {yyyy} {MM} {dd} {server} destekler, örn. "resimler/{yyyy}/{MM}"
    public var template: String

    public init(enabled: Bool = false, template: String = "{yyyy}/{MM}") {
        self.enabled = enabled
        self.template = template
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.template = try c.decodeIfPresent(String.self, forKey: .template) ?? "{yyyy}/{MM}"
    }
}

// MARK: - Sunucu profili

public struct ServerProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var proto: TransferProtocol
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    /// Yüklemenin yapılacağı uzak klasör, örn. /public_html/img
    public var remotePath: String
    /// FTP ile yüklendikten sonra link üretmek için kullanılacak web kökü
    public var publicBaseURL: String?
    public var http: HTTPUploadConfig?
    public var thumbnails: ThumbnailConfig
    public var resize: ResizeConfig
    public var autoSort: AutoSortConfig
    /// İsimlendirilmiş link şablonları: url, bbcode, html, markdown, ...
    public var templates: [String: String]

    public init(id: UUID = UUID(),
                name: String,
                proto: TransferProtocol,
                host: String,
                port: Int? = nil,
                username: String = "",
                password: String = "",
                remotePath: String = "/",
                publicBaseURL: String? = nil,
                http: HTTPUploadConfig? = nil,
                thumbnails: ThumbnailConfig = ThumbnailConfig(),
                resize: ResizeConfig = ResizeConfig(),
                autoSort: AutoSortConfig = AutoSortConfig(),
                templates: [String: String] = LinkTemplate.defaults) {
        self.id = id
        self.name = name
        self.proto = proto
        self.host = host
        self.port = port ?? proto.defaultPort
        self.username = username
        self.password = password
        self.remotePath = remotePath
        self.publicBaseURL = publicBaseURL
        self.http = http
        self.thumbnails = thumbnails
        self.resize = resize
        self.autoSort = autoSort
        self.templates = templates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ServerProfile.placeholder
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "isimsiz"
        self.proto = try c.decodeIfPresent(TransferProtocol.self, forKey: .proto) ?? .ftp
        self.host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        self.port = try c.decodeIfPresent(Int.self, forKey: .port) ?? proto.defaultPort
        self.username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.remotePath = try c.decodeIfPresent(String.self, forKey: .remotePath) ?? "/"
        self.publicBaseURL = try c.decodeIfPresent(String.self, forKey: .publicBaseURL)
        self.http = try c.decodeIfPresent(HTTPUploadConfig.self, forKey: .http)
        self.thumbnails = try c.decodeIfPresent(ThumbnailConfig.self, forKey: .thumbnails) ?? defaults.thumbnails
        self.resize = try c.decodeIfPresent(ResizeConfig.self, forKey: .resize) ?? defaults.resize
        self.autoSort = try c.decodeIfPresent(AutoSortConfig.self, forKey: .autoSort) ?? defaults.autoSort
        self.templates = try c.decodeIfPresent([String: String].self, forKey: .templates) ?? LinkTemplate.defaults
    }

    static let placeholder = ServerProfile(name: "placeholder", proto: .ftp, host: "")
}

// MARK: - Yüklenen dosya

public struct UploadedFile: Codable, Equatable, Sendable {
    public var localPath: String
    public var remoteURL: String
    public var thumbURL: String?
    public var bytes: Int64

    public init(localPath: String, remoteURL: String, thumbURL: String? = nil, bytes: Int64 = 0) {
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.thumbURL = thumbURL
        self.bytes = bytes
    }

    public var filename: String { (localPath as NSString).lastPathComponent }

    public var stem: String { (filename as NSString).deletingPathExtension }
    public var ext: String { (filename as NSString).pathExtension.lowercased() }

    public var displaySize: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
