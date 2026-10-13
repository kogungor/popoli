#!/usr/bin/osascript -l JavaScript
// name: Decode JWT
// icon: key
// group: Developer
// output: html
// match: ^\s*eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\s*$

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function decode(part) {
  let text = part.replace(/-/g, '+').replace(/_/g, '/')
  while (text.length % 4) text += '='
  const data = $.NSData.alloc.initWithBase64EncodedStringOptions($(text), 0)
  if (data.isNil()) fail('Not a JWT')
  return JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)))
}

function escape(text) { return text.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]) }

function run() {
  // Decoding only: the signature is not checked.
  const [header, payload] = env('POPOLI_TEXT').trim().split('.')
  const claims = decode(payload)
  const dates = ['exp', 'iat', 'nbf'].filter(key => typeof claims[key] === 'number').map(key => {
    const date = new Date(claims[key] * 1000)
    const expired = key === 'exp' && date < new Date()
    return `<tr><td><code>${key}</code></td><td>${escape(date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }))}`
      + (expired ? ' <span style="color:#ff453a;font-weight:600">expired</span>' : '') + '</td></tr>'
  })
  return `<b>Header</b><pre>${escape(JSON.stringify(decode(header), null, 2))}</pre>`
    + `<b>Payload</b><pre>${escape(JSON.stringify(claims, null, 2))}</pre>`
    + (dates.length ? `<table>${dates.join('')}</table>` : '')
}
