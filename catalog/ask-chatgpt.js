#!/usr/bin/osascript -l JavaScript
// name: ChatGPT
// group: Ask
// setting: PROMPT
// description: Asks ChatGPT about the selection, in your browser with your own ChatGPT account

ObjC.import('AppKit')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
const open = url => $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(url))
// PROMPT (Settings ▸ Buttons ▸ ChatGPT ▸ Settings…) goes before the selection, e.g. "Explain this:".
const question = () => [env('PROMPT').trim(), env('POPOLI_TEXT')].filter(Boolean).join('\n\n')
function copy(text) {
  const board = $.NSPasteboard.generalPasteboard
  board.clearContents
  board.setStringForType($(text), $.NSPasteboardTypeString)
}

function run() {
  const text = question()
  const link = 'https://chatgpt.com/?q=' + encodeURIComponent(text)
  if (link.length <= 8000) {
    open(link)
    return ''
  }
  // A very long selection doesn't fit in a link: it goes on the clipboard instead.
  copy(text)
  open('https://chatgpt.com/')
  return 'The text is too long for a link, so it was copied: paste it into ChatGPT with ⌘V.'
}
