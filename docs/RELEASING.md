# Releasing FileHasher for macOS

Two editions ship from one codebase and one version number:

| Edition | Channel | Signing | Updates |
| --- | --- | --- | --- |
| Mac App Store | App Store Connect | Apple Distribution (automatic via Xcode) | The store updates it |
| Standalone | GitHub Releases | Developer ID + notarization | Sparkle, reading `appcast.xml` from this repo's raw GitHub URL |

## The ritual (every release)

1. Finalize `CHANGELOG.md`: dated heading naming the channels, all changes listed.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`,
   run `xcodegen generate`, commit.
3. Run the tests on both architectures (Intel mini natively; Apple Silicon via
   a rental if available).
4. Tag: `git tag -s vX.Y.Z` and push with tags. The GitLab push mirror carries
   everything to GitHub automatically.
5. **App Store edition**: archive scheme `FileHasher`, export with method
   `app-store-connect` (destination upload), then attach the build and submit
   in App Store Connect.
6. **Standalone edition**: `scripts/release-standalone.sh` does everything
   (archive, Developer ID export, notarize, staple, zip, Sparkle EdDSA
   signature, sha256 sidecars, GitHub release) and prints the appcast `<item>`.
7. Paste that `<item>` into `appcast.xml`, commit, push. The mirror publishes
   it; Sparkle clients worldwide see the update within their check interval.
8. Update the website and write the announcement post if warranted.

## Secrets map (nothing in this repo)

- Sparkle EdDSA private key: login keychain + Bitwarden
  ("FileHasher Sparkle EdDSA private key"). The public half is committed in
  `project.yml` (`SUPublicEDKey`); that is intentional.
- Notarization: `notarytool` keychain profile `filehasher-notary`, created from
  the ASC API key in Bitwarden ("claude_code_notary ASC developer api key").
- Developer ID and Apple Distribution certificates: login keychain.

## Channel guardrails

- The App Store target must never contain Sparkle: no package dependency, no
  `SUFeedURL`, no update code outside `#if CHANNEL_STANDALONE`.
- Both targets produce `FileHasher.app`; they build into separate product
  directories (`Release` vs `Release-standalone`) so local bundles can't mix.
  Archives were never at risk.
- The standalone entitlements add only `com.apple.security.network.client`.
  Everything else stays identical between editions, including the sandbox.
