import Foundation

/// Outcome category for one sidecar-verification row.
enum VerifyStatus: Sendable {
    case ok            // hash matches the sidecar
    case mismatch      // hash differs from the sidecar
    case missingFile   // sidecar exists but the file it attests to is gone
    case noSidecar     // file matches the scan filter but has no sidecar (audit row)
    case parseError    // sidecar content not recognized as any supported format
    case readError     // the file or its sidecar could not be read
}

/// Outcome of verifying a single sidecar (or a file lacking one).
struct VerifyResult: Sendable {
    let filePath: String            // the file the sidecar attests to
    let sidecarPath: String         // the sidecar itself; "" for noSidecar rows
    let status: VerifyStatus
    let algorithm: HashAlgorithmKind?  // auto-detected from the sidecar's hash length
    let computedHash: String?       // actual hash of the file, when one was computed
    let detail: String?             // mismatch expected/computed, metadata notes, errors
}

/// Per-status counts for a completed verification run.
struct VerifySummary: Sendable {
    var ok = 0, mismatch = 0, missingFile = 0, noSidecar = 0, parseError = 0, readError = 0

    var failed: Int { mismatch + missingFile + parseError + readError }

    mutating func count(_ status: VerifyStatus) {
        switch status {
        case .ok:          ok += 1
        case .mismatch:    mismatch += 1
        case .missingFile: missingFile += 1
        case .noSidecar:   noSidecar += 1
        case .parseError:  parseError += 1
        case .readError:   readError += 1
        }
    }
}

/// Verifies previously written sidecar hash files. Mirrors HashWorker's
/// two-phase shape: `enumerateWork` collects the work list, `verifyAll`
/// processes it. The hash algorithm is auto-detected per sidecar from its
/// hash length (32 hex chars = MD5, 40 = SHA1, 64 = SHA256, 128 = SHA512),
/// so verification is independent of the algorithm selected in the UI. All
/// three sidecar formats parse: bare hash, "HASH *filename", and the extended
/// "HASH *filename *lastModifiedIso8601Utc *sizeBytes". The hash alone decides
/// pass/fail; a differing embedded filename, date, or size on an otherwise-OK
/// row is surfaced as an informational note. Direct port of the Windows app.
struct SidecarVerifier: Sendable {
    /// One unit of verification work. Nil sidecarPath = audit row for a file lacking a sidecar.
    struct WorkItem: Sendable {
        let baseFile: String
        let sidecarPath: String?
    }

    let targetPath: String
    let isFile: Bool
    let sidecarExtension: String
    let allFileTypes: Bool
    let cancel: CancelFlag

    // ── Phase 1: enumeration ─────────────────────────────────────────────────

    func enumerateWork() throws -> (items: [WorkItem], warnings: [String]) {
        let ext   = sidecarExtension
        let extLC = ext.lowercased()
        let fm    = FileManager.default

        if isFile {
            // A sidecar was targeted directly → verify it against its base file.
            if targetPath.lowercased().hasSuffix(extLC) {
                let base = String(targetPath.dropLast(ext.count))
                return ([WorkItem(baseFile: base, sidecarPath: targetPath)], [])
            }

            // A regular file was targeted → verify its sidecar, or report the gap.
            let sidecar = targetPath + ext
            let item = WorkItem(baseFile: targetPath,
                                sidecarPath: fm.fileExists(atPath: sidecar) ? sidecar : nil)
            return ([item], [])
        }

        // Folder: one recursive walk (same warning behavior as HashWorker),
        // then partition into sidecars and filter-matching files lacking one.
        var all:      [String] = []
        var warnings: [String] = []
        var stack = [targetPath]

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
                } else {
                    all.append(full)
                }
            }
        }

        var items: [WorkItem] = []
        var bases = Set<String>()

        for f in all where f.lowercased().hasSuffix(extLC) {
            let base = String(f.dropLast(ext.count))
            bases.insert(base.lowercased())
            items.append(WorkItem(baseFile: base, sidecarPath: f))
        }

        // Completeness audit: files the hashing scan filter would pick up
        // (same rule as HashWorker.enumerateFiles) that have no sidecar.
        for f in all {
            if f.lowercased().hasSuffix(extLC) { continue }
            if !allFileTypes {
                let fileExt = (f as NSString).pathExtension.lowercased()
                guard HashWorker.defaultExtensions.contains(fileExt) else { continue }
            }
            if !bases.contains(f.lowercased()) {
                items.append(WorkItem(baseFile: f, sidecarPath: nil))
            }
        }

        items.sort {
            $0.baseFile.compare($1.baseFile, options: .caseInsensitive) == .orderedAscending
        }
        return (items, warnings)
    }

    // ── Phase 2: verification ────────────────────────────────────────────────

    func verifyAll(items: [WorkItem], logger: Logger,
                   emit: @Sendable (WorkerMessage) -> Void) throws -> VerifySummary {
        var summary = VerifySummary()
        var done = 0

        for item in items {
            try cancel.check()
            let r = try verifyOne(item)
            summary.count(r.status)

            logger.logInfo("VERIFY \(Self.statusLabel(r.status)): \(r.filePath)"
                           + (r.detail.map { "  (\($0))" } ?? ""))

            emit(.verified(r))
            done += 1
            emit(.progress(done))
        }

        return summary
    }

    static func statusLabel(_ s: VerifyStatus) -> String {
        switch s {
        case .ok:          return "OK"
        case .mismatch:    return "MISMATCH"
        case .missingFile: return "MISSING FILE"
        case .noSidecar:   return "NO SIDECAR"
        case .parseError:  return "PARSE ERROR"
        case .readError:   return "READ ERROR"
        }
    }

    private func verifyOne(_ item: WorkItem) throws -> VerifyResult {
        guard let sidecarPath = item.sidecarPath else {
            return VerifyResult(filePath: item.baseFile, sidecarPath: "", status: .noSidecar,
                                algorithm: nil, computedHash: nil,
                                detail: "no sidecar found for this file")
        }

        let line: String
        do {
            let content = try String(contentsOfFile: sidecarPath, encoding: .utf8)
            line = content
                .components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
                .trimmingCharacters(in: .whitespaces) ?? ""
        } catch {
            return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                                status: .readError, algorithm: nil, computedHash: nil,
                                detail: "cannot read sidecar: \(error.localizedDescription)")
        }

        // All three formats are "HASH" optionally followed by " *"-prefixed
        // fields (filename, then ISO date and size for extended). A filename
        // containing the literal sequence " *" would split wrong; accepted —
        // it only affects the informational notes, never pass/fail.
        let fields   = line.components(separatedBy: " *")
        let expected = fields[0].trimmingCharacters(in: .whitespaces)

        guard !expected.isEmpty,
              expected.allSatisfy(\.isHexDigit),
              let algorithm = HashAlgorithmKind.from(hexLength: expected.count)
        else {
            return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                                status: .parseError, algorithm: nil, computedHash: nil,
                                detail: "unrecognized sidecar content: \"\(Self.truncate(line, 60))\"")
        }

        guard FileManager.default.fileExists(atPath: item.baseFile) else {
            return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                                status: .missingFile, algorithm: algorithm, computedHash: nil,
                                detail: "sidecar present but the file is missing")
        }

        let actual: String
        do {
            actual = try HashAlgorithmKind.hashFile(atPath: item.baseFile,
                                                    using: algorithm, cancel: cancel)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                                status: .readError, algorithm: algorithm, computedHash: nil,
                                detail: "cannot read file: \(error.localizedDescription)")
        }

        if actual.caseInsensitiveCompare(expected) != .orderedSame {
            return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                                status: .mismatch, algorithm: algorithm, computedHash: actual,
                                detail: "expected \(expected), computed \(actual)")
        }

        // Hash matches — remaining fields are informational only.
        var notes: [String] = []
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: item.baseFile) {
            let realName = (item.baseFile as NSString).lastPathComponent

            if fields.count >= 2, !fields[1].isEmpty,
               fields[1].caseInsensitiveCompare(realName) != .orderedSame {
                notes.append("sidecar filename \"\(fields[1])\" differs from \"\(realName)\"")
            }

            if fields.count >= 4 {
                if let sidecarUtc = HashTimestamp.iso.date(from: fields[2]),
                   let fileDate = attrs[.modificationDate] as? Date {
                    // Compare at whole-second precision — that's all the sidecar stores.
                    let fileUtc = Date(timeIntervalSince1970:
                                        fileDate.timeIntervalSince1970.rounded(.down))
                    if sidecarUtc != fileUtc {
                        notes.append("modified date differs (sidecar \(fields[2]), "
                                     + "file \(HashTimestamp.iso.string(from: fileUtc)))")
                    }
                }

                if let sidecarSize = Int64(fields[3]),
                   let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
                   sidecarSize != fileSize {
                    notes.append("size differs (sidecar \(sidecarSize), file \(fileSize))")
                }
            }
        }
        // A metadata read failure never demotes an OK row — notes are best-effort.

        return VerifyResult(filePath: item.baseFile, sidecarPath: sidecarPath,
                            status: .ok, algorithm: algorithm, computedHash: actual,
                            detail: notes.isEmpty ? nil : notes.joined(separator: "; "))
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "…"
    }
}
