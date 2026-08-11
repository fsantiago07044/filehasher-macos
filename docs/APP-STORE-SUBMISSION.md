# Getting FileHasher onto the Mac App Store

A working checklist for taking this repo's app from local build to App Store listing.
Account: individual Apple Developer Program membership, Team ID **49KP5XUP9W**
(the `547MPYTGC2` string in certificate names is the Apple ID's personal identifier,
not the team — don't use it in build settings).

## 1. Certificates — what you actually need

You do **not** create App Store certificates by hand. With automatic signing
(already configured in `project.yml`), Xcode requests them for you:

| Certificate | Purpose | When it appears |
| --- | --- | --- |
| Apple Development | Local dev/run builds | Already in your keychain |
| Apple Distribution | Signs the .app for App Store upload | Created by Xcode during first Archive → Distribute |
| Mac Installer Distribution | Signs the .pkg wrapper the store requires | Same — created automatically |
| Developer ID Application / Installer | Only for distribution OUTSIDE the store (notarized direct downloads) | Skip unless wanted later |

Prerequisite: be signed into Xcode → Settings → Accounts with the Apple ID that owns
the paid membership. You can pre-create the two distribution certs there via
"Manage Certificates… → +" if you prefer, but Distribute App will do it anyway.

## 2. One-time setup at developer.apple.com / App Store Connect

1. **Register the bundle ID** `com.fabianasantiago.FileHasher`
   (Certificates, Identifiers & Profiles → Identifiers → + → App IDs → macOS).
   Automatic signing can also register it on first archive.
2. **Create the app record** (App Store Connect → Apps → +):
   - Platform: macOS. Bundle ID: the one above. SKU: e.g. `filehasher-macos`.
   - **Name**: "FileHasher" must be globally unique on the App Store. If taken, use a
     variant for the *store listing only* (e.g. "FileHasher — Checksum Utility");
     the app on disk stays `FileHasher.app`.
3. **Agreements, Tax, and Banking**: accept the Paid/Free Applications agreement.
   Even for a free app the Free Apps agreement must be active.

## 3. Listing assets you must provide

- **Privacy policy URL** (required, even with no data collection). A one-paragraph
  static page on any domain you own works: "FileHasher does not collect, store, or
  transmit any personal data. All hashing happens locally on your Mac."
- **Support URL** (required) — a page with a contact method.
- **App Privacy questionnaire** in App Store Connect → answer "Data Not Collected".
- **Screenshots**: at least one, 1280×800 / 1440×900 / 2560×1600 / 2880×1800.
  Plain window screenshots (⌘⇧4 + Space) at a standard size are fine.
- **Description, keywords, category** (Utilities), **age rating** (4+, nothing applies).
- **Export compliance**: hashing is not encryption — `ITSAppUsesNonExemptEncryption`
  is already `false` in the Info.plist, so no documentation is needed.
- **Icon note**: the current icon is reused from the Windows app (full-bleed square).
  macOS convention is a rounded-rect with margins; review rarely rejects for this,
  but a mac-styled 1024px master is a nice-to-have before submission.

## 4. Build & submit

```text
Xcode → Product → Archive          (Release, x86_64)
Organizer → Distribute App → App Store Connect → Upload
```

- First upload will prompt to create the distribution certificates — allow it.
- After processing (~15 min), attach the build to a version in App Store Connect,
  fill the listing, and Submit for Review.
- Intel-only is accepted by the store; Apple Silicon Macs run it under Rosetta.
  Expect a reviewer note at most. Going universal later is a normal app update
  (`ARCHS: "$(ARCHS_STANDARD)"` in project.yml).

## 5. Sandbox facts relevant to review

- App Sandbox is ON (required) with only `files.user-selected.read-write` — minimal
  entitlements make review easy.
- The parent-folder access prompt (sidecar next to a single selected file) is standard
  powerbox usage; no special justification needed.

## 6. Optional, later

- **TestFlight for Mac**: upload a build, test on other Macs before release.
- **Notarized direct download** (outside the store): needs Developer ID certs and
  `xcrun notarytool` — say the word and it can be wired into CI like the Windows
  repo's signing pipeline.
