# Releasing Swash

Swash is released by GitHub Actions ([`.github/workflows/release.yml`](../.github/workflows/release.yml)). When a push to `main` includes pending changesets (or the workflow is run by hand), it:

1. Imports Apple code-signing certificates from repository secrets, if configured, or falls back to ad-hoc signing.
2. Builds and signs the universal (Apple silicon and Intel) `.app`.
3. Packages it as a `.dmg` disk image and a `.zip` archive.
4. Versions the app from the pending changesets and writes the changelog.
5. Publishes a GitHub Release with the assets attached, and updates the Sparkle `appcast.xml` feed that the app checks for updates.

## Code signing is optional

By default, builds are ad-hoc signed (`CODE_SIGN_IDENTITY="-"`) and need no certificate. If `MACOS_CERTIFICATE` is not set in the repository secrets, the workflow makes ad-hoc builds.

To sign and notarize builds with an Apple Developer account:

1. Export your **Developer ID Application** certificate from Keychain Access as a `.p12` file.
2. Convert it to Base64: `base64 -i Certificate.p12 | pbcopy`.
3. Add these repository secrets under **Settings › Secrets and variables › Actions**:
   - `MACOS_CERTIFICATE`: the Base64 string of your `.p12` certificate.
   - `MACOS_CERTIFICATE_PWD`: the password for the `.p12` file (leave empty if it has none).
   - `KEYCHAIN_PASSWORD`: any temporary password for the CI keychain.
   - `CODE_SIGN_IDENTITY` *(optional)*: the certificate name (detected automatically if omitted).
   - `NOTARIZATION_APPLE_ID`, `NOTARIZATION_PASSWORD`, `NOTARIZATION_TEAM_ID` *(optional)*: for Apple notarization.
