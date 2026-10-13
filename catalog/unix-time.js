#!/usr/bin/osascript -l JavaScript
// name: Unix Time
// icon: clock
// group: Developer
// output: html
// match: ^\s*[0-9]{9,13}(\.[0-9]+)?\s*$

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  const value = parseFloat(env('POPOLI_TEXT'))
  // 13 digits are milliseconds.
  const date = new Date(env('POPOLI_TEXT').trim().split('.')[0].length > 11 ? value : value * 1000)
  const seconds = Math.round((Date.now() - date.getTime()) / 1000)
  const units = [[31536000, 'year'], [2592000, 'month'], [86400, 'day'], [3600, 'hour'], [60, 'minute'], [1, 'second']]
  const [size, unit] = units.find(([size]) => Math.abs(seconds) >= size) ?? [1, 'second']
  const count = Math.floor(Math.abs(seconds) / size)
  const relative = count === 0 ? 'now' : `${count} ${unit}${count === 1 ? '' : 's'} ${seconds > 0 ? 'ago' : 'from now'}`
  return `<b>${date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'medium' })}</b> · ${relative}`
    + `<br><code>${date.toISOString().replace('.000Z', 'Z')}</code> UTC`
}
