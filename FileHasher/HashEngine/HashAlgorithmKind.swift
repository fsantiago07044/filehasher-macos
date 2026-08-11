import CryptoKit
import Foundation

/// The four hash algorithms FileHasher supports, mirroring the Windows app.
enum HashAlgorithmKind: String, CaseIterable, Identifiable, Sendable {
    case md5    = "MD5"
    case sha1   = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var id: String { rawValue }

    /// Length of the hex digest, used to auto-detect the algorithm when verifying sidecars.
    var hexLength: Int {
        switch self {
        case .md5:    return 32
        case .sha1:   return 40
        case .sha256: return 64
        case .sha512: return 128
        }
    }

    /// The standard sidecar extension suggested for this algorithm (".md5", ".sha256", …).
    var standardExtension: String { "." + rawValue.lowercased() }

    static let standardSidecarExtensions =
        HashAlgorithmKind.allCases.map(\.standardExtension)

    static func from(hexLength: Int) -> HashAlgorithmKind? {
        allCases.first { $0.hexLength == hexLength }
    }

    // ── Streaming file hashing ───────────────────────────────────────────────

    /// Hashes the file in 64 KiB chunks, honoring `cancel` between chunks so even
    /// a multi-gigabyte file stops promptly. Returns the uppercase hex digest.
    static func hashFile(atPath path: String, using kind: HashAlgorithmKind,
                         cancel: CancelFlag) throws -> String {
        switch kind {
        case .md5:    return try streamHash(Insecure.MD5.self,  path: path, cancel: cancel)
        case .sha1:   return try streamHash(Insecure.SHA1.self, path: path, cancel: cancel)
        case .sha256: return try streamHash(SHA256.self,        path: path, cancel: cancel)
        case .sha512: return try streamHash(SHA512.self,        path: path, cancel: cancel)
        }
    }

    private static func streamHash<H: HashFunction>(
        _: H.Type, path: String, cancel: CancelFlag) throws -> String
    {
        var hasher = H()
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }

        while true {
            try cancel.check()
            let chunk = try autoreleasepool {
                try handle.read(upToCount: 1 << 16)
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02X", $0) }.joined()
    }
}

/// Cooperative cancellation shared between the UI and the background workers.
/// Deliberately independent of Swift task cancellation so the same flag reaches
/// the innermost chunk loop of an in-flight hash.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}
