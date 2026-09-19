#!/bin/bash
# Regenerates the three Mac App Store screenshots in docs/app-store/ at the
# 1440x900 Apple accepts. Filenames are referenced by docs/APP-STORE-LISTING.md.
#
# Requires: the driving process to have Accessibility permission (System
# Settings > Privacy & Security > Accessibility). The app is driven through
# System Events because it is SwiftUI, where `entire contents of window 1`
# returns nothing and the tree has to be walked by index.
#
# Two things that are not obvious and cost time the first run:
#
#  1. The target folder MUST be granted through the Browse Folder panel, not
#     typed. ~/Downloads is TCC-protected, so a typed path yields "No matching
#     files found" even though the sandbox has a read-only exception for /.
#     The panel grant also gives the write access the sidecars need.
#  2. Region capture picks up the Dock, which floats above windows. The window
#     is positioned clear of it rather than hiding the Dock, which would be a
#     change to the user's system.
set -euo pipefail

APP="${1:-/tmp/fh-shots/Build/Products/Debug/FileHasher.app}"
DEMO="${2:-$HOME/Downloads/FileHasher-Demo}"
OUT="${3:-$(cd "$(dirname "$0")/.." && pwd)}"
WX=70; WY=25; WW=1440; WH=900     # window origin clear of a left-hand Dock

say() { printf '==> %s\n' "$1"; }

say "demo tree: $DEMO"
rm -rf "$DEMO"; mkdir -p "$DEMO/Documents" "$DEMO/Archives"
python3 - "$DEMO" <<'PY'
import os, random, sys
d = sys.argv[1]
spec = [('disk-image.dmg',204800), ('app-installer.pkg',88211), ('readme.txt',11),
        ('Documents/notes.txt',9640), ('Documents/quarterly-report.pdf',22050),
        ('Archives/photos-2026.zip',48211), ('Archives/project-backup.tar.gz',131072)]
r = random.Random(20260817)          # fixed seed: reproducible contents
for rel, size in spec:
    with open(os.path.join(d, rel), 'wb') as f:
        f.write(r.randbytes(size))
PY

say "launching $APP"
killall FileHasher 2>/dev/null || true
sleep 1
open "$APP"
sleep 4

drive() { osascript >/dev/null 2>&1 <<OSA
tell application "System Events" to tell process "FileHasher"
  set frontmost to true
  delay 0.3
  set g to UI element 1 of window 1
  $1
end tell
OSA
}
dismiss() { osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events" to tell process "FileHasher"
  if (count of windows) > 1 then
    click button 1 of window 1
    delay 1
  end if
end tell
OSA
}
status() { osascript 2>/dev/null <<'OSA'
tell application "System Events" to tell process "FileHasher" to return (value of UI element 9 of UI element 1 of window 1) as text
OSA
}
shot() { sleep 1; screencapture -o -x -R "$WX,$WY,$WW,$WH" "$OUT/$1"; say "captured $1"; }

# Grant folder access through the panel (see note 1).
say "granting folder access via the open panel"
drive "click UI element 4 of UI element 1 of g
  delay 1.5
  keystroke \"g\" using {command down, shift down}
  delay 0.8
  keystroke \"$DEMO\"
  delay 0.5
  keystroke return
  delay 1.2
  keystroke return"
sleep 2

say "options: all subfolders, metadata, sidecars"
drive "set tgt to UI element 1 of g
  set opt to UI element 3 of g
  click pop up button 1 of tgt
  delay 0.6
  click menu item \"All subfolders\" of menu 1 of pop up button 1 of tgt
  delay 0.4
  if (value of checkbox 1 of opt) as integer is 0 then click checkbox 1 of opt
  if (value of checkbox 2 of opt) as integer is 0 then click checkbox 2 of opt"

say "shot 1: hash run"
drive "click UI element 7 of g"
sleep 7; dismiss
drive "set position of window 1 to {$WX, $WY}
  set size of window 1 to {$WW, $WH}"
say "  $(status)"
shot "shot1-hash-1440x900.png"

say "shot 2: verification, all OK"
drive "click UI element 4 of g
  delay 0.5
  click UI element 5 of g"
sleep 7; dismiss
say "  $(status)"
shot "shot2-verify-ok-1440x900.png"

say "shot 3: one file tampered"
python3 - "$DEMO/Documents/notes.txt" <<'PY'
import sys
# Flip one byte in place: the size stays identical, so only the hash changes
# and the Size column still matches the other shots.
p = sys.argv[1]
with open(p, 'r+b') as f:
    b = f.read(1); f.seek(0); f.write(bytes([(b[0] + 1) % 256]))
PY
drive "click UI element 4 of g
  delay 0.5
  click UI element 5 of g"
sleep 7; dismiss
say "  $(status)"
shot "shot3-verify-mismatch-1440x900.png"

say "done; review $OUT/shot*.png before committing"
