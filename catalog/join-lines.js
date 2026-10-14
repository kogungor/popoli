#!/usr/bin/osascript -l JavaScript
// name: Join Lines
// group: Lines
// after: paste
// match: \S[^\n]*\n\s*\S
// setting: SEPARATOR
// description: Joins the lines into one, with a space or the SEPARATOR you set (such as , )

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''

function run() {
  const separator = env('SEPARATOR') || ' '
  return env('POPOLI_TEXT').split('\n').map(line => line.trim()).filter(Boolean).join(separator)
}
