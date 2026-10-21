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

Everything up to the submission itself runs from the command line. Only
creating the version record and pressing Submit for Review is web-only.

**Check what is already uploaded before building anything.** Two people, or a
person and an agent, can each upload the same release; see the build-number
warning below for why that is worse than it sounds.

```bash
export DEVELOPER_DIR="/Volumes/Storage_WD50_NVMe_SSD_2TB/Applications/Xcode.app/Contents/Developer"

# 1. archive the App Store target (scheme FileHasher, never FileHasher-Standalone)
xcodebuild archive -project FileHasher.xcodeproj -scheme FileHasher \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath /tmp/fh-archive/FileHasher.xcarchive

# 2. export a signed .pkg. ExportOptions.plist needs method app-store-connect,
#    teamID 49KP5XUP9W, destination export, signingStyle automatic.
xcodebuild -exportArchive \
  -archivePath /tmp/fh-archive/FileHasher.xcarchive \
  -exportOptionsPlist /tmp/fh-export/ExportOptions.plist \
  -exportPath /tmp/fh-export/out \
  -allowProvisioningUpdates

# 3. validate, then upload
xcrun altool --validate-app -f /tmp/fh-export/out/FileHasher.pkg -t macos \
  --apiKey WU67FA9RHB --apiIssuer "$ISSUER"
xcrun altool --upload-app   -f /tmp/fh-export/out/FileHasher.pkg -t macos \
  --apiKey WU67FA9RHB --apiIssuer "$ISSUER"
```

- **`-exportArchive` silently increments the build number.** If the build number
  in `project.yml` is already uploaded, Xcode bumps it rather than failing, and
  says so only in `DistributionSummary.plist` (`buildNumber`). On 2026-10-21 that
  turned a build 5 export into an uploaded build 6, leaving a build in App Store
  Connect that no commit produces. **Read `buildNumber` out of
  `DistributionSummary.plist` after every export** and refuse to ship one that
  does not match `CURRENT_PROJECT_VERSION`, because the tag is the only record of
  what the source was.
- **The API key lives in Bitwarden**, item `claude_code_notary ASC developer api
  key`: Key ID `WU67FA9RHB`, the Issuer ID in its notes, and the `.p8` as an
  attachment. `altool` reads it from `~/.appstoreconnect/private_keys/`. Write it
  there mode 600 and shred it afterwards; it is not on disk by default and should
  not be left there. Use the stored Bitwarden session, never a fresh `bw unlock`.
- **Expired distribution certificates are not a blocker.** The Apple Distribution
  and 3rd Party Mac Developer Installer certificates in the keychain expired in
  2021 and 2025, and signing still works: `-allowProvisioningUpdates` signs with a
  **cloud managed** certificate that never persists as a local identity. So
  `security find-identity` showing nothing usable proves nothing. This is also why
  the keychain cannot explain how earlier releases were signed.
- After processing (~15 min), attach the build to a version in App Store Connect,
  fill the listing, and Submit for Review.
- **The app is universal** (`ARCHS: "$(ARCHS_STANDARD)"`), so both Apple Silicon
  and Intel run natively; Rosetta is not involved.

### Checking state before and after, without the web UI

The App Store Connect API answers "what is already uploaded" with an ES256 JWT
signed by the same `.p8`:

```text
GET /v1/apps?filter[bundleId]=com.fabianasantiago.FileHasher   -> app id
GET /v1/builds?filter[app]=<id>&limit=8&sort=-uploadedDate     -> build numbers,
                                                                  upload times,
                                                                  processingState
```

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
