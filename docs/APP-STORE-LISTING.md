# App Store listing: final copy as submitted

Everything below matches the submitted record.
Note: Fabian edited the description and related text in App Store Connect to remove
em dashes (replaced with semicolons or commas). This doc reflects that style; the
live App Store Connect record is the source of truth for the final wording.

Screenshot originals live in `docs/app-store/` (1440×900, an accepted Mac size).

## Name

**FileHasher — Checksum Utility** (the store name as entered; "FileHasher" alone was already taken)

## Subtitle (max 30 characters)

`Hash, verify, and audit files` *(29 chars)*

## Category

Primary: **Utilities** · Secondary (optional): **Developer Tools**

## Description

```text
FileHasher computes cryptographic hashes for your files and folders, writes standard sidecar hash files next to them, and verifies everything later, so you can prove a download, an installer, a backup, or an archive hasn't changed since you hashed it.

HASH
• Hash a single file or a folder of files, with optional subfolder recursion
• Optionally limit a folder scan to file types you choose (pkg, dmg, zip, and more)
• Four algorithms: MD5, SHA-1, SHA-256, and SHA-512
• Drag and drop a file or folder straight onto the window
• Optional size and last-modified metadata alongside every hash

SIDECAR HASH FILES
• Write a sidecar (for example "report.pdf.sha256") next to each hashed file
• Three formats, including the standard sha256sum line format that command-line tools understand
• Per-file conflict handling when a sidecar already exists: overwrite or skip, individually or for all

VERIFY
• Re-verify a whole folder in one pass: the algorithm is detected automatically per sidecar, so folders with mixed algorithms just work
• Clear verdicts for every file: OK, MISMATCH, MISSING FILE, NO SIDECAR, PARSE ERROR, READ ERROR
• Files that should have a sidecar but don't are surfaced too, so audits are complete

EXPORT AND RECORD
• Export results to a clean, Excel-friendly CSV
• Every run is logged automatically, one log per day
• Copy any hash or file path straight from the results table

PRIVATE BY DESIGN
FileHasher collects nothing and sends nothing. There are no analytics, no accounts, and no network connections; everything happens locally, inside the macOS App Sandbox.

FileHasher for macOS shares its lineage with FileHasher for Windows; sidecar files and CSV exports made on either platform verify cleanly on the other.
```

## Promotional text (max 170 characters, editable without review)

`Hash files and folders, write standard sidecar checksums, and verify them any time; private by design, with no network access at all.` *(134 chars)*

## Keywords (max 100 characters)

`hash,checksum,sha256,sha512,sha1,md5,verify,integrity,sidecar,digest,csv,audit` *(78 chars; "file" and "FileHasher" are matched from the name automatically; don't waste keyword space on them)*

## What's New

1.0.1: `Now a universal app: runs natively on Apple Silicon and Intel Macs. Adds a built-in help guide (Help menu, Cmd-?) covering every feature.`

1.0.0 (shipped): `Initial release of FileHasher for macOS.`

## URLs

- Privacy Policy: https://fabianasantiago.com/privacy-policy/
- Support: https://fabianasantiago.com/filehasher/support/
- Marketing (optional): https://fabianasantiago.com/filehasher/

## Questionnaires

- **App Privacy**: "Data Not Collected" (matches the published policy)
- **Age rating**: answer None/No to everything → rates 4+
- **Export compliance**: already answered in the binary via
  `ITSAppUsesNonExemptEncryption = false`; if asked, the app uses no encryption
  (hashing is not encryption)

## Other fields

- Copyright: `2026 Fabian A. Santiago` (as entered)
- Version: 1.0.0
- SKU suggestion: `filehasher-macos`
- Pricing: **Free** (price tier 0 in all territories)

## Screenshots (docs/app-store/)

| File | Shows |
| --- | --- |
| `shot1-hash-1440x900.png` | Folder hash with subfolders included and metadata, completed run |
| `shot2-verify-ok-1440x900.png` | One-pass verification, all green |
| `shot3-verify-mismatch-1440x900.png` | Tamper detection; one file flagged MISMATCH |

Upload order suggestion: 1 → 3 → 2 (lead with the everyday view, follow with the
payoff, close with the all-clear).
