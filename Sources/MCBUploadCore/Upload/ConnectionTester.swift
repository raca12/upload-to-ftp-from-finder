import Foundation

// MARK: - Bağlantı testi
// Sunucu ekleme ekranındaki "Bağlantıyı Test Et" düğmesinin arkası.

public struct ConnectionTester {
    private let transport: Transport

    public init(transport: Transport = CurlTransport()) {
        self.transport = transport
    }

    /// Başarılıysa kullanıcıya gösterilecek kısa bir mesaj döndürür.
    public func test(_ profile: ServerProfile) throws -> String {
        switch profile.proto {
        case .ftp, .ftps, .ftpsi:
            var directoryPath = profile.remotePath
            if !directoryPath.hasSuffix("/") { directoryPath += "/" }
            let url = PathTools.transferURL(profile: profile, remoteFilePath: directoryPath)

            let credentials = profile.username.isEmpty
                ? ""
                : CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")

            // Bazı sunucular PASV yanıtında iç IP döndürür; ilk denemede bunu yok say.
            // Zaman aşımında EPSV'yi kapatıp yeniden dene (firewall/NAT uyumluluğu).
            func attempt(extra: [String]) throws -> TransportResult {
                var args = ["--silent", "--show-error", "--list-only", "--max-time", "45",
                            "--ftp-skip-pasv-ip", url] + extra
                if profile.proto == .ftps { args.append("--ssl-reqd") }
                return try transport.run(arguments: args, secretConfig: credentials, onProgress: nil)
            }

            var result = try attempt(extra: [])
            if result.exitCode != 0 {
                result = try attempt(extra: ["--disable-epsv"])
            }
            guard result.exitCode == 0 else {
                throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
            }
            let entries = result.stdout.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Localization.text("Bağlantı tamam · %@ içinde %d öğe görünüyor", profile.remotePath, entries.count)

        case .sftp:
            let count = try SFTPRunner().check(profile: profile, path: profile.remotePath)
            return Localization.text("Bağlantı tamam · %@ içinde %d öğe görünüyor", profile.remotePath, count)

        case .http:
            guard let cfg = profile.http else { throw MCBUploadError.httpConfigMissing }
            let credentials = profile.username.isEmpty
                ? ""
                : CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")
            let result = try transport.run(arguments: ["--silent", "--show-error", "-I", "--max-time", "25", cfg.actionURL],
                                           secretConfig: credentials,
                                           onProgress: nil)
            guard result.exitCode == 0 else {
                throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
            }
            let statusLine = result.stdout
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("HTTP/") })?
                .trimmingCharacters(in: .whitespaces) ?? "yanıt alındı"
            let code = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
            if let code, code >= 400 {
                return Localization.text("Sunucuya ulaşıldı · %@ (HEAD desteklenmiyor olabilir, yükleme çalışabilir)", statusLine)
            }
            return Localization.text("Sunucuya ulaşıldı · %@", statusLine)
        }
    }
}
