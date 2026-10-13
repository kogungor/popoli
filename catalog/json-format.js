#!/usr/bin/osascript -l JavaScript
// name: Format JSON
// icon: curlybraces
// group: Developer
// match: ^\s*[\[{]
// description: Pretty-prints JSON

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  try {
    return JSON.stringify(JSON.parse(env('POPOLI_TEXT')), null, 2)
  } catch (e) {
    fail('Not valid JSON: ' + e.message)
  }
}
