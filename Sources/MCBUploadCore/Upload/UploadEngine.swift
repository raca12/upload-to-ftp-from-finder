import Foundation
import UniformTypeIdentifiers

// MARK: - Dosya çakışması çözümü

public enum UploadConflictResolution: Equatable, Sendable {
    case overwrite
    case rename(String)
    case skip
    case cancel
}

public struct ExpandedUploadItem: Equatable, Sendable {
    public let url: URL
    /// Klasör seçildiyse sunucuda korunacak göreli alt klasör yolu (örn. "kampanya/2026")
    public let relativeSubfolder: String?

    public init(url: URL, relativeSubfolder: String? = nil) {
        self.url = url
        self.relativeSubfolder = relativeSubfolder
    }

    public var displayName: String {
        if let sub = relativeSubfolder, !sub.isEmpty {
            return "\(sub)/\(url.lastPathComponent)"
        }
        return url.lastPathComponent
    }
}

// MARK: - Yükleme motoru
//
// Akış: klasörleri aç -> çakışma kontrolü -> resize -> yükle -> thumbnail -> link üret

public struct UploadOptions {
    public var format: String
    /// Sunucu profilindeki klasörün yerine kullanılacak mutlak klasör (kullanıcı yüklerken seçtiyse)
    public var remoteDirectory: String?
    /// Seçilen klasörün altına eklenecek alt klasör
    public var folder: String?
    /// Dosya bazlı göreli alt klasör haritası (standardizedFileURL.path -> "alt/klasor")
    public var subfoldersByFile: [String: String]
    public var makeThumbnail: Bool?
    public var dryRun: Bool
    public var onFileProgress: ((URL, Double) -> Void)?
    public var onFileSkipped: ((URL) -> Void)?
    public var onStatus: ((String) -> Void)?
    /// (remoteDir, existingFilename, suggestedNewName) -> çözüm
    public var onConflict: ((String, String, String) -> UploadConflictResolution)?

    public init(format: String = "url",
                remoteDirectory: String? = nil,
                folder: String? = nil,
                subfoldersByFile: [String: String] = [:],
                makeThumbnail: Bool? = nil,
                dryRun: Bool = false,
                onFileProgress: ((URL, Double) -> Void)? = nil,
                onFileSkipped: ((URL) -> Void)? = nil,
                onStatus: ((String) -> Void)? = nil,
                onConflict: ((String, String, String) -> UploadConflictResolution)? = nil) {
        self.format = format
        self.remoteDirectory = remoteDirectory
        self.folder = folder
        self.subfoldersByFile = subfoldersByFile
        self.makeThumbnail = makeThumbnail
        self.dryRun = dryRun
        self.onFileProgress = onFileProgress
        self.onFileSkipped = onFileSkipped
        self.onStatus = onStatus
        self.onConflict = onConflict
    }
}

public struct UploadEngine {
    private let transport: Transport
    private let images: ImageProcessor

    public init(transport: Transport = CurlTransport(), images: ImageProcessor = ImageProcessor()) {
        self.transport = transport
        self.images = images
    }

    /// Verilen dosya ve klasör URL'lerini tarar; klasörlerin içindeki alt klasörleri göreli yollarıyla açar.
    public static func expandFiles(_ urls: [URL], limit: Int = 2000) -> [ExpandedUploadItem] {
        var out: [ExpandedUploadItem] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if !isDir.boolValue {
                if seen.insert(url.path).inserted {
                    out.append(ExpandedUploadItem(url: url, relativeSubfolder: nil))
                }
                continue
            }

            let rootFolderName = url.lastPathComponent
            let rootPath = url.path.hasSuffix("/") ? url.path : url.path + "/"
            guard let enumerator = fm.enumerator(at: url,
                                                 includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                continue
            }
            for case let childURL as URL in enumerator {
                if out.count >= limit { break }
                let standardized = childURL.standardizedFileURL
                let values = try? standardized.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if (values?.isHidden ?? false) || standardized.lastPathComponent == ".DS_Store" { continue }
                guard seen.insert(standardized.path).inserted else { continue }

                var relDir = ""
                if standardized.path.hasPrefix(rootPath) {
                    let sub = String(standardized.path.dropFirst(rootPath.count))
                    let dirPart = (sub as NSString).deletingLastPathComponent
                    relDir = dirPart.isEmpty || dirPart == "."
                        ? rootFolderName
                        : "\(rootFolderName)/\(dirPart)"
                } else {
                    relDir = rootFolderName
                }
                out.append(ExpandedUploadItem(url: standardized, relativeSubfolder: relDir))
            }
        }
        return out
    }

    /// Çakışma durumunda klasörde olmayan "dosya-1.jpg", "dosya-2.jpg" gibi benzersiz bir ad önerir.
    public static func suggestUniqueName(for filename: String, existing: Set<String>) -> String {
        let ns = filename as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        let lowered = Set(existing.map { $0.lowercased() })
        for index in 1...999 {
            let candidate = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            if !lowered.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return ext.isEmpty ? "\(stem)-\(UUID().uuidString.prefix(4))" : "\(stem)-\(UUID().uuidString.prefix(4)).\(ext)"
    }

    /// Hedef klasörün son parçası ile alt klasörün ilk parçası aynıysa mükerrer klasör oluşmasını önler.
    public static func resolveRemoteDir(rootRemoteDir: String, subfolder: String?) -> String {
        guard let sub = subfolder?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty else {
            return rootRemoteDir
        }
        let rootParts = rootRemoteDir.split(separator: "/").map(String.init)
        var subParts = sub.split(separator: "/").map(String.init)
        if let lastRoot = rootParts.last, let firstSub = subParts.first,
           lastRoot.caseInsensitiveCompare(firstSub) == .orderedSame {
            subParts.removeFirst()
        }
        if subParts.isEmpty { return rootRemoteDir }
        return PathTools.join(rootRemoteDir, subParts.joined(separator: "/"))
    }

    /// Yüklemeden önce kullanıcıya gösterilecek canlı örnek linki üretir.
    public static func previewLink(profile: ServerProfile,
                                   remoteDirectory: String?,
                                   folder: String?,
                                   sampleFileName: String,
                                   relativeSubfolder: String?,
                                   format: String) -> String {
        let autoSort = profile.autoSort.enabled
            ? Template.autoSortPath(template: profile.autoSort.template, serverName: profile.name)
            : nil
        let baseDirectory = remoteDirectory ?? profile.remotePath
        let rootRemoteDir = PathTools.join(baseDirectory, autoSort, folder)
        let remoteDir = resolveRemoteDir(rootRemoteDir: rootRemoteDir, subfolder: relativeSubfolder)
        let remotePath = PathTools.join(remoteDir, sampleFileName)
        let linkPath = PathTools.relativePath(remotePath, base: profile.remotePath)
        let rawURL = PathTools.sanitizeURL(PathTools.publicURL(profile: profile, remoteFilePath: linkPath))

        let sampleURL = URL(fileURLWithPath: sampleFileName)
        let thumbName = Self.thumbName(original: sampleURL, working: sampleURL, config: profile.thumbnails)
        let thumbPath = PathTools.join(remoteDir, thumbName)
        let thumbLinkPath = PathTools.relativePath(thumbPath, base: profile.remotePath)
        let rawThumbURL = profile.thumbnails.enabled
            ? PathTools.sanitizeURL(PathTools.publicURL(profile: profile, remoteFilePath: thumbLinkPath))
            : nil

        let fakeUploaded = UploadedFile(localPath: sampleFileName,
                                        remoteURL: rawURL,
                                        thumbURL: rawThumbURL,
                                        bytes: 0)
        return LinkTemplate.format(fakeUploaded, templateName: format, server: profile) ?? rawURL
    }

    public func upload(files: [URL], profile: ServerProfile, options: UploadOptions) throws -> [UploadedFile] {
        guard !files.isEmpty else { return [] }

        // Doğrudan klasör URL'si verildiyse alt klasörleriyle aç
        var fileList: [URL] = []
        var subfolders = options.subfoldersByFile
        for url in files {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                for item in Self.expandFiles([url]) {
                    fileList.append(item.url)
                    if let sub = item.relativeSubfolder {
                        subfolders[item.url.standardizedFileURL.path] = sub
                    }
                }
            } else {
                fileList.append(url)
            }
        }

        var results: [UploadedFile] = []

        let autoSort = profile.autoSort.enabled
            ? Template.autoSortPath(template: profile.autoSort.template, serverName: profile.name)
            : nil
        let baseDirectory = options.remoteDirectory ?? profile.remotePath
        let rootRemoteDir = PathTools.join(baseDirectory, autoSort, options.folder)

        // Klasör bazlı mevcut dosya önbelleği (çakışma tespiti için)
        var existingFilesByDir: [String: Set<String>] = [:]
        let lister = DirectoryLister(transport: transport)

        func existingFiles(in dir: String) -> Set<String> {
            if let cached = existingFilesByDir[dir] { return cached }
            guard !options.dryRun, profile.proto != .http else {
                existingFilesByDir[dir] = []
                return []
            }
            let entries = (try? lister.list(profile: profile, path: dir)) ?? []
            let names = Set(entries.filter { !$0.isDirectory }.map { $0.name })
            existingFilesByDir[dir] = names
            return names
        }

        for file in fileList {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else {
                throw MCBUploadError.fileNotFound(file.path)
            }

            let status = options.onStatus
            status?("Hazırlanıyor: \(file.lastPathComponent)")
            options.onFileProgress?(file, 0.02)

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

            let sub = subfolders[file.standardizedFileURL.path] ?? subfolders[file.path]
            let remoteDir = Self.resolveRemoteDir(rootRemoteDir: rootRemoteDir, subfolder: sub)
            var remoteName = Self.remoteName(original: file, working: workingFile)

            // 2) Çakışma kontrolü (sunucuda aynı isimde dosya var mı?)
            if let onConflict = options.onConflict, !options.dryRun, profile.proto != .http {
                var known = existingFiles(in: remoteDir)
                if known.contains(where: { $0.caseInsensitiveCompare(remoteName) == .orderedSame }) {
                    let suggested = Self.suggestUniqueName(for: remoteName, existing: known)
                    let decision = onConflict(remoteDir, remoteName, suggested)
                    switch decision {
                    case .overwrite:
                        break
                    case .rename(let customName):
                        let cleaned = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { remoteName = cleaned }
                    case .skip:
                        status?("Atlandı: \(remoteName)")
                        options.onFileSkipped?(file)
                        continue
                    case .cancel:
                        TempFiles.cleanup()
                        return results
                    }
                }
                known.insert(remoteName)
                existingFilesByDir[remoteDir] = known
            }

            let remotePath = PathTools.join(remoteDir, remoteName)

            // 3) Ana dosya
            status?("Yükleniyor: \(remoteName)")
            let uploaded = try transfer(file: workingFile,
                                        profile: profile,
                                        remotePath: remotePath,
                                        remoteName: remoteName,
                                        fieldName: nil,
                                        options: options)
            options.onFileProgress?(file, 1.0)

            let linkPath = PathTools.relativePath(remotePath, base: profile.remotePath)
            var remoteURL = uploaded.url
            if remoteURL.isEmpty {
                remoteURL = PathTools.publicURL(profile: profile, remoteFilePath: linkPath)
            }
            remoteURL = PathTools.sanitizeURL(remoteURL)

            // 4) Thumbnail
            var thumbURL: String?
            let wantsThumb = options.makeThumbnail ?? profile.thumbnails.enabled
            if wantsThumb, profile.thumbnails.upload, images.isImage(file) {
                do {
                    if let thumbLocal = try images.thumbnail(file,
                                                             maxWidth: profile.thumbnails.maxWidth,
                                                             maxHeight: profile.thumbnails.maxHeight,
                                                             quality: profile.thumbnails.quality) {
                        defer { try? FileManager.default.removeItem(at: thumbLocal) }
                        let renamedURL = URL(fileURLWithPath: remoteName)
                        let thumbName = Self.thumbName(original: renamedURL, working: thumbLocal, config: profile.thumbnails)
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
            let secret = curlCredentials(profile)
            let tlsArgs: [String] = {
                switch profile.proto {
                case .ftps, .ftpsi: return ["-k", "--ssl-reqd"]
                default: return ["-k", "--ssl"]
                }
            }()

            func attempt(extra: [String]) throws -> TransportResult {
                var args = baseArgs() + tlsArgs + extra
                args.append(contentsOf: ["--ftp-skip-pasv-ip", "--ftp-create-dirs", "-T", file.path, url])
                return try transport.run(arguments: args, secretConfig: secret, onProgress: progress)
            }

            var result = try attempt(extra: ["--disable-epsv"])
            // Geçici veri kanalı/PASV hatasında kısa bekleme sonrası yeniden dene (Active PORT kullanılmaz, NAT'ta 30 hatası verir)
            if result.exitCode != 0 && result.exitCode != 67 {
                usleep(400_000)
                result = try attempt(extra: [])
            }
            if result.exitCode != 0 && result.exitCode != 67 {
                usleep(600_000)
                result = try attempt(extra: ["--disable-epsv"])
            }
            try ensureSuccess(result)
            return ("", result.stdout)

        case .sftp:
            let result = try SFTPRunner().upload(file: file, profile: profile, remotePath: remotePath)
            try ensureSuccess(result)
            progress(1)
            return ("", result.stdout)

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
         "--max-time", "120", "--connect-timeout", "10"]
    }

    private func curlCredentials(_ profile: ServerProfile) -> String {
        guard !profile.username.isEmpty else { return "" }
        return CurlTransport.configLine(key: "user", value: "\(profile.username):\(profile.password)")
    }

    private func ensureSuccess(_ result: TransportResult) throws {
        guard result.exitCode == 0 else {
            let raw = result.stderr.isEmpty ? result.stdout : result.stderr
            let cleaned = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { line in
                    guard !line.isEmpty else { return false }
                    if line.hasPrefix("Warning: --ssl is an insecure option") { return false }
                    // curl --progress-bar ASCII çubuk satırlarını (#, =, -, O, %, boşluk) ayıkla
                    let nonBar = line.filter { !"#=-O0123456789.,% ".contains($0) }
                    return !nonBar.isEmpty
                }
                .joined(separator: " ")
            throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: cleaned.isEmpty ? raw : cleaned)
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
