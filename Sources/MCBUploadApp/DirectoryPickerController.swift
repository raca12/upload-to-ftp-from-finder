import AppKit
import MCBUploadCore

// MARK: - Sunucudaki klasörü seçme ekranı
// Yükleme penceresindeki "Gözat…" düğmesiyle açılır: FTP'ye bağlanıp klasörleri listeler.

final class DirectoryPickerController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    var onPick: ((String) -> Void)?

    private let profile: ServerProfile
    private let lister = DirectoryLister()
    private var path: String
    private var entries: [RemoteEntry] = []

    private let pathField = NSTextField()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var goButton: NSButton!
    private var upButton: NSButton!
    private var pickButton: NSButton!

    init(profile: ServerProfile, startPath: String) {
        self.profile = profile
        self.path = startPath.isEmpty ? "/" : startPath
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = t("Klasör Seç — %@", profile.name)
        super.init(window: window)
        buildUI()
        load()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) desteklenmiyor") }

    // MARK: - Arayüz

    private func buildUI() {
        guard let content = window?.contentView else { return }

        pathField.stringValue = path
        pathField.placeholderString = "/public_html/resimler"
        pathField.target = self
        pathField.action = #selector(goTapped)
        pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        goButton = NSButton(title: t("Git"), target: self, action: #selector(goTapped))
        goButton.bezelStyle = .rounded
        upButton = NSButton(title: t("↑ Üst klasör"), target: self, action: #selector(upTapped))
        upButton.bezelStyle = .rounded

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let topRow = NSStackView(views: [pathField, goButton, upButton])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = t("Sunucudaki içerik")
        column.width = 480
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: t("İptal"), target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        pickButton = NSButton(title: t("Bu klasörü seç"), target: self, action: #selector(pickTapped))
        pickButton.keyEquivalent = "\r"
        pickButton.bezelStyle = .rounded

        let footer = NSStackView(views: [spinner, statusLabel, NSView(), cancelButton, pickButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.views.last?.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [topRow, scroll, footer])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            topRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        window?.defaultButtonCell = pickButton.cell as? NSButtonCell
    }

    // MARK: - Veri

    private func load() {
        pathField.stringValue = path
        setLoading(true)
        let profile = self.profile
        let path = self.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try DirectoryLister().list(profile: profile, path: path) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.setLoading(false)
                switch result {
                case .success(let entries):
                    self.entries = entries
                    self.tableView.reloadData()
                    let dirCount = entries.filter { $0.isDirectory }.count
                    self.setStatus(t("%d klasör · %d dosya", dirCount, entries.count - dirCount))
                case .failure(let error):
                    self.entries = []
                    self.tableView.reloadData()
                    self.setStatus("✗ " + error.localizedDescription, color: .systemRed)
                }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        goButton.isEnabled = !loading
        upButton.isEnabled = !loading
        pickButton.isEnabled = !loading
    }

    private func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        statusLabel.stringValue = text
        statusLabel.toolTip = text
        statusLabel.textColor = color
    }

    // MARK: - Eylemler

    @objc private func goTapped() {
        var target = pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        if !target.hasPrefix("/") { target = "/" + target }
        path = target
        load()
    }

    @objc private func upTapped() {
        var components = path.split(separator: "/").map(String.init)
        if !components.isEmpty { components.removeLast() }
        path = "/" + components.joined(separator: "/")
        load()
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard entries.indices.contains(row) else { return }
        let entry = entries[row]
        guard entry.isDirectory else {
            setStatus(t("“%@” bir dosya, klasör değil.", entry.name), color: .systemOrange)
            return
        }
        path = (path.hasSuffix("/") ? path : path + "/") + entry.name
        load()
    }

    @objc private func pickTapped() {
        onPick?(path)
        closeSheet()
    }

    @objc private func cancelTapped() {
        closeSheet()
    }

    private func closeSheet() {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let identifier = NSUserInterfaceItemIdentifier("cell")
        var field = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
        if field == nil {
            let label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingMiddle
            field = label
        }
        field?.stringValue = (entry.isDirectory ? "📁  " : "📄  ") + entry.name
        field?.textColor = entry.isDirectory ? .labelColor : .secondaryLabelColor
        return field
    }
}
