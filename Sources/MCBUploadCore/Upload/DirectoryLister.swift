import Foundation

// MARK: - Uzak klasör içeriği
// Yükleme penceresindeki "Gözat…" düğmesi sunucudaki klasörleri buradan okur.

public struct RemoteEntry: Equatable, Sendable {
    public let name: String
    public let isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

// MARK: - FTP LIST çıktısı ayrıştırıcı

public enum FTPListingParser {

    /// Unix (`drwxr-xr-x ... ad`), DOS (`01-02-03 04:05PM <DIR> ad`), MLSD (`type=dir;...;ad`)
    /// ve düz isim listesi (`--list-only`) biçimlerini anlar.
    public static func parse(_ output: String) -> [RemoteEntry] {
        var entries: [RemoteEntry] = []
        var seen = Set<String>()

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("total ") { continue }

            guard let entry = parseLine(line) else { continue }
            guard entry.name != ".", entry.name != ".." else { continue }
            guard seen.insert(entry.name).inserted else { continue }
            entries.append(entry)
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func parseLine(_ line: String) -> RemoteEntry? {
        // MLSD: type=dir;size=123; name
        if line.hasPrefix("type=") {
            let lowered = line.lowercased()
            guard let space = line.firstIndex(of: " ") else { return nil }
            let name = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return RemoteEntry(name: name, isDirectory: lowered.contains("type=dir"))
        }

        // Unix: drwxr-xr-x 2 user group 4096 Nov 11 13:00 ad
        let unix = #"^([dl\-])([rwx\-]{9})\s+\d+\s+\S+\s+\S+\s+[\d,.]+\s+\S+\s+\S+\s+\S+\s(.+)$"#
        if let regex = try? NSRegularExpression(pattern: unix),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           match.numberOfRanges > 2,
           let nameRange = Range(match.range(at: match.numberOfRanges - 1), in: line) {
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return RemoteEntry(name: name, isDirectory: line.hasPrefix("d"))
        }

        // DOS: 01-02-03  04:05PM       <DIR>          ad
        let dos = #"^\d{2}-\d{2}-\d{2,4}\s+\d{1,2}:\d{2}(AM|PM)?\s+(<DIR>|\d+)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: dos, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           match.numberOfRanges > 3,
           let nameRange = Range(match.range(at: 3), in: line) {
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return RemoteEntry(name: name, isDirectory: line.uppercased().contains("<DIR>"))
        }

        // Düz isim listesi: klasör mü dosya mı bilinmiyor → dosya say
        guard !line.contains(" ") || line.split(separator: " ").count > 0 else { return nil }
        if line.contains("/") || line.contains(":") { return nil }
        return RemoteEntry(name: line, isDirectory: false)
    }
}

// MARK: - Klasör listeleme

public struct DirectoryLister {
    private let transport: Transport

    public init(transport: Transport = CurlTransport()) {
        self.transport = transport
    }

    public func list(profile: ServerProfile, path: String) throws -> [RemoteEntry] {
        switch profile.proto {
        case .ftp, .ftps, .ftpsi:
            break
        case .sftp:
            return try SFTPRunner().list(profile: profile, path: path)
        case .http:
            throw MCBUploadError.unsupportedProtocol("HTTP yüklemelerinde klasörü sunucu belirler")
        }

        var directoryPath = path.isEmpty ? "/" : path
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

        func listAttempt(extra: [String]) throws -> TransportResult {
            let args = ["--silent", "--show-error", "--connect-timeout", "8", "--max-time", "15",
                        "--ftp-skip-pasv-ip", "--disable-epsv"] + tlsArgs + extra + [url]
            return try transport.run(arguments: args, secretConfig: credentials, onProgress: nil)
        }

        var result = try listAttempt(extra: [])
        if result.exitCode != 0 {
            result = try listAttempt(extra: ["--ftp-port", "-"])
        }
        guard result.exitCode == 0 else {
            throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return FTPListingParser.parse(result.stdout)
    }
}
