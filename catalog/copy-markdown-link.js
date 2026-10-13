#!/usr/bin/osascript -l JavaScript
// name: Copy as Markdown Link
// icon: link.badge.plus
// for: files
// after: copy
// description: Copies a Markdown link to each selected file

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  return env('POPOLI_FILES').split('\n').filter(Boolean).map(path => {
    const url = $.NSURL.fileURLWithPath(path)
    return `[${ObjC.unwrap(url.lastPathComponent)}](${ObjC.unwrap(url.absoluteString)})`
  }).join('\n')
}
