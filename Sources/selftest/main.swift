import Foundation
import CoreGraphics
import ImageIO
import MCBUploadCore

// Xcode/XCTest olmadan çalışan hafif doğrulama seti.
// Kullanım: ./build.sh --with-selftest && .build/manual/selftest

var failures = 0
var checks = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ \(message)")
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    expect(lhs == rhs, "\(message) — beklenen: \(rhs), gelen: \(lhs)")
}

print("Upload to FTP from Finder self-test")

// MARK: Şablonlar
var values = ["url": "https://x/y.png", "filename": "y.png", "thumb": ""]
expectEqual(Template.render("[img]{url}[/img]", values: values), "[img]https://x/y.png[/img]", "basit şablon")
expectEqual(Template.render("{thumbOrUrl}", values: values), "https://x/y.png", "thumbOrUrl -> url yedeği")

values["thumb"] = "https://x/y_th.png"
expectEqual(Template.render("{thumbOrUrl}", values: values), "https://x/y_th.png", "thumbOrUrl -> thumb")

let server = ServerProfile(name: "S", proto: .ftp, host: "h")
let file = UploadedFile(localPath: "/tmp/a.jpg", remoteURL: "https://x/a.jpg", thumbURL: "https://x/a_th.jpg", bytes: 42)
expectEqual(LinkTemplate.format(file, templateName: "bbcode-image", server: server),
            "[url=https://x/a.jpg][img]https://x/a_th.jpg[/img][/url]", "bbcode-image")
expectEqual(LinkTemplate.format(file, templateName: "markdown", server: server),
            "[a.jpg](https://x/a.jpg)", "markdown")
expect(LinkTemplate.template(named: "yok", in: server) == nil, "bilinmeyen şablon nil")

var custom = server
custom.templates["ozel"] = "{filename}@{server}"
expectEqual(LinkTemplate.format(file, templateName: "ozel", server: custom), "a.jpg@S", "özel şablon")

// MARK: Yollar
expectEqual(PathTools.join("/public_html/img", "2026/11", "a.jpg"), "/public_html/img/2026/11/a.jpg", "path join")
expectEqual(PathTools.join("/", nil, nil, "a.jpg"), "/a.jpg", "path join kök")
expectEqual(PathTools.encodeRemotePath("/resim/çiçek ler.jpg"), "/resim/%C3%A7i%C3%A7ek%20ler.jpg", "yüzde kodlama")

let ftpServer = ServerProfile(name: "S", proto: .ftp, host: "h", port: 2121, remotePath: "/a", publicBaseURL: "https://cdn.x/img/")
expectEqual(PathTools.transferURL(profile: ftpServer, remoteFilePath: "/a/b.jpg"), "ftp://h:2121/a/b.jpg", "transfer url")
expectEqual(PathTools.publicURL(profile: ftpServer, remoteFilePath: "/a/b.jpg"), "https://cdn.x/img/a/b.jpg", "public url")

// MARK: Auto-sort
var components = DateComponents()
components.year = 2026; components.month = 11; components.day = 11
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let date = calendar.date(from: components)!
expectEqual(Template.autoSortPath(template: "resimler/{yyyy}/{MM}", serverName: "S", date: date),
            "resimler/2026/11", "auto-sort")

// MARK: curl yardımcıları
expectEqual(CurlTransport.parsePercent("###  62.5%"), 0.625, "yüzde ayrıştırma")
expectEqual(CurlTransport.configLine(key: "user", value: #"a"b"#), "user = \"a\\\"b\"\n", "curl config kaçış")
expectEqual(UploadEngine.formFileValue(field: "file", path: "/tmp/a.jpg"), "file=@/tmp/a.jpg", "form alanı")
expectEqual(UploadEngine.formFileValue(field: "file", path: "/tmp/a;b.jpg"), "file=@\"/tmp/a;b.jpg\"", "form alanı tırnak")
expectEqual(UploadEngine.extractURL(from: #"{"url":"https://cdn.x/a.jpg"}"#, regex: #""url"\s*:\s*"([^"]+)""#, group: 1),
            "https://cdn.x/a.jpg", "regex ile URL çıkarma")
expectEqual(UploadEngine.unescapeJSONString(#"https:\/\/x.y\/G\u00f6r.jpg"#), "https://x.y/Gör.jpg", "JSON kaçış çözme")
expectEqual(PathTools.sanitizeURL("http://x/a b.jpg"), "http://x/a%20b.jpg", "URL boşluk kodlama")
expectEqual(PathTools.sanitizeURL("http://x/a%20b.jpg"), "http://x/a%20b.jpg", "URL çift kodlama yok")

// MARK: FTP LIST ayrıştırma
let unixListing = """
total 32
drwxr-xr-x    2 owner    group        4096 Nov 11 16:31 resimler
-rw-r--r--    1 owner    group      102400 Nov 11 16:31 foto.jpg
drwxr-xr-x    5 owner    group        4096 Jan 01  2024 eski klasör
"""
let parsedUnix = FTPListingParser.parse(unixListing)
expectEqual(parsedUnix.count, 3, "unix LIST satır sayısı")
expectEqual(parsedUnix.first?.isDirectory, true, "klasörler önce")
expectEqual(parsedUnix.first?.name, "eski klasör", "unix klasör adı (boşluklu)")
expect(parsedUnix.contains(RemoteEntry(name: "foto.jpg", isDirectory: false)), "unix dosya adı")

let dosListing = """
11-11-26  04:31PM       <DIR>          resimler
11-11-26  04:31PM              102400 foto.jpg
"""
let parsedDOS = FTPListingParser.parse(dosListing)
expectEqual(parsedDOS.count, 2, "dos LIST satır sayısı")
expectEqual(parsedDOS.first?.name, "resimler", "dos klasör adı")
expectEqual(parsedDOS.first?.isDirectory, true, "dos klasör tespiti")

let mlsdListing = "type=dir;size=0; resimler\ntype=file;size=42; foto.jpg\n"
let parsedMLSD = FTPListingParser.parse(mlsdListing)
expectEqual(parsedMLSD.count, 2, "mlsd satır sayısı")
expectEqual(parsedMLSD.first?.isDirectory, true, "mlsd klasör tespiti")

expectEqual(FTPListingParser.parse("foto.jpg\nadlar.txt\n").count, 2, "düz isim listesi")

// MARK: Link yolu
expectEqual(PathTools.relativePath("/public_html/img/2026/a.jpg", base: "/public_html/img"), "/2026/a.jpg", "link yolu kısaltma")
expectEqual(PathTools.relativePath("/public_html/img/a.jpg", base: "/public_html/img/"), "/a.jpg", "link yolu (sondaki /)")
expectEqual(PathTools.relativePath("/baska/a.jpg", base: "/public_html/img"), "/baska/a.jpg", "link yolu eşleşmezse")
let ftpImg = ServerProfile(name: "S", proto: .ftp, host: "h", port: 2121,
                           remotePath: "/public_html/img", publicBaseURL: "https://cdn.x/img/")
expectEqual(PathTools.publicURL(profile: ftpImg, remoteFilePath: PathTools.relativePath("/public_html/img/2026/a.jpg", base: ftpImg.remotePath)),
            "https://cdn.x/img/2026/a.jpg", "ftp linki")

// MARK: Profil deposu
let base = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-\(UUID().uuidString)")
let store = ProfileStore(baseDirectory: base)
try store.save([server])
expectEqual((try store.load()).count, 1, "kaydet/yükle")
expectEqual(try store.find("s").host, "h", "isimle bulma")
do {
    _ = try store.find("yok-boyle")
    expect(false, "olmayan sunucu hata vermeli")
} catch {
    expect(true, "")
}
try? FileManager.default.removeItem(at: base)

// MARK: Parola
let hash = PasswordHasher.hash("gizli-parola", iterations: 2_000)
expect(PasswordHasher.verify("gizli-parola", encoded: hash, iterations: 2_000), "parola doğrulama")
expect(!PasswordHasher.verify("yanlis", encoded: hash, iterations: 2_000), "yanlış parola reddi")
expect(hash != PasswordHasher.hash("gizli-parola", iterations: 2_000), "hash'ler tuzlu (farklı)")

let secBase = FileManager.default.temporaryDirectory.appendingPathComponent("mcb-sec-\(UUID().uuidString)")
let secStore = SecurityStore(baseDirectory: secBase)
try secStore.setPassword("123456", policy: .everyUpload)
expect(secStore.load().hasPassword, "parola kaydedildi")
expect(secStore.load().policy == .everyUpload, "politika kaydedildi")
expect(secStore.verify("123456"), "depodan doğrulama")
expect(!secStore.verify("654321"), "depodan yanlış parola")
try secStore.removePassword()
expect(!secStore.load().hasPassword, "parola kaldırıldı")
try? FileManager.default.removeItem(at: secBase)

// MARK: Keychain
let credStore = CredentialStore(service: "com.mcb.upload.selftest")
let credAccount = UUID().uuidString
expect(credStore.setPassword("gizli-parola", for: credAccount), "keychain yazma")
expectEqual(credStore.password(for: credAccount) ?? "", "gizli-parola", "keychain okuma")
credStore.setPassword("yeni-parola", for: credAccount)
expectEqual(credStore.password(for: credAccount) ?? "", "yeni-parola", "keychain güncelleme")
credStore.deletePassword(for: credAccount)
expect(credStore.password(for: credAccount) == nil, "keychain silme")

// Profil deposu parolayı JSON'a yazmamalı
let secBase2 = FileManager.default.temporaryDirectory.appendingPathComponent("rightload-kc-\(UUID().uuidString)")
let kcStore = ProfileStore(baseDirectory: secBase2, credentials: credStore)
var kcServer = ServerProfile(name: "KC", proto: .ftp, host: "h", username: "u", password: "sifre123")
try kcStore.save([kcServer])
let rawJSON = try String(contentsOf: secBase2.appendingPathComponent("servers.json"), encoding: .utf8)
expect(!rawJSON.contains("sifre123"), "parola JSON'da düz metin değil")
expectEqual((try kcStore.load()).first?.password ?? "", "sifre123", "parola Keychain'den çözüldü")
kcServer.password = ""
try kcStore.save([kcServer])
expect(credStore.password(for: kcServer.id.uuidString) == nil, "boş parola keychain'den silindi")
try? FileManager.default.removeItem(at: secBase2)

// MARK: Alt klasör açma ve çakışma isimlendirme
let treeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("mcb-tree-\(UUID().uuidString)")
let nestedDir = treeRoot.appendingPathComponent("kampanya/2026/nisan", isDirectory: true)
try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
let topFile = treeRoot.appendingPathComponent("kampanya/kapak.jpg")
let nestedFile = nestedDir.appendingPathComponent("banner.jpg")
try Data("1".utf8).write(to: topFile)
try Data("2".utf8).write(to: nestedFile)

let expanded = UploadEngine.expandFiles([treeRoot.appendingPathComponent("kampanya")])
expectEqual(expanded.count, 2, "alt klasörlerdeki tüm dosyalar bulundu")
expect(expanded.contains(where: { $0.relativeSubfolder == "kampanya" && $0.url.lastPathComponent == "kapak.jpg" }), "üst klasör göreli yolu")
expect(expanded.contains(where: { $0.relativeSubfolder == "kampanya/2026/nisan" && $0.url.lastPathComponent == "banner.jpg" }), "iç içe alt klasör göreli yolu")
try? FileManager.default.removeItem(at: treeRoot)

expectEqual(UploadEngine.suggestUniqueName(for: "foto.jpg", existing: ["foto.jpg", "foto-1.jpg"]), "foto-2.jpg", "çakışmada sıradaki boş isim")
expectEqual(CurlTransport.parsePercent("### 12.0%\r##### 48,5%\r###"), 0.485, "çok satırlı ve virgüllü yüzde okuma")

// MARK: Yerelleştirme
Localization.preferred = .english
expectEqual(Localization.text("Yükle"), "Upload", "İngilizce çeviri")
expectEqual(Localization.text("Klasör"), "Folder", "İngilizce çeviri 2")
Localization.preferred = .turkish
expectEqual(Localization.text("Yükle"), "Yükle", "Türkçe metin aynen döner")
expectEqual(Localization.text("Bilinmeyen anahtar"), "Bilinmeyen anahtar", "eksik çeviride Türkçe")
Localization.preferred = .system

// MARK: FileZilla içe aktarma
let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<FileZilla3><Servers><Server>
<Host>ftp.ornek.com</Host><Port>2121</Port><Protocol>0</Protocol>
<User>kullanici</User><Pass encoding="base64">\(Data("gizli".utf8).base64EncodedString())</Pass>
<RemoteDir>0 0 4 5 /public_html/img</RemoteDir><Name>Ornek</Name>
</Server></Servers></FileZilla3>
"""
let xmlURL = FileManager.default.temporaryDirectory.appendingPathComponent("fz-\(UUID().uuidString).xml")
try xml.data(using: .utf8)!.write(to: xmlURL)
let imported = try FileZillaImporter.importServers(from: xmlURL)
expectEqual(imported.count, 1, "filezilla kayıt sayısı")
if let first = imported.first {
    expectEqual(first.port, 2121, "filezilla port")
    expectEqual(first.password, "gizli", "filezilla base64 şifre")
    expectEqual(first.remotePath, "/public_html/img", "filezilla uzak klasör")
}
try? FileManager.default.removeItem(at: xmlURL)

// MARK: Görsel işleme
let processor = ImageProcessor()
if let source = ImageProcessorTests.makeSample(width: 1600, height: 1000) {
    expect(processor.isImage(source), "isImage")
    let size = processor.imageSize(source)
    expectEqual(size?.width, 1600, "kaynak genişlik")
    if let resized = try processor.resized(source, maxWidth: 800, maxHeight: 800, quality: 0.9) {
        let resizedSize = processor.imageSize(resized)
        expect(resizedSize?.width == 800, "resize genişlik 800 (gelen: \(resizedSize?.width ?? -1))")
        try? FileManager.default.removeItem(at: resized)
    } else {
        expect(false, "resize dosyası üretilemedi")
    }
    if let thumb = try processor.thumbnail(source, maxWidth: 400, maxHeight: 400, quality: 0.8) {
        let thumbSize = processor.imageSize(thumb)
        expect((thumbSize?.width ?? 9999) <= 400 && (thumbSize?.height ?? 9999) <= 400,
               "thumbnail sınırları (gelen: \(String(describing: thumbSize)))")
        try? FileManager.default.removeItem(at: thumb)
    } else {
        expect(false, "thumbnail üretilemedi")
    }
    try? FileManager.default.removeItem(at: source)
}
TempFiles.cleanup()

print(failures == 0 ? "✓ \(checks) kontrol geçti" : "✗ \(failures)/\(checks) kontrol başarısız")
exit(failures == 0 ? 0 : 1)

// MARK: - Test görseli üretici

enum ImageProcessorTests {
    static func makeSample(width: Int, height: Int) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).png")
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = {
                  context.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
                  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                  return context.makeImage()
              }(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
}
