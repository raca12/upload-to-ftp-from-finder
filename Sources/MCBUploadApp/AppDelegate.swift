import AppKit
import MCBUploadCore

extension Notification.Name {
    static let mcbServersChanged = Notification.Name("mcbServersChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var windowController: MainWindowController?
    private let store = ProfileStore()
    private let security = SecurityStore()
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private let inbox = RequestInbox()
    private var inboxObserver: NSObjectProtocol?
    private var inboxTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tek örnek: ikinci kopya açılmasın (test için MCB_ALLOW_MULTIPLE=1)
        if ProcessInfo.processInfo.environment["MCB_ALLOW_MULTIPLE"] == nil {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mcb.upload")
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate(options: [.activateAllWindows])
                exit(0)
            }
        }

        installMainMenu()
        buildStatusItem()
        NotificationCenter.default.addObserver(forName: .mcbServersChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshMenu()
        }

        // Finder eklentisinden gelen yükleme istekleri
        inboxObserver = RequestInbox.observeApp { [weak self] in
            self?.drainInbox()
        }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.drainInbox()
        }
        RunLoop.main.add(timer, forMode: .common)
        inboxTimer = timer
        drainInbox()
        // İlk çalıştırma: ayar dosyası ve örnek profiller
        _ = try? store.ensureSeeded()
        // Kilit politikası: uygulama açılışında parola
        if security.load().hasPassword, security.load().policy.requiresUnlockOnLaunch {
            if !AppLock.shared.require(.launch) {
                NSApp.terminate(nil)
                return
            }
        }

        if CommandLine.arguments.contains("--show-window") {
            showWindow()
        }
        if CommandLine.arguments.contains("--onboarding") {
            openOnboarding()
        }

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
        if CommandLine.arguments.contains("--add-server") {
            showWindow()
            windowController?.presentServerEditor(nil)
        }
    }

    // MARK: - Düzenleme menüsü (⌘C/⌘V/⌘A kısayolları için gerekli)

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: t("Düzenle"))
        editMenuItem.submenu = editMenu

        func add(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: t(title), action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            editMenu.addItem(item)
        }

        add("Geri Al", Selector(("undo:")), "z")
        add("Yinele", Selector(("redo:")), "Z", [.command, .shift])
        editMenu.addItem(.separator())
        add("Kes", #selector(NSText.cut(_:)), "x")
        add("Kopyala", #selector(NSText.copy(_:)), "c")
        add("Yapıştır", #selector(NSText.paste(_:)), "v")
        add("Sil", #selector(NSText.delete(_:)), "")
        add("Tümünü Seç", #selector(NSText.selectAll(_:)), "a")

        NSApp.mainMenu = mainMenu

        // Menü çubuğu olmayan uygulamalarda kısayolların garanti çalışması için
        // yerel klavye izleyicisi (Edit menüsü + bu katman birlikte çalışır).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // macOS'ta standart ⌘V; Windows alışkanlığıyla Ctrl+V de kabul edilir.
            let hasCommand = event.modifierFlags.contains(.command)
            let hasControl = event.modifierFlags.contains(.control)
            guard hasCommand || hasControl else { return event }
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let shift = event.modifierFlags.contains(.shift)

            let selector: Selector?
            switch key {
            case "v": selector = #selector(NSText.paste(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "x": selector = #selector(NSText.cut(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = shift ? Selector(("redo:")) : Selector(("undo:"))
            default: selector = nil
            }

            guard let selector, NSApp.keyWindow?.firstResponder is NSText else { return event }
            if NSApp.sendAction(selector, to: nil, from: nil) { return nil }
            return event
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Upload to FTP")
        item.button?.toolTip = "Upload to FTP from Finder"
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(withTitle: t("Uygulamayı Aç"), action: #selector(showWindow), keyEquivalent: "o").target = self
        menu.addItem(withTitle: t("Dosya Yükle…"), action: #selector(chooseFiles), keyEquivalent: "u").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Sunucu Ekle… (FTP)"), action: #selector(addServer), keyEquivalent: "n").target = self
        menu.addItem(withTitle: t("Seçili Sunucuyu Düzenle…"), action: #selector(editServer), keyEquivalent: "e").target = self
        menu.addItem(.separator())

        let servers = (try? store.load(resolvePasswords: false)) ?? []
        if servers.isEmpty {
            let empty = NSMenuItem(title: t("Sunucu tanımlı değil"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let serverMenu = NSMenu()
            for server in servers {
                let entry = NSMenuItem(title: "\(server.name) — \(server.proto.displayName)",
                                       action: #selector(uploadToServer(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = server.id.uuidString
                serverMenu.addItem(entry)
            }
            let parent = NSMenuItem(title: t("Hızlı Yükle"), action: nil, keyEquivalent: "")
            parent.submenu = serverMenu
            menu.addItem(parent)
        }

        menu.addItem(withTitle: t("Finder entegrasyonunu ayarla…"), action: #selector(openOnboarding), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("Güvenlik ve Dil…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        if security.load().hasPassword {
            menu.addItem(withTitle: t("Kilitle"), action: #selector(lockNow), keyEquivalent: "l").target = self
        }
        menu.addItem(withTitle: t("Ayar Dosyasını Aç"), action: #selector(openSettingsFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Çıkış"), action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    // MARK: - Eylemler

    // MARK: - Finder köprüsü

    private func drainInbox() {
        guard let requests = try? inbox.takeAll(), !requests.isEmpty else { return }
        NSLog("Upload to FTP: %d Finder isteği alındı", requests.count)
        for request in requests {
            showWindow()
            windowController?.handle(request)
        }
    }

    @objc private func showWindow() {
        let controller = windowController ?? MainWindowController()
        windowController = controller
        controller.reloadProfiles(selectID: nil)
        controller.promptForFirstServerIfNeeded()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func chooseFiles() {
        showWindow()
        windowController?.addFilesViaPanel()
    }

    @objc private func addServer() {
        showWindow()
        windowController?.presentServerEditor(nil)
    }

    @objc private func editServer() {
        showWindow()
        windowController?.editSelectedServerInEditor()
    }

    @objc private func uploadToServer(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let uuid = UUID(uuidString: idString),
              let server = (try? store.load(resolvePasswords: false))?.first(where: { $0.id == uuid }) else { return }
        showWindow()
        windowController?.selectServer(server)
        windowController?.addFilesViaPanel()
    }

    @objc private func openOnboarding() {
        if onboardingController == nil { onboardingController = OnboardingWindowController() }
        onboardingController?.window?.center()
        onboardingController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.window?.center()
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func lockNow() {
        AppLock.shared.lockNow()
        statusItem?.menu = buildMenu()
        let alert = NSAlert()
        alert.messageText = t("Uygulama kilitli")
        alert.informativeText = t("Bir sonraki işlemde parola sorulacak.")
        alert.runModal()
    }

    @objc private func openSettingsFile() {
        _ = try? store.ensureSeeded()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
        // Terminate engellenirse (modal pencere vb.) 1 sn sonra zorla çık
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exit(0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Finder'da "Birlikte Aç → Upload to FTP from Finder"
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false }
        guard !files.isEmpty else { return }
        showWindow()
        windowController?.addFiles(files)
    }
}
