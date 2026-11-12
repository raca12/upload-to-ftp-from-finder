import AppKit
import MCBUploadCore

// MARK: - Sunucu ekleme / düzenleme ekranı
// "＋" düğmesiyle açılır: FTP bilgileri buradan girilir, kod/JSON düzenlenmez.

/// Sunucunun yükleme sonrası verdiği cevaptan linki nasıl çıkaracağımızı anlatan hazır seçenekler.
enum ResponsePreset: Int, CaseIterable {
    case jsonURL
    case jsonLink
    case plainText
    case htmlLink
    case custom

    var title: String {
        switch self {
        case .jsonURL: return "JSON cevabı → “url” alanı"
        case .jsonLink: return "JSON cevabı → “link” alanı"
        case .plainText: return "Cevap sadece link (düz metin)"
        case .htmlLink: return "HTML sayfası → ilk link"
        case .custom: return "Özel kalıp (gelişmiş)"
        }
    }

    var helpText: String {
        switch self {
        case .jsonURL: return "Sunucu {\"url\":\"https://…\"} gibi cevap veriyorsa bunu seç."
        case .jsonLink: return "Sunucu {\"link\":\"https://…\"} gibi cevap veriyorsa bunu seç."
        case .plainText: return "Sunucu sadece linki yazıp döndürüyorsa bunu seç."
        case .htmlLink: return "Sunucu bir HTML sayfası döndürüp link içindeyse bunu seç."
        case .custom: return "Bunlar uymuyorsa kendi kalıbını yaz (düzenli ifade bilgisi gerekir)."
        }
    }

    /// Cevaptan linki çeken düzenli ifade. `nil` = cevabın kendisi link.
    var regex: String? {
        switch self {
        case .jsonURL: return #""url"\s*:\s*"([^"]+)""#
        case .jsonLink: return #""link"\s*:\s*"([^"]+)""#
        case .plainText: return nil
        case .htmlLink: return #"href="([^"]+)""#
        case .custom: return nil
        }
    }

    static func detect(from regex: String?) -> ResponsePreset {
        guard let regex, !regex.isEmpty else { return .plainText }
        if regex == ResponsePreset.jsonURL.regex { return .jsonURL }
        if regex == ResponsePreset.jsonLink.regex { return .jsonLink }
        if regex == ResponsePreset.htmlLink.regex { return .htmlLink }
        return .custom
    }
}

final class ServerEditorController: NSWindowController {

    var onSave: ((ServerProfile) -> Void)?
    var onDelete: ((ServerProfile) -> Void)?

    private var original: ServerProfile?
    private let tester = ConnectionTester()
    private let profileStore = ProfileStore()

    private let nameField = NSTextField()
    private let protocolPopup = NSPopUpButton()
    private let hostField = NSTextField()
    private let portField = NSTextField()
    private let userField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let remotePathField = NSTextField()
    private let publicURLField = NSTextField()

    private let autoSortCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoSortField = NSTextField()
    private let thumbCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let thumbSizeField = NSTextField()

    private let actionURLField = NSTextField()
    private let fileFieldField = NSTextField()
    private let presetPopup = NSPopUpButton()
    private let regexField = NSTextField()
    private let presetHelp = NSTextField(labelWithString: "")

    private let testButton = NSButton(title: Localization.text("Bağlantıyı Test Et"), target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: Localization.text("Kaydet"), target: nil, action: nil)

    private var httpRows: [NSStackView] = []
    private var customRegexRow: NSStackView?
    private var formRows: [NSStackView] = []
    private var rootStack: NSStackView?
    private var isEditing: Bool { original != nil }

    private static let labelWidth: CGFloat = 150

    // MARK: - Kurulum

    convenience init(server: ServerProfile?) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = server == nil ? Localization.text("Sunucu Ekle") : Localization.text("Sunucuyu Düzenle")
        self.init(window: window)
        self.original = server
        buildUI()
        fill(from: server)
    }

    // MARK: - Arayüz

    private func styleField(_ field: NSTextField, placeholder: String, help: String, minWidth: CGFloat = 340) {
        field.placeholderString = placeholder
        field.toolTip = help
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    }

    private func row(_ title: String, _ controls: [NSView], help: String? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.toolTip = help
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let stack = NSStackView(views: [label] + controls + [spacer])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .secondaryLabelColor
        field.font = .systemFont(ofSize: 11)
        return field
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        styleField(nameField, placeholder: "Blog sunucusu",
                   help: Localization.text("Bu sunucuya listede hangi adla görüneceği"))
        styleField(hostField, placeholder: "ftp.ornek.com",
                   help: Localization.text("FTP sunucusunun adresi. “ftp://” yazmana gerek yok, sadece alan adı."))
        styleField(portField, placeholder: "21", help: Localization.text("Genelde 21 (FTP) veya 990 (güvenli FTP). Boş bırakırsan protokole göre dolar."), minWidth: 0)
        portField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        styleField(userField, placeholder: "kullanici", help: Localization.text("Hosting firmanın verdiği FTP kullanıcı adı"))
        styleField(passwordField, placeholder: "••••••", help: Localization.text("FTP şifresi. Mac'inde bu dosyada saklanır (izinler kısıtlı)."))
        styleField(remotePathField, placeholder: "/public_html/resimler",
                   help: Localization.text("Varsayılan hedef klasör. Yükleme penceresinde “Gözat…” ile her seferinde değiştirebilirsin."))
        styleField(publicURLField, placeholder: "https://site.com/resimler",
                   help: Localization.text("Dosyaların web'de göründüğü kök adres. Linkler bu adresten üretilir."))

        protocolPopup.addItems(withTitles: ["FTP",
                                            Localization.text("FTPS (güvenli, explicit)"),
                                            Localization.text("FTPS (güvenli, implicit)"),
                                            "HTTP POST",
                                            "SFTP"])
        protocolPopup.toolTip = Localization.text("Sunucu türü. Hosting panelinde “FTP” ya da “FTPS” yazar.")
        protocolPopup.target = self
        protocolPopup.action = #selector(protocolChanged)
        portField.stringValue = "21"

        autoSortCheck.target = self
        autoSortCheck.action = #selector(toggleAutoSort)
        autoSortCheck.toolTip = Localization.text("Her yüklemede tarihe göre alt klasör aç (örn. 2026/11)")
        autoSortField.placeholderString = "{yyyy}/{MM}"
        autoSortField.stringValue = "{yyyy}/{MM}"
        autoSortField.isEnabled = false
        autoSortField.toolTip = Localization.text("{yyyy} yıl, {MM} ay, {dd} gün yerine geçer.")
        autoSortField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        thumbCheck.state = .on
        thumbCheck.toolTip = Localization.text("Yüklenen fotoğrafın küçük hâlini ayrıca yükler (forum/önizleme için)")
        thumbSizeField.placeholderString = "400"
        thumbSizeField.stringValue = "400"
        thumbSizeField.toolTip = Localization.text("Küçük resmin en uzun kenarı (piksel)")
        thumbSizeField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        styleField(actionURLField, placeholder: "https://site.com/upload.php",
                   help: Localization.text("Dosyanın gönderileceği adres (sunucu tarafındaki yükleme betiği)."))
        styleField(fileFieldField, placeholder: "file",
                   help: Localization.text("Sunucunun dosyayı beklediği form alanının adı. Genelde “file” olur."),
                   minWidth: 200)

        presetPopup.addItems(withTitles: ResponsePreset.allCases.map(\.title))
        presetPopup.toolTip = Localization.text("Sunucu yükleme sonrası bir cevap döndürür. Linki o cevaptan nasıl alacağımızı seç.")
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        presetHelp.font = .systemFont(ofSize: 11)
        presetHelp.textColor = .secondaryLabelColor

        styleField(regexField, placeholder: "\"url\"\\s*:\\s*\"([^\"]+)\"",
                   help: Localization.text("Gelişmiş: cevaptan linki çeken düzenli ifade. İlk grup link olarak kullanılır."),
                   minWidth: 260)

        let autoSortRow = row(t("Otomatik klasör"), [autoSortCheck, autoSortField, caption(t("tarih şablonu"))],
                              help: "Yükleme tarihine göre alt klasör oluşturur")
        let thumbRow = row(t("Küçük resim"), [thumbCheck, caption(t("en/boy")), thumbSizeField, caption("px")],
                           help: "Thumbnail üretimi")

        let httpActionRow = row(t("Yükleme adresi (URL)"), [actionURLField],
                                help: "Dosyanın gönderileceği adres")
        let httpFieldRow = row(t("Form parametresi"), [fileFieldField],
                               help: "Sunucunun dosyayı beklediği form alanı adı")
        let presetRow = row(t("Link nasıl bulunur?"), [presetPopup],
                            help: "Cevaptan dosya linkini çıkarma yöntemi")
        presetRow.addArrangedSubview(presetHelp)
        let regexRow = row(t("Özel kalıp"), [regexField], help: t("Düzenli ifade (gelişmiş kullanıcılar için)"))

        httpRows = [httpActionRow, httpFieldRow, presetRow]
        customRegexRow = regexRow

        let hint = NSTextField(wrappingLabelWithString:
            Localization.text("FTP'de link üretmek için “Link kökü” gerekir: dosya /public_html/resimler/a.jpg adresine gidiyorsa link kökü https://site.com/resimler olmalı."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.usesSingleLineMode = true
        statusLabel.maximumNumberOfLines = 1
        statusLabel.cell?.truncatesLastVisibleLine = true
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        testButton.target = self
        testButton.action = #selector(testTapped)
        testButton.bezelStyle = .rounded
        testButton.toolTip = Localization.text("FTP'ye bağlanıp klasörü listelemeyi dener")

        let cancelButton = NSButton(title: Localization.text("İptal"), target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let deleteButton = NSButton(title: Localization.text("Sil"), target: self, action: #selector(deleteTapped))
        deleteButton.bezelStyle = .rounded
        deleteButton.isHidden = !isEditing

        statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let footer = NSStackView(views: [testButton, statusLabel, footerSpacer, deleteButton, cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.spacing = 10

        formRows = [
            row(t("Ad"), [nameField], help: t("Listede görünecek isim")),
            row(t("Protokol"), [protocolPopup], help: "FTP / FTPS / HTTP"),
            row(t("Sunucu adresi (host)"), [hostField], help: t("Örn. ftp.ornek.com")),
            row(t("Port"), [portField], help: t("Genelde 21")),
            row(t("Kullanıcı adı"), [userField], help: t("FTP kullanıcı adı")),
            row(t("Şifre"), [passwordField], help: t("FTP şifresi")),
            row(t("Varsayılan klasör"), [remotePathField], help: t("Yükleme penceresinde değiştirilebilir")),
            row(t("Link kökü (web)"), [publicURLField], help: t("Dosyaların web adresi")),
            autoSortRow,
            thumbRow,
            httpActionRow,
            httpFieldRow,
            presetRow,
            regexRow,
        ]
        let form = NSStackView(views: formRows)
        form.orientation = .vertical
        form.spacing = 10
        form.alignment = .leading

        let stack = NSStackView(views: [form, hint, footer])
        rootStack = stack
        stack.orientation = .vertical
        stack.spacing = 18
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalToConstant: 660),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        formRows.forEach { $0.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true }

        updateHTTPVisibility()
        updatePresetHelp()
        window?.defaultButtonCell = saveButton.cell as? NSButtonCell
        window?.initialFirstResponder = nameField
        resizeToFit()
    }

    // MARK: - Doldurma

    private func fill(from server: ServerProfile?) {
        guard let server else { return }

        nameField.stringValue = server.name
        switch server.proto {
        case .ftp: protocolPopup.selectItem(at: 0)
        case .ftps: protocolPopup.selectItem(at: 1)
        case .ftpsi: protocolPopup.selectItem(at: 2)
        case .http: protocolPopup.selectItem(at: 3)
        case .sftp: protocolPopup.selectItem(at: 4)
        }
        hostField.stringValue = server.host
        portField.stringValue = "\(server.port)"
        userField.stringValue = server.username
        let resolvedPassword = server.password.isEmpty ? profileStore.password(for: server) : server.password
        passwordField.stringValue = resolvedPassword
        remotePathField.stringValue = server.remotePath
        publicURLField.stringValue = server.publicBaseURL ?? ""
        autoSortCheck.state = server.autoSort.enabled ? .on : .off
        autoSortField.stringValue = server.autoSort.template
        autoSortField.isEnabled = server.autoSort.enabled
        thumbCheck.state = server.thumbnails.enabled ? .on : .off
        thumbSizeField.stringValue = "\(server.thumbnails.maxWidth)"

        if let http = server.http {
            actionURLField.stringValue = http.actionURL
            fileFieldField.stringValue = http.fileField
            regexField.stringValue = http.fileURLRegex ?? ""
            let preset = ResponsePreset.detect(from: http.fileURLRegex)
            presetPopup.selectItem(at: preset.rawValue)
        } else {
            presetPopup.selectItem(at: ResponsePreset.jsonURL.rawValue)
        }
        updateHTTPVisibility()
        updatePresetHelp()
    }

    // MARK: - Protokol / seçenekler

    private var selectedProto: TransferProtocol {
        switch protocolPopup.indexOfSelectedItem {
        case 1: return .ftps
        case 2: return .ftpsi
        case 3: return .http
        case 4: return .sftp
        default: return .ftp
        }
    }

    private var selectedPreset: ResponsePreset {
        ResponsePreset(rawValue: presetPopup.indexOfSelectedItem) ?? .jsonURL
    }

    @objc private func protocolChanged() {
        let proto = selectedProto
        let current = portField.stringValue
        if current.isEmpty || ["21", "990", "22"].contains(current) {
            portField.stringValue = "\(proto.defaultPort)"
        }
        updateHTTPVisibility()
        setStatus("")
    }

    @objc private func presetChanged() {
        updatePresetHelp()
        updateHTTPVisibility()
    }

    private func updatePresetHelp() {
        presetHelp.stringValue = selectedPreset.helpText
    }

    private func updateHTTPVisibility() {
        let isHTTP = selectedProto == .http
        httpRows.forEach { $0.isHidden = !isHTTP }
        customRegexRow?.isHidden = !isHTTP || selectedPreset != .custom
        if isHTTP { setStatus("") }
        resizeToFit()
    }

    /// Pencereyi formun gerçek yüksekliğine oturtur (boş alan bırakmaz).
    private func resizeToFit() {
        guard let window, let stack = rootStack else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height) + 40
        window.setContentSize(NSSize(width: 720, height: max(260, height)))
    }

    @objc private func toggleAutoSort() {
        autoSortField.isEnabled = autoSortCheck.state == .on
    }

    private func setStatus(_ text: String, color: NSColor = .secondaryLabelColor) {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        statusLabel.stringValue = singleLine
        statusLabel.toolTip = singleLine
        statusLabel.textColor = color
    }

    // MARK: - Eylemler

    @objc private func testTapped() {
        guard var profile = buildProfile(showErrors: true) else { return }
        if profile.password.isEmpty { profile.password = profileStore.password(for: profile) }
        testButton.isEnabled = false
        setStatus(t("Test ediliyor…"))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.tester.test(profile) }
            DispatchQueue.main.async {
                self.testButton.isEnabled = true
                switch result {
                case .success(let message):
                    self.setStatus("✓ " + message, color: .systemGreen)
                case .failure(let error):
                    self.setStatus("✗ " + error.localizedDescription, color: .systemRed)
                }
            }
        }
    }

    @objc private func saveTapped() {
        guard let profile = buildProfile(showErrors: true) else { return }
        onSave?(profile)
        closeSheet()
    }

    @objc private func deleteTapped() {
        guard let profile = original else { return }
        onDelete?(profile)
        closeSheet()
    }

    @objc private func cancelTapped() {
        closeSheet()
    }

    private func closeSheet() {
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        }
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Doğrulama

    private func buildProfile(showErrors: Bool) -> ServerProfile? {
        func fail(_ message: String) -> ServerProfile? {
            if showErrors { setStatus("✗ " + message, color: .systemRed) }
            return nil
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let proto = selectedProto

        if name.isEmpty { return fail(t("Sunucuya bir ad ver (örn. “Blog”).")) }

        if host.isEmpty { return fail(t("Sunucu adresi boş olamaz.")) }
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) else {
            return fail(t("Port 1–65535 arasında bir sayı olmalı."))
        }

        var profile = original ?? ServerProfile(name: name, proto: proto, host: host)
        profile.name = name
        profile.proto = proto
        profile.host = host
        profile.port = port
        profile.username = userField.stringValue.trimmingCharacters(in: .whitespaces)
        let enteredPassword = passwordField.stringValue
        if !enteredPassword.isEmpty {
            profile.password = enteredPassword
        } else if let orig = original {
            profile.password = orig.password.isEmpty ? profileStore.password(for: orig) : orig.password
        } else {
            profile.password = ""
        }

        var remotePath = remotePathField.stringValue.trimmingCharacters(in: .whitespaces)
        if remotePath.isEmpty { remotePath = "/" }
        if !remotePath.hasPrefix("/") { remotePath = "/" + remotePath }
        profile.remotePath = remotePath

        let publicURL = publicURLField.stringValue.trimmingCharacters(in: .whitespaces)
        profile.publicBaseURL = publicURL.isEmpty ? nil : publicURL

        profile.autoSort.enabled = autoSortCheck.state == .on
        let template = autoSortField.stringValue.trimmingCharacters(in: .whitespaces)
        profile.autoSort.template = template.isEmpty ? "{yyyy}/{MM}" : template

        profile.thumbnails.enabled = thumbCheck.state == .on
        if let size = Int(thumbSizeField.stringValue.trimmingCharacters(in: .whitespaces)), size > 0 {
            profile.thumbnails.maxWidth = size
            profile.thumbnails.maxHeight = size
        }

        if proto == .http {
            let action = actionURLField.stringValue.trimmingCharacters(in: .whitespaces)
            if action.isEmpty { return fail(t("HTTP için “Yükleme adresi” gerekli.")) }
            let field = fileFieldField.stringValue.trimmingCharacters(in: .whitespaces)

            var regex: String?
            switch selectedPreset {
            case .custom:
                let custom = regexField.stringValue.trimmingCharacters(in: .whitespaces)
                if custom.isEmpty { return fail(t("“Özel kalıp” seçildi ama kalıp boş.")) }
                regex = custom
            default:
                regex = selectedPreset.regex
            }

            profile.http = HTTPUploadConfig(actionURL: action,
                                            fileField: field.isEmpty ? "file" : field,
                                            fields: original?.http?.fields ?? [:],
                                            headers: original?.http?.headers ?? [:],
                                            fileURLRegex: regex,
                                            thumbURLRegex: original?.http?.thumbURLRegex,
                                            matchGroup: original?.http?.matchGroup ?? 1)
        } else {
            profile.http = nil
        }

        return profile
    }
}
