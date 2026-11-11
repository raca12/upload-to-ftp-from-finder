import AppKit

// Upload to FTP from Finder — menu bar uygulaması (AppKit, programatik arayüz)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
