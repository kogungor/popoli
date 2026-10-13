# Security

## Reporting a vulnerability

Please don't open a public issue. Report it privately through GitHub instead: **Security ▸ Report a vulnerability** ([open the form](https://github.com/kogungor/popoli/security/advisories/new)). Describe what an attacker can do and how, with the version of Popoli and of macOS.

You will get an answer within a few days. Fixes ship in a new release, and the report is credited in its notes unless you would rather not be named.

Only the latest release gets security fixes.

## How Popoli protects you

Popoli reads what you select and runs extensions, so it is built to keep both in your hands.

**Extensions are code, and you decide what runs.**

- **You approve every install.** Nothing installs by itself: selected text, `popoli://install` links and files all open a review window with the extension's full code. Popoli installs it only when you click **Install**.
- **Warnings for risky code.** The review window flags code that, for example:
  - downloads and runs code,
  - deletes files,
  - reads keys, passwords or browser data,
  - asks for administrator rights,
  - starts itself at login,
  - hides what it does.

  It also notes code that connects to the internet or controls other apps. With a red warning, Return cancels instead of installing. The warnings are hints from patterns, not a verdict: read code you don't trust.
- **No silent changes.** Installed extensions don't update themselves.
- **Downloads** must use `https://`, are at most 256 KB, and can't be binary files.

**Saved keys stay with the extensions you gave them to.**

- **Stored in the keychain.** API keys live in the macOS keychain, never in extension files.
- **Asked before use.** An extension that wants a key saved for another one has to be allowed first.
- **Tied to the file.** A permission belongs to one extension file with its exact contents: if the file changes or another file takes its place, Popoli asks again.

**Result cards can't reach out.**

- **No scripts:** formatted output in a card runs no JavaScript.
- **Nothing from the internet:** a card loads nothing from the internet, so a remote image can't report that you selected something.
- **No redirects:** a card can't move to another page.
- **Safe links:** only `http`, `https` and `mailto` links open, in your browser.

**Only Finder can open a terminal.** `popoli://terminal` links carry a secret that only Popoli's Finder extension can read. A web page or another app can't make Popoli open a terminal in a folder it chooses, where a shell prompt could run that folder's code.

**Passwords are left alone.**

- **No bar in password managers:** the bar doesn't appear in 1Password, Bitwarden, Passwords, Keychain Access, KeePassXC, LastPass or Enpass. You can change that in **Settings ▸ General**.
- **No bar in password fields.**
- **Your clipboard isn't turned into a lasting password:** when Popoli copies a selection to read it, it puts your clipboard back, but never a password that a password manager marked as concealed. Its app could no longer clear it.

**Updates and the app:**

- **Updates** are signed with an EdDSA key and notarized by Apple; Sparkle checks both before installing.
- **The app** uses the hardened runtime, and the Finder extension runs in a sandbox.

## What Popoli can't protect you from

- **An extension you install** can do whatever you can. It also has Popoli's own permissions: Accessibility, which lets it control other apps, and Finder automation. Install only extensions you have read or whose author you trust.
- **Software already running on your Mac as you** can change files in your extensions folder.
