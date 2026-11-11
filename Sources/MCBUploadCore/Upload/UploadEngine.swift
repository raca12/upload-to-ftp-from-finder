import Foundation
import UniformTypeIdentifiers

// MARK: - Yükleme motoru
//
// Akış: resize (opsiyonel) -> yükle -> thumbnail üret & yükle -> link üret

public struct UploadOptions {
    public var format: String
    /// Sunucu profilindeki klasörün yerine kullanılacak mutlak klasör (kullanıcı yüklerken seçtiyse)
    public var remoteDirectory: String?
    /// Seçilen klasörün altına eklenecek alt klasör
    public var folder: String?
    public var makeThumbnail: Bool?
    public var dryRun: Bool
    public var onFileProgress: ((URL, Double) -> Void)?
    public var onStatus: ((String) -> Void)?

    public init(format: String = "url",
                remoteDirectory: String? = nil,
                folder: String? = nil,
                makeThumbnail: Bool? = nil,
                dryRun: Bool = false,
                onFileProgress: ((URL, Double) -> Void)? = nil,
                onStatus: ((String) -> Void)? = nil) {
        self.format = format
        self.remoteDirectory = remoteDirectory
        self.folder = folder
        self.makeThumbnail = makeThumbnail
        self.dryRun = dryRun
        self.onFileProgress = onFileProgress
        self.onStatus = onStatus
    }
}

public struct UploadEngine {
    private let transport: Transport
    private let images: ImageProcessor

    public init(transport: Transport = CurlTransport(), images: ImageProcessor = ImageProcessor()) {
        self.transport = transport
        self.images = images
    }

    public func upload(files: [URL], profile: ServerProfile, options: UploadOptions) throws -> [UploadedFile] {
        guard !files.isEmpty else { return [] }
        var results: [UploadedFile] = []

        let autoSort = profile.autoSort.enabled
            ? Template.autoSortPath(template: profile.autoSort.template, serverName: profile.name)
            : nil
        let baseDirectory = options.remoteDirectory ?? profile.remotePath
        let remoteDir = PathTools.join(baseDirectory, autoSort, options.folder)

        for file in files {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else {
                throw MCBUploadError.fileNotFound(file.path)
            }

            let status = options.onStatus
            status?("Hazırlanıyor: \(file.lastPathComponent)")

            // 1) Yükleme öncesi yeniden boyutlandırma
            var workingFile = file
            var tempToClean: URL?
            if profile.resize.enabled, images.isImage(file) {
                if let resized = try images.resized(file,
                                                   maxWidth: profile.resize.maxWidth,
                                                   maxHeight: profile.resize.maxHeight,
                                                   quality: profile.resize.quality) {
                    workingFile = resized
                    tempToClean = resized
                    status?("Yeniden boyutlandırıldı: \(file.lastPathComponent)")
                }
            }

            defer {
                if let tempToClean { try? FileManager.default.removeItem(at: tempToClean) }
            }

            let remoteName = Self.remoteName(original: file, working: workingFile)
            let remotePath = PathTools.join(remoteDir, remoteName)

            // 2) Ana dosya
            status?("Yükleniyor: \(remoteName)")
            let uploaded = try transfer(file: workingFile,
                                        profile: profile,
                                        remotePath: remotePath,
                                        remoteName: remoteName,
                                        fieldName: nil,
                                        options: options)

            let linkPath = PathTools.relativePath(remotePath, base: profile.remotePath)
            var remoteURL = uploaded.url
            if remoteURL.isEmpty {
                remoteURL = PathTools.publicURL(profile: profile, remoteFilePath: linkPath)
            }
            remoteURL = PathTools.sanitizeURL(remoteURL)

            // 3) Thumbnail
            var thumbURL: String?
            let wantsThumb = options.makeThumbnail ?? profile.thumbnails.enabled
            if wantsThumb, profile.thumbnails.upload, images.isImage(file) {
                do {
                    if let thumbLocal = try images.thumbnail(file,
                                                             maxWidth: profile.thumbnails.maxWidth,
                                                             maxHeight: profile.thumbnails.maxHeight,
                                                             quality: profile.thumbnails.quality) {
                        defer { try? FileManager.default.removeItem(at: thumbLocal) }
                        let thumbName = Self.thumbName(original: file, working: thumbLocal, config: profile.thumbnails)
                        let thumbPath = PathTools.join(remoteDir, thumbName)
                        status?("Thumbnail yükleniyor: \(thumbName)")
                        let thumbUpload = try transfer(file: thumbLocal,
                                                       profile: profile,
                                                       remotePath: thumbPath,
                                                       remoteName: thumbName,
                                                       fieldName: nil,
                                                       options: options)
                        let thumbLinkPath = PathTools.relativePath(thumbPath, base: profile.remotePath)
                        thumbURL = PathTools.sanitizeURL(thumbUpload.url.isEmpty
                            ? PathTools.publicURL(profile: profile, remoteFilePath: thumbLinkPath)
                            : thumbUpload.url)
                    }
                } catch {
                    // Thumbnail hatası ana yüklemeyi bozmasın
                    status?("Thumbnail atlandı: \(error.localizedDescription)")
                }
            }

            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            results.append(UploadedFile(localPath: file.path,
                                        remoteURL: remoteURL,
                                        thumbURL: thumbURL,
                                        bytes: size))
        }

        TempFiles.cleanup()
        return results
    }

    // MARK: - Aktarım

    private func transfer(file: URL,
                          profile: ServerProfile,
                          remotePath: String,
                          remoteName: String?,
                          fieldName: String?,
                          options: UploadOptions) throws -> (url: String, response: String) {
        if options.dryRun {
            return (PathTools.publicURL(profile: profile, remoteFilePath: remotePath), "")
        }

        let progress: (Double) -> Void = { value in options.onFileProgress?(file, value) }

        switch profile.proto {
        case .ftp, .ftps, .ftpsi:
            let url = PathTools.transferURL(profile: profile, remoteFilePath: remotePath)
            var args = baseArgs()
            if profile.proto == .ftps { args.append("--ssl-reqd") }
            args.append(contentsOf: ["--ftp-create-dirs", "-T", file.path, url])
            let secret = curlCredentials(profile)
            let result = try transport.run(arguments: args, secretConfig: secret, onProgress: progress)
            try ensureSuccess(result)
            return ("", result.stdout)

        case .sftp:
            throw MCBUploadError.unsupportedProtocol("SFTP (macOS'ta sistem curl'ü SSH desteklemiyor — Faz 2'de libssh2/swift-nio-ssh ile gelecek)")

        case .http:
            guard let cfg = profile.http else { throw MCBUploadError.httpConfigMissing }
            var args = baseArgs()
            args.append(contentsOf: ["-X", "POST", cfg.actionURL])
            for (key, value) in cfg.headers {
                args.append(contentsOf: ["-H", "\(key): \(value)"])
            }
            let field = fieldName ?? cfg.fileField
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
            args.append(contentsOf: ["-F", Self.formFileValue(field: field,
                                                              path: file.path,
                                                              filename: remoteName,
                                                              mimeType: mime)])
            for (key, value) in cfg.fields.sorted(by: { $0.key < $1.key }) {
                args.append(contentsOf: ["--form-string", "\(key)=\(value)"])
            }
            let secret = curlCredentials(profile)
            let result = try transport.run(arguments: args, secretConfig: secret, onProgress: progress)
            try ensureSuccess(result)
            let url = Self.extractURL(from: result.stdout, regex: cfg.fileURLRegex, group: cfg.matchGroup) ?? ""
            return (url, result.stdout)
        }
    }

    private func baseArgs() -> [String] {
        ["--progress-bar", "--show-error", "--fail-with-body",
         "--max-time", "900", "--connect-timeout", "20", "--retry", "1"]
    }

    private func curlCredentials(_ profile: ServerProfile) -> String {
        guard !profile.username.isEmpty else { return "" }
        return CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")
    }

    private func ensureSuccess(_ result: TransportResult) throws {
        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: message)
        }
    }

    // MARK: - Yardımcılar

    /// -F alanı için güvenli değer: file=@"/yol/dosya adı.jpg";type=image/jpeg;filename=hedef.jpg
    public static func formFileValue(field: String,
                                     path: String,
                                     filename: String? = nil,
                                     mimeType: String? = nil) -> String {
        let needsQuotes = path.contains(where: { $0 == ";" || $0 == "," || $0 == "\"" || $0 == "\\" })
        var value = "\(field)=@"
        if needsQuotes {
            value += "\"" + path.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        } else {
            value += path
        }
        if let mimeType, !mimeType.isEmpty {
            value += ";type=\(mimeType)"
        }
        if let filename, !filename.isEmpty {
            let safe = filename.replacingOccurrences(of: "\"", with: "")
            value += needsQuotes ? ";filename=\"\(safe)\"" : ";filename=\(safe)"
        }
        return value
    }

    public static func extractURL(from response: String, regex: String?, group: Int) -> String? {
        if let regex, !regex.isEmpty {
            guard let re = try? NSRegularExpression(pattern: regex, options: [.anchorsMatchLines, .dotMatchesLineSeparators]) else {
                return nil
            }
            let range = NSRange(response.startIndex..<response.endIndex, in: response)
            guard let match = re.firstMatch(in: response, options: [], range: range) else { return nil }
            let index = min(max(0, group), match.numberOfRanges - 1)
            guard let r = Range(match.range(at: index), in: response) else { return nil }
            return unescapeJSONString(String(response[r])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Regex yoksa: yanıt tek başına bir URL ise onu kullan
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        return nil
    }

    /// JSON yanıtından regex ile alınan değerdeki kaçış dizilerini çözer (\u0308, \/, \" gibi).
    public static func unescapeJSONString(_ input: String) -> String {
        guard input.contains("\\") else { return input }
        var out = ""
        let pending: [Character] = Array(input)
        var index = 0
        while index < pending.count {
            let ch = pending[index]
            guard ch == "\\", index + 1 < pending.count else {
                out.append(ch)
                index += 1
                continue
            }
            let next = pending[index + 1]
            switch next {
            case "n": out.append("\n"); index += 2
            case "t": out.append("\t"); index += 2
            case "r": out.append("\r"); index += 2
            case "u":
                if index + 5 < pending.count,
                   let code = UInt32(String(pending[(index + 2)...(index + 5)]), radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    out.append(Character(scalar))
                    index += 6
                } else {
                    out.append(next); index += 2
                }
            default:
                out.append(next); index += 2
            }
        }
        return out
    }

    static func remoteName(original: URL, working: URL) -> String {
        let stem = original.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        let ext = working.pathExtension.isEmpty ? original.pathExtension : working.pathExtension
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    static func thumbName(original: URL, working: URL, config: ThumbnailConfig) -> String {
        let stem = original.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        let ext = working.pathExtension.isEmpty ? original.pathExtension : working.pathExtension
        return ext.isEmpty ? "\(stem)\(config.suffix)" : "\(stem)\(config.suffix).\(ext)"
    }
}
