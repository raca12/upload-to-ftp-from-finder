import Foundation

// MARK: - Aktarım katmanı
//
// MVP'de /usr/bin/curl alt süreç olarak kullanılır: FTP, FTPS, HTTP(S) hazır gelir,
// şifre `--config -` ile stdin'den verilir (ps çıktısında görünmez).
// Faz 2'de libcurl/POSIX istemcisiyle değiştirilebilir; tek bağımlılık bu protokol.

public struct TransportResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol Transport {
    func run(arguments: [String],
             secretConfig: String,
             onProgress: ((Double) -> Void)?) throws -> TransportResult
}

public struct CurlTransport: Transport {
    public let curlPath: String

    public init(curlPath: String = "/usr/bin/curl") {
        self.curlPath = curlPath
    }

    /// curl --config dosyası için güvenli tırnaklama: user = "..."
    public static func configLine(key: String, value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\(key) = \"\(escaped)\"\n"
    }

    public func run(arguments: [String],
                    secretConfig: String,
                    onProgress: ((Double) -> Void)?) throws -> TransportResult {
        // Kapalı boruya yazma uygulamayı düşürmesin
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: curlPath)
        var finalArguments = arguments
        if !secretConfig.isEmpty && !finalArguments.contains("--config") && !finalArguments.contains("-K") {
            finalArguments.insert(contentsOf: ["--config", "-"], at: 0)
        }
        process.arguments = finalArguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let lock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()
        var lastProgress: Double = 0
        var emitted: Double = -1

        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = outPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.lock(); stdoutData.append(chunk); lock.unlock()
            }
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = errPipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.lock(); stderrData.append(chunk); lock.unlock()
                if let onProgress,
                   let text = String(data: chunk, encoding: .utf8),
                   let pct = CurlTransport.parsePercent(text),
                   abs(pct - emitted) >= 0.005 || pct >= 0.999 {
                    emitted = pct
                    lastProgress = pct
                    onProgress(pct)
                }
            }
            group.leave()
        }

        try process.run()

        let stdinHandle = inPipe.fileHandleForWriting
        if !secretConfig.isEmpty, let data = secretConfig.data(using: .utf8) {
            try? stdinHandle.write(contentsOf: data)
        }
        try? stdinHandle.close()

        process.waitUntilExit()
        group.wait()

        _ = lastProgress
        let out = String(data: stdoutData, encoding: .utf8) ?? ""
        let err = String(data: stderrData, encoding: .utf8) ?? ""
        return TransportResult(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }

    public static func parsePercent(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3}(?:[.,][0-9]+)?)\s*%"#) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard let last = matches.last,
              last.numberOfRanges > 1,
              let range = Range(last.range(at: 1), in: text) else {
            return nil
        }
        let raw = String(text[range]).replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(raw) else { return nil }
        return min(1, max(0, value / 100))
    }
}
