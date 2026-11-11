import XCTest
@testable import MCBUploadCore

final class TemplateTests: XCTestCase {

    func testRenderBasicTokens() {
        let values = ["url": "https://x/y.png", "filename": "y.png", "thumb": ""]
        XCTAssertEqual(Template.render("[img]{url}[/img]", values: values), "[img]https://x/y.png[/img]")
        XCTAssertEqual(Template.render("{filename} -> {url}", values: values), "y.png -> https://x/y.png")
    }

    func testThumbOrUrlFallsBackToURL() {
        let file = UploadedFile(localPath: "/tmp/a.jpg", remoteURL: "https://x/a.jpg", thumbURL: nil, bytes: 10)
        let server = ServerProfile(name: "s", proto: .ftp, host: "h")
        let rendered = LinkTemplate.format(file, templateName: "bbcode-image", server: server)
        XCTAssertEqual(rendered, "[url=https://x/a.jpg][img]https://x/a.jpg[/img][/url]")
    }

    func testThumbOrUrlPrefersThumb() {
        let file = UploadedFile(localPath: "/tmp/a.jpg", remoteURL: "https://x/a.jpg", thumbURL: "https://x/a_th.jpg", bytes: 10)
        let server = ServerProfile(name: "s", proto: .ftp, host: "h")
        XCTAssertEqual(LinkTemplate.format(file, templateName: "bbcode-image", server: server),
                       "[url=https://x/a.jpg][img]https://x/a_th.jpg[/img][/url]")
    }

    func testCustomTemplateOverridesDefault() {
        var server = ServerProfile(name: "s", proto: .ftp, host: "h")
        server.templates["bbcode"] = "<{url}|{filename}>"
        let file = UploadedFile(localPath: "/tmp/a b.jpg", remoteURL: "https://x/a%20b.jpg", thumbURL: nil, bytes: 1)
        XCTAssertEqual(LinkTemplate.format(file, templateName: "bbcode", server: server),
                       "<https://x/a%20b.jpg|a b.jpg>")
    }

    func testUnknownTemplateIsNil() {
        let server = ServerProfile(name: "s", proto: .ftp, host: "h")
        XCTAssertNil(LinkTemplate.template(named: "yok-boyle-bir-sey", in: server))
    }

    func testAutoSortPath() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 11
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: components)!
        let path = Template.autoSortPath(template: "resimler/{yyyy}/{MM}", serverName: "S", date: date)
        XCTAssertEqual(path, "resimler/2026/11")
    }
}

final class PathToolsTests: XCTestCase {

    func testJoin() {
        XCTAssertEqual(PathTools.join("/public_html/img", "2026/11", "a.jpg"), "/public_html/img/2026/11/a.jpg")
        XCTAssertEqual(PathTools.join("/", nil, nil, "a.jpg"), "/a.jpg")
        XCTAssertEqual(PathTools.join("", "x/", "/y.jpg"), "/x/y.jpg")
    }

    func testEncodeSpacesAndTurkish() {
        XCTAssertEqual(PathTools.encodeRemotePath("/resim/çiçek ler.jpg"), "/resim/%C3%A7i%C3%A7ek%20ler.jpg")
    }

    func testPublicURL() {
        let server = ServerProfile(name: "s", proto: .ftp, host: "h", remotePath: "/a", publicBaseURL: "https://cdn.example.com/img/")
        XCTAssertEqual(PathTools.publicURL(profile: server, remoteFilePath: "/a/b.jpg"),
                       "https://cdn.example.com/img/a/b.jpg")
    }

    func testTransferURLUsesPortOnlyWhenNonStandard() {
        let ftp = ServerProfile(name: "s", proto: .ftp, host: "h", port: 21)
        XCTAssertEqual(PathTools.transferURL(profile: ftp, remoteFilePath: "/a/b.jpg"), "ftp://h/a/b.jpg")
        let custom = ServerProfile(name: "s", proto: .ftp, host: "h", port: 2121)
        XCTAssertEqual(PathTools.transferURL(profile: custom, remoteFilePath: "/a/b.jpg"), "ftp://h:2121/a/b.jpg")
        let implicit = ServerProfile(name: "s", proto: .ftpsi, host: "h")
        XCTAssertEqual(PathTools.transferURL(profile: implicit, remoteFilePath: "/b.jpg"), "ftps://h/b.jpg")
    }
}

final class UploadEngineHelpersTests: XCTestCase {

    func testExtractURLWithRegex() {
        let body = #"{"ok":true,"url":"https://cdn.x/a.jpg","delete":"https://cdn.x/del/1"}"#
        XCTAssertEqual(UploadEngine.extractURL(from: body, regex: #""url"\s*:\s*"([^"]+)""#, group: 1),
                       "https://cdn.x/a.jpg")
    }

    func testExtractURLFromPlainURLResponse() {
        XCTAssertEqual(UploadEngine.extractURL(from: "  https://cdn.x/a.jpg \n", regex: nil, group: 1),
                       "https://cdn.x/a.jpg")
    }

    func testExtractURLReturnsNilWhenNotFound() {
        XCTAssertNil(UploadEngine.extractURL(from: "<html>hata</html>", regex: nil, group: 1))
    }

    func testFormFileValueQuoting() {
        XCTAssertEqual(UploadEngine.formFileValue(field: "file", path: "/tmp/a.jpg"), "file=@/tmp/a.jpg")
        XCTAssertEqual(UploadEngine.formFileValue(field: "file", path: "/tmp/a;b.jpg"), "file=@\"/tmp/a;b.jpg\"")
    }

    func testRemoteAndThumbNames() {
        let original = URL(fileURLWithPath: "/tmp/Tatlı Çiçek.JPG")
        let working = URL(fileURLWithPath: "/tmp/uuid.jpg")
        XCTAssertEqual(UploadEngine.remoteName(original: original, working: working), "Tatlı Çiçek.jpg")
        XCTAssertEqual(UploadEngine.thumbName(original: original, working: working, config: ThumbnailConfig()),
                       "Tatlı Çiçek_th.jpg")
    }

    func testProgressPercentParsing() {
        XCTAssertEqual(CurlTransport.parsePercent("# # 62.5%"), 0.625)
        XCTAssertEqual(CurlTransport.parsePercent("abc\r###  100.0%"), 1.0)
        XCTAssertNil(CurlTransport.parsePercent("no percent here"))
    }

    func testCurlConfigEscaping() {
        XCTAssertEqual(CurlTransport.configLine(key: "user", value: #"a"b\c"#),
                       "user = \"a\\\"b\\\\c\"\n")
    }
}

final class ProfileStoreTests: XCTestCase {

    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("mcb-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTrip() throws {
        let store = ProfileStore(baseDirectory: directory)
        var server = ServerProfile(name: "Test", proto: .ftps, host: "ftp.x", username: "u", password: "p", remotePath: "/img")
        server.thumbnails.maxWidth = 320
        try store.save([server])

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "Test")
        XCTAssertEqual(loaded[0].proto, .ftps)
        XCTAssertEqual(loaded[0].thumbnails.maxWidth, 320)
        XCTAssertEqual(try store.find("test").host, "ftp.x")
    }

    func testMissingJSONDefaultsAreApplied() throws {
        let json = #"{"version":1,"servers":[{"name":"Minimal","proto":"ftp","host":"h"}]}"#
        try json.data(using: .utf8)!.write(to: directory.appendingPathComponent("servers.json"))
        let store = ProfileStore(baseDirectory: directory)
        let server = try store.find("Minimal")
        XCTAssertEqual(server.port, 21)
        XCTAssertEqual(server.thumbnails.enabled, true)
        XCTAssertEqual(server.resize.enabled, false)
        XCTAssertFalse(server.templates.isEmpty)
    }

    func testFindThrowsForUnknown() throws {
        let store = ProfileStore(baseDirectory: directory)
        XCTAssertThrowsError(try store.find("yok"))
    }
}

final class FileZillaImporterTests: XCTestCase {

    func testImportSitemanager() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FileZilla3>
          <Servers>
            <Server>
              <Host>ftp.ornek.com</Host>
              <Port>2121</Port>
              <Protocol>0</Protocol>
              <Type>0</Type>
              <User>kullanici</User>
              <Pass encoding="base64">\(Data("gizli".utf8).base64EncodedString())</Pass>
              <RemoteDir>0 0 4 5 /public_html/img</RemoteDir>
              <Name>Ornek Site</Name>
            </Server>
            <Server>
              <Host>sftp.ornek.com</Host>
              <Port>22</Port>
              <Protocol>1</Protocol>
              <User>root</User>
              <Name>Root SFTP</Name>
            </Server>
          </Servers>
        </FileZilla3>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sitemanager-\(UUID().uuidString).xml")
        try xml.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let servers = try FileZillaImporter.importServers(from: url)
        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers[0].name, "Ornek Site")
        XCTAssertEqual(servers[0].host, "ftp.ornek.com")
        XCTAssertEqual(servers[0].port, 2121)
        XCTAssertEqual(servers[0].username, "kullanici")
        XCTAssertEqual(servers[0].password, "gizli")
        XCTAssertEqual(servers[0].remotePath, "/public_html/img")
        XCTAssertEqual(servers[1].proto, .sftp)
        XCTAssertEqual(servers[1].port, 22)
    }
}
