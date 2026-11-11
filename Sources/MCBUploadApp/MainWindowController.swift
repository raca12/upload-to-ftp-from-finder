import AppKit
import MCBUploadCore

// MARK: - Kuyruk öğesi

final class QueueItem {
    enum State {
        case queued
        case uploading(Int)
        case done
        case error
    }

    let url: URL
    var state: State = .queued
    var progress: Double = 0
    let size: Int64

    var statusText: String {
        switch state {
        case .queued: return t("Sırada")
        case .uploading(let percent): return t("Yükleniyor %d%%", percent)
        case .done: return t("Tamam")
        case .error: return t("Hata")
        }
    }

    init(url: URL) {
        self.url = url
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - Sürükle-bırak kabul eden görünüm

final class DropView: NSView {
    var onFiles: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) desteklenmiyor") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return false }
        onFiles?(urls)
        return true
    }
}

// MARK: - Ana pencere

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {

    private let store = ProfileStore()
    private let engine = UploadEngine()

    private var items: [QueueItem] = []
    private var profiles: [ServerProfile] = []
    private var isUploading = false

    private var serverPopup: NSPopUpButton!
    private var formatPopup: NSPopUpButton!
    private var tableView: NSTableView!
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var linksTextView: NSTextView!
    private var uploadButton: NSButton!
    private var addButton: NSButton!
    private var activeEditor: ServerEditorController?
    private var activePicker: DirectoryPickerController?
    private var folderField: NSTextField!
    private var folderUserEdited = false
    private var browseButton: NSButton!
    private var didPromptForFirstServer = false

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Upload to FTP from Finder"
        window.minSize = NSSize(width: 620, height: 460)
        window.center()
        self.init(window: window)
        buildUI()
        reloadProfiles()
    }

    // MARK: - Arayüz

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Üst satır: sunucu + link biçimi + butonlar
        serverPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        serverPopup.target = self
        serverPopup.action = #selector(serverChanged)
        serverPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPopup.addItems(withTitles: ["url", "bbcode", "bbcode-image", "html", "html-image", "markdown", "markdown-image"])
        formatPopup.selectItem(withTitle: "bbcode-image")

        addButton = NSButton(title: t("Dosya Ekle…"), target: self, action: #selector(addFilesTapped))
        uploadButton = NSButton(title: t("Yükle"), target: self, action: #selector(uploadTapped))
        uploadButton.keyEquivalent = "\r"
        uploadButton.bezelStyle = .rounded
        window?.defaultButtonCell = uploadButton.cell as? NSButtonCell

        let addServerButton = NSButton(title: "＋", target: self, action: #selector(addServerTapped))
        addServerButton.bezelStyle = .rounded
        addServerButton.toolTip = "Yeni sunucu ekle (FTP bilgilerini gir)"

        let editServerButton = NSButton(title: "⋯", target: self, action: #selector(editServerTapped))
        editServerButton.bezelStyle = .rounded
        editServerButton.toolTip = "Seçili sunucuyu düzenle"

        let header = NSStackView(views: [serverPopup, addServerButton, editServerButton, formatPopup, NSView(), addButton, uploadButton])
        header.orientation = .horizontal
        header.spacing = 8
        header.distribution = .fill

        // Klasör satırı: yüklemenin gideceği sunucu klasörü
        folderField = NSTextField()
        folderField.placeholderString = "/public_html/resimler"
        folderField.toolTip = "Yüklemenin yapılacağı sunucu klasörü. Sunucuda gezinmek için “Gözat…” kullan."
        folderField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        folderField.delegate = self

        browseButton = NSButton(title: t("Gözat…"), target: self, action: #selector(browseTapped))
        browseButton.bezelStyle = .rounded
        browseButton.toolTip = "Sunucudaki klasörleri listele ve seç"

        let folderLabel = NSTextField(labelWithString: t("Klasör"))
        folderLabel.textColor = .secondaryLabelColor

        let folderRow = NSStackView(views: [folderLabel, folderField, browseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8
        folderLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true

        // Dosya tablosu
        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true

        for (identifier, title, width) in [("file", t("Dosya"), 380.0), ("status", t("Durum"), 220.0), ("size", t("Boyut"), 90.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        let drop = DropView(frame: .zero)
        drop.onFiles = { [weak self] urls in self?.addFiles(urls) }
        drop.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: drop.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: drop.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
        ])

        // İlerleme + durum
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0

        statusLabel = NSTextField(labelWithString: t("Dosyaları buraya sürükleyebilir veya “Dosya Ekle…” kullanabilirsin."))
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let progressRow = NSStackView(views: [progressBar, statusLabel])
        progressRow.orientation = .horizontal
        progressRow.spacing = 10
        progressBar.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Linkler
        let linksLabel = NSTextField(labelWithString: t("Linkler"))
        linksLabel.font = .boldSystemFont(ofSize: 12)

        linksTextView = NSTextView()
        linksTextView.isEditable = true
        linksTextView.isRichText = false
        linksTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        linksTextView.autoresizingMask = [.width]
        linksTextView.textContainerInset = NSSize(width: 4, height: 6)

        let linksScroll = NSScrollView()
        linksScroll.documentView = linksTextView
        linksScroll.hasVerticalScroller = true
        linksScroll.borderType = .bezelBorder
        linksScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        linksScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let copyButton = NSButton(title: t("Linkleri Kopyala"), target: self, action: #selector(copyLinks))
        let clearButton = NSButton(title: t("Listeyi Temizle"), target: self, action: #selector(clearQueue))
        let hint = NSTextField(labelWithString: t("Yükleme bitince linkler otomatik panoya kopyalanır."))
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        let footer = NSStackView(views: [copyButton, clearButton, hint])
        footer.orientation = .horizontal
        footer.spacing = 8

        let root = NSStackView(views: [header, folderRow, drop, progressRow, linksLabel, linksScroll, footer])
        root.orientation = .vertical
        root.spacing = 10
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])

        for view in [header, folderRow, drop, progressRow, linksScroll, footer] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    // MARK: - Veri

    func reloadProfiles(selectID: UUID? = nil) {
        profiles = (try? store.load()) ?? []
        serverPopup.removeAllItems()
        if profiles.isEmpty {
            serverPopup.addItem(withTitle: t("Sunucu yok — “＋” ile FTP ekle"))
            serverPopup.isEnabled = false
            uploadButton?.isEnabled = false
        } else {
            serverPopup.isEnabled = true
            uploadButton?.isEnabled = !isUploading
            serverPopup.addItems(withTitles: profiles.map { "\($0.name)  (\($0.proto.displayName))" })
            if let selectID, let index = profiles.firstIndex(where: { $0.id == selectID }) {
                serverPopup.selectItem(at: index)
            }
        }
        tableView?.reloadData()
        updateFolderControls()
    }

    /// Sunucuya göre klasör alanını hazırlar (HTTP'de klasörü sunucu belirler).
    /// `force` = true ise kullanıcının seçtiği klasör de sıfırlanır.
    private func updateFolderControls(force: Bool = false) {
        guard let profile = selectedProfile else {
            folderField?.stringValue = ""
            folderField?.isEnabled = false
            browseButton?.isEnabled = false
            return
        }
        let canBrowse = profile.proto != .http
        folderField?.isEnabled = canBrowse
        browseButton?.isEnabled = canBrowse
        if canBrowse {
            if force || !folderUserEdited || folderField?.stringValue.isEmpty == true {
                folderField?.stringValue = profile.remotePath
                folderUserEdited = false
            }
            folderField?.placeholderString = profile.remotePath
        } else {
            folderUserEdited = false
            folderField?.stringValue = ""
            folderField?.placeholderString = t("HTTP yüklemelerinde klasörü sunucu belirler")
        }
    }

    // MARK: - Sunucu ekleme / düzenleme

    func presentServerEditor(_ server: ServerProfile?) {
        guard AppLock.shared.require(.action) else { return }
        guard let parent = window else { return }
        let editor = ServerEditorController(server: server)
        activeEditor = editor
        editor.onSave = { [weak self] profile in
            guard let self else { return }
            do {
                try self.store.upsert(profile)
                self.reloadProfiles(selectID: profile.id)
                self.statusLabel?.stringValue = t("Sunucu kaydedildi: %@", profile.name)
                self.activeEditor = nil
                NotificationCenter.default.post(name: .mcbServersChanged, object: nil)
            } catch {
                self.statusLabel?.stringValue = "Kaydedilemedi: \(error.localizedDescription)"
            }
        }
        editor.onDelete = { [weak self] profile in
            guard let self else { return }
            try? self.store.delete(id: profile.id)
            self.reloadProfiles()
            self.statusLabel?.stringValue = t("Sunucu silindi: %@", profile.name)
            self.activeEditor = nil
            NotificationCenter.default.post(name: .mcbServersChanged, object: nil)
        }
        if let sheet = editor.window {
            parent.beginSheet(sheet, completionHandler: nil)
        }
    }

    /// Finder eklentisinden gelen isteği işler.
    func handle(_ request: UploadRequest) {
        guard !request.files.isEmpty else {
            statusLabel.stringValue = t("Finder’dan dosya alınamadı — menüyü dosyalar (veya içi dolu bir klasör) üzerinde kullan.")
            return
        }
        addFiles(request.files.map { URL(fileURLWithPath: $0) })
        if let name = request.serverName {
            selectServer(named: name)
        }
        switch request.mode {
        case .upload:
            if let profile = selectedProfile { startUpload(to: profile) }
        case .queue:
            statusLabel.stringValue = t("Dosyalar kuyrukta — hedef klasörü seç, sonra “Yükle”ye bas.")
        }
    }

    func selectServer(named name: String) {
        guard let index = profiles.firstIndex(where: { $0.name == name }) else { return }
        serverPopup.selectItem(at: index)
        updateFolderControls(force: true)
    }

    @objc private func addServerTapped() { presentServerEditor(nil) }

    func editSelectedServerInEditor() { presentServerEditor(selectedProfile) }

    /// Hiç sunucu yoksa ilk açılışta doğrudan FTP ekleme formunu göster.
    func promptForFirstServerIfNeeded() {
        guard !didPromptForFirstServer, profiles.isEmpty else { return }
        didPromptForFirstServer = true
        DispatchQueue.main.async { [weak self] in
            self?.presentServerEditor(nil)
        }
    }

    @objc private func editServerTapped() { presentServerEditor(selectedProfile) }

    func selectServer(_ server: ServerProfile) {
        if let index = profiles.firstIndex(where: { $0.id == server.id }) {
            serverPopup.selectItem(at: index)
        }
    }

    private var selectedProfile: ServerProfile? {
        guard serverPopup.isEnabled, serverPopup.indexOfSelectedItem >= 0 else { return nil }
        let index = serverPopup.indexOfSelectedItem
        return profiles.indices.contains(index) ? profiles[index] : nil
    }

    // MARK: - Dosya ekleme

    func addFilesViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Kuyruğa Ekle"
        panel.message = "Yüklenecek dosyaları seç"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.addFiles(panel.urls)
        }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(items.map { $0.url })
        let newItems = urls
            .map { $0.standardizedFileURL }
            .filter { !existing.contains($0) }
            .map(QueueItem.init(url:))
        items.append(contentsOf: newItems)
        tableView?.reloadData()
        statusLabel?.stringValue = t("%d dosya kuyrukta", items.count)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Yükleme

    @objc private func uploadTapped() { startUpload() }

    func startUpload() {
        guard let profile = selectedProfile else {
            statusLabel.stringValue = t("Tanımlı sunucu yok — “＋” ile sunucu ekle.")
            return
        }
        startUpload(to: profile)
    }

    func startUpload(to profile: ServerProfile) {
        guard AppLock.shared.require(.upload) else { return }
        guard !isUploading else { return }
        guard !items.isEmpty else {
            statusLabel.stringValue = t("Önce dosya ekle.")
            return
        }

        isUploading = true
        uploadButton.isEnabled = false
        addButton.isEnabled = false
        progressBar.doubleValue = 0
        linksTextView.string = ""
        for item in items {
            item.state = .queued
            item.progress = 0
        }
        tableView.reloadData()

        let format = formatPopup.titleOfSelectedItem ?? "url"
        let urls = items.map { $0.url }
        let engine = self.engine

        var options = UploadOptions(format: format)
        let folderText = folderField.stringValue.trimmingCharacters(in: .whitespaces)
        if profile.proto != .http, !folderText.isEmpty {
            if folderText.hasPrefix("/") {
                options.remoteDirectory = folderText
            } else {
                options.folder = folderText
            }
        }
        options.onStatus = { [weak self] message in
            DispatchQueue.main.async {
                self?.statusLabel?.stringValue = message
            }
        }
        options.onFileProgress = { [weak self] file, value in
            DispatchQueue.main.async {
                guard let self else { return }
                if let index = self.items.firstIndex(where: { $0.url == file }) {
                    self.items[index].progress = value
                    self.items[index].state = .uploading(Int(value * 100))
                    self.tableView.reloadData(forRowIndexes: IndexSet(integer: index),
                                              columnIndexes: IndexSet(integersIn: 0..<3))
                }
                let total = self.items.reduce(0.0) { $0 + $1.progress } / Double(max(1, self.items.count))
                self.progressBar.doubleValue = total
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [UploadedFile] = []
            var failure: Error?
            do {
                results = try engine.upload(files: urls, profile: profile, options: options)
            } catch {
                failure = error
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishUpload(results: results, error: failure, profile: profile, format: format)
            }
        }
    }

    private func finishUpload(results: [UploadedFile], error: Error?, profile: ServerProfile, format: String) {
        isUploading = false
        uploadButton.isEnabled = true
        addButton.isEnabled = true

        let donePaths = Set(results.map { $0.localPath })
        for item in items {
            if donePaths.contains(item.url.path) {
                item.state = .done
                item.progress = 1
            } else if error != nil {
                item.state = .error
            }
        }
        tableView.reloadData()

        if let error {
            progressBar.doubleValue = 0
            statusLabel.stringValue = t("Hata: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = t("Yükleme başarısız")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        progressBar.doubleValue = 1
        let links = results.compactMap { LinkTemplate.format($0, templateName: format, server: profile) }
        linksTextView.string = links.joined(separator: "\n")
        if !links.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(links.joined(separator: "\n"), forType: .string)
        }
        let bytes = results.reduce(Int64(0)) { $0 + $1.bytes }
        statusLabel.stringValue = t("%d dosya yüklendi · %@ · linkler panoda", results.count, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
    }

    // MARK: - Eylemler

    @objc private func addFilesTapped() { addFilesViaPanel() }

    @objc private func serverChanged() {
        uploadButton.isEnabled = !isUploading
        updateFolderControls(force: true)
    }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === folderField {
            folderUserEdited = true
        }
    }

    @objc private func browseTapped() {
        guard AppLock.shared.require(.action) else { return }
        guard let profile = selectedProfile, let parent = window else { return }
        guard profile.proto != .http else {
            let alert = NSAlert()
            alert.messageText = t("Klasör seçimi yalnızca FTP'de")
            alert.informativeText = t("HTTP yüklemelerinde hedef klasörü sunucu tarafındaki betik belirler.")
            alert.runModal()
            return
        }
        let picker = DirectoryPickerController(profile: profile,
                                               startPath: folderField.stringValue.isEmpty ? profile.remotePath : folderField.stringValue)
        picker.onPick = { [weak self] path in
            self?.folderField.stringValue = path
            self?.folderUserEdited = true
            self?.activePicker = nil
            self?.statusLabel?.stringValue = t("Hedef klasör: %@", path)
        }
        activePicker = picker
        parent.beginSheet(picker.window!, completionHandler: { [weak self] _ in
            self?.activePicker = nil
        })
    }

    @objc private func clearQueue() {
        items.removeAll()
        tableView.reloadData()
        linksTextView.string = ""
        progressBar.doubleValue = 0
        statusLabel.stringValue = t("Liste temizlendi.")
    }

    @objc private func copyLinks() {
        let text = linksTextView.string
        guard !text.isEmpty else {
            statusLabel.stringValue = t("Kopyalanacak link yok.")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusLabel.stringValue = t("Linkler panoya kopyalandı.")
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, items.indices.contains(row) else { return nil }
        let identifier = tableColumn.identifier
        var field = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
        if field == nil {
            let label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 12)
            field = label
        }
        let item = items[row]
        switch identifier.rawValue {
        case "file":
            field?.stringValue = item.url.lastPathComponent
            field?.textColor = .labelColor
        case "status":
            field?.stringValue = item.statusText
            switch item.state {
            case .error: field?.textColor = .systemRed
            case .done: field?.textColor = .systemGreen
            default: field?.textColor = .secondaryLabelColor
            }
        case "size":
            field?.stringValue = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
            field?.textColor = .secondaryLabelColor
        default:
            break
        }
        return field
    }
}
