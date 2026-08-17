import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<ResultRow.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            targetSection
            algorithmSection
            optionsSection
            actionRow
            progressSection
            resultsTable
            statusBar
        }
        .padding(10)
        .disabled(false)
    }

    // ── Target ───────────────────────────────────────────────────────────────

    private var targetSection: some View {
        GroupBox("Target") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("File or folder path: type, browse, or drop here",
                              text: $model.targetPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse File…")   { model.browseForFile() }
                        .disabled(model.isRunning)
                    Button("Browse Folder…") { model.browseForFolder() }
                        .disabled(model.isRunning)
                }
                Toggle("Include subfolders  (scan the folder recursively)",
                       isOn: $model.scanRecursively)
                    .disabled(!model.folderOptionsEnabled)
                HStack(spacing: 8) {
                    Toggle("Limit to file types:", isOn: $model.limitFileTypes)
                    TextField("e.g. pkg, dmg, zip", text: $model.fileTypesText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .disabled(!model.limitFileTypes)
                    Menu("Suggestions") {
                        ForEach(AppModel.fileTypeSuggestions, id: \.self) { ext in
                            Button(ext) { model.appendFileType(ext) }
                        }
                    }
                    .frame(width: 130)
                    Text("Off = every file is scanned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!model.folderOptionsEnabled)
            }
            .padding(4)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.setTarget(url)
            return true
        }
    }

    // ── Algorithm ────────────────────────────────────────────────────────────

    private var algorithmSection: some View {
        GroupBox("Hash Algorithm") {
            Picker("", selection: $model.algorithm) {
                ForEach(HashAlgorithmKind.allCases) { algo in
                    Text(algo.rawValue).tag(algo)
                }
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.isRunning)
    }

    // ── Options ──────────────────────────────────────────────────────────────

    private var optionsSection: some View {
        GroupBox("Options") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Include file metadata  (size and last modified date)",
                       isOn: $model.includeMetadata)

                Toggle("Write sidecar hash files next to each file",
                       isOn: $model.writeSidecars)
                HStack(spacing: 12) {
                    Text("Extension:")
                    TextField("", text: $model.sidecarExtension)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Picker("", selection: $model.sidecarFormat) {
                        Text(model.algoSumFormatLabel).tag(SidecarFormat.algoSum)
                        Text("Hash only").tag(SidecarFormat.hashOnly)
                        Text("Extended  (HASH *filename *modified *size)")
                            .tag(SidecarFormat.extended)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                }
                .padding(.leading, 20)
                .disabled(!model.writeSidecars)

                Toggle("Export results to CSV", isOn: $model.exportCsv)
                HStack {
                    TextField("CSV output path", text: $model.csvPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { model.browseForCsv() }
                }
                .padding(.leading, 20)
                .disabled(!model.exportCsv)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.isRunning)
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private var actionRow: some View {
        HStack {
            Button("Clear Results") { model.clearResults() }
                .disabled(model.isRunning)
            Spacer()
            Button("Verify Sidecars") { model.verify() }
                .disabled(model.isRunning)
            Button("Stop") { model.stop() }
                .disabled(!model.isRunning)
            Button("▶  Run") { model.run() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isRunning)
        }
    }

    // ── Progress / status ────────────────────────────────────────────────────

    @ViewBuilder
    private var progressSection: some View {
        Group {
            if model.isEnumerating {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                ProgressView(value: Double(model.progressDone),
                             total: Double(max(model.progressTotal, 1)))
                    .progressViewStyle(.linear)
                    .tint(model.runComplete ? .blue : .green)
            }
        }
        Text(model.statusText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // ── Results table ────────────────────────────────────────────────────────

    private var resultsTable: some View {
        Table(model.rows, selection: $selection) {
            TableColumn("File Path") { row in
                Text(row.pathDisplay)
                    .foregroundStyle(row.color.map(AnyShapeStyle.init)
                                     ?? AnyShapeStyle(.primary))
                    .help(row.pathDisplay)
            }
            .width(min: 200, ideal: 420)

            TableColumn(model.hashColumnTitle) { row in
                Text(row.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(row.color.map(AnyShapeStyle.init)
                                     ?? AnyShapeStyle(.primary))
                    .help(row.value)
            }
            .width(min: 160, ideal: 430)

            TableColumn("Size (bytes)") { row in
                Text(row.size)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 90)

            TableColumn("Modified (UTC)") { row in
                Text(row.modified)
            }
            .width(min: 100, ideal: 140)
        }
        .contextMenu(forSelectionType: ResultRow.ID.self) { ids in
            if let row = ids.first.flatMap(model.row(withId:)),
               let path = row.realPath {
                Button("Reveal in Finder") { model.revealInFinder(path) }
                Button("Open Terminal Here") { model.openTerminal(at: path) }
                Divider()
                Button("Copy Hash") { model.copyToClipboard(row.hash, what: "Hash") }
                    .disabled(row.hash == nil)
                Button("Copy File Path") { model.copyToClipboard(path, what: "Path") }
            }
        } primaryAction: { ids in
            if let row = ids.first.flatMap(model.row(withId:)),
               let path = row.realPath {
                model.revealInFinder(path)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    // ── Status bar ───────────────────────────────────────────────────────────

    private var statusBar: some View {
        HStack {
            if let logPath = model.logPath {
                Button {
                    model.openLogFolder()
                } label: {
                    Text("Log: \(logPath)  (click to open log folder)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
            } else {
                Text("Log: (not yet started)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
