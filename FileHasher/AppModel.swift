import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One row in the results table. Warning rows show "[WARN]" in the path
/// column and carry no payload, mirroring the Windows ListView.
struct ResultRow: Identifiable, Sendable {
    enum Severity: Sendable {
        case normal, success, warning, error
    }

    let id = UUID()
    let pathDisplay: String
    let value: String          // hash, verification verdict, or warning text
    let size: String
    let modified: String
    let severity: Severity
    let realPath: String?      // nil for warning rows
    let hash: String?          // copyable hash, when one was computed

    var color: Color? {
        switch severity {
        case .normal:  return nil
        case .success: return Color(nsColor: .systemGreen)
        case .warning: return Color(nsColor: .systemOrange)
        case .error:   return Color(nsColor: .systemRed)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {

    // ── Target ───────────────────────────────────────────────────────────────
    @Published var targetPath = "" {
        didSet { updateFolderOptionsEnabled() }
    }
    @Published var scanRecursively = false
    @Published var limitFileTypes = false
    @Published var fileTypesText = ""
    @Published private(set) var folderOptionsEnabled = false

    /// macOS-appropriate suggestions for the file-type limit. Suggestions only;
    /// nothing is pre-filled. exe/msi stay available for anyone verifying
    /// Windows installers from a Mac.
    static let fileTypeSuggestions = ["pkg", "dmg", "iso", "zip", "exe", "msi"]

    // ── Algorithm ────────────────────────────────────────────────────────────
    @Published var algorithm: HashAlgorithmKind = .sha256 {
        didSet { algorithmChanged() }
    }

    // ── Options ──────────────────────────────────────────────────────────────
    @Published var includeMetadata = false
    @Published var writeSidecars = false
    @Published var sidecarExtension = ".sha256"
    @Published var sidecarFormat: SidecarFormat = .algoSum
    @Published var exportCsv = false
    @Published var csvPath = ""

    // ── Run state ────────────────────────────────────────────────────────────
    @Published private(set) var isRunning = false
    @Published private(set) var isEnumerating = false
    @Published private(set) var progressDone = 0
    @Published private(set) var progressTotal = 0
    @Published private(set) var runComplete = false   // turns the bar blue, like Windows
    @Published private(set) var statusText = "Ready."
    @Published private(set) var hashColumnTitle = "SHA256"
    @Published private(set) var logPath: String?

    @Published private(set) var rows: [ResultRow] = []

    private var allResults: [HashResult] = []
    private var logger: Logger?
    private var cancelFlag = CancelFlag()
    private var runTask: Task<Void, Never>?

    /// Security-scoped URLs granted by open/save panels or drag-and-drop.
    /// Held for the app's lifetime so sandbox access stays valid mid-run.
    private var accessGrants: [URL] = []

    // ── Target selection ─────────────────────────────────────────────────────

    func browseForFile() {
        let panel = NSOpenPanel()
        panel.title = "Select a file to hash"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setTarget(url)
        }
    }

    func browseForFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select a folder to scan recursively"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setTarget(url)
        }
    }

    func browseForCsv() {
        let panel = NSSavePanel()
        panel.title = "Save results as CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "FileHasher_\(stamp.string(from: Date())).csv"
        if panel.runModal() == .OK, let url = panel.url {
            accessGrants.append(url)
            csvPath = url.path
        }
    }

    /// Called from the browse panels and from drag-and-drop onto the target box.
    func setTarget(_ url: URL) {
        accessGrants.append(url)
        targetPath = url.path
    }

    /// Recursion and the file-type limit only matter when more than one file
    /// could be hashed, i.e. when the target is a folder.
    private func updateFolderOptionsEnabled() {
        let path = targetPath.trimmingCharacters(in: .whitespaces)
        var isDir: ObjCBool = false
        folderOptionsEnabled = !path.isEmpty
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Appends a suggested file type to the limit field, skipping duplicates.
    func appendFileType(_ ext: String) {
        let current = HashOptions.parseFileTypes(fileTypesText)
        guard !current.contains(ext) else { return }
        fileTypesText = current.isEmpty ? ext : fileTypesText
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,")) + ", " + ext
        limitFileTypes = true
    }

    // ── Sidecar UI ↔ algorithm coupling ──────────────────────────────────────

    /// Keeps the suggested sidecar extension in step with the selected hash
    /// algorithm. The extension is only rewritten while it still holds one of
    /// the four standard values; a custom extension the user typed is never
    /// clobbered. (The "{algo}sum format" radio label updates in the view.)
    private func algorithmChanged() {
        let current = sidecarExtension.trimmingCharacters(in: .whitespaces).lowercased()
        if HashAlgorithmKind.standardSidecarExtensions.contains(current) {
            sidecarExtension = algorithm.standardExtension
        }
    }

    var algoSumFormatLabel: String {
        "\(algorithm.rawValue.lowercased())sum format  (HASH *filename)"
    }

    // ── Run ──────────────────────────────────────────────────────────────────

    func run() {
        guard !isRunning else { return }

        let path = targetPath.trimmingCharacters(in: .whitespaces)
        guard let isFile = validateTarget(path) else { return }

        if exportCsv, csvPath.trimmingCharacters(in: .whitespaces).isEmpty {
            showAlert(title: "Missing CSV path",
                      message: "Please specify a CSV output path.", style: .warning)
            return
        }

        let typeFilter = (!isFile && limitFileTypes)
            ? HashOptions.parseFileTypes(fileTypesText)
            : []
        if !isFile, limitFileTypes, typeFilter.isEmpty {
            showAlert(title: "No file types",
                      message: "\"Limit to file types\" is on, but no file types are "
                        + "listed. Add types (for example: pkg, dmg) or turn the "
                        + "limit off to scan every file.",
                      style: .warning)
            return
        }

        // Sandbox: writing a sidecar next to a single selected file needs
        // access to its parent folder, which selecting the file alone does
        // not grant. Ask once, up front.
        if writeSidecars, isFile {
            ensureParentFolderAccess(
                forFileAt: path,
                explanation: "To write the sidecar hash file next to the selected file, "
                    + "FileHasher needs permission for the file's folder.")
        }

        let opts = HashOptions(
            targetPath:         path,
            isFile:             isFile,
            algorithm:          algorithm,
            includeMetadata:    includeMetadata,
            writeSidecarHashes: writeSidecars,
            sidecarExtension:   sidecarExtension.trimmingCharacters(in: .whitespaces),
            sidecarFormat:      sidecarFormat,
            recursive:          !isFile && scanRecursively,
            fileTypeFilter:     typeFilter)

        guard let logger = startRun(columnTitle: opts.algorithm.rawValue) else { return }
        logger.logInfo("Target: \(path)  |  Algorithm: \(opts.algorithm.rawValue)  |  "
            + "Recursive: \(opts.recursive)  |  "
            + "Types: \(opts.fileTypeFilter.isEmpty ? "(all)" : opts.fileTypeFilter.joined(separator: ","))  |  "
            + "Metadata: \(opts.includeMetadata)  |  Sidecar: \(opts.writeSidecarHashes)")

        statusText = "Enumerating files…"
        runTask = Task { await self.performRun(opts, logger: logger) }
    }

    private func performRun(_ opts: HashOptions, logger: Logger) async {
        let cancel = cancelFlag
        let worker = HashWorker(options: opts, cancel: cancel)
        let csvWanted  = exportCsv
        let csvOutPath = csvPath.trimmingCharacters(in: .whitespaces)

        do {
            // Phase 1 – enumerate
            let (allFiles, warnings) = try await Task.detached(priority: .userInitiated) {
                try worker.enumerateFiles()
            }.value
            for w in warnings {
                appendWarning(w)
                logger.logWarning(w)
            }

            var files = allFiles
            if files.isEmpty {
                statusText = "No matching files found."
                finishRun()
                return
            }

            // Phase 1b – per-file sidecar conflict resolution, before any hashing
            var sidecarSkipped = 0, sidecarOverwritten = 0
            if opts.writeSidecarHashes {
                let ext = opts.sidecarExtension
                let conflicting = files.filter {
                    FileManager.default.fileExists(atPath: $0 + ext)
                }

                if !conflicting.isEmpty {
                    var skipAll = false, overwriteAll = false
                    var toSkip = Set<String>()

                    for conflictFile in conflicting {
                        try cancel.check()
                        let decision: SidecarConflictAction
                        if skipAll {
                            decision = .skip
                        } else if overwriteAll {
                            decision = .overwrite
                        } else {
                            decision = showSidecarConflictDialog(
                                filePath: conflictFile, sidecarPath: conflictFile + ext)
                            if decision == .skipAll      { skipAll = true }
                            if decision == .overwriteAll { overwriteAll = true }
                        }

                        if decision == .skip || decision == .skipAll {
                            toSkip.insert(conflictFile)
                            sidecarSkipped += 1
                        } else {
                            sidecarOverwritten += 1
                        }
                    }

                    files.removeAll { toSkip.contains($0) }
                }
            }

            // Phase 2 – hash
            statusText = "Hashing \(files.count.formatted()) file(s)…"
            isEnumerating = false
            progressTotal = files.count
            progressDone = 0

            let toHash = files
            let stream = AsyncThrowingStream<WorkerMessage, Error> { continuation in
                Task.detached(priority: .userInitiated) {
                    do {
                        try worker.hashAll(files: toHash, logger: logger) {
                            continuation.yield($0)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            for try await message in stream {
                switch message {
                case .warning(let w):
                    appendWarning(w)
                    logger.logWarning(w)
                case .hashed(let r):
                    addHashRow(r)
                case .progress(let n):
                    progressDone = n
                    statusText = "Hashing \(n.formatted()) / \(progressTotal.formatted())…"
                case .verified:
                    break
                }
            }

            // Done
            let successes = allResults.filter(\.success).count
            let errors    = allResults.count - successes
            logger.logSessionEnd(processed: successes, errors: errors)

            statusText = "Done: \(successes.formatted()) hashed, "
                + "\(errors.formatted()) error(s).  Log: \(logger.logPath)"
            runComplete = true

            // CSV export
            if csvWanted, !csvOutPath.isEmpty {
                exportCsvFile(algorithm: opts.algorithm.rawValue,
                              includeMetadata: opts.includeMetadata,
                              toPath: csvOutPath, logger: logger)
            }

            var msg = "Files hashed:  \(successes.formatted())\n"
                    + "Errors:  \(errors.formatted())"
            if sidecarSkipped > 0 {
                msg += "\nSidecars skipped:  \(sidecarSkipped.formatted())"
            }
            if sidecarOverwritten > 0 {
                msg += "\nSidecars overwritten:  \(sidecarOverwritten.formatted())"
            }
            msg += "\n\nLog: \(logger.logPath)"

            showAlert(title: "Hashing complete!", message: msg, style: .informational)
        } catch is CancellationError {
            statusText = "Cancelled."
            logger.logWarning("Operation cancelled by user.")
        } catch {
            showAlert(title: "Error",
                      message: "Unexpected error:\n\(error.localizedDescription)",
                      style: .critical)
            statusText = "Error: \(error.localizedDescription)"
        }

        finishRun()
    }

    // ── Verify sidecars ──────────────────────────────────────────────────────

    func verify() {
        guard !isRunning else { return }

        let path = targetPath.trimmingCharacters(in: .whitespaces)
        guard let isFile = validateTarget(path) else { return }

        let ext = sidecarExtension.trimmingCharacters(in: .whitespaces)
        if ext.isEmpty {
            showAlert(title: "Missing extension",
                      message: "Please specify the sidecar extension to verify "
                        + "(Options → Extension).",
                      style: .warning)
            return
        }

        // Sandbox: verifying a single file means reading its sibling sidecar,
        // which needs parent-folder access just like sidecar writing does.
        if isFile {
            ensureParentFolderAccess(
                forFileAt: path,
                explanation: "To read the sidecar hash file next to the selected file, "
                    + "FileHasher needs permission for the file's folder.")
        }

        let typeFilter = (!isFile && limitFileTypes)
            ? HashOptions.parseFileTypes(fileTypesText)
            : []

        guard let logger = startRun(columnTitle: "Verification") else { return }
        logger.logInfo("Verify sidecars | Target: \(path)  |  Extension: \(ext)  |  "
            + "Recursive: \(!isFile && scanRecursively)  |  "
            + "Types: \(typeFilter.isEmpty ? "(all)" : typeFilter.joined(separator: ","))")

        statusText = "Enumerating sidecars…"
        let verifier = SidecarVerifier(targetPath: path, isFile: isFile,
                                       sidecarExtension: ext,
                                       recursive: !isFile && scanRecursively,
                                       fileTypeFilter: typeFilter,
                                       cancel: cancelFlag)
        runTask = Task { await self.performVerify(verifier, extension: ext, logger: logger) }
    }

    private func performVerify(_ verifier: SidecarVerifier, extension ext: String,
                               logger: Logger) async {
        do {
            let (items, warnings) = try await Task.detached(priority: .userInitiated) {
                try verifier.enumerateWork()
            }.value
            for w in warnings {
                appendWarning(w)
                logger.logWarning(w)
            }

            if items.isEmpty {
                statusText = "No \"\(ext)\" sidecars or matching files found."
                finishRun()
                return
            }

            statusText = "Verifying \(items.count.formatted()) item(s)…"
            isEnumerating = false
            progressTotal = items.count
            progressDone = 0

            var summary = VerifySummary()
            let stream = AsyncThrowingStream<WorkerMessage, Error> { continuation in
                Task.detached(priority: .userInitiated) {
                    do {
                        _ = try verifier.verifyAll(items: items, logger: logger) {
                            continuation.yield($0)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            for try await message in stream {
                switch message {
                case .warning(let w):
                    appendWarning(w)
                    logger.logWarning(w)
                case .verified(let v):
                    summary.count(v.status)
                    addVerifyRow(v)
                case .progress(let n):
                    progressDone = n
                    statusText = "Verifying \(n.formatted()) / \(progressTotal.formatted())…"
                case .hashed:
                    break
                }
            }

            logger.logSessionEnd(processed: summary.ok, errors: summary.failed)

            statusText = "Done: \(summary.ok.formatted()) OK, "
                + "\(summary.failed.formatted()) problem(s), "
                + "\(summary.noSidecar.formatted()) without sidecar.  Log: \(logger.logPath)"
            runComplete = true

            var msg = "OK:  \(summary.ok.formatted())\n"
                    + "Mismatches:  \(summary.mismatch.formatted())\n"
                    + "Missing files:  \(summary.missingFile.formatted())\n"
                    + "No sidecar:  \(summary.noSidecar.formatted())"
            if summary.parseError > 0 {
                msg += "\nParse errors:  \(summary.parseError.formatted())"
            }
            if summary.readError > 0 {
                msg += "\nRead errors:  \(summary.readError.formatted())"
            }
            msg += "\n\nLog: \(logger.logPath)"

            showAlert(title: "Verification complete!", message: msg,
                      style: summary.failed > 0 ? .warning : .informational)
        } catch is CancellationError {
            statusText = "Cancelled."
            logger.logWarning("Verification cancelled by user.")
        } catch {
            showAlert(title: "Error",
                      message: "Unexpected error:\n\(error.localizedDescription)",
                      style: .critical)
            statusText = "Error: \(error.localizedDescription)"
        }

        finishRun()
    }

    // ── Stop / Clear ─────────────────────────────────────────────────────────

    func stop() {
        cancelFlag.cancel()
        statusText = "Stopping…"
    }

    func clearResults() {
        allResults.removeAll()
        rows.removeAll()
        progressDone = 0
        progressTotal = 0
        runComplete = false
        statusText = "Ready."
    }

    // ── Shared run plumbing ──────────────────────────────────────────────────

    /// Validates the target path box. Returns true for a file, false for a
    /// directory, nil (after showing an alert) when invalid.
    private func validateTarget(_ path: String) -> Bool? {
        if path.isEmpty {
            showAlert(title: "No target",
                      message: "Please select a file or folder first.", style: .warning)
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            showAlert(title: "Invalid path",
                      message: "Path does not exist (or is not accessible to the app):\n\(path)",
                      style: .warning)
            return nil
        }
        return !isDir.boolValue
    }

    private func startRun(columnTitle: String) -> Logger? {
        let newLogger: Logger
        do {
            newLogger = try Logger()
        } catch {
            showAlert(title: "Log error",
                      message: "Could not create the log file:\n\(error.localizedDescription)",
                      style: .critical)
            return nil
        }

        allResults.removeAll()
        rows.removeAll()
        hashColumnTitle = columnTitle
        progressDone = 0
        progressTotal = 0
        runComplete = false
        isEnumerating = true
        isRunning = true
        cancelFlag = CancelFlag()
        logger = newLogger
        logPath = newLogger.logPath
        return newLogger
    }

    private func finishRun() {
        isRunning = false
        isEnumerating = false
        runTask = nil
    }

    // ── Row construction ─────────────────────────────────────────────────────

    private static let sizeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private func addHashRow(_ r: HashResult) {
        allResults.append(r)
        rows.append(ResultRow(
            pathDisplay: r.filePath,
            value:       r.success ? r.hash : "ERROR: \(r.errorMessage ?? "unknown")",
            size:        r.length.map {
                Self.sizeFormatter.string(from: NSNumber(value: $0)) ?? String($0)
            } ?? "",
            modified:    r.lastWriteUtc.map { HashTimestamp.display.string(from: $0) } ?? "",
            severity:    r.success ? .normal : .error,
            realPath:    r.filePath,
            hash:        r.success ? r.hash : nil))
    }

    private func addVerifyRow(_ v: VerifyResult) {
        var verdict: String
        switch v.status {
        case .ok:       verdict = "OK (\(v.algorithm?.rawValue ?? "?"))"
        case .mismatch: verdict = "MISMATCH (\(v.algorithm?.rawValue ?? "?"))"
        default:        verdict = SidecarVerifier.statusLabel(v.status)
        }
        if let detail = v.detail {
            verdict += "; \(detail)"
        }

        let severity: ResultRow.Severity
        switch v.status {
        case .ok:        severity = .success
        case .noSidecar: severity = .warning
        default:         severity = .error
        }

        rows.append(ResultRow(
            pathDisplay: v.filePath,
            value:       verdict,
            size:        "",
            modified:    "",
            severity:    severity,
            realPath:    v.filePath,
            hash:        v.computedHash))
    }

    private func appendWarning(_ message: String) {
        rows.append(ResultRow(pathDisplay: "[WARN]", value: message,
                              size: "", modified: "",
                              severity: .warning, realPath: nil, hash: nil))
    }

    // ── CSV ──────────────────────────────────────────────────────────────────

    private func exportCsvFile(algorithm: String, includeMetadata: Bool,
                               toPath path: String, logger: Logger) {
        do {
            try CsvExporter.export(results: allResults, algorithm: algorithm,
                                   includeMetadata: includeMetadata, toPath: path)
            logger.logInfo("CSV exported to: \(path)")
            statusText = "CSV saved: \(path)"
        } catch {
            showAlert(title: "Export error",
                      message: "CSV export failed:\n\(error.localizedDescription)",
                      style: .warning)
        }
    }

    // ── Dialogs ──────────────────────────────────────────────────────────────

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }

    private func showSidecarConflictDialog(filePath: String,
                                           sidecarPath: String) -> SidecarConflictAction {
        var details: String
        let fm = FileManager.default
        if let fi = try? fm.attributesOfItem(atPath: filePath),
           let si = try? fm.attributesOfItem(atPath: sidecarPath) {
            let local = DateFormatter()
            local.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let size = (fi[.size] as? NSNumber)?.int64Value ?? 0
            let fileMod = (fi[.modificationDate] as? Date).map { local.string(from: $0) } ?? "?"
            let sideMod = (si[.modificationDate] as? Date).map { local.string(from: $0) } ?? "?"
            details = "File: \((filePath as NSString).lastPathComponent)\n"
                    + "Size: \(Self.sizeFormatter.string(from: NSNumber(value: size)) ?? "\(size)") bytes\n"
                    + "Modified: \(fileMod)\n\n"
                    + "Existing sidecar: \((sidecarPath as NSString).lastPathComponent)\n"
                    + "Sidecar written: \(sideMod)"
        } else {
            details = "File: \((filePath as NSString).lastPathComponent)\n"
                    + "Sidecar: \((sidecarPath as NSString).lastPathComponent)"
        }

        let alert = NSAlert()
        alert.messageText = "This file already has a sidecar hash file"
        alert.informativeText = details
            + "\n\nRe-hash and overwrite the sidecar, or skip this file?"
        alert.alertStyle = .warning
        // First button = default, matching the Windows dialog's default of Skip.
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Skip All")
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Overwrite All")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .skip
        case .alertSecondButtonReturn: return .skipAll
        case .alertThirdButtonReturn:  return .overwrite
        default:                       return .overwriteAll
        }
    }

    /// Sandbox helper: selecting a single file grants access to that file only.
    /// Reading or writing its sibling sidecar needs the containing folder, so
    /// ask the user to grant it via an open panel pointed at the parent.
    private func ensureParentFolderAccess(forFileAt path: String, explanation: String) {
        let parent = (path as NSString).deletingLastPathComponent
        if accessGrants.contains(where: {
            $0.hasDirectoryPath && parent == $0.path
        }) {
            return
        }

        let panel = NSOpenPanel()
        panel.message = explanation + "\nClick \"Grant Access\" to allow it."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: parent, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            accessGrants.append(url)
        }
        // Declining is allowed; the sidecar read/write will surface its own
        // error row or warning, same as any other access problem.
    }

    // ── Row actions (context menu / double-click) ────────────────────────────

    func row(withId id: ResultRow.ID) -> ResultRow? {
        rows.first { $0.id == id }
    }

    func revealInFinder(_ path: String) {
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        // File gone since it was hashed; fall back to the folder alone.
        let dir = (path as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue {
            NSWorkspace.shared.open(URL(fileURLWithPath: dir, isDirectory: true))
        }
    }

    func openTerminal(at path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir),
              isDir.boolValue,
              let terminal = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Terminal")
        else { return }

        NSWorkspace.shared.open([URL(fileURLWithPath: dir, isDirectory: true)],
                                withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in
                    self.statusText = "Could not open Terminal: \(error.localizedDescription)"
                }
            }
        }
    }

    func copyToClipboard(_ text: String?, what: String) {
        guard let text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "\(what) copied to clipboard."
    }

    func openLogFolder() {
        guard let logPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logPath)])
    }

    // ── About ────────────────────────────────────────────────────────────────

    func showAbout() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"

        let alert = NSAlert()
        alert.messageText = "FileHasher"
        alert.informativeText = "Version \(version)\n\n"
            + "A file and folder hashing utility for macOS,\n"
            + "derived from FileHasher for Windows.\n\n"
            + "Author: Fabian Santiago\n"
            + "Copyright © 2026 Fabian Santiago"
        alert.alertStyle = .informational
        alert.runModal()
    }
}
