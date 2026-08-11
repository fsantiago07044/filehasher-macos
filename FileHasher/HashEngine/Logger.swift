import Foundation

/// Thread-safe, append-only log writer. Log files are stored in the app's
/// Application Support directory (inside the sandbox container) under
/// FileHasher/Logs/ and named by date, matching the Windows app's
/// %APPDATA%\FileHasher\Logs\ convention.
final class Logger: @unchecked Sendable {
    let logPath: String

    private let handle: FileHandle
    private let lock = NSLock()

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let logDir = support.appendingPathComponent("FileHasher/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")

        let url = logDir.appendingPathComponent("FileHasher_\(day.string(from: Date())).log")
        logPath = url.path

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()

        writeRaw("--- Session started \(Self.utcNow()) UTC ---")
    }

    deinit {
        try? handle.close()
    }

    // ── Public API ───────────────────────────────────────────────────────────

    func logResult(_ result: HashResult, algorithm: String) {
        if result.success {
            var line = "\(Self.ts()) | \(algorithm) | OK | \(result.hash) | \(result.filePath)"
            if let length = result.length {
                line += " | \(length) bytes"
            }
            if let modified = result.lastWriteUtc {
                line += " | modified \(HashTimestamp.iso.string(from: modified))"
            }
            writeRaw(line)
        } else {
            writeRaw("\(Self.ts()) | \(algorithm) | ERROR | "
                     + "\(result.errorMessage ?? "unknown error") | \(result.filePath)")
        }
    }

    func logWarning(_ message: String) { writeRaw("\(Self.ts()) | WARN | \(message)") }
    func logInfo(_ message: String)    { writeRaw("\(Self.ts()) | INFO | \(message)") }

    func logSessionEnd(processed: Int, errors: Int) {
        writeRaw("--- Session ended \(Self.utcNow()) UTC | \(processed) hashed, \(errors) error(s) ---")
    }

    // ── Internals ────────────────────────────────────────────────────────────

    private static func ts() -> String { HashTimestamp.iso.string(from: Date()) }

    private static func utcNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone   = TimeZone(identifier: "UTC")
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func writeRaw(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data = (line + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}
