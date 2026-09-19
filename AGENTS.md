# Agent instructions

The conventions, toolchain details and known traps for this repo live in
**[CLAUDE.md](CLAUDE.md)**. Read it before making changes; it is written for any
agent or contributor, not just Claude, and it exists because most of what is in
it cost someone a wasted afternoon to discover.

Points that catch people out fastest:

- **Xcode is on an external volume.** Set `DEVELOPER_DIR` per command; a bare
  `xcodebuild` fails with "requires Xcode", and `xcode-select -s` needs sudo.
- **Compile-gate with `build-for-testing`, not `build`.** Plain `build` silently
  skips the test target, so "BUILD SUCCEEDED" says nothing about test code.
- **New Swift files need four hand-written `project.pbxproj` entries**, or they
  are excluded from their target with no warning.
- **`xcodebuild test` cannot launch the app host here**, cause unknown. CLAUDE.md
  lists what has already been ruled out; ask Fabian to run the suite in Xcode.
- **Push to `origin`** (a private GitLab that mirrors to GitHub). The `github`
  remote sorts first in `git remote -v`; do not mistake it for the only one.
- **No em dashes** in anything written for this repo.

The Windows sibling (`filehasher`) has its own `CLAUDE.md`; output formats and
the scan model are kept compatible between the two, while the defaults
deliberately differ.
