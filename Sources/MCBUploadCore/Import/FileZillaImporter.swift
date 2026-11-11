import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - FileZilla içe aktarma
// MCB Upload 2.0.1'deki "Import servers from FileZilla" özelliğinin karşılığı.

public struct FileZillaImporter {

    public static var defaultPaths: [URL] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            support.appendingPathComponent("FileZilla/sitemanager.xml"),
            support.appendingPathComponent("FileZilla/filezilla.xml"),
            support.appendingPathComponent("FileZilla/recentservers.xml"),
        ]
    }

    public static func importServers(from url: URL) throws -> [ServerProfile] {
        let data = try Data(contentsOf: url)
        let document = try XMLDocument(data: data, options: [.nodePreserveAll])
        let nodes = (try? document.nodes(forXPath: "//Server")) ?? []
        return nodes.compactMap { profile(from: $0) }
    }

    private static func profile(from node: XMLNode) -> ServerProfile? {
        func child(_ name: String) -> String? {
            node.children?
                .first(where: { $0.name == name })?
                .stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let host = child("Host"), !host.isEmpty else { return nil }
        let name = child("Name") ?? host
        let protocolNumber = Int(child("Protocol") ?? "0") ?? 0
        let port = Int(child("Port") ?? "") ?? 0

        let proto: TransferProtocol
        switch protocolNumber {
        case 1: proto = .sftp
        case 2: proto = .ftpsi
        case 3, 4, 6: proto = .ftps
        default: proto = .ftp
        }

        var password = child("Pass") ?? ""
        if let passNode = node.children?.first(where: { $0.name == "Pass" }) as? XMLElement,
           let encoding = passNode.attributes?.first(where: { $0.name == "encoding" })?.stringValue,
           encoding == "base64",
           let decoded = Data(base64Encoded: password),
           let text = String(data: decoded, encoding: .utf8) {
            password = text
        }

        // RemoteDir biçimi: "0 0 4 5 /public_html/img"
        var remotePath = child("RemoteDir") ?? "/"
        if remotePath.range(of: #"^\d+ \d+ \d+ \d+ ?"#, options: .regularExpression) != nil {
            remotePath = remotePath.replacingOccurrences(of: #"^\d+ \d+ \d+ \d+ ?"#,
                                                         with: "",
                                                         options: .regularExpression)
        }
        if remotePath.isEmpty { remotePath = "/" }

        return ServerProfile(
            name: name,
            proto: proto,
            host: host,
            port: port > 0 ? port : nil,
            username: child("User") ?? "",
            password: password,
            remotePath: remotePath,
            publicBaseURL: nil
        )
    }
}
