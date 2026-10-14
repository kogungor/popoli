#!/usr/bin/osascript -l JavaScript
// name: Gemini
// group: Ask
// after: copy
// setting: PROMPT
// description: Opens Gemini with the selection copied, to paste with ⌘V (Gemini takes no text from links)

ObjC.import('AppKit')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
const open = url => $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(url))
// PROMPT (Settings ▸ Buttons ▸ Gemini ▸ Settings…) goes before the selection, e.g. "Explain this:".
const question = () => [env('PROMPT').trim(), env('POPOLI_TEXT')].filter(Boolean).join('\n\n')

// Gemini's web app ignores text in its link, so Popoli copies the question (after: copy).
function run() {
  open('https://gemini.google.com/app')
  return question()
}
