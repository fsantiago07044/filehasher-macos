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

echo "==> Building (Release, universal, hermetic DerivedData)"
# We deliberately do NOT use xcodebuild archive/-exportArchive here: archiving
# an app that embeds a signed binary xcframework (Sparkle via SPM) trips an
# Xcode bug ("Sparkle.xcframework-macos.signature couldn't be copied to
# Signatures ... File exists") even with pristine DerivedData. A plain Release
# build plus manual inside-out Developer ID signing is the documented Sparkle
# distribution path and is fully deterministic.
xcodebuild -scheme FileHasher-Standalone -configuration Release build \
  -derivedDataPath "$WORK/DerivedData" > "$WORK/build.log" 2>&1 || {
    tail -20 "$WORK/build.log" >&2; echo "build failed" >&2; exit 1; }
grep -q "BUILD SUCCEEDED" "$WORK/build.log" || {
    tail -20 "$WORK/build.log" >&2; echo "build did not succeed" >&2; exit 1; }

APP_SRC="$WORK/DerivedData/Build/Products/Release-standalone/FileHasher.app"
[ -d "$APP_SRC" ] || { echo "built app not found at $APP_SRC" >&2; exit 1; }
mkdir -p "$EXPORT_DIR"
APP="$EXPORT_DIR/FileHasher.app"
rm -rf "$APP" && ditto "$APP_SRC" "$APP"
xattr -cr "$APP"

echo "==> Signing with Developer ID (inside-out)"
IDENTITY="Developer ID Application: Fabian Santiago (49KP5XUP9W)"
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Installer.xpc"
[ -f "$FW/Versions/B/Autoupdate" ] && codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Autoupdate"
[ -d "$FW/Versions/B/Updater.app" ] && codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Updater.app"
codesign -f -s "$IDENTITY" -o runtime "$FW"
codesign -f -s "$IDENTITY" -o runtime \
  --entitlements "$REPO_ROOT/FileHasher/FileHasher-Standalone.entitlements" "$APP"
codesign --verify --strict --deep "$APP" && echo "    deep signature verified"
codesign -dv "$APP" 2>&1 | grep "Authority=Developer ID Application" | head -1

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
