import AppKit
import MCBUploadCore

// MARK: - Güvenlik ve Dil ayarları

final class SettingsWindowController: NSWindowController {

    private let store = SecurityStore()
    private let currentField = NSSecureTextField()
    private let newField = NSSecureTextField()
    private let repeatField = NSSecureTextField()
    private let policyPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let lockOnCloseCheck = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)
    private var currentRow: NSTextField?

    private static let labelWidth: CGFloat = 160

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = Localization.text("Güvenlik ve Dil")
        self.init(window: window)
        build()
        loadValues()
    }

    private func row(_ title: String, _ controls: [NSView]) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let stack = NSStackView(views: [label] + controls + [spacer])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        return stack
    }

    private func build() {
        guard let content = window?.contentView else { return }

        for field in [currentField, newField, repeatField] {
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
        }
        currentField.placeholderString = Localization.text("Mevcut parola")
        newField.placeholderString = Localization.text("Yeni parola")
        repeatField.placeholderString = Localization.text("Yeni parola")

        let hint = NSTextField(wrappingLabelWithString:
            Localization.text("Parola belirlemek için iki alanı doldur."))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        policyPopup.addItems(withTitles: LockPolicy.allCases.map { policyTitle($0) })
        policyPopup.widthAnchor.constraint(equalToConstant: 260).isActive = true

        languagePopup.addItems(withTitles: AppLanguage.allCases.map { $0.displayName })
        languagePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        lockOnCloseCheck.title = Localization.text("Pencere kapanınca kilitle")

        saveButton.title = Localization.text("Parola belirle")
        saveButton.target = self
        saveButton.action = #selector(savePassword)
        saveButton.bezelStyle = .rounded

        removeButton.title = Localization.text("Parolayı kaldır")
        removeButton.target = self
        removeButton.action = #selector(removePassword)
        removeButton.bezelStyle = .rounded
        removeButton.contentTintColor = .systemRed

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.usesSingleLineMode = true
        statusLabel.lineBreakMode = .byTruncatingTail

        let closeButton = NSButton(title: Localization.text("Kapat"), target: self, action: #selector(closeTapped))
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded

        let securityTitle = NSTextField(labelWithString: Localization.text("Parola kilidi"))
        securityTitle.font = .boldSystemFont(ofSize: 13)

        let passwordButtons = NSStackView(views: [saveButton, removeButton])
        passwordButtons.orientation = .horizontal
        passwordButtons.spacing = 8

        let current = row(Localization.text("Mevcut parola"), [currentField])
        currentRow = current.arrangedSubviews.first as? NSTextField

        let form = NSStackView(views: [
            securityTitle,
            current,
            row(Localization.text("Yeni parola"), [newField]),
            row(Localization.text("Yeni parola (tekrar)"), [repeatField]),
            row("", [passwordButtons]),
            row(Localization.text("Ne zaman sorulsun?"), [policyPopup]),
            row("", [lockOnCloseCheck]),
            row(Localization.text("Dil"), [languagePopup]),
            row("", [hint]),
            row("", [statusLabel]),
        ])
        form.orientation = .vertical
        form.spacing = 10
        form.alignment = .leading

        let footer = NSStackView(views: [NSView(), closeButton])
        footer.orientation = .horizontal
        footer.spacing = 8

        let stack = NSStackView(views: [form, footer])
        stack.orientation = .vertical
        stack.spacing = 18
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        form.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true }

        window?.defaultButtonCell = closeButton.cell as? NSButtonCell

        content.layoutSubtreeIfNeeded()
        let height = form.fittingSize.height + hint.fittingSize.height + footer.fittingSize.height + 36 + 40
        window?.setContentSize(NSSize(width: 620, height: max(320, height)))
    }

    private func policyTitle(_ policy: LockPolicy) -> String {
        switch policy {
        case .never: return Localization.text("Hiç")
        case .launch: return Localization.text("Uygulama açılırken")
        case .everyUpload: return Localization.text("Her yüklemede")
        case .everyAction: return Localization.text("Her işlemde")
        }
    }

    private func loadValues() {
        let settings = store.load()
        if settings.hasPassword {
            policyPopup.selectItem(at: LockPolicy.allCases.firstIndex(of: settings.policy) ?? 1)
            currentField.isHidden = false
            currentRow?.isHidden = false
            removeButton.isEnabled = true
            saveButton.title = Localization.text("Parolayı değiştir")
        } else {
            policyPopup.selectItem(at: LockPolicy.allCases.firstIndex(of: settings.policy) ?? 0)
            currentField.isHidden = true
            currentRow?.isHidden = true
            removeButton.isEnabled = false
            saveButton.title = Localization.text("Parola belirle")
        }
        lockOnCloseCheck.state = settings.lockOnWindowClose ? .on : .off
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: Localization.preferred) ?? 0)
        policyPopup.isEnabled = true
        currentField.stringValue = ""
        newField.stringValue = ""
        repeatField.stringValue = ""
    }

    @objc private func savePassword() {
        var settings = store.load()

        // Mevcut parola varsa doğrula
        if settings.hasPassword {
            guard store.verify(currentField.stringValue) else {
                setStatus(Localization.text("Mevcut parola yanlış."), color: .systemRed)
                return
            }
        }

        let password = newField.stringValue
        guard password.count >= 6 else {
            setStatus(Localization.text("Parola en az 6 karakter olmalı."), color: .systemRed)
            return
        }
        guard password == repeatField.stringValue else {
            setStatus(Localization.text("Parolalar eşleşmiyor."), color: .systemRed)
            return
        }

        settings.policy = LockPolicy.allCases[max(0, policyPopup.indexOfSelectedItem)]
        settings.lockOnWindowClose = lockOnCloseCheck.state == .on
        do {
            try store.save(settings)
            try store.setPassword(password, policy: settings.policy)
            setStatus(Localization.text("Parola kaydedildi."), color: .systemGreen)
            AppLock.shared.markUnlocked()
            loadValues()
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
        }
        applyLanguage()
    }

    @objc private func removePassword() {
        let settings = store.load()
        if settings.hasPassword, !store.verify(currentField.stringValue) {
            setStatus(Localization.text("Mevcut parola yanlış."), color: .systemRed)
            return
        }
        do {
            try store.removePassword()
            var updated = store.load()
            updated.policy = LockPolicy.allCases[max(0, policyPopup.indexOfSelectedItem)]
            updated.lockOnWindowClose = lockOnCloseCheck.state == .on
            try store.save(updated)
            setStatus(Localization.text("Parola kaldırıldı."), color: .systemGreen)
            loadValues()
        } catch {
            setStatus(error.localizedDescription, color: .systemRed)
        }
    }

    @objc private func closeTapped() {
        // Politika seçimi parola olmadan da kaydedilsin
        var settings = store.load()
        settings.policy = LockPolicy.allCases[max(0, policyPopup.indexOfSelectedItem)]
        settings.lockOnWindowClose = lockOnCloseCheck.state == .on
        try? store.save(settings)
        applyLanguage()
        window?.close()
    }

    private func applyLanguage() {
        let selected = AppLanguage.allCases[max(0, languagePopup.indexOfSelectedItem)]
        guard selected != Localization.preferred else { return }
        Localization.preferred = selected
        let alert = NSAlert()
        alert.messageText = Localization.text("Dili değiştirdikten sonra uygulamayı yeniden başlat.")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }
}
