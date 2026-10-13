# Changelog

Each version's section becomes the notes of its GitHub release and of the update window in the app (`scripts/release.sh` copies it from here).

## 0.9.4 (beta)

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
