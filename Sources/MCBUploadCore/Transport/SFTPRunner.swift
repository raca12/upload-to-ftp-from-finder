import Foundation

// MARK: - SFTP
//
// macOS'un sistem curl'ünde SSH yok; bu yüzden Apple'ın gelen OpenSSH `sftp` istemcisini
// batch modunda kullanıyoruz. Parola, askpass betiği + ortam değişkeniyle verilir
// (komut satırında görünmez).

public struct SFTPRunner {

    public init() {}

    public func run(profile: ServerProfile, commands: [String], timeout: TimeInterval = 300) throws -> TransportResult {
        guard !profile.host.isEmpty else {
            throw MCBUploadError.missingCredential("host")
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcb-sftp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        // Parolayı komut satırına koymamak için askpass betiği
        let askpass = workDirectory.appendingPathComponent("askpass.sh")
        try "#!/bin/sh\nprintf '%s\\n' \"$MCB_SFTP_PASSWORD\"\n"
            .write(to: askpass, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)

        // NOT: `-b` (batch dosyası) verilirse ssh parola istemez; bu yüzden komutlar
        // stdin'den besleniyor (askpass'ın çalışması için şart).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [
            "-q",
            "-P", "\(profile.port)",
            "-oBatchMode=\(profile.password.isEmpty ? "yes" : "no")",
            "-oStrictHostKeyChecking=accept-new",
            "-oConnectTimeout=20",
            "\(profile.username.isEmpty ? NSUserName() : profile.username)@\(profile.host)",
        ]

        // Test/CI: kendi known_hosts dosyasını kullan (gerçek kullanımda ~/.ssh/known_hosts)
        if let knownHosts = ProcessInfo.processInfo.environment["MCB_SFTP_KNOWN_HOSTS"], !knownHosts.isEmpty {
            process.arguments = process.arguments.map { $0 } // no-op, aşağıda ekleniyor
            var arguments = process.arguments ?? []
            arguments.insert("-oUserKnownHostsFile=\(knownHosts)", at: 1)
            process.arguments = arguments
        }

        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = askpass.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = ":0"
        if !profile.password.isEmpty {
            environment["MCB_SFTP_PASSWORD"] = profile.password
        }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        try process.run()

        let script = commands.joined(separator: "\n") + "\nbye\n"
        try? inPipe.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try? inPipe.fileHandleForWriting.close()

        // Zaman aşımı
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(100_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(300_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        let rawStdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stdout = rawStdout.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("sftp> ") }
            .joined(separator: "\n")
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if ProcessInfo.processInfo.environment["MCB_SFTP_DEBUG"] != nil {
            let dump = """
            COMMAND: sftp \(process.arguments?.joined(separator: " ") ?? "")
            EXIT: \(process.terminationStatus)
            STDOUT:
            \(stdout)
            STDERR:
            \(stderr)

            """
            if let data = dump.data(using: .utf8) {
                if let handle = FileHandle(forWritingAtPath: "/tmp/mcb-sftp-debug.log") {
                    handle.seekToEndOfFile(); handle.write(data)
                } else {
                    try? data.write(to: URL(fileURLWithPath: "/tmp/mcb-sftp-debug.log"))
                }
            }
        }

        return TransportResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    // MARK: - Yükleme

    public func upload(file: URL, profile: ServerProfile, remotePath: String) throws -> TransportResult {
        let directory = (remotePath as NSString).deletingLastPathComponent
        var commands: [String] = []

        // Uzak klasör zincirini oluştur ("-" öneki: zaten varsa hata verme)
        var current = ""
        for component in directory.split(separator: "/") {
            current += "/" + component
            commands.append("-mkdir \"\(escape(String(current)))\"")
        }

        commands.append("put \"\(escape(file.path))\" \"\(escape(remotePath))\"")
        return try run(profile: profile, commands: commands)
    }

    public func list(profile: ServerProfile, path: String) throws -> [RemoteEntry] {
        let result = try run(profile: profile, commands: ["ls -l \"\(escape(path))\""])
        guard result.exitCode == 0 else {
            throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return FTPListingParser.parse(result.stdout)
    }

    public func check(profile: ServerProfile, path: String) throws -> Int {
        let result = try run(profile: profile, commands: ["ls -1 \"\(escape(path))\""])
        guard result.exitCode == 0 else {
            throw MCBUploadError.transportFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return result.stdout.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
