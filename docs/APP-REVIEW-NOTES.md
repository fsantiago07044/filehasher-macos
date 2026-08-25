# App Review reply (Guideline 2.1, Information Needed)

NOTE (2026-08-25): item 2 below was updated for the universal 1.0.1 era.
The ASC App Review Information -> Notes field still holds the older
Intel-only wording from the 1.0.0 submission; it is locked while 1.0.1 is
In Review. Refresh that field with the current items 2-7 at the next
opportunity (after approval, or during any resubmission).

Paste the reply below into the Resolution Center thread, attach
`filehasher-review-demo.mov`, and also copy items 2 through 7 into
App Review Information -> Notes for future submissions.

Context: this reply accompanies build 2 (version 1.0.0), which refines the
folder-scan options (all files scanned by default, opt-in subfolder recursion,
optional user-defined file-type limit). Screenshots were updated to match.

---

Hello, thank you for the review. Answers to each item:

1. SCREEN RECORDING
A screen recording is attached. It was captured on a physical Mac
(Mac mini 2018, Intel) running macOS Sequoia 15.7.9, and begins with
launching the app. It shows the typical user flow through the core
features: selecting a folder with the standard macOS open panel, enabling
options, computing SHA-256 hashes of the folder's files, writing sidecar
checksum files, and then verifying those sidecars (all results OK).
The app has no account registration, login, or account deletion; no paid
content, purchases, or subscriptions; no user-generated content; and it
requests no access to sensitive data or device capabilities. The only
permission interaction is the standard macOS file-selection dialog
(shown in the recording), through which the user explicitly chooses what
the sandboxed app may read.

2. DEVICES AND OPERATING SYSTEMS TESTED
The app is a universal binary (arm64 + x86_64) and is tested natively on
both architectures before each release:
- Apple Silicon: Mac (M-series) running macOS 26.6.2
- Intel: Mac mini (2018), Model Identifier Macmini8,1, 6-core Intel
  Core i7, running macOS Sequoia 15.7.9 (the newest macOS available for
  Intel hardware)
Minimum system version is macOS 13. The hashing engine is additionally
covered by an automated test suite (16 unit tests, including known hash
vectors for all four algorithms) that runs natively on both
architectures.

3. PURPOSE AND TARGET AUDIENCE
FileHasher computes cryptographic hashes (MD5, SHA-1, SHA-256, SHA-512)
of files and folders the user selects, writes standard sidecar checksum
files next to them (including the sha256sum line format used by
command-line tools), verifies those sidecars later, and exports results
to CSV. The problem it solves: proving that a download, installer, disk
image, backup, or archive has not changed since it was hashed, or that
it matches a checksum published by a vendor. Target audience: anyone who
verifies downloaded software or disk images, plus IT, QA, and archival
users who audit file sets for integrity. Its value is that verification
is local, private (no network access at all), and interoperable with
standard checksum tooling on other platforms.

4. SETUP AND ACCESS INSTRUCTIONS
No setup, login, credentials, or sample files are required. To exercise
the main features: launch the app, click "Browse Folder…", choose any
folder containing files (any file types work, for example a folder of
documents), and click Run to hash them. To exercise verification, check
"Write sidecar hash files next to each file" before running, then click
"Verify Sidecars" after the run completes; every file should report OK.
Optional features: "Include subfolders" scans recursively, "Limit to
file types" restricts a scan to a comma-separated extension list, and
"Export results to CSV" saves a spreadsheet via the standard save panel.

5. EXTERNAL SERVICES
None. The app uses no external services, tools, or platforms: no data
providers, no authentication services, no payment processors, no AI
services, no analytics or crash reporting SDKs. It makes no network
connections of any kind. Hashing uses Apple's CryptoKit framework, and
all processing happens locally inside the macOS App Sandbox.

6. REGIONAL DIFFERENCES
None. The app functions identically in all regions and territories, with
no region-dependent features or content.

7. REGULATED INDUSTRIES / PROTECTED MATERIAL
Not applicable. The app does not operate in a regulated industry and
contains no third-party or protected material. All code and artwork are
the developer's own.
