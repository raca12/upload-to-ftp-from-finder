import Foundation

// MARK: - Çoklu dil
//
// Anahtar = Türkçe metin. Türkçe için tablo gerekmez (anahtar aynen döner),
// diğer dillerde tablodan çevrilir; eksik çeviride Türkçe gösterilir.

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case turkish = "tr"
    case english = "en"

    public var displayName: String {
        switch self {
        case .system: return Localization.text("Sistem dili")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    public var shortCode: String {
        switch self {
        case .system: return Locale.preferredLanguages.first?.prefix(2).description ?? "en"
        case .turkish: return "tr"
        case .english: return "en"
        }
    }
}

public enum Localization {

    private static let languageKey = "MCBLanguage"

    /// Kullanıcının seçimi (UserDefaults).
    public static var preferred: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: languageKey),
                  let value = AppLanguage(rawValue: raw) else { return .english }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
        }
    }

    /// Gerçekten kullanılan dil (sistem dili çözümlenmiş).
    public static var current: AppLanguage {
        let preferred = self.preferred
        guard preferred == .system else { return preferred }
        let systemCode = Locale.preferredLanguages.first?.prefix(2).description ?? "en"
        return systemCode == "tr" ? .turkish : .english
    }

    public static func text(_ key: String) -> String {
        guard current == .english else { return key }
        return english[key] ?? key
    }

    public static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    // MARK: - İngilizce sözlük

    static let english: [String: String] = [
        // Uygulama / menü
        "Uygulamayı Aç": "Open App",
        "Finder'dan FTP'ye Yükle": "Upload to FTP from Finder",
        "Sunucu tanımlı değil — uygulamayı aç": "No servers configured — open the app",
        "Dosya Yükle…": "Upload Files…",
        "Sunucu Ekle… (FTP)": "Add Server… (FTP)",
        "Seçili Sunucuyu Düzenle…": "Edit Selected Server…",
        "Hızlı Yükle": "Quick Upload",
        "Hızlı yükle → %@": "Quick upload → %@",
        "Ayar Dosyasını Aç": "Open Settings File",
        "Finder entegrasyonu": "Finder integration",
        "Finder'da sağ tık menüsü": "Right-click menu in Finder",
        "Dosyalara sağ tıklayıp doğrudan sunucuya yüklemek için Finder eklentisini bir kez etkinleştir.": "Enable the Finder extension once to upload files straight from the right-click menu.",
        "Finder eklentisini etkinleştir": "Enable Finder extension",
        "Sistem Ayarlarını Aç": "Open System Settings",
        "Finder eklentisi etkin": "Finder extension is enabled",
        "Finder eklentisi henüz etkin değil": "Finder extension is not enabled yet",
        "Finder entegrasyonunu ayarla…": "Set up Finder integration…",
        "Güvenlik ve Dil…": "Security & Language…",
        "Kilitle": "Lock",
        "Çıkış": "Quit",
        "Sunucu tanımlı değil": "No servers configured",
        "Sistem dili": "System language",
        "Türkçe": "Turkish",
        "English": "English",

        // Ana pencere
        "Klasör": "Folder",
        "Gözat…": "Browse…",
        "Dosya": "File",
        "Durum": "Status",
        "Boyut": "Size",
        "Dosya Ekle…": "Add Files…",
        "Yükle": "Upload",
        "Sırada": "Queued",
        "Yükleniyor %d%%": "Uploading %d%%",
        "Tamam": "Done",
        "Hata": "Error",
        "Linkler": "Links",
        "Linkleri Kopyala": "Copy Links",
        "Listeyi Temizle": "Clear List",
        "Yükleme bitince linkler otomatik panoya kopyalanır.": "Links are copied to the clipboard automatically when the upload finishes.",
        "Dosyaları buraya sürükleyebilir veya “Dosya Ekle…” kullanabilirsin.": "Drag files here or use “Add Files…”.",
        "Önce dosya ekle.": "Add some files first.",
        "Tanımlı sunucu yok — “＋” ile sunucu ekle.": "No server configured — add one with “＋”.",
        "Liste temizlendi.": "List cleared.",
        "Kopyalanacak link yok.": "There are no links to copy.",
        "Linkler panoya kopyalandı.": "Links copied to the clipboard.",
        "%d dosya yüklendi · %@ · linkler panoda": "%d files uploaded · %@ · links copied",
        "%d dosya kuyrukta": "%d files queued",
        "Hedef klasör: %@": "Target folder: %@",
        "Dosyalar kuyrukta — hedef klasörü seç, sonra “Yükle”ye bas.": "Files queued — choose the target folder, then press “Upload”.",
        "Finder’dan dosya alınamadı — menüyü dosyalar (veya içi dolu bir klasör) üzerinde kullan.": "No files received from Finder — use the menu on files (or a folder with files).",
        "Sunucu kaydedildi: %@": "Server saved: %@",
        "Sunucu silindi: %@": "Server deleted: %@",

        // Sunucu formu
        "Sunucu Ekle": "Add Server",
        "Sunucuyu Düzenle": "Edit Server",
        "Ad": "Name",
        "Protokol": "Protocol",
        "Sunucu adresi (host)": "Server address (host)",
        "Port": "Port",
        "Kullanıcı adı": "Username",
        "Şifre": "Password",
        "Varsayılan klasör": "Default folder",
        "Link kökü (web)": "Link root (web)",
        "Otomatik klasör": "Auto folder",
        "Küçük resim": "Thumbnail",
        "Yükleme adresi (URL)": "Upload URL",
        "Form parametresi": "Form parameter",
        "Link nasıl bulunur?": "How to find the link?",
        "Özel kalıp": "Custom pattern",
        "Özel kalıp (gelişmiş)": "Custom pattern (advanced)",
        "JSON cevabı → “url” alanı": "JSON response → “url” field",
        "JSON cevabı → “link” alanı": "JSON response → “link” field",
        "Cevap sadece link (düz metin)": "Response is just the link (plain text)",
        "HTML sayfası → ilk link": "HTML page → first link",
        "Bağlantıyı Test Et": "Test Connection",
        "İptal": "Cancel",
        "Kaydet": "Save",
        "Sil": "Delete",
        "Test ediliyor…": "Testing…",
        "tarih şablonu": "date pattern",
        "en/boy": "width/height",
        "Sunucuya bir ad ver (örn. “Blog”).": "Give the server a name (e.g. “Blog”).",
        "Sunucu adresi boş olamaz.": "Server address cannot be empty.",
        "Port 1–65535 arasında bir sayı olmalı.": "Port must be a number between 1 and 65535.",
        "SFTP henüz desteklenmiyor.": "SFTP is not supported yet.",
        "HTTP için “Yükleme adresi” gerekli.": "HTTP requires an “Upload URL”.",
        "“Özel kalıp” seçildi ama kalıp boş.": "“Custom pattern” is selected but the pattern is empty.",
        "“%@” silinsin mi?": "Delete “%@”?",
        "Sunucu listeden kaldırılacak. Yüklenecek dosyalara dokunulmaz.": "The server will be removed from the list. Uploaded files are not touched.",
        "Vazgeç": "Cancel",
        "FTP'de link üretmek için “Link kökü” gerekir: dosya /public_html/resimler/a.jpg adresine gidiyorsa link kökü https://site.com/resimler olmalı.":
            "For FTP you need a “Link root”: if the file lands at /public_html/resimler/a.jpg, the link root should be https://site.com/resimler.",
        "FTP: dosya /public_html/resimler/a.jpg adresine gidiyorsa “Web adresi” https://site.com/resimler olmalı — linkler buradan üretilir.":
            "FTP: if the file lands at /public_html/resimler/a.jpg, “Web address” should be https://site.com/resimler — links are built from it.",

        // Klasör seçici
        "Klasör Seç — %@": "Choose Folder — %@",
        "Git": "Go",
        "↑ Üst klasör": "↑ Parent folder",
        "Sunucudaki içerik": "Contents on server",
        "Bu klasörü seç": "Choose this folder",
        "%d klasör · %d dosya": "%d folders · %d files",
        "“%@” bir dosya, klasör değil.": "“%@” is a file, not a folder.",

        // Kilit ekranı
        "Uygulama kilitli": "App locked",
        "Parola": "Password",
        "Aç": "Unlock",
        "Yanlış parola.": "Wrong password.",
        "FTP bilgilerini korumak için parola gir.": "Enter your password to protect the FTP credentials.",
        "Parola gerekli": "Password required",
        "Yükleme için parola gir.": "Enter your password to upload.",
        "Bu işlem için parola gir.": "Enter your password for this action.",

        // Ayarlar
        "Güvenlik ve Dil": "Security & Language",
        "Parola kilidi": "Password lock",
        "Parola belirle": "Set password",
        "Yeni parola": "New password",
        "Yeni parola (tekrar)": "New password (repeat)",
        "Parolayı kaldır": "Remove password",
        "Ne zaman sorulsun?": "When to ask?",
        "Hiç": "Never",
        "Uygulama açılırken": "When the app opens",
        "Her yüklemede": "On every upload",
        "Her işlemde": "On every action",
        "Dil": "Language",
        "Dili değiştirdikten sonra uygulamayı yeniden başlat.": "Restart the app after changing the language.",
        "Parola kaydedildi.": "Password saved.",
        "Parola kaldırıldı.": "Password removed.",
        "Parolayı değiştir": "Change password",
        "Bir sonraki işlemde parola sorulacak.": "You will be asked for the password on the next action.",
        "Parola belirlemek için iki alanı doldur.": "Fill in both fields to set a password.",
        "Düzenle": "Edit",
        "Geri Al": "Undo",
        "Yinele": "Redo",
        "Kes": "Cut",
        "Kopyala": "Copy",
        "Yapıştır": "Paste",
        "Tümünü Seç": "Select All",
        "Kapat": "Close",
        "OK": "OK",
        "Bu sunucuya listede hangi adla görüneceği": "How this server appears in the list",
        "FTP sunucusunun adresi. “ftp://” yazmana gerek yok, sadece alan adı.": "FTP server address. No need for “ftp://”, just the host name.",
        "Genelde 21 (FTP) veya 990 (güvenli FTP). Boş bırakırsan protokole göre dolar.": "Usually 21 (FTP) or 990 (secure FTP). Filled in automatically based on the protocol.",
        "Hosting firmanın verdiği FTP kullanıcı adı": "FTP username provided by your host",
        "FTP şifresi. Mac'inde bu dosyada saklanır (izinler kısıtlı).": "FTP password. Stored on your Mac in a file with restricted permissions.",
        "Varsayılan hedef klasör. Yükleme penceresinde “Gözat…” ile her seferinde değiştirebilirsin.": "Default target folder. You can change it per upload with “Browse…”.",
        "Dosyaların web'de göründüğü kök adres. Linkler bu adresten üretilir.": "Public root where the files are served. Links are built from it.",
        "Sunucu türü. Hosting panelinde “FTP” ya da “FTPS” yazar.": "Server type. Your hosting panel usually says “FTP” or “FTPS”.",
        "Her yüklemede tarihe göre alt klasör aç (örn. 2026/11)": "Create a date-based subfolder on every upload (e.g. 2026/11)",
        "{yyyy} yıl, {MM} ay, {dd} gün yerine geçer.": "{yyyy} = year, {MM} = month, {dd} = day.",
        "Yüklenen fotoğrafın küçük hâlini ayrıca yükler (forum/önizleme için)": "Also uploads a thumbnail of the image (for forums/previews)",
        "Küçük resmin en uzun kenarı (piksel)": "Longest edge of the thumbnail (pixels)",
        "Dosyanın gönderileceği adres (sunucu tarafındaki yükleme betiği).": "Address the file is sent to (the upload script on your server).",
        "Sunucunun dosyayı beklediği form alanının adı. Genelde “file” olur.": "Form field the server expects the file in. Usually “file”.",
        "Sunucu yükleme sonrası bir cevap döndürür. Linki o cevaptan nasıl alacağımızı seç.": "The server returns a response after upload. Choose how to extract the link from it.",
        "Gelişmiş: cevaptan linki çeken düzenli ifade. İlk grup link olarak kullanılır.": "Advanced: regular expression that extracts the link. First group is used.",
        "FTP'ye bağlanıp klasörü listelemeyi dener": "Connects over FTP and lists the folder",
        "Listede görünecek isim": "Name shown in the list",
        "Örn. ftp.ornek.com": "e.g. ftp.example.com",
        "Genelde 21": "Usually 21",
        "FTP kullanıcı adı": "FTP username",
        "FTP şifresi": "FTP password",
        "Yükleme penceresinde değiştirilebilir": "Can be changed in the upload window",
        "Dosyaların web adresi": "Public web address of the files",
        "Düzenli ifade (gelişmiş kullanıcılar için)": "Regular expression (advanced users)",
        "SFTP Faz 2'de gelecek — şimdilik FTP/FTPS kullan.": "SFTP is coming later — use FTP/FTPS for now.",
        "Yükleme başarısız": "Upload failed",
        "Klasör seçimi yalnızca FTP'de": "Folder selection is only available for FTP",
        "HTTP yüklemelerinde hedef klasörü sunucu tarafındaki betik belirler.": "For HTTP uploads the script on the server decides the target folder.",
        "HTTP yüklemelerinde klasörü sunucu belirler": "For HTTP uploads the server decides the folder",
        "FTPS (güvenli, explicit)": "FTPS (secure, explicit)",
        "FTPS (güvenli, implicit)": "FTPS (secure, implicit)",
        "SFTP": "SFTP",
        "Sunucu {\"url\":\"https://…\"} gibi cevap veriyorsa bunu seç.": "Choose this if the server responds like {\"url\":\"https://…\"}.",
        "Sunucu {\"link\":\"https://…\"} gibi cevap veriyorsa bunu seç.": "Choose this if the server responds like {\"link\":\"https://…\"}.",
        "Sunucu sadece linki yazıp döndürüyorsa bunu seç.": "Choose this if the server returns just the link.",
        "Sunucu bir HTML sayfası döndürüp link içindeyse bunu seç.": "Choose this if the server returns an HTML page containing the link.",
        "Bunlar uymuyorsa kendi kalıbını yaz (düzenli ifade bilgisi gerekir).": "Otherwise write your own pattern (regular expressions required).",
        "Parolalar eşleşmiyor.": "Passwords do not match.",
        "Parola en az 6 karakter olmalı.": "Password must be at least 6 characters.",
        "Mevcut parola yanlış.": "Current password is wrong.",
        "Mevcut parola": "Current password",
        "Uygulama açılırken parola sorulsun": "Ask for password when the app opens",
        "Pencere kapanınca kilitle": "Lock when the window closes",

        // Hatalar / çekirdek
        "Sunucu bulunamadı: %@. `mcb servers` ile listeye bakabilirsin.": "Server not found: %@. See the list with `mcb servers`.",
        "Bu protokol henüz desteklenmiyor: %@": "This protocol is not supported yet: %@",
        "HTTP profili için 'http.actionURL' tanımlanmalı.": "The HTTP profile needs 'http.actionURL'.",
        "Eksik bilgi: %@": "Missing information: %@",
        "Aktarım başarısız (çıkış kodu %d): %@": "Transfer failed (exit code %d): %@",
        "Dosya yüklendi ama yanıttan URL çıkarılamadı. Yanıt: %@": "File uploaded but no URL could be extracted from the response. Response: %@",
        "Dosya bulunamadı: %@": "File not found: %@",
        "Bağlantı tamam · %@ içinde %d öğe görünüyor": "Connected · %@ has %d entries",
        "Sunucuya ulaşıldı · %@": "Server reached · %@",
        "Sunucuya ulaşıldı · %@ (HEAD desteklenmiyor olabilir, yükleme çalışabilir)": "Server reached · %@ (HEAD may be unsupported, upload may still work)",
    ]
}
