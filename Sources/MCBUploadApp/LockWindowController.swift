import AppKit
import MCBUploadCore

// MARK: - Oturum kilidi
// Parola ayarlıysa uygulama açılışında ve/veya her işlemde parola ister.

enum LockPurpose {
    case launch
    case upload
    case action

    var message: String {
        switch self {
        case .launch: return Localization.text("FTP bilgilerini korumak için parola gir.")
        case .upload: return Localization.text("Yükleme için parola gir.")
        case .action: return Localization.text("Bu işlem için parola gir.")
        }
    }
}

final class AppLock {
    static let shared = AppLock()

    private let store = SecurityStore()
    private var sessionUnlocked = false

    var hasPassword: Bool { store.load().hasPassword }
    var policy: LockPolicy { store.load().policy }

    func markUnlocked() { sessionUnlocked = true }
    func lockNow() { sessionUnlocked = false }

    /// Gerekliyse parola sorar; devam edilebilirse true döner.
    func require(_ purpose: LockPurpose) -> Bool {
        let settings = store.load()
        guard settings.hasPassword else { return true }

        let needed: Bool
        switch settings.policy {
        case .never:
            needed = false
        case .launch:
            needed = !sessionUnlocked
        case .everyUpload:
            needed = purpose == .upload
        case .everyAction:
            needed = true
        }
        guard needed else { return true }

        guard let window = LockWindowController.present(message: purpose.message) else { return false }
        sessionUnlocked = true
        // pencere kapanana kadar bekle
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return LockWindowController.wasUnlocked
    }
}

// MARK: - Kilit penceresi

final class LockWindowController: NSWindowController {

    static var wasUnlocked = false
    private static var active: LockWindowController?

    private let messageLabel = NSTextField(labelWithString: "")
    private let passwordField = NSSecureTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let store = SecurityStore()

    static func present(message: String) -> NSWindow? {
        wasUnlocked = false
        let controller = LockWindowController(message: message)
        active = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        return controller.window
    }

    init(message: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.title = Localization.text("Uygulama kilitli")
        window.level = .modalPanel
        super.init(window: window)
        build(message: message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) desteklenmiyor") }

    private func build(message: String) {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: Localization.text("Uygulama kilitli"))
        title.font = .boldSystemFont(ofSize: 15)

        messageLabel.stringValue = message
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2

        passwordField.placeholderString = Localization.text("Parola")
        passwordField.target = self
        passwordField.action = #selector(unlockTapped)
        passwordField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.usesSingleLineMode = true

        let unlockButton = NSButton(title: Localization.text("Aç"), target: self, action: #selector(unlockTapped))
        unlockButton.keyEquivalent = "\r"
        unlockButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: Localization.text("İptal"), target: self, action: #selector(cancelTapped))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let header = NSStackView(views: [icon, NSStackView(views: [title, messageLabel])])
        header.orientation = .horizontal
        header.spacing = 14
        (header.arrangedSubviews.last as? NSStackView)?.orientation = .vertical
        (header.arrangedSubviews.last as? NSStackView)?.spacing = 4

        let buttons = NSStackView(views: [NSView(), cancelButton, unlockButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [header, passwordField, errorLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        window?.initialFirstResponder = passwordField
        window?.defaultButtonCell = unlockButton.cell as? NSButtonCell
    }

    @objc private func unlockTapped() {
        let password = passwordField.stringValue
        if store.verify(password) {
            Self.wasUnlocked = true
            NSApp.stopModal()
        } else {
            errorLabel.stringValue = Localization.text("Yanlış parola.")
            passwordField.stringValue = ""
            NSSound.beep()
        }
    }

    @objc private func cancelTapped() {
        Self.wasUnlocked = false
        NSApp.stopModal()
    }
}
