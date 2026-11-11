import AppKit
import FinderSync
import os
import MCBUploadCore

// MARK: - Finder Sync eklentisi
// Finder'da sağ tık → "Finder'dan FTP'ye Yükle" → sunucu → yükle.

final class FinderSyncExtension: FIFinderSync {

    private let store = ProfileStore(baseDirectory: MCBUploadPaths.sharedBaseDirectory)
    private let inbox = RequestInbox(baseDirectory: MCBUploadPaths.sharedBaseDirectory)
    private let log = Logger(subsystem: "com.mcb.upload", category: "finder")

    /// Menü öğeleri Finder tarafından kopyalanabildiği için sunucuyu `tag` ile taşıyoruz.
    private var serverMap: [Int: ServerProfile] = [:]

    override init() {
        super.init()
        var monitored = [URL(fileURLWithPath: MCBUploadPaths.realHomeDirectory)]
        monitored += (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                                  includingPropertiesForKeys: nil)) ?? []
        FIFinderSyncController.default().directoryURLs = Set(monitored)

        let count = (try? store.load(resolvePasswords: false))?.count ?? -1
        log.log("başladı — okunan sunucu: \(count, privacy: .public)")
    }

    // MARK: - Araç çubuğu

    override var toolbarItemName: String { "Upload to FTP" }
    override var toolbarItemToolTip: String { Localization.text("Finder'dan FTP'ye Yükle") }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Upload to FTP")
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    // MARK: - Sağ tık menüsü

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false   // Finder doğrulaması öğeleri devre dışı bırakmasın

        let servers = (try? store.load(resolvePasswords: false)) ?? []
        serverMap = [:]
        for (index, server) in servers.enumerated() {
            serverMap[index + 1] = server
        }

        let root = NSMenuItem(title: Localization.text("Finder'dan FTP'ye Yükle"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: Localization.text("Finder'dan FTP'ye Yükle"))
        submenu.autoenablesItems = false
        root.submenu = submenu

        if servers.isEmpty {
            let empty = NSMenuItem(title: Localization.text("Sunucu tanımlı değil — uygulamayı aç"), action: #selector(openApp(_:)), keyEquivalent: "")
            empty.target = self
            submenu.addItem(empty)
        } else {
            for (index, server) in servers.enumerated() {
                let item = NSMenuItem(title: server.name, action: nil, keyEquivalent: "")
                let serverMenu = NSMenu(title: server.name)
                serverMenu.autoenablesItems = false

                let here = NSMenuItem(title: "Buraya yükle  (\(server.remotePath))",
                                      action: #selector(uploadToDefaultFolder(_:)),
                                      keyEquivalent: "")
                here.target = self
                here.tag = index + 1
                serverMenu.addItem(here)

                let choose = NSMenuItem(title: "Klasör seçerek yükle…",
                                        action: #selector(queueAndChooseFolder(_:)),
                                        keyEquivalent: "")
                choose.target = self
                choose.tag = index + 1
                serverMenu.addItem(choose)

                item.submenu = serverMenu
                submenu.addItem(item)
            }
        }

        // Alt menüye girmeden çalışan kısayollar (teşhis + hız)
        submenu.addItem(.separator())
        let queue = NSMenuItem(title: "Kuyruğa ekle (klasörü uygulamada seç)",
                              action: #selector(queueOnly(_:)), keyEquivalent: "")
        queue.target = self
        submenu.addItem(queue)

        let open = NSMenuItem(title: Localization.text("Uygulamayı Aç"), action: #selector(openApp(_:)), keyEquivalent: "")
        open.target = self
        submenu.addItem(open)

        menu.addItem(root)

        // Alt menüye girmeden tek tıkla çalışan kısayol (ilk sunucu)
        if let first = servers.first {
            let quick = NSMenuItem(title: Localization.text("Hızlı yükle → %@", first.name),
                                   action: #selector(uploadToDefaultFolder(_:)),
                                   keyEquivalent: "")
            quick.target = self
            quick.tag = 1
            menu.addItem(quick)
        }

        log.log("menü hazır — sunucu: \(servers.count, privacy: .public), tür: \(menuKind.rawValue, privacy: .public)")
        return menu
    }

    // MARK: - Eylemler

    /// Seçili dosyalar; klasör seçildiyse içindeki dosyaları (en fazla 300) toplar.
    private var selectedFiles: [String] {
        let urls = FIFinderSyncController.default().selectedItemURLs()
            ?? [FIFinderSyncController.default().targetedURL()].compactMap { $0 }
        var files: [String] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                files.append(contentsOf: Self.files(in: url, limit: 300))
            } else {
                files.append(url.path)
            }
        }
        return files
    }

    private static func files(in folder: URL, limit: Int) -> [String] {
        var result: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                             includingPropertiesForKeys: keys,
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return result
        }
        for case let url as URL in enumerator {
            if result.count >= limit { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            if (values?.isHidden ?? false) || url.lastPathComponent == ".DS_Store" { continue }
            result.append(url.path)
        }
        return result
    }

    private func server(for sender: NSMenuItem) -> ServerProfile? {
        if let server = serverMap[sender.tag] { return server }
        // Yedek: menu kopyalanırken tag kaybolduysa ada göre bul
        let title = sender.title.components(separatedBy: "  (").first ?? sender.title
        return (try? store.load(resolvePasswords: false))?.first(where: { $0.name == title })
    }

    @objc private func uploadToDefaultFolder(_ sender: NSMenuItem) {
        log.log("tıklama: buraya yükle — tag \(sender.tag, privacy: .public)")
        guard let server = server(for: sender) else {
            log.error("sunucu bulunamadı (tag \(sender.tag, privacy: .public), başlık \(sender.title, privacy: .public))")
            return
        }
        submit(UploadRequest(mode: .upload, serverName: server.name, files: selectedFiles))
    }

    @objc private func queueAndChooseFolder(_ sender: NSMenuItem) {
        log.log("tıklama: klasör seç — tag \(sender.tag, privacy: .public)")
        guard let server = server(for: sender) else {
            log.error("sunucu bulunamadı (tag \(sender.tag, privacy: .public))")
            return
        }
        submit(UploadRequest(mode: .queue, serverName: server.name, files: selectedFiles))
    }

    @objc private func queueOnly(_ sender: NSMenuItem) {
        log.log("tıklama: kuyruğa ekle")
        submit(UploadRequest(mode: .queue, files: selectedFiles))
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        log.log("tıklama: uygulamayı aç")
        openMainApp()
    }

    // MARK: - Köprü

    private func submit(_ request: UploadRequest) {
        guard !request.files.isEmpty else {
            // Kullanıcıya görünür geri bildirim: uygulamayı aç, durumu yaz
            log.error("seçili dosya yok — uygulama bilgilendirilecek")
            var empty = request
            empty.files = []
            try? inbox.submit(empty)
            RequestInbox.notifyApp()
            openMainApp()
            return
        }
        do {
            try inbox.submit(request)
            log.log("istek yazıldı: \(request.files.count, privacy: .public) dosya, mod \(request.mode.rawValue, privacy: .public)")
        } catch {
            log.error("istek yazılamadı: \(error.localizedDescription, privacy: .public)")
            return
        }
        RequestInbox.notifyApp()
        openMainApp()
    }

    /// .appex → PlugIns → Contents → Upload to FTP from Finder.app
    private func openMainApp() {
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()   // PlugIns
            .deletingLastPathComponent()   // Contents
            .deletingLastPathComponent()   // Upload to FTP from Finder.app
        guard appURL.pathExtension == "app" else {
            log.error("uygulama yolu bulunamadı: \(appURL.path, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                self.log.error("uygulama açılamadı: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
