import Foundation

/// One section within a help topic: an optional heading, paragraphs, and an
/// optional bullet list. Paragraph and bullet strings may use inline Markdown
/// (bold, code) which the help view renders.
struct HelpSection: Identifiable {
    let id = UUID()
    var heading: String? = nil
    var paragraphs: [String] = []
    var bullets: [String] = []
}

/// One topic in the help window's sidebar.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String     // SF Symbol name
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum HelpContent {
    /// The marketing version of the running app, read from the bundle so the
    /// help content (and the support email subject) tracks every update
    /// automatically.
    static let appVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

#if CHANNEL_STANDALONE
    /// Which distribution this build came from; surfaces in About, the help
    /// Support topic, and the support email subject.
    static let channelName = "Standalone edition"
    static let channelSlug = "-standalone"
#else
    static let channelName = "Mac App Store edition"
    static let channelSlug = ""
#endif

    /// Support mail link with a pre-filled, version- and channel-stamped subject.
    static let supportMailto =
        "mailto:support@fabianasantiago.com?subject=FileHasher-MacOS-\(appVersion)\(channelSlug)"

    /// Privacy topic copy differs by channel: the Standalone edition's Sparkle
    /// update checks are its one network activity, and the help must say so.
    /// (#if cannot wrap array-literal elements, hence whole-array selection.)
    private static let sandboxParagraph =
        "The app runs inside the macOS App Sandbox, so it can only access files and folders you explicitly select or drag in. The one extra prompt you may see, a folder picker when writing or verifying a sidecar for a single selected file, exists because the sandbox scopes access to exactly what you chose."
#if CHANNEL_STANDALONE
    private static let privacyParagraphs = [
        "FileHasher collects nothing and sends nothing about you or your files. It has no analytics and no accounts; hashing happens entirely on your Mac.",
        "This Standalone edition makes exactly one kind of network connection: with your consent, it contacts GitHub to check for app updates and downloads them when you approve. No personal data rides along, and update checks can be declined or turned off at any time. The Mac App Store edition makes no network connections at all.",
        sandboxParagraph,
    ]
#else
    private static let privacyParagraphs = [
        "FileHasher collects nothing and sends nothing. It has no analytics, no accounts, and it makes no network connections; everything happens locally on your Mac.",
        sandboxParagraph,
    ]
#endif

    static let topics: [HelpTopic] = [
        HelpTopic(id: "start", title: "Getting Started", icon: "play.circle", sections: [
            HelpSection(paragraphs: [
                "FileHasher computes cryptographic hashes of files and folders you choose, writes standard sidecar checksum files next to them, and verifies those sidecars later. Use it to prove that a download, installer, disk image, backup, or archive has not changed since you hashed it, or that it matches a checksum published by a vendor.",
            ]),
            HelpSection(heading: "Quick start", bullets: [
                "Click **Browse Folder…** (or **Browse File…**) and choose what to hash. You can also drag a file or folder onto the Target box.",
                "Pick an algorithm. **SHA256** is the default and the right choice for almost everything.",
                "Click **Run**. Each file appears in the results table with its hash.",
                "To create verifiable records, check **Write sidecar hash files next to each file** before running, then use **Verify Sidecars** any time later.",
            ]),
        ]),

        HelpTopic(id: "target", title: "Choosing a Target", icon: "folder", sections: [
            HelpSection(paragraphs: [
                "The target can be a single file or a folder. Use the browse buttons, drag and drop onto the Target box, or type a path.",
            ]),
            HelpSection(heading: "A note on typed paths", paragraphs: [
                "FileHasher runs in the macOS App Sandbox: it can only read locations you have explicitly granted. Files chosen through the browse buttons or drag and drop are always accessible; a typed or pasted path only works for locations the app can already reach. If a typed path reports \"not accessible\", select it with a browse button instead.",
            ]),
        ]),

        HelpTopic(id: "scan", title: "Folder Scan Options", icon: "line.3.horizontal.decrease.circle", sections: [
            HelpSection(paragraphs: [
                "When the target is a folder, every file at the folder's top level is hashed by default. Two options refine that:",
            ]),
            HelpSection(heading: "Include subfolders", paragraphs: [
                "Check this to scan the folder recursively, descending into every subfolder. It is off by default.",
            ]),
            HelpSection(heading: "Limit to file types", paragraphs: [
                "Check this to restrict the scan to specific file types, then enter a comma-separated list of extensions, for example: `pkg, dmg, zip`. The **Suggestions** menu inserts common ones. Leading dots and capitalization do not matter; `.PKG` and `pkg` mean the same thing.",
                "With the limit off (or the list empty), every file is scanned. The same limit drives the sidecar verification audit: only matching files are reported as **NO SIDECAR**.",
            ]),
        ]),

        HelpTopic(id: "algorithms", title: "Hash Algorithms", icon: "number.circle", sections: [
            HelpSection(bullets: [
                "**MD5**: fast, but not collision-resistant. Use only to match older published checksums.",
                "**SHA1**: legacy; deprecated for most security purposes.",
                "**SHA256**: the default. Recommended for general use.",
                "**SHA512**: the strongest option; produces a longer digest.",
            ]),
            HelpSection(paragraphs: [
                "The hash column header, the CSV export header, and the suggested sidecar extension all follow the selected algorithm.",
            ]),
        ]),

        HelpTopic(id: "sidecars", title: "Sidecar Hash Files", icon: "doc.badge.plus", sections: [
            HelpSection(paragraphs: [
                "A sidecar is a small text file written next to each hashed file; hashing `report.pdf` with SHA256 produces `report.pdf.sha256` alongside it. Sidecars are how FileHasher remembers hashes for later verification.",
            ]),
            HelpSection(heading: "Extension", paragraphs: [
                "The suffix appended to the original filename. The suggestion follows the selected algorithm (`.md5`, `.sha1`, `.sha256`, `.sha512`); a custom extension you type is never overwritten.",
            ]),
            HelpSection(heading: "Format", bullets: [
                "**{algo}sum format** (default): `HASH *filename`, compatible with the standard md5sum, sha1sum, sha256sum, and sha512sum command-line tools.",
                "**Hash only**: the raw hash string with no filename.",
                "**Extended**: `HASH *filename *lastModified *sizeBytes`, with the timestamp in ISO-8601 UTC.",
            ]),
            HelpSection(heading: "When a sidecar already exists", paragraphs: [
                "FileHasher pauses before hashing begins and asks, file by file: **Overwrite**, **Overwrite All**, **Skip**, or **Skip All**. Skipped files are excluded from the run. All decisions are collected before any file is touched.",
                "Sidecar files themselves are never treated as hash targets while sidecar writing is on, so repeated runs never produce chains like `.sha256.sha256`.",
            ]),
            HelpSection(heading: "Folder permission for single files", paragraphs: [
                "Writing a sidecar next to a single selected file needs permission for that file's folder, which selecting the file alone does not grant; FileHasher asks once with a folder picker. Folder targets never need this.",
            ]),
        ]),

        HelpTopic(id: "verify", title: "Verifying Sidecars", icon: "checkmark.seal", sections: [
            HelpSection(paragraphs: [
                "**Verify Sidecars** re-hashes files and compares the result against their sidecars, using the current Target and the Extension configured under the sidecar options (the write checkbox does not need to be on). Folder targets follow the same subfolder and file-type options as hashing; targeting a single file verifies that file's sidecar, and targeting a sidecar directly verifies it against its base file.",
                "The algorithm is detected automatically per sidecar from the length of the stored hash, so a folder with mixed-algorithm sidecars verifies in one pass. All three sidecar formats are recognized.",
            ]),
            HelpSection(heading: "Verdicts", bullets: [
                "**OK** (green): the re-computed hash matches the sidecar.",
                "**MISMATCH** (red): the hash differs; the row shows the expected and computed values.",
                "**MISSING FILE** (red): a sidecar exists but the file it attests to is gone.",
                "**NO SIDECAR** (orange): the file matches the current scan options but has no sidecar; a completeness audit.",
                "**PARSE ERROR** (red): the sidecar's content is not a recognized format.",
                "**READ ERROR** (red): the file or its sidecar could not be read.",
            ]),
            HelpSection(paragraphs: [
                "The hash alone decides pass or fail. For extended-format sidecars, a differing embedded filename, date, or size on an otherwise matching row is shown as an informational note; a file's modified date often changes legitimately on copy or restore.",
            ]),
        ]),

        HelpTopic(id: "csv", title: "CSV Export", icon: "tablecells", sections: [
            HelpSection(paragraphs: [
                "Check **Export results to CSV** and choose an output path before running. The CSV is written after hashing completes: UTF-8 with BOM (opens correctly in Excel), sorted by file path, successful rows only.",
                "Columns are `Path` and the algorithm; with **Include file metadata** on, `LengthBytes` and `LastWriteUtc` are added. CSV export applies to hashing runs, not verification runs.",
            ]),
        ]),

        HelpTopic(id: "results", title: "Results Table", icon: "list.bullet.rectangle", sections: [
            HelpSection(paragraphs: [
                "Each hashed or verified file is one row. Errors appear in red, warnings in orange. With **Include file metadata** on, size and modified (UTC) columns are filled in.",
            ]),
            HelpSection(heading: "Row actions", bullets: [
                "**Reveal in Finder**: opens the file's location (also triggered by double-click).",
                "**Open Terminal Here**: opens Terminal in the file's folder.",
                "**Copy Hash** and **Copy File Path**: copy the row's values.",
            ]),
            HelpSection(paragraphs: [
                "Right-click a row for these actions. **Clear Results** empties the table and resets the progress bar; **Stop** cancels a run cleanly, keeping the rows already produced.",
            ]),
        ]),

        HelpTopic(id: "logs", title: "Logs", icon: "doc.text.magnifyingglass", sections: [
            HelpSection(paragraphs: [
                "Every run is logged automatically, one file per day. Each entry records the timestamp (UTC), algorithm, result, hash, and file path, plus size and modified date when metadata is on. A session header and footer mark the start and end of each run.",
                "Click the log path at the bottom of the window to reveal the log folder in Finder.",
            ]),
        ]),

        HelpTopic(id: "privacy", title: "Privacy & Permissions", icon: "lock.shield", sections: [
            HelpSection(paragraphs: privacyParagraphs),
        ]),

        HelpTopic(id: "support", title: "Support", icon: "questionmark.circle", sections: [
            HelpSection(paragraphs: [
                "You are running the \(channelName), version \(appVersion).",
                "Questions, bug reports, or feature ideas are welcome at [support@fabianasantiago.com](\(supportMailto)). The link pre-fills the subject with your app version and edition; adding your macOS version and what you expected to happen makes fixes faster.",
                "The support page and privacy policy are also available from the Help menu.",
            ]),
        ]),
    ]
}
