import AppKit
import MCBUploadCore

// MARK: - İlk açılış: Finder eklentisini etkinleştirme
//
// Kurulumdan sonra kullanıcı terminale `pluginkit` yazmak zorunda kalmasın.

final class OnboardingWindowController: NSWindowController {

    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var enableButton: NSButton!
    private var settingsButton: NSButton!

    private static let extensionID = "com.mcb.upload.FinderSync"
    static let didOnboardKey = "MCBDidOnboardFinder"

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 270),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = Localization.text("Finder entegrasyonu")
        self.init(window: window)
        build()
        refreshStatus()
    }

    // MARK: - Arayüz

    private func build() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView(image: NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: Localization.text("Finder'da sağ tık menüsü"))
        title.font = .boldSystemFont(ofSize: 16)

        detailLabel.stringValue = Localization.text("Dosyalara sağ tıklayıp doğrudan sunucuya yüklemek için Finder eklentisini bir kez etkinleştir.")
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)

        statusLabel.font = .systemFont(ofSize: 12)

        enableButton = NSButton(title: Localization.text("Finder eklentisini etkinleştir"),
                                target: self, action: #selector(enableTapped))
        enableButton.bezelStyle = .rounded

        settingsButton = NSButton(title: Localization.text("Sistem Ayarlarını Aç"),
                                  target: self, action: #selector(openSettingsTapped))
        settingsButton.bezelStyle = .rounded

        let doneButton = NSButton(title: Localization.text("Kapat"), target: self, action: #selector(closeTapped))
        doneButton.keyEquivalent = "\u{1b}"
        doneButton.bezelStyle = .rounded

        let header = NSStackView(views: [icon, NSStackView(views: [title, detailLabel])])
        header.orientation = .horizontal
        header.spacing = 16
        (header.arrangedSubviews.last as? NSStackView)?.orientation = .vertical
        (header.arrangedSubviews.last as? NSStackView)?.spacing = 6

        let buttons = NSStackView(views: [enableButton, settingsButton, NSView(), doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [header, statusLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 24
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalToConstant: 420),
        ])
    }

    // MARK: - Durum

    private func extensionEnabled() -> Bool {
        let result = CommandRunner.run("/usr/bin/pluginkit",
                                       ["-m", "-i", Self.extensionID])
        return result.output.contains("+")
    }

    private func refreshStatus() {
        if extensionEnabled() {
            statusLabel.stringValue = "✓ " + Localization.text("Finder eklentisi etkin")
            statusLabel.textColor = .systemGreen
            enableButton.isEnabled = false
            settingsButton.isEnabled = false
            UserDefaults.standard.set(true, forKey: Self.didOnboardKey)
        } else {
            statusLabel.stringValue = "✗ " + Localization.text("Finder eklentisi henüz etkin değil")
            statusLabel.textColor = .systemOrange
            enableButton.isEnabled = true
            settingsButton.isEnabled = true
        }
    }

    // MARK: - Eylemler

    @objc private func enableTapped() {
        enableButton.isEnabled = false
        _ = CommandRunner.run("/usr/bin/pluginkit", ["-e", "use", "-i", Self.extensionID])
        _ = CommandRunner.run("/usr/bin/killall", ["Finder"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshStatus()
        }
    }

    @objc private func openSettingsTapped() {
        let urls = [
            "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    @objc private func closeTapped() {
        window?.close()
    }
}

// MARK: - Komut çalıştırıcı

enum CommandRunner {
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
