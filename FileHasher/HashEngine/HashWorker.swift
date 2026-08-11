import Foundation

/// Messages emitted by the background workers while a run is in progress.
/// Consumed in order on the main actor via an AsyncThrowingStream, so UI
/// updates can never race the run's completion.
enum WorkerMessage: Sendable {
    case warning(String)
    case hashed(HashResult)
    case verified(VerifyResult)
    case progress(Int)
}

/// Enumerates and hashes files according to `HashOptions`. Pure synchronous
/// logic — the caller runs it on a background task and receives results
/// through the `emit` callback. Direct port of the Windows HashWorker.
struct HashWorker: Sendable {
    let options: HashOptions
    let cancel: CancelFlag

    /// Extensions hashed when "Scan all file types" is off — matches the
    /// Windows app (and the original PowerShell script's) installer focus.
    static let defaultExtensions: Set<String> = ["exe", "msi"]

    // ── Phase 1: enumeration (returns before any hashing begins) ─────────────

    /// Recursively collects target files. Unreadable directories produce a
    /// warning instead of aborting the run.
    func enumerateFiles() throws -> (files: [String], warnings: [String]) {
        if options.isFile {
            return ([options.targetPath], [])
        }

        let restrictExtensions = !options.allFileTypes
        // When writing sidecars, never treat sidecar files themselves as targets —
        // that would create .sha256.sha256 chains on repeated runs.
        let sidecarExt = options.writeSidecarHashes
            ? options.sidecarExtension.lowercased()
            : nil

        let fm = FileManager.default
        var results:  [String] = []
        var warnings: [String] = []
        var stack = [options.targetPath]

        while let dir = stack.popLast() {
            try cancel.check()

            let entries: [String]
            do {
                entries = try fm.contentsOfDirectory(atPath: dir)
            } catch {
                warnings.append("Cannot list contents of: \(dir)  (\(error.localizedDescription))")
                continue
            }

            for name in entries {
                let full = (dir as NSString).appendingPathComponent(name)

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    stack.append(full)
                    continue
                }

                if let sidecarExt, full.lowercased().hasSuffix(sidecarExt) {
                    continue
                }

                if restrictExtensions {
                    let ext = (full as NSString).pathExtension.lowercased()
                    guard Self.defaultExtensions.contains(ext) else { continue }
                }

                results.append(full)
            }
        }

        return (results, warnings)
    }

    // ── Phase 2: hashing ─────────────────────────────────────────────────────

    func hashAll(files: [String], logger: Logger,
                 emit: @Sendable (WorkerMessage) -> Void) throws {
        var done = 0
        for path in files {
            try cancel.check()
            let result = try hashFile(atPath: path, emit: emit)
            logger.logResult(result, algorithm: options.algorithm.rawValue)
            emit(.hashed(result))
            done += 1
            emit(.progress(done))
        }
    }

    // ── Single-file hashing ──────────────────────────────────────────────────

    private func hashFile(atPath path: String,
                          emit: @Sendable (WorkerMessage) -> Void) throws -> HashResult {
        do {
            let hash = try HashAlgorithmKind.hashFile(
                atPath: path, using: options.algorithm, cancel: cancel)

            let attrs        = try? FileManager.default.attributesOfItem(atPath: path)
            let length       = (attrs?[.size] as? NSNumber)?.int64Value
            let lastWriteUtc = attrs?[.modificationDate] as? Date

            if options.writeSidecarHashes {
                writeSidecar(forPath: path, hash: hash, emit: emit)
            }

            return HashResult(
                filePath:     path,
                hash:         hash,
                length:       options.includeMetadata ? length       : nil,
                lastWriteUtc: options.includeMetadata ? lastWriteUtc : nil,
                success:      true,
                errorMessage: nil)
        } catch is CancellationError {
            // A mid-file Stop must end the run, not produce an error row.
            throw CancellationError()
        } catch {
            return HashResult(filePath: path, hash: "", length: nil, lastWriteUtc: nil,
                              success: false, errorMessage: error.localizedDescription)
        }
    }

    // ── Sidecar writing ──────────────────────────────────────────────────────

    static func sidecarContent(format: SidecarFormat, hash: String,
                               fileName: String, modified: Date?, size: Int64?) -> String {
        switch format {
        case .hashOnly:
            return hash
        case .extended:
            let dateStr = modified.map { HashTimestamp.iso.string(from: $0) } ?? ""
            let sizeStr = size.map(String.init) ?? ""
            return "\(hash) *\(fileName) *\(dateStr) *\(sizeStr)"
        case .algoSum:
            return "\(hash) *\(fileName)"
        }
    }

    private func writeSidecar(forPath path: String, hash: String,
                              emit: @Sendable (WorkerMessage) -> Void) {
        // Guard: never write a sidecar for a file that is itself a sidecar.
        if path.lowercased().hasSuffix(options.sidecarExtension.lowercased()) {
            return
        }

        let sidecarPath = path + options.sidecarExtension
        let attrs   = try? FileManager.default.attributesOfItem(atPath: path)
        let content = Self.sidecarContent(
            format:   options.sidecarFormat,
            hash:     hash,
            fileName: (path as NSString).lastPathComponent,
            modified: attrs?[.modificationDate] as? Date,
            size:     (attrs?[.size] as? NSNumber)?.int64Value)

        do {
            try (content + "\n").write(toFile: sidecarPath, atomically: true, encoding: .utf8)
        } catch {
            emit(.warning("Sidecar write failed for: \(path)  (\(error.localizedDescription))"))
        }
    }
}

enum SidecarConflictAction {
    case overwrite
    case overwriteAll
    case skip
    case skipAll
}
