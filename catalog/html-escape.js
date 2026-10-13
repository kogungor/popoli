#!/usr/bin/osascript -l JavaScript
// name: HTML Escape
// icon: chevron.left.forwardslash.chevron.right
// group: Encode

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  const map = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }
  return env('POPOLI_TEXT').replace(/[&<>"']/g, c => map[c])
}
