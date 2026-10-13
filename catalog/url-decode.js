#!/usr/bin/osascript -l JavaScript
// name: URL Decode
// icon: link
// group: Decode
// match: %[0-9A-Fa-f]{2}
// description: Decodes %20-style URL encoding

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  try {
    return decodeURIComponent(env('POPOLI_TEXT').replace(/\+/g, ' '))
  } catch (e) {
    fail('Not valid URL encoding')
  }
}
