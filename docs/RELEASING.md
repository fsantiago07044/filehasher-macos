# Releasing FileHasher for macOS

Two editions ship from one codebase and one version number:

| Edition | Channel | Signing | Updates |
| --- | --- | --- | --- |
| Mac App Store | App Store Connect | Apple Distribution (automatic via Xcode) | The store updates it |
| Standalone | GitHub Releases | Developer ID + notarization | Sparkle, reading `appcast.xml` from this repo's raw GitHub URL |

## The ritual (every release)

0. Confirm a Developer ID certificate from the **G2** authority is in the
   keychain (see below). The release script checks this and stops if not.
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
- Developer ID and Apple Distribution certificates: login keychain. The
  Developer ID one must come from the **G2** authority; see below.

## Developer ID certificate authority (G2)

Apple's original `Developer ID Certification Authority` expires **2027-02-01**,
and every certificate it issued stops working that day regardless of the date
printed on the certificate itself. Apple notified the account on 2026-10-01.

What this does and does not affect here:

- **Already-released Standalone builds are safe.** 1.0.2 and earlier were signed
  with a secure timestamp and ship a stapled notarization ticket, which is what
  lets a signature outlive its issuing authority. Nothing needs re-signing and
  nothing needs re-releasing.
- **No installer packages are distributed.** The `.pkg` deadline in Apple's
  notice does not apply; the Standalone edition ships as a notarized `.zip`.
- **The App Store edition is untouched.** It signs with Apple Distribution,
  issued by a different authority.
- **Standalone releases need a G2 certificate.** Provisioned 2026-10-21: SHA-1
  `2D970B18FB9D8A5EBD9FD2996C6254AFFE948CFA`, expiring **2027-11-20**. G2 leaf
  certificates expire annually rather than every five years, so this is now a
  yearly errand.
- **Renew through the web portal, never through Xcode.** developer.apple.com >
  Certificates, Identifiers & Profiles > + > Developer ID Application, choose
  the **G2 Sub-CA** intermediate, then upload a CSR from Keychain Access >
  Certificate Assistant > Request a Certificate From a Certificate Authority
  (saved to disk). **Xcode > Settings > Accounts > Manage Certificates never
  asks which intermediate to use**: on 16.4 it silently issued from the dying
  authority, which cost a certificate slot on 2026-10-21. The portal is the only
  route that exposes the choice.
- **Leave the old certificates in the keychain and do not revoke them.**
  `487FFC51...` signed the shipped 1.0.2; revoking it is the one action that
  could break software already installed.

`scripts/release-standalone.sh` enforces this. It resolves the signing identity
by SHA-1 hash rather than by name, refuses to build if the only valid Developer
ID certificate is from the old authority, and asserts that the finished
signature carries a secure timestamp. Resolving by hash also sidesteps a
`codesign` failure that would otherwise appear the moment both certificates are
valid at once: they share a common name, and `codesign -s <name>` rejects an
ambiguous match.

Sparkle updates survive the change. The app's designated requirement pins the
team (`subject.OU = 49KP5XUP9W`) and the Apple marker OID
`1.2.840.113635.100.6.2.6`, which the G2 intermediate also carries, so an update
signed by the new certificate validates against clients running the old build.

## Channel guardrails

- The App Store target must never contain Sparkle: no package dependency, no
  `SUFeedURL`, no update code outside `#if CHANNEL_STANDALONE`.
- Both targets produce `FileHasher.app`; they build into separate product
  directories (`Release` vs `Release-standalone`) so local bundles can't mix.
  Archives were never at risk.
- The standalone entitlements add only `com.apple.security.network.client`.
  Everything else stays identical between editions, including the sandbox.
