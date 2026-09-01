# Changelog

## 1.0.2 (in progress)

- New Standalone edition, distributed outside the Mac App Store: Developer ID
  signed, notarized, universal, and self-updating via Sparkle (with user
  consent; updates are fetched from GitHub releases). The App Store edition
  is unchanged and contains no update machinery
- About dialog, help Support topic, and the support email subject now name
  the edition (Mac App Store or Standalone)
- Standalone privacy note: the one network activity is the update check;
  the help window's Privacy topic explains it per edition

## 1.0.1, released 2026-08-25 (Mac App Store)

- Universal binary: FileHasher now runs natively on Apple Silicon and
  Intel Macs (previously Intel-only, via Rosetta 2 on Apple Silicon)

- Real in-app help: the Help menu now opens a native help window with topics
  covering every feature (Getting Started, scan options, algorithms, sidecars,
  verification verdicts, CSV, logs, privacy), replacing the empty system stub.
  Cmd-? opens it; Support Website and Privacy Policy links sit alongside.
- The support email link in Help pre-fills its subject with the installed
  app version (FileHasher-MacOS-x.y.z), read from the bundle so it updates
  itself on every release

## 1.0.0 (build 2), 2026-08-16

Folder scanning redesigned for macOS conventions (the Windows app keeps its
installer-focused defaults; the two apps remain output-compatible):

- Folder scans now hash **all files by default**; the Windows-inherited
  .exe/.msi default filter is gone
- **Include subfolders** option; recursion is now opt-in instead of always on
- **Limit to file types** option: a user-typed, comma-separated extension list
  with macOS-appropriate suggestions (pkg, dmg, iso, zip, exe, msi); nothing is
  pre-filled. The verify audit ("NO SIDECAR") honors the same limit
- Build number bumped for App Store resubmission

## 0.1.0 — 2026-08-11

Initial macOS port of FileHasher for Windows (SwiftUI, Intel x86_64, sandboxed).

- File and recursive-folder hashing: MD5 / SHA1 / SHA256 / SHA512 (streaming, cancellable mid-file)
- `.exe`/`.msi` default scan filter with "Scan all file types" override
- Sidecar hash files: `{algo}sum`, hash-only, and extended formats; per-file conflict
  dialog (Overwrite / Overwrite All / Skip / Skip All) resolved before hashing begins
- Sidecar verification with per-sidecar algorithm auto-detection and the full verdict
  set (OK / MISMATCH / MISSING FILE / NO SIDECAR / PARSE ERROR / READ ERROR)
- CSV export (UTF-8 BOM, Excel-friendly), optional size/modified metadata columns
- Per-day run logs, results context menu (Reveal in Finder, Open Terminal Here,
  Copy Hash, Copy File Path), drag-and-drop targets
- Engine unit-test suite (13 tests)

Not ported from Windows: UAC elevation (superseded by the App Sandbox model) and the
experimental MSI inner-file scan (Windows Installer API dependency).
