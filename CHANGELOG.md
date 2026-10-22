# Changelog

Each version's section becomes the notes of its GitHub release and of the update window in the app (`scripts/release.sh` copies it from here).

## 0.10.0 (beta)

### New

- **Collect:** gather snippets as you read, and use them together.
  - **Collect** on the bar (the tray icon) adds the selection to a collection. Each page, conversation or document gets one of its own, so a Claude chat and a web page you read in between never mix. ⇧-click starts a new one.
  - **Collected ›** on the bar then pastes or copies them all, a blank line apart, or with ⌥ as Markdown quotes, each with a link back to where it came from.
  - **Collections…** in the menu bar menu lists them. Rename them, drag snippets between them, merge them, or run an extension such as Ask ChatGPT on all the snippets at once. A snippet's ↗ opens its page scrolled to the snippet and highlighted.
  - **Collect Everything Here** (the pin) gathers from any app into one collection, for research across many pages.
  - Collections stay on your Mac, readable only by you, and are deleted 7 days after the last snippet was added. **Settings ▸ General** can keep them in memory only.
  - Thanks to Ömür Şahiner for the idea.

## 0.9.9 (beta)

### Fixed

- **Selecting by dragging in Sublime Text** (and other apps that don't show their text to Accessibility): the bar didn't appear after a drag, only after a double-click. Popoli took a press on the text for a press on the window's title bar.
- **Dragging a window by its title:** pressing on the window's title text and dragging could show the bar for text selected in that window. It now counts as the title bar, like the rest of it.

## 0.9.8 (beta)

### Fixed

- **Finder in icon view:** clicking a file or folder showed no bar, because Popoli took the icon for a button. It now offers Copy, Copy Path, Open in Terminal and Open in › as it does in list and column view.

### Improved

- **Diagnostics log:** notes when Finder gives Popoli no selection, to help when the bar doesn't appear for files.

## 0.9.7 (beta)

### New

- **Open in ›:** open what you selected in Finder in your editor, or start an AI coding tool in that folder, from the right-click menu or the bar.
  - **Editors and IDEs:** VS Code, Cursor, Windsurf, Zed, Sublime Text, Nova, BBEdit, Xcode, Kiro, Antigravity, Android Studio and the JetBrains IDEs. A folder opens as a project, a file as a file; ⌥-click on the bar opens the folder a file is in.
  - **AI tools:** Claude Code, Codex, Gemini CLI, OpenCode, Cursor CLI, Copilot CLI and Aider start in a new window of your terminal, in the folder, and the shell stays open when they end.
  - Popoli finds the ones installed and starts with the three editors you used most recently and every AI tool it found. **Settings ▸ General ▸ Open in** changes the list, and **Add App…** and **Add Command…** add anything else.
  - Like Open in Terminal, the right-click menu reaches Popoli with a secret only it knows, and only what is turned on in Settings can run.

### Improved

- **An all-icon bar with labels:** every button is an icon now, Cut, Copy, Paste and Copy Path included. Point at one and its name slides in above the bar in a small glass label, with what ⇧ or ⌥ does; move along the bar and the label glides with you, and it fades when you leave. Groups show an icon with a chevron and list what is inside. Extensions without an icon get their initials, and the catalog's Case, Lines and Ask extensions got icons.
- **Path** is called **Copy Path** on the bar, as in the Finder menu.
- **What's new after an update:** the first time a new version opens, a small window shows its highlights, each with a button to try it, covering every version since the one you had. **What’s New…** in the menu shows it again. Buttons that came with the update carry a small blue dot, and NEW in their label, for their first few appearances.

## 0.9.6 (beta)

### New

- **Homebrew:** `brew install --cask kogungor/tap/popoli`.
- **Diagnostics log:** **Settings ▸ General ▸ Diagnostics log** writes one line per selection: the app, how the text was read, the buttons shown and how long it took, or why nothing showed. It never contains the selected text, so it can be attached to a bug report as it is.

### New in the catalog

- **Case ›:** Lowercase, Sentence case, camelCase (⇧-click for PascalCase), snake_case (⇧-click for CONSTANT_CASE), kebab-case and Slug join Uppercase and Title Case in one group. Text with Turkish or Azerbaijani letters gets their rules for i and ı.
- **Lines ›:** Sort Lines (numbers in order, ⇧-click for Z to A), Remove Duplicates, Join Lines and Trim Whitespace.
- **Ask ›:** ChatGPT, Claude, Perplexity and Gemini open with the selection in your browser, signed in with your own account, so they use your subscription and need no API key. A `PROMPT` setting puts your instruction before the selection.

### New for extensions

- **`shortcut:`** runs a shortcut from the Shortcuts app with the selection (or the files selected in Finder), and what it returns is shown, pasted or copied like a script's output. Anything you can build in Shortcuts becomes a button without code.
- **`service:`** runs a service from the Services menu with the selection, such as **Make Sticky** or **Convert Text to Full Width**.

### Fixed

- **Cut and Paste in Sublime Text:** they were missing, because Sublime reports its window rather than a text field as focused. In that case the Edit menu now decides, as in other apps.
- **Title Case** keeps apostrophes ("Don't", not "Don'T") and acronyms such as NASA.

### Improved

- **Web pages in Safari and Firefox-based browsers:** text selected on a page is read through Accessibility (the browser's text markers) instead of with ⌘C, so Popoli no longer touches the clipboard there, the bar comes up faster (a drag: about 65 ms instead of 115 ms) and sits right above the selection. Also for other apps built on WebKit, such as Mail.
- **Settings ▸ Catalog:** an AI category, and the category menu lists the categories the catalog has, including ones added later.

## 0.9.5 (beta)

### New

- **Settings ▸ Catalog:** browse the ready-made extensions inside Popoli, search them, filter by category, and install one with a click. Each row says whether the extension works on Finder files, goes online, needs an API key or has settings. Installed extensions are marked, and when the catalog has a newer version of one you haven't edited, the button says **Update**.
- **Verified installs:** the review window shows when an extension is exactly the one listed in the catalog, and says so when the downloaded file differs from the list.
- **Update badge:** when a new version is out, a red dot appears on the menu bar icon, next to **Update to Popoli <version>…** in the menu and a notification, which comes once per version.

### Fixed

- **Updates arrive sooner:** Popoli checks every hour instead of once a day.
- **Automatic downloads went unnoticed:** with **Download and install updates automatically** on, a downloaded update waited for Popoli to quit, which a menu bar app rarely does, and nothing said so. Now the menu offers **Install Popoli <version> and Restart**, and a notification does the same.
- **Open in Terminal after updating:** after an update, the Finder menu could keep running the previous version of Popoli's Finder extension, whose links the new version ignores. Popoli now restarts an outdated Finder extension when it starts. The first right-click right after an update may still miss the items.
- **Installing JavaScript for Automation:** an extension pasted as text whose first line is `#!/usr/bin/osascript -l JavaScript` was saved as `.applescript` and failed to run. It is saved as `.js` now.

### Improved

- **Review window:** names the language a script is written in (Python, Node.js, JavaScript for Automation…) instead of the command that runs it.

### New for extensions

- **`description:`** — a one-line summary, shown in **Settings ▸ Catalog**. Put it last in the header: versions before 0.9.5 stop reading the header at a key they don't know.
- **One catalog:** the examples installed on first launch are now part of [catalog/](https://github.com/kogungor/popoli/tree/main/catalog), listed in `catalog/starter.txt`.

## 0.9.4 (beta)

### Security

- **Terminal links come only from Finder:** `popoli://terminal` links now need a secret that only Popoli's Finder extension can read. Before, a web page could make Popoli open a terminal in a folder of its choosing, and a shell prompt that runs git there could run that folder's code.
- **Keys go only to extensions you allow:** an extension that names a key saved for another one has to be allowed first, and again when its file changes. Extensions you already have keep their keys.
- **Warnings before installing:** the review window flags code that downloads and runs code, deletes files, reads keys or passwords, asks for administrator rights, starts at login or hides what it does, and notes code that connects to the internet or controls other apps. With a red warning, Return cancels.
- **Result cards load nothing from the internet** and open only `http`, `https` and `mailto` links.
- **Passwords:** the bar stays out of password managers (1Password, Bitwarden, Passwords, Keychain Access, KeePassXC, LastPass, Enpass), and a password marked as concealed is never put back on the clipboard after Popoli copies a selection.
- **Logs:** a failing extension logs only its name, never what it printed.
- [SECURITY.md](https://github.com/kogungor/popoli/blob/main/SECURITY.md) describes how Popoli protects you and how to report a problem.

### Fixed

- **Restarting:** a new copy of Popoli started while the previous one was still quitting could hand over to it and quit, leaving none running.

### New for extensions

- **Groups:** extensions with the same `group:` share one button on the bar, such as **Encode ›**, that opens them. When only one of them fits the selection, the bar shows it directly.
- **Formatted output in the card:** with `output: html` or `markdown`, the result card shows headings, lists, tables, code and images (as `data:` URLs or files next to the extension). Copy and Replace keep the formatting.
- **Extension catalog:** about 30 ready-made extensions in [catalog/](https://github.com/kogungor/popoli/tree/main/catalog), from **Settings ▸ Guide ▸ Extension Catalog**:
  - **Text:** Calculate, Convert (units, temperatures, currencies), Color, Call, Email.
  - **Encode › and Decode ›:** Base64, URL, HTML, QR codes.
  - **Developer ›:** Format and Minify JSON, Unix Time, Hex ↔ Decimal, Decode JWT, SHA-256.
  - **Add to ›:** Notes, Reminders, Things, Todoist, Obsidian, Calendar.
  - **Finder:** Copy as Markdown Link, Copy Contents, SHA-256, Merge PDFs, Image › Resize, To JPEG, To PNG.
- **The browser's page:** extensions that use `$POPOLI_BROWSER_URL` or `$POPOLI_BROWSER_TITLE`, and links with `{url}`, get the page open in the browser in front. Works with Safari, Chrome, Brave, Edge, Arc, Vivaldi, Opera, Firefox and Zen.

## 0.9.3 (beta)

### New

- **Update notifications:** when the daily check finds a new version, Popoli posts a notification and adds **Update to Popoli <version>…** to the top of its menu. Clicking either shows what's new and installs it. Before, the update window could open unseen behind other windows. macOS asks once whether Popoli may send notifications; without that permission, the menu item still appears.
- **Rearrange the bar where you use it:** hold ⌘ and drag a button along the bar. The other buttons make room, and the new order is saved: it is the same order as in **Settings ▸ Buttons**. A ⌘-click that doesn't move still counts as a click.

## 0.9.2 (beta)

### Improved

- **Open in Terminal with several items:** with several items selected in the same folder, Open in Terminal (in Finder's right-click menu and on the bar) opens a terminal in that folder. With items from different folders it is not shown. Before, the right-click menu picked one of them, and the bar only offered it for a single item. Copy Path still copies every path, one per line.
- **Finder selection without freezes:** Popoli asks Finder for the selected files in the background, waits at most a second and reads at most 1,000 of them. Before, a busy Finder (a large copy, a slow network drive) or a very large selection could freeze the bar and the menu bar icon until Finder answered.

## 0.9.1 (beta)

### New

- **Move to Applications:** Popoli opened straight from the disk image offers to move itself to the Applications folder and continues from there.
- **Opening Popoli while it runs shows Settings.** A menu bar app has no window to bring forward, so before, nothing seemed to happen.
- **Disk image:** releases come as a disk image to drag to Applications, next to the zip used for updates.

### Fixed

- **One Popoli at a time:** opening another copy of Popoli (from the disk image, a second download or a build) no longer adds another menu bar icon and another bar. The copy that is already running shows Settings instead. A copy in the Applications folder takes over from one running elsewhere.
- **Finder right-click menu:** only the running copy's Finder extension stays registered. Before, Finder could use the extension of another copy, such as one on a disk image that was ejected since.

## 0.9.0 (beta)

The first public release of Popoli, an action bar for the text you select on macOS.

### Selection bar

- Select text in any app and a Liquid Glass bar appears above it with the actions that fit: **Search**, **Open Link**, **Cut**, **Copy**, **Paste**, **Look Up**, **Translate** and your extensions.
- Buttons only show where they make sense:
  - Cut and Paste only in editable text.
  - Open Link for a single link.
  - Look Up for up to 4 words.
- Hold a key while clicking for an alternative:
  - **⇧ Search** looks for the exact phrase.
  - **⇧ Copy** adds to what is already on the clipboard.
  - **⌥ Paste** pastes and matches the style.
  - **⌥ Path** copies paths quoted for the shell.
  - **⌥ Look Up** opens the Dictionary app.
  - **⌥ Translate** replaces the selection with the translation.
- **⌃⌥P** shows the bar for the current selection, even in apps where it normally stays away. The shortcut can be changed.
- Clicking into an empty text field offers a bar with just **Paste**.
- **Dark** (default), **Light** or **System** style. The dark glass stays readable on white pages.

### Translation and dictionary

- **On-device translation:** Translate uses Apple's Translation framework, so the text never leaves your Mac.
- **The card:**
  - **From → To** menus for a one-off change.
  - **Copy**, **Replace** and **Google** (opens Google Translate).
- **Default languages:** set them in **Settings ▸ Translate**; the source language is detected automatically.
- **Look Up:** shows the macOS dictionary definition in the same card.

### Finder

- Select files in Finder and the bar offers **Copy**, **Path** and **Open in Terminal**.
- **Open in Terminal** and **Copy Path** in Finder's right-click menu, on folders, files and the empty background of a window.
- Works with Terminal, iTerm, Ghostty, Warp, WezTerm and kitty.

### Extensions

- **One file per extension:** put it in `~/.config/popoli/extensions`. It starts with a few `# key: value` lines, and code in any language can follow (zsh, Python, Node, AppleScript…).
- **No code needed** for links (`url:`) and keyboard shortcuts (`keys:`).
- **When it shows:** `match:` (a regular expression), `apps:` and `for: files`.
- **Formatted text:** `input:` and `output:` let an extension read and paste formatted text as HTML or Markdown.
- **Settings and API keys:** `setting:` and `secret:` add values the user fills in. API keys are stored in the macOS keychain.
- **Installing shared extensions:**
  - select their text and click **Install Extension** on the bar,
  - open a `popoli://install?url=…` link,
  - use **Install Extension…** in the menu bar menu,
  - or drop the file on **Settings ▸ Buttons**.

  Popoli always shows what an extension does and its full code before installing it.
- **Examples included:** Uppercase, Title Case, Word Count, Speak, Copy Names, Wikipedia, Improve Writing (Claude), Copy as Markdown and Rich Text.
- **Help:** **Settings ▸ Guide** is a cheat sheet with ready-made examples, and **New Extension…** writes a commented template.

### App

- **Settings:** General, Buttons (turn buttons on or off and drag to reorder), Translate and Guide.
- **Excluded apps:** a list of apps where the bar stays away, and **Don't Show in <App>** in the menu bar menu.
- **Launch at login.**
- **Updates:** releases are signed and notarized, and arrive through Sparkle (**Check for Updates…**).

### Requirements

macOS 26 (Tahoe) or later on Apple silicon.

### Known limitations

- **Beta:** every app exposes its text a little differently. If the bar misbehaves somewhere, please [open an issue](https://github.com/kogungor/popoli/issues) with the app's name.
- **English only:** the interface is in English for now.
