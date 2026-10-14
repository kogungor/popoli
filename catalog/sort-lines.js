#!/usr/bin/osascript -l JavaScript
// name: Sort Lines
// group: Lines
// after: paste
// match: \S[^\n]*\n\s*\S
// description: Sorts the lines A to Z, with numbers in order (2 before 10); ⇧-click for Z to A

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''

function run() {
  const text = env('POPOLI_TEXT')
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' })
  const lines = text.split('\n').filter(line => line.trim()).sort(collator.compare)
  if (env('POPOLI_SHIFT') === '1') lines.reverse()
  return lines.join('\n') + (text.endsWith('\n') ? '\n' : '')
}
