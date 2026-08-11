import Foundation

/// Writes hashing results to CSV. Matches the Windows app's output:
/// UTF-8 with BOM (opens correctly in Excel without an import wizard),
/// only successful rows, sorted by file path.
enum CsvExporter {
    static func export(results: [HashResult], algorithm: String,
                       includeMetadata: Bool, toPath path: String) throws {
        var out = "Path,\(algorithm)"
        if includeMetadata {
            out += ",LengthBytes,LastWriteUtc"
        }
        out += "\n"

        let rows = results
            .filter(\.success)
            .sorted { $0.filePath.compare($1.filePath) == .orderedAscending }

        for r in rows {
            out += escape(r.filePath) + "," + r.hash
            if includeMetadata {
                out += ","
                out += r.length.map(String.init) ?? ""
                out += ","
                out += r.lastWriteUtc.map { HashTimestamp.iso.string(from: $0) } ?? ""
            }
            out += "\n"
        }

        var data = Data([0xEF, 0xBB, 0xBF])   // UTF-8 BOM
        data.append(out.data(using: .utf8) ?? Data())
        try data.write(to: URL(fileURLWithPath: path))
    }

    static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
