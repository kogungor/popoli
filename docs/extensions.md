<p align="center">
  <img src="../Assets/popoli.png" width="96" alt="Popoli icon">
</p>

<h1 align="center">Writing Popoli Extensions</h1>

<p align="center">
  <a href="../README.md">Home</a> ·
  <a href="usage.md">User Guide</a> ·
  <b>Writing Extensions</b>
</p>

---

An extension adds a button to the Popoli bar. It is **one file** in

```
~/.config/popoli/extensions/
```

that starts with a few `# key: value` comment lines. Below them, write code in any language, or nothing at all for links and shortcuts. Save the file and the button appears; there is no restart, build step or manifest.

- [Quick start](#quick-start)
- [Anatomy of an extension](#anatomy-of-an-extension)
- [Header reference](#header-reference)
- [What the script gets](#what-the-script-gets)
- [What happens with the output](#what-happens-with-the-output)
- [When the button appears](#when-the-button-appears)
- [Extensions without code](#extensions-without-code)
- [Files selected in Finder](#files-selected-in-finder)
- [Settings and API keys](#settings-and-api-keys)
- [Formatted text and Markdown](#formatted-text-and-markdown)
- [Modifier keys](#modifier-keys)
- [Icons](#icons)
- [Languages](#languages)
- [AppleScript](#applescript)
- [Debugging](#debugging)
- [Examples](#examples)
- [Installing and sharing extensions](#installing-and-sharing-extensions)

## Quick start

1. Click the Popoli menu bar icon ▸ **New Extension…**. Popoli writes `my-extension.sh` from a commented template and opens it in your text editor.
2. Change `name:`, write what the script should print, and save.
3. Select some text: your button is on the bar.

Alternatively, open **Settings ▸ Guide** and click **Use This** next to any example to get a working file in one click.

## Anatomy of an extension

```zsh
#!/bin/zsh              ← optional: picks the language
# name: Uppercase       ← header: "key: value" comment lines
# icon: AB
# after: paste
                        ← the header ends at the first other line
print -rn -- ${(U)POPOLI_TEXT}   ← code: whatever it prints is the result
```

- **Comments:** header lines are comments in the file's language: `#` for most languages, `//` for JavaScript, `--` for AppleScript.
- **Order:** the `#!` line, if any, comes first. Then header lines, one per line, in any order.
- **End of the header:** the header stops at the first line that is not a `key: value` comment, such as a blank line, code, or a plain `#` comment. You can therefore write normal comments after an empty `#` line without them being read as settings.
- **File names:** use any name. The file name identifies the extension, so renaming a file resets its on/off state and position in **Settings ▸ Buttons**.

## Header reference

| Key | Required | Values | Meaning |
|---|---|---|---|
| `name:` | **yes** | any text | Button title and tooltip; also the title of the result card |
| `icon:` | no | SF Symbol name · up to 3 characters · emoji · image file | See [Icons](#icons). Without an icon, the bar shows the name |
| `after:` | no | `show` · `paste` · `copy` · `none` | What happens with the output. See [below](#what-happens-with-the-output) |
| `match:` | no | regular expression | Only show the button when the selection matches |
| `apps:` | no | bundle IDs, comma-separated | Only show the button in these apps |
| `for:` | no | `text` (default) · `files` | `files`: run on files selected in Finder |
| `url:` | no | link containing `{text}` or `{url}` | Makes it a [link extension](#links) (no code) |
| `keys:` | no | e.g. `cmd shift H` | Makes it a [shortcut extension](#keyboard-shortcuts) (no code) |
| `input:` | no | `text` (default) · `html` · `markdown` | Hand the script the selection [with its formatting](#formatted-text-and-markdown) |
| `output:` | no | `text` (default) · `html` · `markdown` | Show, paste or copy the script's output [as formatted text](#formatted-text-and-markdown) |
| `group:` | no | any text, e.g. `Encode` | Shares [one button](#groups) on the bar with the other extensions of the group |
| `setting:` | no | `NAME` or `NAME = default` | A [value the user can change](#settings-and-api-keys), given to the script as `$NAME`; repeatable |
| `secret:` | no | `NAME` | An [API key kept in the keychain](#settings-and-api-keys), given to the script as `$NAME`; repeatable |

Unknown keys end the header, so a typo such as `# nmae: …` shows up as *Missing "name:"* in **Settings ▸ Buttons**.

## What the script gets

| | |
|---|---|
| `$POPOLI_TEXT` | The selected text |
| stdin | The selected text, or with `for: files` the file paths, one per line |
| `"$@"` | With `for: files`: the file paths as arguments |
| `$POPOLI_FILES` | With `for: files`: the file paths, one per line |
| `$POPOLI_APP` | Bundle ID of the app with the selection, e.g. `com.apple.Safari` |
| `$POPOLI_APP_NAME` | Its name, e.g. `Safari` |
| `$POPOLI_MARKDOWN`, `$POPOLI_HTML` | With `input: markdown` or `html`: the formatted selection |
| `$POPOLI_SHIFT`, `$POPOLI_OPTION`, `$POPOLI_COMMAND`, `$POPOLI_CONTROL` | `1` if that key was held while clicking, else `0` |
| `$POPOLI_MODIFIERS` | The held keys as words, e.g. `shift option` |
| `$NAME` | The value of each `setting:` and `secret:` |
| `$POPOLI_BROWSER_URL`, `$POPOLI_BROWSER_TITLE` | The [page open in the browser](#the-browsers-page) in front, if the script uses them |

The script also runs with these conditions:

- **Working directory:** the extensions folder.
- **`PATH`:** starts with `/opt/homebrew/bin:/usr/local/bin`, so Homebrew tools are found.
- **`LANG`:** `en_US.UTF-8` unless you set it yourself, so non-ASCII text such as `é ñ ß å` works in shell tools.
- **Time limit:** 60 seconds, after which the script is stopped.
- **Executable bit:** not needed.

## What happens with the output

What the script prints to **stdout** is the result. A single trailing newline is removed.

| `after:` | Result |
|---|---|
| `show` *(default)* | Shown in a glass card with **Copy**, and **Replace** in editable text. With `output: html` or `markdown` the card shows it [formatted](#formatted-output-in-the-card). Nothing is shown if the output is empty |
| `paste` | Replaces the selection. The button only appears in editable text |
| `copy` | Copied to the clipboard, with a *Copied* notification |
| `none` | Ignored. Use this for actions such as speaking, opening apps or saving files |

**Errors:** if the script exits with a non-zero status, Popoli shows the first line of **stderr** as an error notification:

```zsh
[[ $POPOLI_TEXT == http* ]] || { echo "Not a link" >&2; exit 1 }
```

## When the button appears

Without any conditions, a text extension appears whenever text is selected. You can narrow that down:

- **`match:`** is a regular expression (ICU syntax, as in `NSRegularExpression`) that must match somewhere in the selection. Use `^` and `$` to match the whole selection.
  ```
  # match: ^https?://\S+$        a single link
  # match: ^\s*[\[{]             looks like JSON
  # match: ^\d+$                 a number
  # match: (?i)error|warning     contains a word, case-insensitive
  ```
- **`apps:`** limits the button to apps by bundle ID:
  ```
  # apps: com.apple.Notes, md.obsidian
  ```
  To find an app's bundle ID: `osascript -e 'id of app "Notes"'`
- **`after: paste`** extensions automatically appear only in editable text.
- **`for: files`** extensions appear only for files selected in Finder.

The user can still switch any extension off or move it in **Settings ▸ Buttons**.

## Extensions without code

Put the header in a `.popoli` file (or any file) and leave out the code.

### Links

```
# name: Maps
# icon: map
# url: https://maps.apple.com/?q={text}
```

`{text}` is replaced with the selection, trimmed and URL-encoded. The link opens in your default browser or in the app that handles it, so `things:///add?title={text}`-style app URLs work too.

`{url}` is replaced with the address of the [page open in the browser](#the-browsers-page), URL-encoded:

```
# name: Archive Page
# icon: archivebox
# url: https://web.archive.org/save/{url}
```

A `url:` must contain `{text}` or `{url}`.

### Keyboard shortcuts

```
# name: Highlight
# icon: highlighter
# keys: cmd ctrl H
# apps: com.apple.Preview
```

The shortcut is pressed in the app where the text is selected, so the selection is still there for it to act on. It is usually combined with `apps:`.

| Modifiers | Named keys |
|---|---|
| `cmd` `command` `⌘` | `return` `enter` `tab` `space` `escape` `esc` |
| `option` `opt` `alt` `⌥` | `delete` `backspace` `forwarddelete` |
| `ctrl` `control` `⌃` | `left` `right` `up` `down` |
| `shift` `⇧` | `home` `end` `pageup` `pagedown` `f1` … `f12` |

- **Other keys:** any single character, such as letters, digits or `,` `.` `/` `[` `]`.
- **Layouts:** keys follow your keyboard layout.
- **Separators:** separate parts with spaces or `+` (`cmd+shift+h`).

## Files selected in Finder

With `for: files`, the extension works on the files and folders selected in Finder instead of on text. The paths arrive as arguments (`"$@"`), in `$POPOLI_FILES` and on stdin.

```zsh
#!/bin/zsh
# name: Open in VS Code
# icon: chevron.left.forwardslash.chevron.right
# for: files
# after: none

open -a "Visual Studio Code" "$@"
```

```zsh
#!/bin/zsh
# name: Copy Names
# icon: textformat
# for: files
# after: copy

for f in "$@"; do print -r -- "${f:t}"; done
```

## Settings and API keys

An extension can ask for values the user fills in once. A good example is an API key for a web service such as Claude, DeepL or OpenAI.

```zsh
# secret: ANTHROPIC_API_KEY
# setting: MODEL = claude-opus-5-5
# setting: TONE = friendly
```

- **`secret: NAME`** is for keys and tokens:
  - **Entering it:** the user enters it in **Settings ▸ Buttons ▸ *extension* ▸ Settings…**.
  - **Storage:** it is stored encrypted in the macOS **login keychain**, never in the extension file. You can share the file safely.
  - **Sharing between extensions:** secrets are shared by name. Every extension that declares `ANTHROPIC_API_KEY` uses the key entered once.
  - **Missing key:** clicking the button opens the settings sheet instead of running the script.
- **`setting: NAME = default`** is for ordinary values. The user can change them in the same sheet; if they don't, the default is used.
- **In the script:** both arrive as environment variables named exactly as declared (`$ANTHROPIC_API_KEY`, `$MODEL`, `$TONE`). Names use letters, digits and `_`.

Why a key at all? Popoli itself needs none. A key is only needed when an extension talks to a paid web service: the service uses it to know who is calling and whom to bill. It is like a password, which is why it lives in the keychain.

## Formatted text and Markdown

Most apps put formatted text (HTML or RTF) on the clipboard next to the plain text. Popoli can use it:

- **`input: markdown`:** the script gets the selection converted to Markdown. Headings, **bold**, *italic*, links, lists, code, quotes and tables are kept. `$POPOLI_MARKDOWN` has the same text, and `$POPOLI_HTML` the original HTML.
- **`input: html`:** the script gets the HTML itself.
- **`output: markdown`** (or `html`): when the result is pasted or copied (`after: paste` or `copy`), Popoli converts it to formatted text. Rich editors such as Notes, Mail, Pages and Google Docs paste it with formatting; plain-text places get the text as it is. When it is shown (`after: show`, the default), the card shows it [formatted](#formatted-output-in-the-card).

How the formatted selection is read: Popoli copies the selection (⌘C), reads the formats and puts your clipboard back. Apps that only copy plain text give the plain text.

```zsh
#!/bin/zsh
# name: Copy as Markdown
# icon: MD
# input: markdown
# after: copy

cat
```

````zsh
#!/bin/zsh
# name: Rich Text
# icon: textformat
# output: markdown
# after: paste
# match: (?m)^(#{1,6} |[-*+] |\d+\. |> |```)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)

cat
````

## Formatted output in the card

With `output: html` or `markdown`, the result card shows the output formatted: headings, lists, tables, code and images. **Copy** and **Replace** keep the formatting.

- **Images:** use `data:` URLs (`<img src="data:image/png;base64,…">` or SVG), or files next to the extension (`<img src="logo.png">`).
- **Size:** the card grows with the content up to about 360 pt; longer output scrolls inside it.
- **Scripts in the HTML don't run**, and nothing is loaded from the internet: no remote images, styles or fonts. A request would tell a server that you just selected something.
- **Links:** only `http`, `https` and `mailto` links open, in your browser. The card never moves to another page.

```zsh
#!/bin/zsh
# name: Color
# icon: paintpalette
# output: html
# match: ^#[0-9A-Fa-f]{6}$

print -r -- "<div style='width:64px;height:32px;border-radius:8px;background:$POPOLI_TEXT'></div>
<p><b>$POPOLI_TEXT</b></p>"
```

## Groups

Extensions with the same `group:` share one button on the bar, for example **Encode ›**. Clicking it shows the group's buttons in place of the bar, with **‹** to go back.

```zsh
#!/bin/zsh
# name: Base64
# group: Encode

print -rn -- "$POPOLI_TEXT" | base64
```

- **Only what fits:** the group button lists only the extensions that fit the selection. When just one of them fits, the bar shows that one directly.
- **Position:** the group button sits where its first extension is in **Settings ▸ Buttons**. ⌘-dragging it on the bar moves the whole group.

## The browser's page

An extension that mentions `$POPOLI_BROWSER_URL` or `$POPOLI_BROWSER_TITLE` (or a link with `{url}`) gets the address and title of the page open in the browser in front:

```zsh
#!/bin/zsh
# name: Quote with Link
# icon: quote.opening
# output: markdown
# after: copy

print -r -- "> $POPOLI_TEXT

— [$POPOLI_BROWSER_TITLE]($POPOLI_BROWSER_URL)"
```

- **Supported browsers:**
  - Safari, Chrome, Brave, Edge, Arc, Vivaldi and Opera, through AppleScript. macOS asks once whether Popoli may control the browser.
  - Firefox, Zen, Waterfox and LibreWolf, through Accessibility: Popoli reads the address bar. These browsers hide `https://`, so Popoli adds it back.
- **Other apps:** both variables are empty when the app in front is not a browser.
- **No needless asking:** the page is only looked up for extensions that use it, so other extensions never trigger the browser permission.
- **Checking it:** `Popoli.app/Contents/MacOS/Popoli --browser-tab app.zen-browser.zen` prints what an extension would get.

## Modifier keys

When the user holds ⇧, ⌥, ⌘ or ⌃ while clicking a button, your script can tell. Use it to offer a second behaviour without a second button:

```zsh
#!/bin/zsh
# name: Search Docs
# icon: book

query=$(jq -rn --arg q "$POPOLI_TEXT" '$q | @uri')
if [[ $POPOLI_OPTION == 1 ]]; then
  open "https://developer.apple.com/search/?q=$query"
else
  open "https://developer.mozilla.org/search?q=$query"
fi
```

Popoli's own buttons follow the same idea: ⌥-click **Paste** pastes without formatting, ⇧-click **Copy** adds to the clipboard. The [User Guide](usage.md#hold--or--for-more) has the full list.

## Icons

| `icon:` | Looks like |
|---|---|
| `speaker.wave.2` | An **SF Symbol**. Browse names in Apple's free *SF Symbols* app |
| `AB`, `W`, `Aa` | Up to **3 letters**, drawn in bold |
| `🔤` | An **emoji**, in color |
| `icon.png` | An **image** next to the extension file (`png`, `svg`, `pdf`, `jpg`, `tiff`), scaled to 18 pt |

- **Light and dark:** symbols, letters and images are drawn as templates, so they follow the light and dark styles. Draw images black on transparent.
- **No icon:** the bar shows the extension's name as text.

## Languages

The first line picks the interpreter. It must be an absolute path, such as `#!/bin/zsh` or `#!/usr/bin/env python3`. Without a `#!` line, the file extension decides:

| File | Runs with |
|---|---|
| `.py` | `python3` |
| `.js`, `.mjs` | `node` |
| `.rb` | `ruby` |
| `.pl` | `perl` |
| `.swift` | `swift` |
| `.sh` | `/bin/sh` |
| `.bash` | `/bin/bash` |
| `.applescript`, `.scpt` | `osascript` (see [AppleScript](#applescript)) |
| anything else | `/bin/zsh` |

The interpreter must be installed: macOS ships `zsh`, `bash`, `perl`, `osascript` and, with Xcode's tools, `python3` and `swift`. `node` and `ruby` come from Homebrew and the like.

Popoli ignores these files in the folder: hidden files, `README*`, and `.md`, `.txt`, `.log`, `.png`, `.jpg`, `.jpeg`, `.svg`, `.pdf`. You can therefore keep notes and icon images next to your extensions.

## AppleScript

AppleScript files use `--` comments for the header. The selected text arrives as the first item of `argv`; with `for: files`, each file is one item. Whatever the script returns is the output.

```applescript
-- name: New Note
-- icon: note.text
-- after: none

on run argv
    tell application "Notes" to make new note with properties {body:item 1 of argv}
end run
```

The first time an extension controls another app, macOS asks whether Popoli may do so.

## Debugging

**The button doesn't appear.**

1. Open **Settings ▸ Buttons**. A broken extension is listed with the reason in red, for example *Missing "name:" in the header*, *Unknown keys: …* or *url: must be a link containing {text}*.
2. Check that its checkbox is on.
3. Check its condition, shown under its name: `match:`, `apps:`, `after: paste` (editable text only) or `for: files`.

**The button appears but fails.**

- **Error message:** the notification shows the first line of stderr.
- **Run the script yourself in Terminal** with the same input:
  ```bash
  POPOLI_TEXT="hello world" zsh ~/.config/popoli/extensions/uppercase.sh
  echo "hello world" | python3 ~/.config/popoli/extensions/count-lines.py
  ```
- **Stopped scripts:** a script that takes longer than 60 seconds is stopped.

**Changes don't show.** Popoli rereads the folder when it changes. If your editor saved somewhere else, use **Settings ▸ Buttons ▸ Edit** to open the right file.

## Examples

All of these are also in **Settings ▸ Guide**, where **Use This** creates the file for you.

### Improve writing with Claude (API key in the keychain)

```zsh
#!/bin/zsh
# name: Improve Writing
# icon: wand.and.stars
# after: paste
# secret: ANTHROPIC_API_KEY
# setting: MODEL = claude-opus-5-5
# setting: INSTRUCTION = Improve the writing: fix grammar and spelling and make it clearer. Keep the language, meaning and tone.

# Asks Claude to rewrite the selection and puts the result in its place.
# Add your Anthropic API key in Settings ▸ Buttons ▸ Improve Writing ▸ Settings…
# (it is kept in the macOS keychain, not in this file).

prompt="$INSTRUCTION
Reply with the rewritten text only, nothing else.

<text>
$POPOLI_TEXT
</text>"

body=$(jq -n --arg model "$MODEL" --arg prompt "$prompt" \
  '{model: $model, max_tokens: 16000, fallbacks: "default", messages: [{role: "user", content: $prompt}]}')

# The key goes in through a header file, so it never shows up in the process list.
response=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H @<(print -r -- "x-api-key: $ANTHROPIC_API_KEY") \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: server-side-fallback-2026-07-01" \
  -d "$body") || { echo "Could not reach the Anthropic API" >&2; exit 1 }

error=$(print -r -- "$response" | jq -r '.error.message // empty')
[[ -n $error ]] && { echo "$error" >&2; exit 1 }
[[ $(print -r -- "$response" | jq -r '.stop_reason') == refusal ]] && { echo "Claude declined this request" >&2; exit 1 }

print -rn -- "$(print -r -- "$response" | jq -r '[.content[] | select(.type == "text") | .text] | join("")')"
```

Enter your Anthropic API key once under **Settings ▸ Buttons ▸ Improve Writing ▸ Settings…**. `MODEL` and `INSTRUCTION` can be changed there too. For example, `INSTRUCTION = Rewrite this as a short, friendly email.` makes it a different tool. `jq` and `curl` ship with macOS.

### Clean up text, replace the selection

```zsh
#!/bin/zsh
# name: Trim Lines
# icon: text.alignleft
# after: paste

print -rn -- "$POPOLI_TEXT" | sed -E 's/[[:space:]]+$//'
```

### Pretty-print JSON (Node)

```js
#!/usr/bin/env node
// name: Pretty JSON
// icon: curlybraces
// match: ^\s*[\[{]
// after: paste

let input = "";
process.stdin.on("data", d => input += d);
process.stdin.on("end", () => process.stdout.write(JSON.stringify(JSON.parse(input), null, 2)));
```

### Count words and characters, show the result

```zsh
#!/bin/zsh
# name: Word Count
# icon: number

words=$(print -rn -- "$POPOLI_TEXT" | wc -w | tr -d ' ')
chars=$(print -rn -- "$POPOLI_TEXT" | wc -m | tr -d ' ')
echo "$words words · $chars characters"
```

### Title Case (Python)

```python
#!/usr/bin/env python3
# name: Title Case
# icon: Aa
# after: paste

import sys
print(sys.stdin.read().title(), end="")
```

### Base64 decode, only for Base64-looking text

```zsh
#!/bin/zsh
# name: Base64 Decode
# icon: lock.open
# match: ^[A-Za-z0-9+/=\s]{8,}$

print -rn -- "$POPOLI_TEXT" | base64 -D
```

### Read aloud

```zsh
#!/bin/zsh
# name: Speak
# icon: speaker.wave.2
# after: none

say -- "$POPOLI_TEXT"
```

### Open a GitHub issue by number

```
# name: Issue
# icon: number.circle
# match: ^\d+$
# url: https://github.com/kogungor/popoli/issues/{text}
```

### Search a site

```
# name: Wikipedia
# icon: W
# url: https://en.wikipedia.org/w/index.php?search={text}
```

### Use the app's own shortcut

```
# name: Bold
# icon: bold
# keys: cmd B
# apps: com.apple.Notes, com.apple.TextEdit
```

### Shell commands on selected files

```zsh
#!/bin/zsh
# name: Zip
# icon: doc.zipper
# for: files
# after: none

cd "${1:h}" && zip -rq "${1:t:r}.zip" "${@:t}"
```

### Ask a command-line tool

```zsh
#!/bin/zsh
# name: Explain Command
# icon: questionmark.circle
# match: ^[a-z0-9_-]+$

man -P cat "$POPOLI_TEXT" 2>/dev/null | col -b | sed -n '/^NAME/,/^SYNOPSIS/p' | head -5
```

## Installing and sharing extensions

**What the review window checks:** before installing, Popoli shows the code and flags patterns worth a second look:

- **In red:**
  - downloading and running code,
  - deleting files,
  - reading keys, passwords or browser data,
  - administrator rights,
  - starting at login,
  - hidden code.

  With a red warning, Return cancels instead of installing.
- **In orange:** connecting to the internet, and controlling other apps.
- **Keys:** an extension that names a `secret:` someone already saved gets it only after you allow it, and only while its file stays the same. See [SECURITY.md](../SECURITY.md).

**The catalog:** [catalog/](../catalog/) in this repository has ready-made extensions, each with a link you can paste into **Install Extension…**. Pull requests with new ones are welcome.


An extension is just text, so it's easy to pass around. However one arrives, Popoli first opens a **review window** that shows:

- what the extension does (runs a script, opens a link, asks for a key…),
- its full code,
- whether it replaces one you already have.

Nothing is installed until you click **Install**, and nothing runs until you use it.

| How | |
|---|---|
| **Select its text** | Anywhere: a GitHub file or gist, a code block in a README, a chat message. When the selection starts with a Popoli header, the bar shows **Install Extension**. |
| **Open a link** | `popoli://install?url=https://…` opens the review window for that file. GitHub file pages (`github.com/…/blob/…`) and gists work too. |
| **Install Extension…** | In the menu bar menu, or **Settings ▸ Buttons ▸ Install…**. Paste a link or choose a file. |
| **Drop a file** | Drop it onto the list in **Settings ▸ Buttons**. |
| **Open the file** | Double-click a `.popoli` file. Scripts can be opened with Popoli from Finder's **Open With** menu. |

To share one, put the file in a gist or a repository and share the link, or paste its text where people can select it. A one-click link for your own web page:

```html
<a href="popoli://install?url=https://gist.githubusercontent.com/you/1234abcd/raw">Install in Popoli</a>
```

GitHub removes custom links such as `popoli://` from READMEs. Readers there can select the code block instead.

- **Limits:** extensions are UTF-8 text files up to 256 KB. Links must be `https://`.
- **Updating:** installing a file with the same name replaces the old one. The review window says so first.

> [!CAUTION]
> Extensions run with your user's permissions. Read an extension before installing it, just like any script you download.
