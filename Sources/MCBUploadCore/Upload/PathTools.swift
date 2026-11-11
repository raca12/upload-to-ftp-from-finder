import Foundation

// MARK: - Hatalar

public enum MCBUploadError: LocalizedError {
    case serverNotFound(String)
    case unsupportedProtocol(String)
    case httpConfigMissing
    case missingCredential(String)
    case transportFailed(exitCode: Int32, message: String)
    case urlNotDetected(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotFound(let name):
            return Localization.text("Sunucu bulunamadı: %@. `mcb servers` ile listeye bakabilirsin.", name)
        case .unsupportedProtocol(let proto):
            return Localization.text("Bu protokol henüz desteklenmiyor: %@", proto)
        case .httpConfigMissing:
            return Localization.text("HTTP profili için 'http.actionURL' tanımlanmalı.")
        case .missingCredential(let what):
            return Localization.text("Eksik bilgi: %@", what)
        case .transportFailed(let code, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty ? "?" : trimmed
            return Localization.text("Aktarım başarısız (çıkış kodu %d): %@", code, detail)
        case .urlNotDetected(let response):
            let preview = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return Localization.text("Dosya yüklendi ama yanıttan URL çıkarılamadı. Yanıt: %@", String(preview.prefix(400)))
        case .fileNotFound(let path):
            return Localization.text("Dosya bulunamadı: %@", path)
        }
    }
}

// MARK: - Uzak yol / URL yardımcıları

public enum PathTools {
    /// "/public_html/img/" + "2026/11" + "resim.jpg" -> "/public_html/img/2026/11/resim.jpg"
    public static func join(_ parts: String?...) -> String {
        let pieces = parts
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "/" }
            .flatMap { $0.split(separator: "/").map(String.init) }
        let joined = pieces.joined(separator: "/")
        return "/" + joined
    }

    public static func encodeRemotePath(_ path: String) -> String {
        // Boşluk ve Türkçe karakterleri yüzde-kodla, "/" korunur.
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "/-._~!$&'()*+,;=:@")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    /// FTP protokolünde yükleme adresini üretir.
    public static func transferURL(profile: ServerProfile, remoteFilePath: String) -> String {
        let host = profile.host
        let portPart = (profile.port == profile.proto.defaultPort) ? "" : ":\(profile.port)"
        switch profile.proto {
        case .ftps:
            return "ftp://\(host)\(portPart)\(encodeRemotePath(remoteFilePath))"
        case .ftpsi:
            return "ftps://\(host)\(portPart)\(encodeRemotePath(remoteFilePath))"
        case .ftp:
            return "ftp://\(host)\(portPart)\(encodeRemotePath(remoteFilePath))"
        case .sftp:
            return "sftp://\(host)\(portPart)\(encodeRemotePath(remoteFilePath))"
        case .http:
            return profile.http?.actionURL ?? ""
        }
    }

    /// Seçilen mutlak yolu, profilin klasörüne göre kısaltır.
    /// Örn. base "/public_html/img", path "/public_html/img/2026/a.jpg" → "/2026/a.jpg"
    public static func relativePath(_ path: String, base: String) -> String {
        var normalizedBase = base.trimmingCharacters(in: .whitespaces)
        if normalizedBase.isEmpty || normalizedBase == "/" { return path }
        if normalizedBase.hasSuffix("/") { normalizedBase.removeLast() }
        if path == normalizedBase { return "/" }
        if path.hasPrefix(normalizedBase + "/") {
            return String(path.dropFirst(normalizedBase.count))
        }
        return path
    }

    /// Sunucudan dönen linkteki boşluk/Unicode karakterleri kodlar (zaten kodlanmış % dizilerini bozmadan).
    public static func sanitizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "%/:#?&=@+,!$'()*~")
        let composed = trimmed.precomposedStringWithCanonicalMapping
        return composed.addingPercentEncoding(withAllowedCharacters: allowed) ?? composed
    }

    /// FTP yüklemede genel erişilebilir link: publicBaseURL + uzak yol.
    public static func publicURL(profile: ServerProfile, remoteFilePath: String) -> String {
        guard let base = profile.publicBaseURL?.trimmingCharacters(in: .whitespaces), !base.isEmpty else {
            return encodeRemotePath(remoteFilePath)
        }
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmedBase + encodeRemotePath(remoteFilePath)
    }
}
