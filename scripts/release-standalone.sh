#!/bin/zsh
# Release the Standalone (Sparkle) edition of FileHasher.
#
# Pipeline: archive (Developer ID) -> export -> notarize -> staple -> zip ->
# EdDSA-sign for Sparkle -> sha256 sidecars -> GitHub release -> appcast entry.
#
# Prerequisites (one-time, already provisioned):
#   - Developer ID Application certificate in the login keychain, issued by the
#     G2 authority (the original Developer ID Sub-CA expires 2027-02-01)
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

echo "==> Resolving Developer ID signing identity"
# Apple's original "Developer ID Certification Authority" expires 2027-02-01 and
# takes every certificate it issued with it, so a release must be signed by a
# certificate from the G2 authority. Both authorities issue certificates with
# the identical common name, and `codesign -s <name>` refuses an ambiguous
# match, so resolve to a SHA-1 hash and check the issuer rather than trusting
# the name. Already-released builds are unaffected: they carry a secure
# timestamp and a stapled notarization ticket, which is what keeps them
# installable after the authority expires.
DEVID_CN="Developer ID Application: Fabian Santiago (49KP5XUP9W)"
CERT_DUMP="$WORK/devid-certs.pem"
security find-certificate -a -Z -c "$DEVID_CN" -p > "$CERT_DUMP"

IDENTITY=""
G2_EXPIRY=""
G2_EPOCH=0
OLD_CA_EXPIRY=""
SHA1=""
PEM=""
while IFS= read -r line; do
  case "$line" in
    "SHA-1 hash: "*)
      SHA1="${line#SHA-1 hash: }"
      PEM=""
      ;;
    "-----BEGIN CERTIFICATE-----")
      PEM="$line"
      ;;
    "-----END CERTIFICATE-----")
      PEM="$PEM
$line"
      if print -r -- "$PEM" | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
        ISSUER=$(print -r -- "$PEM" | openssl x509 -noout -issuer 2>/dev/null)
        ENDS=$(print -r -- "$PEM" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        case "$ISSUER" in
          *"OU=G2"*|*"OU = G2"*)
            # Renewal leaves two valid G2 certificates overlapping for a while;
            # take the one that lasts longest.
            EPOCH=$(date -j -f "%b %e %T %Y %Z" "$ENDS" "+%s" 2>/dev/null || echo 0)
            if [ "$EPOCH" -ge "$G2_EPOCH" ]; then
              IDENTITY="$SHA1"; G2_EXPIRY="$ENDS"; G2_EPOCH="$EPOCH"
            fi
            ;;
          *) OLD_CA_EXPIRY="$ENDS" ;;
        esac
      fi
      PEM=""
      ;;
    *)
      [ -n "$PEM" ] && PEM="$PEM
$line"
      ;;
  esac
done < "$CERT_DUMP"

if [ -z "$IDENTITY" ]; then
  echo "ERROR: no valid Developer ID Application certificate from the G2 authority." >&2
  [ -n "$OLD_CA_EXPIRY" ] && \
    echo "       The one in the keychain is from the original Sub-CA and dies $OLD_CA_EXPIRY." >&2
  cat >&2 <<'MSG'

       Create a replacement before signing anything new, using the WEB PORTAL:
         developer.apple.com > Certificates, Identifiers & Profiles > +
           > Developer ID Application
           > choose the "G2 Sub-CA" intermediate, then upload a CSR from
             Keychain Access > Certificate Assistant > Request a Certificate
             From a Certificate Authority (saved to disk)

       Do NOT use Xcode > Settings > Accounts > Manage Certificates for this.
       Xcode 16.4 never asks which intermediate to use and silently issues from
       the dying authority (confirmed 2026-10-21, one wasted certificate slot).

       Leave the old certificates in the keychain; do not revoke them.
MSG
  exit 1
fi
echo "    $IDENTITY (G2 authority, expires $G2_EXPIRY)"

echo "==> Validating the Standalone entitlements"
# codesign parses entitlements with AMFI's stricter XML reader, which rejects
# things `plutil -lint` accepts. A double hyphen inside an XML comment is
# illegal XML and cost a whole build on 1.1.1: the failure surfaced only after
# the Release build, as "AMFIUnserializeXML: syntax error near line N".
ENT="$REPO_ROOT/FileHasher/FileHasher-Standalone.entitlements"
xmllint --noout "$ENT" || { echo "ERROR: $ENT is not well-formed XML" >&2; exit 1; }
plutil -lint "$ENT" >/dev/null || { echo "ERROR: $ENT is not a valid plist" >&2; exit 1; }
# prove codesign itself accepts it, against a throwaway copy of a system binary
ENTPROBE="$WORK/entitlements-probe"
cp /bin/echo "$ENTPROBE" && xattr -cr "$ENTPROBE"
codesign -f -s "$IDENTITY" -o runtime --entitlements "$ENT" "$ENTPROBE" 2>&1   || { echo "ERROR: codesign rejected $ENT (see the AMFI message above)" >&2; exit 1; }
rm -f "$ENTPROBE"
echo "    entitlements parse and sign cleanly"

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
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Installer.xpc"
[ -f "$FW/Versions/B/Autoupdate" ] && codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Autoupdate"
[ -d "$FW/Versions/B/Updater.app" ] && codesign -f -s "$IDENTITY" -o runtime "$FW/Versions/B/Updater.app"
codesign -f -s "$IDENTITY" -o runtime "$FW"
codesign -f -s "$IDENTITY" -o runtime \
  --entitlements "$REPO_ROOT/FileHasher/FileHasher-Standalone.entitlements" "$APP"
codesign --verify --strict --deep "$APP" && echo "    deep signature verified"
# Capture once and test in the shell. `cmd | grep -q` under `set -o pipefail`
# is a race: grep exits at the first match, cmd dies of SIGPIPE, and pipefail
# reports the pipeline as failed even though the match succeeded. That falsely
# failed the 1.1.1 release after a clean sign, and passed on 1.1.0, which is
# exactly how an intermittent bug behaves.
SIGINFO="$(codesign -dvvv "$APP" 2>&1)"
print -r -- "$SIGINFO" | grep -E "^Authority=Developer ID" || true
# A secure timestamp is what lets a signature outlive its issuing authority,
# and notarization rejects submissions without one. Catch it here, not there.
case "$SIGINFO" in
  *"Timestamp="*) ;;
  *) echo "ERROR: signature carries no secure timestamp" >&2; exit 1 ;;
esac

echo "==> Verifying universal binary and Sparkle presence"
ARCHS_OUT="$(lipo -archs "$APP/Contents/MacOS/FileHasher")"
case "$ARCHS_OUT" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *) echo "not universal (got: $ARCHS_OUT)" >&2; exit 1 ;;
esac
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
# `xattr -cr` acts on what a symlink POINTS AT, never on the link itself, so
# every symlink in Sparkle.framework kept its com.apple.provenance attribute.
# ditto stores those in the archive; Archive Utility, which is what Finder uses,
# cannot set xattrs on a symlink and writes AppleDouble "._Name" sidecars beside
# them instead. Those land in the framework's ROOT, which is sealed, so the app
# a normal user extracts is rejected: "unsealed contents present in the root
# directory of an embedded framework". The zip verifies perfectly if you extract
# it with ditto, which is why 1.1.1 shipped broken. -s acts on the link itself.
find "$APP" -type l -print0 | xargs -0 xattr -c -s 2>/dev/null || true
LINKX=$(find "$APP" -type l -exec xattr -s -l {} \; 2>/dev/null | wc -l | tr -d ' ')
[ "$LINKX" = "0" ] || { echo "ERROR: $LINKX xattr(s) still on symlinks; the zip would break Finder extraction" >&2; exit 1; }
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying the zip the way a USER opens it (Archive Utility, not ditto)"
# The whole point: ditto round-trips its own archives correctly, so testing with
# ditto proves nothing about what a user gets. Extract with Archive Utility and
# assess the result, or this class of packaging bug ships again.
AUDIR="$WORK/finder-extract"
rm -rf "$AUDIR" && mkdir -p "$AUDIR"
ditto "$ZIP" "$AUDIR/$(basename "$ZIP")"
open -W -a "/System/Library/CoreServices/Applications/Archive Utility.app" "$AUDIR/$(basename "$ZIP")"
AUAPP="$AUDIR/FileHasher.app"
[ -d "$AUAPP" ] || { echo "ERROR: Archive Utility produced no FileHasher.app in $AUDIR" >&2; exit 1; }
STRAY=$(find "$AUAPP" -name "._*" | wc -l | tr -d ' ')
[ "$STRAY" = "0" ] || {
  echo "ERROR: Archive Utility extraction left $STRAY AppleDouble file(s); the bundle seal is broken:" >&2
  find "$AUAPP" -name "._*" >&2
  exit 1; }
codesign --verify --strict --deep "$AUAPP" \
  || { echo "ERROR: the Finder-extracted app fails codesign verification" >&2; exit 1; }
spctl --assess --type execute "$AUAPP" \
  || { echo "ERROR: the Finder-extracted app is rejected by Gatekeeper" >&2; exit 1; }
echo "    Finder-extracted app verifies and Gatekeeper accepts it"
rm -rf "$AUDIR"

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
# A /start/,/end/ range in awk tests the end pattern on the START line too, and
# the heading "## 1.1.1, released ..." matches /^## [0-9]/ itself, so the range
# collapsed to that one line and every release since the Standalone debut got
# the "See CHANGELOG.md." fallback instead of its notes. Walk it with a flag.
NOTES=$(awk -v v="$VERSION" '
  !inb && $0 ~ "^## " v "([,.[:space:]]|$)" { inb=1; next }
  inb && /^## [0-9]/ { exit }
  inb { print }
' CHANGELOG.md)
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
