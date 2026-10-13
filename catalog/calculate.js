#!/usr/bin/osascript -l JavaScript
// name: Calculate
// icon: equal.circle
// match: ^(?=.*[0-9])(?=.*[-+*/^%x×÷])[0-9\s+\-*/().,^%x×÷]+$
// description: Works out a calculation such as 12*(3+4)/2

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  let expression = env('POPOLI_TEXT').replace(/\s+/g, '').replace(/[x×]/g, '*').replace(/÷/g, '/').replace(/\^/g, '**')
  // A comma is the decimal mark when there is no dot (1,5*2), a thousands separator otherwise.
  expression = expression.includes('.') ? expression.replace(/,/g, '') : expression.replace(/,/g, '.')
  if (!/^[0-9+\-*/().%]+$/.test(expression)) fail('Not a calculation')
  let result
  try {
    result = Function('"use strict"; return (' + expression + ')')()
  } catch (e) {
    fail('Not a calculation')
  }
  if (typeof result !== 'number' || !isFinite(result)) fail('No result')
  return String(parseFloat(result.toPrecision(12)))
}
