#!/usr/bin/osascript -l JavaScript
// name: Obsidian
// icon: square.and.pencil
// group: Add to
// after: none
// setting: OBSIDIAN_VAULT

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

ObjC.import('AppKit')

// A new note named after its first line. With OBSIDIAN_VAULT empty, Obsidian uses the vault that is open.
function run() {
  const text = env('POPOLI_TEXT')
  const name = text.split('\n')[0].replace(/[\\/:*?"<>|#^\[\]]/g, ' ').trim().slice(0, 60) || 'Popoli'
  const vault = env('OBSIDIAN_VAULT')
  const url = 'obsidian://new?' + (vault ? 'vault=' + encodeURIComponent(vault) + '&' : '')
    + 'name=' + encodeURIComponent(name) + '&content=' + encodeURIComponent(text)
  $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(url))
}
