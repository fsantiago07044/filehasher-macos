# FileHasher for macOS

A utility to hash files and folders, write sidecar hash files, verify them later, and export results to CSV.

> **Derived from [FileHasher for Windows](https://github.com/fsantiago07044/filehasher).**
> This repository is a native macOS (SwiftUI) port of the Windows WinForms application and is
> maintained as a sibling project. The app itself is named **FileHasher** on both
> platforms. Output behavior (sidecar formats, verification verdicts, CSV layout, log format)
> is kept deliberately identical so sidecars and CSVs produced on one platform verify and
> compare cleanly on the other. Folder-scan defaults differ by design: the Windows app's
> .exe/.msi installer focus is a Windows convention, so the macOS app scans all files by
> default, with opt-in recursion and an optional user-defined file-type limit.

---

## Requirements

- **Running:** macOS 13 Ventura or later. Builds are **universal** (Apple Silicon
  and Intel, native on both).
- **Building:** Xcode 15+ (developed with Xcode 26), plus [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  if you modify the project structure.

## Building

```bash
# Regenerate the Xcode project after changing project.yml or adding files
xcodegen generate

# Build
xcodebuild -scheme FileHasher -configuration Release build

# Run the engine unit tests
xcodebuild -scheme FileHasher test
```

Or just open `FileHasher.xcodeproj` in Xcode and press ⌘R.

## Usage

The UI mirrors the Windows app:

- **Target** — pick a file or folder with the browse buttons, drag-and-drop onto the
  Target box, or type a path. Folder scans hash **every file by default**, top level only.
- **Include subfolders** — check to scan the folder recursively (off by default).
- **Limit to file types** — optionally restrict a folder scan to a comma-separated
  list of extensions you type yourself (a Suggestions menu offers common ones:
  pkg, dmg, iso, zip, exe, msi). Off, or an empty list, means every file is scanned.
  The same limit drives the verify audit: only matching files are reported as
  `NO SIDECAR`.
- **Hash Algorithm** — MD5, SHA1, SHA256 (default), SHA512.
- **Include file metadata** — adds Size and Modified (UTC) columns to results and CSV.
- **Write sidecar hash files** — writes e.g. `setup.exe.sha256` next to each hashed file.
  Same three formats as Windows: `{algo}sum` (`HASH *filename`), hash only, and extended
  (`HASH *filename *modifiedIso8601Utc *sizeBytes`). Existing sidecars trigger the same
  per-file Overwrite / Overwrite All / Skip / Skip All conflict dialog, resolved before
  any hashing starts.
- **Verify Sidecars** — re-hashes files against existing sidecars. The algorithm is
  auto-detected per sidecar from the stored hash length, so mixed-algorithm folders
  verify in one pass. Verdicts: `OK`, `MISMATCH`, `MISSING FILE`, `NO SIDECAR` (audit),
  `PARSE ERROR`, `READ ERROR`. The hash alone decides pass/fail; extended-format
  metadata differences are informational notes.
- **Export results to CSV** — UTF-8 with BOM, sorted by path, successful rows only.
  Columns: `Path`, `<Algorithm>`, and with metadata `LengthBytes`, `LastWriteUtc`.
- **Results context menu** — Reveal in Finder, Open Terminal Here, Copy Hash,
  Copy File Path. Double-click reveals in Finder.
- **Logs** — every run is logged to
  `~/Library/Containers/com.fabianasantiago.FileHasher/Data/Library/Application Support/FileHasher/Logs/FileHasher_YYYY-MM-DD.log`.
  Click the log path in the status bar to open the folder.

## Differences from the Windows app

| Windows | macOS |
| --- | --- |
| UAC elevation (Run as Administrator) | Not applicable — the app is sandboxed; access comes from user file selection |
| Hash files inside MSI installers (experimental) | Not ported — depends on the Windows Installer database API |
| Open PowerShell / Command Prompt here | Open Terminal Here |
| Open in File Explorer | Reveal in Finder |

### Sandbox notes

FileHasher runs in the macOS App Sandbox (required for Mac App Store distribution):

- Files and folders chosen via the browse buttons or drag-and-drop are readable/writable.
- **Typed or pasted paths** only work for locations the app can already access; prefer
  browsing or drag-and-drop.
- Writing or verifying a sidecar **next to a single selected file** needs access to the
  file's parent folder; the app asks you to grant it with one extra folder-picker click.
  Folder targets need no extra grant.

## Automated testing

`FileHasherTests` covers the hashing engine: known hash vectors for all four algorithms,
streaming cancellation, enumeration filters and sidecar exclusion, all three sidecar
formats round-tripped through the verifier, mixed-algorithm verification, every verify
verdict, and CSV escaping/layout/BOM.

```bash
xcodebuild -scheme FileHasher test
```

## Acknowledgements

Direct port of [FileHasher for Windows](https://github.com/fsantiago07044/filehasher),
which grew out of an original PowerShell hashing script.

## License

[MIT](LICENSE) — © 2026 Fabian Santiago
