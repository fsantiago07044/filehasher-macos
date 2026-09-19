# Working on FileHasher (macOS)

Repo layout, conventions, and the traps that have already bitten us once.
The Windows sibling lives in a separate repo (`filehasher`, its own `CLAUDE.md`);
output formats (sidecars, CSV, logs) are kept compatible between the two, and
since 2026-09-19 so is the scan **model**, though the **defaults** deliberately
differ. See "Parity with the Windows app" below.

- **Remotes: `origin` is a private GitLab that mirrors to GitHub.** The
  `github` remote exists in the clone but is not where work is pushed. **Push
  to `origin`.** `git remote -v` lists `github` first alphabetically, so do not
  truncate that output and conclude GitHub is the only remote. Run
  `git remote -v` for the actual URLs rather than hardcoding them here.
- Two shipping editions from one codebase: **FileHasher** (sandboxed, Mac App
  Store) and **FileHasher-Standalone** (Developer ID, notarized, self-updating
  via Sparkle). `FileHasherTests` is attached to the App Store target.

## Build and toolchain

- **Xcode lives on an external volume**, which macOS supports officially:
  `/Volumes/Storage_WD50_NVMe_SSD_2TB/Applications/Xcode.app` (16.4), with an
  alias at `/Applications/Xcode alias`. `xcode-select -p` still points at
  CommandLineTools, so a bare `xcodebuild` fails with "requires Xcode". **Do not
  run `xcode-select -s`**; it needs sudo. Set `DEVELOPER_DIR` per command:

  ```bash
  export DEVELOPER_DIR="/Volumes/Storage_WD50_NVMe_SSD_2TB/Applications/Xcode.app/Contents/Developer"
  ```

  DerivedData also lives on an external volume, separate from the one holding
  Xcode. Pass `-derivedDataPath` for throwaway builds so they never land there.
- **Compile-gate with `build-for-testing`, never plain `build`.** `xcodebuild
  build` compiles only the app target and **silently skips the test target**, so
  test-file changes go unchecked and "BUILD SUCCEEDED" says nothing about them:

  ```bash
  xcodebuild build-for-testing -project FileHasher.xcodeproj -scheme FileHasher \
    -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/fh-bft
  ```

  Verify the classes actually made it in, rather than trusting the exit code:

  ```bash
  nm -gU /tmp/fh-bft/Build/Products/Debug/FileHasher.app/Contents/PlugIns/FileHasherTests.xctest/Contents/MacOS/FileHasherTests \
    | grep -oE 'HashEngineTests|PreferencesTests|PathSeedTests' | sort -u
  ```

- **New Swift files must be wired into `project.pbxproj` by hand.** The project
  uses explicit `PBXFileReference`s with **no**
  `PBXFileSystemSynchronizedRootGroup`, so a new file is silently excluded from
  its target. Four entries are needed, mirroring an existing file with fresh
  24-hex ids: a `PBXBuildFile`, a `PBXFileReference`, the group's `children`
  entry, and the target's `Sources` phase entry.
- **Every build rewrites `project.pbxproj`**, renaming the Standalone target's
  `productReference` from `FileHasher-Standalone.app` to `FileHasher.app`. It is
  cosmetic and safe to discard: both targets set `PRODUCT_NAME = FileHasher` and
  are separated by `CONFIGURATION_BUILD_DIR` (`$(CONFIGURATION)-standalone`),
  which is why the release script collects `Release-standalone/FileHasher.app`.
  Check the diff before committing so a real change is not lost in the noise.

## Tests

- `FileHasherTests` holds `HashEngineTests` (enumeration, hashing, sidecars),
  `PreferencesTests` and `PathSeedTests`. **No `XCUIApplication` anywhere**:
  these are engine and model tests, so Fabian using the mouse and keyboard
  cannot disturb them, unlike the Windows FlaUI suite.
- The target is **app-hosted** (`TEST_HOST` is FileHasher.app), so running them
  launches the real app; its window appears briefly and may steal focus.
- **`xcodebuild test` does not work from the CLI here, cause unknown
  (2026-09-18).** It fails with *"Could not launch FileHasherTests ... The file
  FileHasher.app couldn't be opened because there is no such file"*, which is
  false: the bundle exists and `codesign --verify --deep --strict` passes.
  **Ruled out, do not re-chase:** the external volumes and DerivedData location
  (fails on internal paths too), code signing, provisioning
  (`-allowProvisioningUpdates` embedded no profile and changed nothing; the only
  profile on disk is a Mac Team **Store** profile, which is what release builds
  need), and `clean test`. Stripping the sandbox
  (`CODE_SIGN_ENTITLEMENTS="" ENABLE_APP_SANDBOX=NO`) worked **once** and never
  again, so do not present it as the fix. The leading untested hypothesis is
  TCC: Xcode may need Files and Folders > Removable Volumes or Full Disk Access,
  and the test runner runs in the background so it never triggers the prompt.
- Until that is solved: **compile-gate here, and ask Fabian to run the suite in
  Xcode.** Do not claim tests pass on the strength of a build.
- Anything touching preferences must use an injected `UserDefaults` suite, never
  `.standard`. `AppModel(defaults:)` exists for exactly this: the app-hosted
  tests run inside the real app and would otherwise read and overwrite Fabian's
  own preferences.

## Release

- `scripts/release-standalone.sh` is the Standalone path and **requires the tag
  to exist first**. It deliberately avoids `xcodebuild archive`/`-exportArchive`,
  which trips an Xcode bug on Sparkle's signed xcframework, in favour of a plain
  Release build plus manual inside-out Developer ID signing, then `notarytool`
  with the `filehasher-notary` keychain profile. Do not "modernise" it to
  archive-based export.
- The App Store edition ships separately; `docs/APP-STORE-SUBMISSION.md`,
  `docs/APP-STORE-LISTING.md` and `docs/APP-REVIEW-NOTES.md` cover it.
  `APP-REVIEW-NOTES.md` is a record of what was submitted for a past review, so
  correct it only where it describes the app as it is today.
- **UI changes invalidate the App Store screenshots** (the shot list in
  `docs/APP-STORE-LISTING.md`). Raise regenerating them rather than waiting to
  be asked. The Windows repo has the same obligation for the Microsoft Store and
  for UniGetUI.

## Parity with the Windows app

- **Same model, different defaults, on purpose.** Both apps take a subfolder
  **depth** (`HashOptions.maxDepth`: nil unlimited, 0 the chosen folder only, n
  levels) rather than a recursion boolean. This app defaults to **0**, Windows
  to **unlimited**, because that is what each has always done; changing either
  would silently alter what existing users' scans cover, and on this side it
  would mean hashing files through App Review that nobody asked for.
- The hash walk and the sidecar verifier **must** be given the same depth. A
  shallower verify than the run that wrote the sidecars reports `NO SIDECAR` for
  files the hash run never visited.
- **Preferences follow one rule:** if a control's enabled state depends on the
  target, its value describes that target rather than a standing preference, so
  it is not persisted. Nothing that writes files is persisted either. Here that
  leaves the algorithm and *Include file metadata*. Adding a field for the
  target path, the Subfolders depth, the file-type filter, or anything behind
  the sidecar or CSV gates should fail `PreferencesTests`.
- Differences that are deliberate, not drift: this app scans every file type by
  default with an optional typed extension list (Windows defaults to
  `.exe`/`.msi` with a checkbox); it saves preferences on change (Windows on
  close); `NSOpenPanel` cannot pre-select a file, so browse panels open at the
  parent folder; and there is no inner-MSI scan, which needs the Windows
  Installer database API.

## Style

- No em dashes in any text written for this repo (docs, UI strings, comments);
  use semicolons, commas, colons, or parentheses.
- The macOS app is published by **Fabian personally**, unlike the Windows app
  (FSP Productions, LLC). The support email subject convention is
  `FileHasher-macOS-<version>` and names the edition.
