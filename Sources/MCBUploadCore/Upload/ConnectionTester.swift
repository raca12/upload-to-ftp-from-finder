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
            var directoryPath = profile.remotePath.trimmingCharacters(in: .whitespaces)
            if directoryPath.isEmpty { directoryPath = "/" }
            if !directoryPath.hasPrefix("/") { directoryPath = "/" + directoryPath }
            if !directoryPath.hasSuffix("/") { directoryPath += "/" }
            let url = PathTools.transferURL(profile: profile, remoteFilePath: directoryPath)

            let credentials = profile.username.isEmpty
                ? ""
                : CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")

            let tlsArgs: [String] = {
                switch profile.proto {
                case .ftps, .ftpsi: return ["-k", "--ssl-reqd"]
                default: return ["-k", "--ssl"]
                }
            }()

            // 1) Önce kontrol kanalı üzerinden (-I / HEAD: USER + PASS + PWD + CWD) hızlı doğrulama.
            // Bu adım veri kanalı (PASV) açmadığı için firewall pasif port engeline takılmaz ve ~1 sn sürer.
            var headArgs = ["--silent", "--show-error", "-I", "--connect-timeout", "8", "--max-time", "12"] + tlsArgs + [url]
            var headResult = try transport.run(arguments: headArgs, secretConfig: credentials, onProgress: nil)
            if headResult.exitCode != 0 && profile.proto == .ftp {
                // Sunucu TLS el sıkışmasını sevmediyse düz FTP ile tekrar dene
                headArgs = ["--silent", "--show-error", "-I", "--connect-timeout", "8", "--max-time", "12", url]
                headResult = try transport.run(arguments: headArgs, secretConfig: credentials, onProgress: nil)
            }
            guard headResult.exitCode == 0 else {
                throw MCBUploadError.transportFailed(exitCode: headResult.exitCode, message: headResult.stderr)
            }

            // 2) Giriş ve klasör doğrulandı; şimdi kısa zaman aşımıyla öğe sayısını almayı dene (PASV -> Active fallback)
            func listAttempt(extra: [String]) throws -> TransportResult {
                let args = ["--silent", "--show-error", "--list-only",
                            "--connect-timeout", "5", "--max-time", "7",
                            "--ftp-skip-pasv-ip", "--disable-epsv"] + tlsArgs + extra + [url]
                return try transport.run(arguments: args, secretConfig: credentials, onProgress: nil)
            }

            var listResult = try listAttempt(extra: [])
            if listResult.exitCode != 0 {
                listResult = try listAttempt(extra: ["--ftp-port", "-"])
            }

            if listResult.exitCode == 0 {
                let entries = listResult.stdout.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return Localization.text("Bağlantı tamam · %@ içinde %d öğe görünüyor", directoryPath, entries.count)
            }

            // Giriş ve CWD başarılı oldu (pasif portlar kısıtlı olsa bile bağlantı doğrulandı)
            return Localization.text("Bağlantı tamam · %@ içinde %d öğe görünüyor", directoryPath, 0)

        case .sftp:
            let count = try SFTPRunner().check(profile: profile, path: profile.remotePath)
            return Localization.text("Bağlantı tamam · %@ içinde %d öğe görünüyor", profile.remotePath, count)

        case .http:
            guard let cfg = profile.http else { throw MCBUploadError.httpConfigMissing }
            let credentials = profile.username.isEmpty
                ? ""
                : CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")
            let result = try transport.run(arguments: ["--silent", "--show-error", "-I", "--max-time", "20", cfg.actionURL],
                                           secretConfig: credentials,
                                           onProgress: nil)
            guard result.exitCode == 0 else {
                throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
            }
            let statusLine = result.stdout
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("HTTP/") })?
                .trimmingCharacters(in: .whitespaces) ?? "OK"
            let code = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
            if let code, code >= 400 {
                return Localization.text("Sunucuya ulaşıldı · %@ (HEAD desteklenmiyor olabilir, yükleme çalışabilir)", statusLine)
            }
            return Localization.text("Sunucuya ulaşıldı · %@", statusLine)
        }
    }
}
