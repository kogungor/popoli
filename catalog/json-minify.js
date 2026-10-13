#!/usr/bin/osascript -l JavaScript
// name: Minify JSON
// icon: curlybraces
// group: Developer
// match: ^\s*[\[{]
// description: Puts JSON on one line

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  try {
    return JSON.stringify(JSON.parse(env('POPOLI_TEXT')))
  } catch (e) {
    fail('Not valid JSON: ' + e.message)
  }
}
