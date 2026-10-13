#!/usr/bin/osascript -l JavaScript
// name: URL Encode
// icon: link
// group: Encode

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  return encodeURIComponent(env('POPOLI_TEXT'))
}
