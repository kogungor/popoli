#!/usr/bin/osascript -l JavaScript
// name: Hex ↔ Decimal
// icon: number
// group: Developer
// match: ^\s*(0[xX][0-9A-Fa-f]+|[0-9]+|[0-9A-Fa-f]*[A-Fa-f][0-9A-Fa-f]*)\s*$
// description: Shows a number in decimal, hex and binary

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  const text = env('POPOLI_TEXT').trim()
  // Digits only read as decimal; anything with a-f (or 0x) as hex.
  const hex = /^0x/i.test(text) || /[a-f]/i.test(text)
  const value = BigInt(hex ? '0x' + text.replace(/^0x/i, '') : text)
  return `Decimal: ${value.toString(10)}\nHex: 0x${value.toString(16).toUpperCase()}\nBinary: ${value.toString(2)}`
}
