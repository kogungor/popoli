<h1 align="center">Releasing Popoli</h1>

<p align="center">
  <a href="../README.md">Home</a> ·
  <a href="usage.md">User Guide</a> ·
  <a href="extensions.md">Writing Extensions</a> ·
  <b>Releasing</b>
</p>

---

Releases are Developer ID signed, notarized by Apple, published on GitHub Releases, and announced to installed copies through Sparkle's `appcast.xml` in this repository:

- **Feed URL:** the app reads `SUFeedURL` in `Info.plist`, which points at `https://raw.githubusercontent.com/kogungor/popoli/main/appcast.xml`.
- **Signatures:** every update is signed with an EdDSA key whose public half is built into the app, so a tampered download is rejected.

## One-time setup

1. **Developer ID certificate.** *Developer ID Application* must be in your keychain (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates).

2. **Update signing key.** Sparkle's tool creates the key pair. It keeps the private key in your login keychain and prints the public key:
   ```bash
   vendor/Sparkle/bin/generate_keys
   vendor/Sparkle/bin/generate_keys -p > updates/public-key.txt
   git add updates/public-key.txt
   ```
   - **Back up the private key:** export it with `generate_keys -x <file>` and keep it somewhere safe. Without it you cannot ship updates to people who already have Popoli.
   - **When the updater turns on:** builds only include the updater once `updates/public-key.txt` exists. Until then, **Check for Updates…** is hidden.

3. **Notarization credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com), then store it in your keychain:
   ```bash
   xcrun notarytool store-credentials popoli-notary --apple-id you@example.com --team-id 23R67A5LKT
   ```

4. **GitHub CLI.** `gh auth login`, with push access to this repository.

## Each release

1. Bump `CFBundleShortVersionString` in `Info.plist`, e.g. `1.0.2`.
2. Optionally write release notes to `dist/Popoli-<version>.md`. Sparkle shows them in the update window.
3. Run:
   ```bash
   scripts/release.sh
   ```
   The script:
   - builds with `RELEASE=1` (Developer ID, hardened runtime),
   - notarizes and staples,
   - zips the app and updates `appcast.xml`,
   - creates the GitHub release `v<version>` with the zip.
4. Commit and push `appcast.xml`. Installed copies find the update on their next check, which happens daily and on launch.

## How users get updates

- **Automatic checks:** they are on by default. Change them in **Settings ▸ General ▸ Updates**:
  - check automatically,
  - download and install automatically,
  - check now.
- **Manual checks:** use **Check for Updates…** in the menu bar menu.
- **What Sparkle does:** it downloads the zip, verifies the EdDSA signature and Apple's notarization, replaces the app and relaunches it.
- **Settings and extensions stay:** settings live in `defaults`, extensions in `~/.config/popoli/extensions`.
- **Finder menu after an update:** if an update changes the Finder extension, macOS may keep using the old one until Finder restarts. Users can restart it once with `killall Finder`.
