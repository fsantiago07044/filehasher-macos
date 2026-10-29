# App Store listing: final copy as submitted

Everything below matches the submitted record.
Note: Fabian edited the description and related text in App Store Connect to remove
em dashes (replaced with semicolons or commas). This doc reflects that style; the
live App Store Connect record is the source of truth for the final wording.

**The two drift.** On 2026-10-21 the live description still read "with optional
subfolder recursion" while this file had been updated months earlier, so the repo
copy was not what customers were reading. Re-checked 2026-10-29: the live
description and What's New now match this file exactly, and the 3 screenshots
are in place; promotional text was the one field out of step (see below). Before editing the description, pull the
live text rather than trusting this file, and paste the result back here so they
match. The API path is
`GET /v1/appStoreVersions/<id>/appStoreVersionLocalizations`; the version ids come
from `GET /v1/apps/6802073927/appStoreVersions`. The description is version-bound,
so it can only change as part of a submission, unlike promotional text.

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
• Hash a single file or a folder of files, scanning the folder alone, every subfolder, or a set number of levels deep
• Optionally limit a folder scan to file types you choose (pkg, dmg, zip, and more)
• Four algorithms: MD5, SHA-1, SHA-256, and SHA-512
• Drag and drop a file or folder straight onto the window
• Optional size and last-modified metadata alongside every hash
• Your algorithm and metadata choices are remembered between launches; the options that write files always start off

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

FileHasher is a universal app, running natively on both Apple Silicon and Intel Macs.
```

## Promotional text (max 170 characters, editable without review)

Promo text changes the live listing **instantly, without review**, so it must
never describe a build that has not shipped yet. Set it only once the matching
version is live.

**It does NOT carry across version records, and nothing warns you.** Checked
against the live listing on 2026-10-29: 1.0.0 and 1.0.1 both have promotional
text, and **1.1.0 has none at all**. Creating the 1.1.0 version record dropped
it, the field was never filled in, and the listing then ran with no promotional
text from go-live on 2026-10-22 until it was noticed. Unlike the description,
this field is silent when empty: the store simply shows the description, so
nothing looks wrong. **Add checking it to the post-approval pass**, and read it
back from the API rather than assuming, since the web product page does not
render it:
`GET /v1/appStoreVersions/<id>/appStoreVersionLocalizations` -> `promotionalText`.
The Developer-role key can read this; writing it needs App Manager, so the
value itself goes in through the web UI.

For 1.1.0 (the current live version):
`Choose how deep a folder scan goes, down to a set number of levels. Hash, sidecar, and verify your files; private by design, no network access at all.` *(150 chars)*

Superseded, kept for the record (1.0.1, the universal build):
`Now universal: runs natively on Apple Silicon and Intel Macs. Hash, sidecar, and verify your files; private by design, no network access at all.` *(144 chars)*

Superseded, kept for the record (1.0.0, the initial release):
`Hash files and folders, write standard sidecar checksums, and verify them any time; private by design, with no network access at all.` *(133 chars)*

## Keywords (max 100 characters)

`hash,checksum,sha256,sha512,sha1,md5,verify,integrity,sidecar,digest,csv,audit` *(78 chars; "file" and "FileHasher" are matched from the name automatically; don't waste keyword space on them)*

## What's New

Note the App Store edition went **1.0.1 to 1.1.0**: there was no 1.0.2 on the
store, since that release was the Standalone edition's debut and changed nothing
in the app itself. So 1.1.0's What's New covers everything since 1.0.1.

1.1.0:

```text
SUBFOLDER DEPTH
The Include subfolders checkbox is now a Subfolders control. Scan just the folder you picked, which is still the default, every subfolder beneath it, or a set number of levels deep. Verify Sidecars uses the same depth as hashing, so a verification pass can never report files as missing a sidecar simply because it did not look that far.

PREFERENCES ARE REMEMBERED
Your hash algorithm and the Include file metadata option are now remembered between launches. The options that write files, sidecar hash files and CSV export, deliberately start switched off every time, so a run only ever creates files because you asked it to in that session.

BROWSE PANELS OPEN WHERE YOU ARE
The file and folder pickers now open at the path already in the box instead of wherever the system last left them, and the CSV panel keeps the filename you chose. A path that no longer exists falls back to the nearest folder that does.
```

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

## Screenshots

Kept **per release**, in `docs/app-store/<version>/`, so an older listing's shots
stay retrievable rather than being overwritten. The loose `shot*-1440x900.png`
files at the top of `docs/app-store/` are the pre-1.1.0 set and are left in place.

Current set, 1.1.0 (`docs/app-store/1.1.0/`):

| File | Shows |
| --- | --- |
| `filehasher-1.1.0-01-hash.png` | Folder hash with subfolders included and metadata, completed run |
| `filehasher-1.1.0-02-verify-ok.png` | One-pass verification, all green |
| `filehasher-1.1.0-03-verify-mismatch.png` | Tamper detection; one file flagged MISMATCH |

Upload order suggestion: 01 → 03 → 02 (lead with the everyday view, follow with
the payoff, close with the all-clear).

**Two upload traps, both hit on 1.1.0:**

- **Names must differ from the previous release's.** App Store Connect copies the
  previous version's screenshots into a new version record, and uploading a file
  whose name matches one already in the set fails with "the screenshot couldn't
  be saved". Version-stamped names avoid it; the old shots still need deleting
  from the set afterwards, or the listing shows six.
- **No alpha channel, and sRGB.** `screencapture` emits RGBA tagged with the
  capture display's ICC profile. An alpha channel is a documented cause of the
  same "couldn't be saved" error. The capture script now normalises its own
  output, so this only needs checking if shots are produced some other way:
  `sips -g hasAlpha -g profile <file>` must say `no` and `sRGB IEC61966-2.1`.

Deleting screenshots or editing listing metadata through the API needs an **App
Manager** key; the Bitwarden key is Developer role, which can read metadata and
upload builds but returns 403 on metadata writes.
