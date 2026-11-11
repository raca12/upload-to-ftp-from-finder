import Foundation
import MCBUploadCore

// mcb — Upload to FTP from Finder komut satırı arayüzü
//
// Kullanım:
//   mcb upload <dosya...> --server <ad> [--folder alt] [--format bbcode]
//   mcb servers
//   mcb import-filezilla [yol]
//   mcb config
//   mcb init

let stdout = FileHandle.standardOutput
let stderr = FileHandle.standardError

func out(_ text: String) {
    stdout.write((text + "\n").data(using: .utf8)!)
}

func err(_ text: String) {
    stderr.write((text + "\n").data(using: .utf8)!)
}

func progressLine(_ text: String) {
    stderr.write(("\r\u{1B}[K" + text).data(using: .utf8)!)
}

let help = """
mcb — sağ tıkla yükle, link kapında.

KULLANIM
  mcb upload <dosya...> --server <ad> [seçenekler]
  mcb servers                       Kayıtlı sunucuları listeler
  mcb password set|remove|status    Parola kilidi (--policy …)
  mcb test <ad>                     Bağlantıyı test eder
  mcb ls <ad> [klasör]              Sunucudaki klasörleri listeler
  mcb remove-server <ad>            Sunucuyu siler
  mcb import-filezilla [yol]        FileZilla sitelerini içe aktarır
  mcb config                        Ayar dosyasının yolunu yazar
  mcb init                          Örnek profilleri oluşturur

UPLOAD SEÇENEKLERİ
  -s, --server <ad>   Sunucu adı veya ID (zorunlu)
  -d, --dir <yol>     Hedef klasörü değiştir (örn. /public_html/2026)
  -f, --folder <alt>  Seçilen klasörün altına yaz (örn. 2026/kampanya)
  -t, --format <ad>   Link biçimi: url | bbcode | bbcode-image | html |
                      html-image | markdown | markdown-image | <özel>
      --no-thumb      Thumbnail üretme
      --dry-run       Hiçbir şey yüklemeden planı göster
      --json          Sonucu JSON yazar (panoya kopyalamaz)
      --no-clipboard  Panoya kopyalama
  -h, --help          Bu yardım
"""

// MARK: - Argüman ayrıştırma

var argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first, !["-h", "--help", "help"].contains(command) else {
    out(help)
    exit(0)
}
argv.removeFirst()

if command == "--version" || command == "version" {
    out("mcb 0.2.0 (Upload to FTP from Finder)")
    exit(0)
}

var flags: [String: String] = [:]
var switches: Set<String> = []
var positional: [String] = []

do {
    var i = 0
    let valueFlags: Set<String> = ["--server", "-s", "--folder", "-f", "--format", "-t", "--dir", "-d", "--policy"]
    while i < argv.count {
        let arg = argv[i]
        if arg.hasPrefix("-") {
            if let eq = arg.firstIndex(of: "="), arg.hasPrefix("--") {
                let key = String(arg[arg.startIndex..<eq])
                flags[key] = String(arg[arg.index(after: eq)...])
                i += 1
                continue
            }
            if valueFlags.contains(arg) {
                guard i + 1 < argv.count else {
                    err("Eksik değer: \(arg)")
                    exit(2)
                }
                flags[arg] = argv[i + 1]
                i += 2
                continue
            }
            switches.insert(arg)
            i += 1
            continue
        }
        positional.append(arg)
        i += 1
    }

    let store = ProfileStore()
    let engine = UploadEngine()

    func value(_ long: String, _ short: String) -> String? {
        flags[long] ?? flags[short]
    }

    /// Çalıştırılabilir dosyanın yanındaki "mcb" ikilisi için portatif mod uyarısı.
    func copyToClipboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        process.standardInput = pipe
        do {
            try process.run()
            pipe.fileHandleForWriting.write(text.data(using: .utf8)!)
            try? pipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            err("Panoya kopyalanamadı: \(error.localizedDescription)")
        }
    }

    switch command {
    case "config":
        out(store.fileURL.path)

    case "init":
        try FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
        try store.save(ServerProfile.examples)
        out("Örnek profiller yazıldı: \(store.fileURL.path)")

    case "password":
        let action = positional.first ?? "status"
        let security = SecurityStore()
        switch action {
        case "set":
            guard let password = positional.dropFirst().first, password.count >= 6 else {
                err("Kullanım: mcb password set <parola> [--policy launch|every-upload|every-action|never]")
                exit(2)
            }
            let policy: LockPolicy
            switch flags["--policy"] ?? "launch" {
            case "never": policy = .never
            case "every-upload": policy = .everyUpload
            case "every-action": policy = .everyAction
            default: policy = .launch
            }
            try security.setPassword(password, policy: policy)
            out("Parola ayarlandı · politika: \(policy.rawValue)")
        case "remove":
            try security.removePassword()
            out("Parola kaldırıldı.")
        default:
            let settings = security.load()
            out("Parola: \(settings.hasPassword ? "var" : "yok") · politika: \(settings.policy.rawValue)")
        }

    case "ls":
        guard let name = positional.first else {
            err("Kullanım: mcb ls <sunucu> [klasör]")
            exit(2)
        }
        let profile = try store.find(name)
        let path = positional.count > 1 ? positional[1] : profile.remotePath
        let entries = try DirectoryLister().list(profile: profile, path: path)
        out("\(path)")
        for entry in entries {
            out("  \(entry.isDirectory ? "📁" : "📄") \(entry.name)")
        }
        if entries.isEmpty { out("  (boş)") }

    case "test":
        guard let name = positional.first else {
            err("Kullanım: mcb test <sunucu adı>")
            exit(2)
        }
        let profile = try store.find(name)
        let message = try ConnectionTester().test(profile)
        out("✓ " + message)

    case "remove-server":
        guard let name = positional.first else {
            err("Kullanım: mcb remove-server <sunucu adı>")
            exit(2)
        }
        let profile = try store.find(name)
        try store.delete(id: profile.id)
        out("Silindi: \(profile.name)")

    case "servers":
        let servers = try store.load()
        if servers.isEmpty {
            err("Kayıtlı sunucu yok. `mcb init` ile örnekleri oluşturabilirsin.")
            out("Ayar dosyası: \(store.fileURL.path)")
            exit(1)
        }
        let nameWidth = max(6, servers.map { $0.name.count }.max() ?? 6)
        out("AD".padding(toLength: nameWidth, withPad: " ", startingAt: 0) + "  PROTOKOL      HOST              UZAK KLASÖR")
        for s in servers {
            let name = s.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let proto = s.proto.displayName.padding(toLength: 13, withPad: " ", startingAt: 0)
            let host = "\(s.host):\(s.port)".padding(toLength: 17, withPad: " ", startingAt: 0)
            out("\(name)  \(proto)  \(host)  \(s.remotePath)")
        }

    case "import-filezilla":
        let paths = positional.isEmpty ? FileZillaImporter.defaultPaths : [URL(fileURLWithPath: (positional[0] as NSString).expandingTildeInPath)]
        var found: [URL] = []
        var imported: [ServerProfile] = []
        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            found.append(path)
            imported.append(contentsOf: (try? FileZillaImporter.importServers(from: path)) ?? [])
        }
        guard !imported.isEmpty else {
            err("İçe aktarılacak FileZilla sunucusu bulunamadı (\(paths.map(\.path).joined(separator: ", "))).")
            exit(1)
        }
        var existing = try store.load()
        var added = 0
        for profile in imported {
            if !existing.contains(where: { $0.name == profile.name && $0.host == profile.host }) {
                existing.append(profile)
                added += 1
            }
        }
        try store.save(existing)
        out("\(added) sunucu eklendi (\(found.count) dosyadan). Toplam: \(existing.count)")

    case "upload":
        guard let serverName = value("--server", "-s") else {
            err("--server zorunlu. `mcb servers` ile listeye bak.")
            exit(2)
        }
        guard !positional.isEmpty else {
            err("Yüklenecek dosya belirtilmedi.")
            exit(2)
        }
        let profile = try store.find(serverName)
        let format = value("--format", "-t") ?? "url"

        if LinkTemplate.template(named: format, in: profile) == nil {
            let available = Set(profile.templates.keys).union(LinkTemplate.defaults.keys).sorted()
            err("Bilinmeyen biçim: \(format). Kullanılabilir: \(available.joined(separator: ", "))")
            exit(2)
        }

        let files = positional.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        var lastPrintedFile: URL?
        var lastPercent: Double = -1

        var options = UploadOptions(format: format, folder: value("--folder", "-f"))
        if let dir = value("--dir", "-d") {
            if dir.hasPrefix("/") { options.remoteDirectory = dir } else { options.folder = dir }
        }
        options.dryRun = switches.contains("--dry-run")
        if switches.contains("--no-thumb") { options.makeThumbnail = false }
        options.onStatus = { message in
            if !switches.contains("--json") { progressLine("→ \(message)") }
        }
        options.onFileProgress = { file, value in
            lastPrintedFile = file
            lastPercent = value
            if !switches.contains("--json") {
                let pct = Int((value * 100).rounded())
                let barWidth = 24
                let filled = Int(Double(barWidth) * value)
                let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: barWidth - filled)
                progressLine("  \(file.lastPathComponent)  \(bar)  \(pct)%")
            }
        }

        let started = Date()
        let uploaded = try engine.upload(files: files, profile: profile, options: options)
        if !switches.contains("--json") {
            stderr.write("\r\u{1B}[K".data(using: .utf8)!)
        }

        let elapsed = Date().timeIntervalSince(started)
        let totalBytes = uploaded.reduce(Int64(0)) { $0 + $1.bytes }

        if switches.contains("--json") {
            let encoder = JSONEncoder.mcb
            let data = try encoder.encode(uploaded)
            out(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            for file in uploaded {
                guard let link = LinkTemplate.format(file, templateName: format, server: profile) else { continue }
                out(link)
            }
            err("\(uploaded.count) dosya · \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) · \(String(format: "%.1f", elapsed)) sn · format: \(format)")
            if !switches.contains("--no-clipboard") {
                let links = uploaded.compactMap { LinkTemplate.format($0, templateName: format, server: profile) }
                copyToClipboard(links.joined(separator: "\n"))
                err("Linkler panoya kopyalandı.")
            }
        }
        _ = (lastPrintedFile, lastPercent)

    default:
        err("Bilinmeyen komut: \(command)\n")
        out(help)
        exit(2)
    }
} catch {
    err("Hata: \(error.localizedDescription)")
    exit(1)
}
