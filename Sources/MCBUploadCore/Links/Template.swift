import Foundation

// MARK: - Basit şablon motoru
//
// MCB Upload'un "URLMask" ve "custom URL tags" özelliklerinin karşılığı.
// Yer tutucular: {url} {thumb} {thumbOrUrl} {filename} {stem} {ext} {size}
//                {server} {folder} {yyyy} {MM} {dd} {uuid}

public enum Template {

    public static let tokens: Set<String> = [
        "url", "thumb", "thumbOrUrl", "filename", "stem", "ext", "size",
        "server", "folder", "yyyy", "MM", "dd", "uuid"
    ]

    public static func render(_ template: String, values: [String: String]) -> String {
        var out = template
        // thumbOrUrl önce çözülür: thumb yoksa url'ye düşer
        let thumb = values["thumb"] ?? ""
        let url = values["url"] ?? ""
        out = out.replacingOccurrences(of: "{thumbOrUrl}", with: thumb.isEmpty ? url : thumb)
        for (key, value) in values where key != "thumbOrUrl" {
            out = out.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return out
    }

    /// Bugünkü tarihe göre otomatik klasör yolu üretir (Auto-Sort).
    public static func autoSortPath(template: String, serverName: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy"
        let yyyy = f.string(from: date)
        f.dateFormat = "MM"
        let mm = f.string(from: date)
        f.dateFormat = "dd"
        let dd = f.string(from: date)
        return render(template, values: ["yyyy": yyyy, "MM": mm, "dd": dd, "server": serverName])
    }

    public static func values(for file: UploadedFile, server: ServerProfile) -> [String: String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy"
        let yyyy = f.string(from: Date())
        f.dateFormat = "MM"
        let mm = f.string(from: Date())
        f.dateFormat = "dd"
        let dd = f.string(from: Date())
        return [
            "url": file.remoteURL,
            "thumb": file.thumbURL ?? "",
            "filename": file.filename,
            "stem": file.stem,
            "ext": file.ext,
            "size": file.displaySize,
            "server": server.name,
            "folder": server.remotePath,
            "yyyy": yyyy, "MM": mm, "dd": dd,
            "uuid": UUID().uuidString
        ]
    }
}

// MARK: - Hazır link şablonları

public enum LinkTemplate {
    public static let defaults: [String: String] = [
        "url": "{url}",
        "bbcode": "[url={url}]{filename}[/url]",
        "bbcode-image": "[url={url}][img]{thumbOrUrl}[/img][/url]",
        "html": "<a href=\"{url}\">{filename}</a>",
        "html-image": "<a href=\"{url}\"><img src=\"{thumbOrUrl}\" alt=\"{filename}\"></a>",
        "markdown": "[{filename}]({url})",
        "markdown-image": "[![{filename}]({thumbOrUrl})]({url})",
    ]

    /// Sunucu profilinde tanımlı şablonu, yoksa yerleşik olanı döndürür.
    public static func template(named name: String, in server: ServerProfile) -> String? {
        if let custom = server.templates[name] { return custom }
        return defaults[name]
    }

    public static func format(_ file: UploadedFile, templateName: String, server: ServerProfile) -> String? {
        guard let raw = template(named: templateName, in: server) else { return nil }
        return Template.render(raw, values: Template.values(for: file, server: server))
    }
}
