import Foundation
import MCBUploadCore

// Kısa yerelleştirme yardımcısı (anahtar = Türkçe metin)
@inline(__always) func t(_ key: String) -> String {
    Localization.text(key)
}

@inline(__always) func t(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Localization.text(key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}
