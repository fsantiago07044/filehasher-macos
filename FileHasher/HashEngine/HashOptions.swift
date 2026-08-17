import Foundation

/// Content layout of a sidecar hash file.
enum SidecarFormat: String, CaseIterable, Identifiable, Sendable {
    /// `HASH *filename`: the md5sum/sha1sum/sha256sum/sha512sum tool line format.
    case algoSum  = "algosum"
    /// The raw hash string with no filename.
    case hashOnly = "hashonly"
    /// `HASH *filename *lastModifiedIso8601Utc *sizeBytes`.
    case extended = "extended"

    var id: String { rawValue }
}

/// Immutable snapshot of all user-selected options passed to the worker.
struct HashOptions: Sendable {
    var targetPath: String
    var isFile: Bool
    var algorithm: HashAlgorithmKind
    var includeMetadata: Bool
    var writeSidecarHashes: Bool
    var sidecarExtension: String   // e.g. ".sha256"
    var sidecarFormat: SidecarFormat
    var recursive: Bool            // folder targets: descend into subfolders (off by default)
    var fileTypeFilter: [String]   // lowercased extensions without dots; empty = hash all files

    /// Parses a user-typed, comma-separated list of file types into normalized
    /// extensions: trimmed, leading dots stripped, lowercased, de-duplicated,
    /// original order preserved. "pkg, .DMG, zip,, dmg" -> ["pkg", "dmg", "zip"].
    static func parseFileTypes(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in raw.split(whereSeparator: { $0 == "," || $0 == " " }) {
            var ext = piece.trimmingCharacters(in: .whitespaces).lowercased()
            while ext.hasPrefix(".") { ext.removeFirst() }
            if !ext.isEmpty, seen.insert(ext).inserted {
                result.append(ext)
            }
        }
        return result
    }
}

/// Outcome of hashing a single file.
struct HashResult: Sendable {
    let filePath: String
    let hash: String          // uppercase hex; empty on failure
    let length: Int64?        // nil when includeMetadata is false or on failure
    let lastWriteUtc: Date?   // nil when includeMetadata is false or on failure
    let success: Bool
    let errorMessage: String?
}

/// Shared ISO-8601 (whole-second, UTC) formatting used by sidecars, logs and CSV.
enum HashTimestamp {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone   = TimeZone(identifier: "UTC")
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "yyyy-MM-dd HH:mm:ss" in UTC: the results-table display format.
    static let display: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone   = TimeZone(identifier: "UTC")
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
