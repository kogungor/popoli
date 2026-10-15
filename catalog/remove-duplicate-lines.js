#!/usr/bin/osascript -l JavaScript
// name: Remove Duplicates
// icon: square.on.square.dashed
// group: Lines
// after: paste
// match: \S[^\n]*\n\s*\S
// description: Keeps the first of each repeated line, in the original order; blank lines stay

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''

function run() {
  const seen = new Set()
  return env('POPOLI_TEXT').split('\n').filter(line => {
    const key = line.trimEnd()
    if (!key) return true
    if (seen.has(key)) return false
    seen.add(key)
    return true
  }).join('\n')
}
