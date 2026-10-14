#!/usr/bin/osascript -l JavaScript
// name: Trim Whitespace
// group: Lines
// after: paste
// match: ^\s|\s$|[ \t\u00A0]{2,}|[ \t]\n|\n[ \t]|\n{3,}|\t|\u00A0
// description: Removes spaces at the ends of lines, repeated spaces and extra blank lines

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''

function run() {
  return env('POPOLI_TEXT')
    .split('\n')
    .map(line => line.replace(/[ \t\u00A0]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}
