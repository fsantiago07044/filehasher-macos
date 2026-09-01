#!/bin/zsh
# Release the Standalone (Sparkle) edition of FileHasher.
#
# Pipeline: archive (Developer ID) -> export -> notarize -> staple -> zip ->
# EdDSA-sign for Sparkle -> sha256 sidecars -> GitHub release -> appcast entry.
#
# Prerequisites (one-time, already provisioned):
#   - Developer ID Application certificate in the login keychain
#   - notarytool keychain profile:  filehasher-notary
#   - Sparkle EdDSA private key in the login keychain (backup in Bitwarden:
#     "FileHasher Sparkle EdDSA private key")
#   - Sparkle CLI tools (sign_update) available; pass SPARKLE_BIN or keep the
#     default path below
#   - gh CLI authenticated as fsantiago07044
#
# Usage:  scripts/release-standalone.sh
#   Run from the repo root on a clean, tagged checkout. Reads the version from
#   project.yml. Writes work products to ./release-work/ (gitignored).
#
# NO SECRETS live in this script or in the repo: signing keys stay in the
# keychain, notary credentials in the notarytool profile.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SPARKLE_BIN="${SPARKLE_BIN:-$HOME/.local/sparkle/bin}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/Storage_WD50_NVMe_SSD_2TB/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
TAG="v${VERSION}"
# Work dir must live OUTSIDE ~/Documents: that tree is file-provider synced,
# and the sync stamps every written file with FinderInfo xattrs, which
# codesign rejects ("resource fork ... detritus not allowed").
WORK="${TMPDIR:-/tmp}/filehasher-release-work"
ARCHIVE="$WORK/FileHasher-Standalone.xcarchive"
EXPORT_DIR="$WORK/export"
ZIP="$WORK/FileHasher-${VERSION}.zip"

echo "==> Releasing FileHasher Standalone ${VERSION} (build ${BUILD}), tag ${TAG}"
echo "==> Work dir: $WORK"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree not clean; commit or stash first." >&2
  exit 1
fi
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "ERROR: tag $TAG does not exist; tag the release first (git tag -s $TAG)." >&2
  exit 1
fi

rm -rf "$WORK" && mkdir -p "$WORK"

echo "==> Archiving (Release, universal, hermetic DerivedData)"
# A dedicated DerivedData per release avoids the stale-SPM-signature quirk
# ("Sparkle.xcframework-macos.signature ... already exists" -> malformed
# archive) and makes every release build from a clean slate.
xcodebuild -scheme FileHasher-Standalone -configuration Release archive \
  -archivePath "$ARCHIVE" -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates > "$WORK/archive.log" 2>&1 || {
    tail -20 "$WORK/archive.log" >&2; echo "archive failed" >&2; exit 1; }
grep -q "\*\* ARCHIVE SUCCEEDED \*\*" "$WORK/archive.log" || {
    tail -20 "$WORK/archive.log" >&2; echo "archive did not succeed" >&2; exit 1; }
[ -f "$ARCHIVE/Info.plist" ] || { echo "archive malformed" >&2; exit 1; }

echo "==> Exporting with Developer ID signing"
cat > "$WORK/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>49KP5XUP9W</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/export-options.plist" \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates > "$WORK/export.log" 2>&1 || {
    tail -20 "$WORK/export.log" >&2; echo "export failed" >&2; exit 1; }
tail -3 "$WORK/export.log" 
APP="$EXPORT_DIR/FileHasher.app"
[ -d "$APP" ] || { echo "export failed" >&2; exit 1; }

echo "==> Verifying universal binary and Sparkle presence"
lipo -archs "$APP/Contents/MacOS/FileHasher" | grep -q "x86_64 arm64" || { echo "not universal" >&2; exit 1; }
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || { echo "Sparkle missing from bundle" >&2; exit 1; }

# Belt and braces: strip any extended attributes before signing artifacts move on
xattr -cr "$APP"

echo "==> Notarizing (this waits for Apple)"
ditto -c -k --keepParent "$APP" "$WORK/notarize-upload.zip"
xcrun notarytool submit "$WORK/notarize-upload.zip" \
  --keychain-profile filehasher-notary --wait | tail -3

echo "==> Stapling ticket"
xcrun stapler staple "$APP" | tail -1
spctl --assess --type execute -v "$APP" 2>&1 | tail -1

echo "==> Building distribution zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Sparkle EdDSA signature"
SIGN_OUT=$("$SPARKLE_BIN/sign_update" "$ZIP")
echo "    $SIGN_OUT"
ED_SIG=$(echo "$SIGN_OUT" | grep -oE 'sparkle:edSignature="[^"]+"' | cut -d'"' -f2)
ZIP_LEN=$(stat -f%z "$ZIP")

echo "==> sha256 sidecars (FileHasher's own format)"
for f in "$ZIP"; do
  HASH=$(shasum -a 256 "$f" | awk '{print toupper($1)}')
  printf '%s *%s\n' "$HASH" "$(basename "$f")" > "$f.sha256"
done

echo "==> GitHub release"
NOTES=$(awk "/^## ${VERSION}/,/^## [0-9]/" CHANGELOG.md | sed '$d' | tail -n +2)
gh release create "$TAG" \
  --repo fsantiago07044/filehasher-macos \
  --title "FileHasher ${VERSION}" \
  --notes "${NOTES:-See CHANGELOG.md.}" \
  "$ZIP" "$ZIP.sha256" 2>/dev/null \
  || gh release upload "$TAG" --repo fsantiago07044/filehasher-macos --clobber "$ZIP" "$ZIP.sha256"

DOWNLOAD_URL="https://github.com/fsantiago07044/filehasher-macos/releases/download/${TAG}/FileHasher-${VERSION}.zip"

echo "==> Appcast entry"
DATE_RFC=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")
cat <<ITEM

Add this <item> to appcast.xml, commit, and push (the GitLab->GitHub mirror
publishes it; Sparkle clients read the raw GitHub URL):

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${DATE_RFC}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>https://fabianasantiago.com/filehasher/</link>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${ZIP_LEN}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}" />
    </item>
ITEM

echo "==> Done. Remember the release ritual: dated CHANGELOG heading, appcast committed, website updated."
