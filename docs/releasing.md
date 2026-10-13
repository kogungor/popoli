<h1 align="center">Releasing Popoli</h1>

<p align="center">
  <a href="../README.md">Home</a> ·
  <a href="usage.md">User Guide</a> ·
  <a href="extensions.md">Writing Extensions</a> ·
  <b>Releasing</b>
</p>

---

- [Branches](#branches)
- [One-time setup](#one-time-setup)
- [Making a release](#making-a-release)
- [How users get updates](#how-users-get-updates)

## Branches

| Branch | What it holds | How it changes |
|---|---|---|
| `dev` (default) | The next version | Pull requests from feature branches, **squash** merged |
| `main` | What is released | Pull requests from `dev`, **merge commit** (never squash, or `dev` and `main` drift apart) |
| `feature/…`, `fix/…`, `chore/…` | One change each | Branched from `dev` |

- **Both protected:** `dev` and `main` only change through pull requests. A **Build** check runs on every pull request; it is the GitHub Actions workflow in `.github/workflows/build.yml`. It builds an unsigned copy and runs smoke tests, and needs no secrets.
- **Releases come from `main` only.** `scripts/release.sh` refuses to run anywhere else.

## One-time setup

1. **Developer ID certificate.** *Developer ID Application* must be in your keychain (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates).

2. **Update signing key.** Sparkle's tool creates the key pair, keeps the private key in your login keychain and prints the public key:
   ```bash
   vendor/Sparkle/bin/generate_keys
   vendor/Sparkle/bin/generate_keys -p > updates/public-key.txt
   ```
   - **Commit the public key:** `updates/public-key.txt` holds the public half and belongs in the repository.
   - **Back up the private key:** export it with `generate_keys -x <file>` and keep it somewhere safe, outside the repository. Without it you cannot ship updates to people who already have Popoli.

3. **Notarization credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com) ▸ Sign-In and Security ▸ App-Specific Passwords, then:
   ```bash
   xcrun notarytool store-credentials popoli-notary --apple-id you@example.com --team-id 23R67A5LKT
   ```
   An App Store Connect API key works too: use `--key`, `--key-id` and `--issuer` instead.

4. **GitHub CLI.** `gh auth login`.

## Making a release

1. **Bump the version and write the notes on `dev`.** On a branch:
   - change `CFBundleShortVersionString` in `Info.plist` (e.g. `0.9.1`),
   - add a `## 0.9.1` section at the top of [CHANGELOG.md](../CHANGELOG.md) with what is new, changed and fixed. Anything after the version in the heading goes into the release title, e.g. `## 1.0.0 (stable)`.

   Then open a pull request to `dev` and merge it.
2. **Bring it to `main`.** Open a pull request from `dev` to `main` and merge it with **Create a merge commit**.
3. **Release from `main`:**
   ```bash
   git switch main && git pull
   scripts/release.sh
   ```
   - **Release notes:** the script takes the version's section from `CHANGELOG.md` and stops if there is none. The notes appear on GitHub and in the update window.
   - **What the script does:**
     - Builds with `RELEASE=1` (Developer ID, hardened runtime).
     - Notarizes the app and staples the ticket.
     - Writes `appcast.xml`, starting from the previous release's appcast. Sparkle signs the new entry with your private key.
     - Creates the GitHub release `v<version>` on `main`, with the zip and `appcast.xml` attached.

You don't have to commit anything afterwards. The app reads its update feed from `https://github.com/kogungor/popoli/releases/latest/download/appcast.xml`, which always points at the newest release.

## How users get updates

- **Automatic checks:** Sparkle checks once a day and on launch. Users can change this in **Settings ▸ General ▸ Updates** or check by hand with **Check for Updates…** in the menu bar menu.
- **Installing:** it downloads the zip, verifies the EdDSA signature and Apple's notarization, replaces the app and relaunches it.
- **Settings and extensions stay:** settings live in `defaults`, extensions in `~/.config/popoli/extensions`.
- **Finder menu:** if an update changes the Finder extension, macOS may keep the old one until Finder restarts. Users can run `killall Finder` once.
