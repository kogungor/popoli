#!/usr/bin/osascript -l JavaScript
// name: Decode JWT
// icon: key
// group: Developer
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

function run() {
  // Decoding only: the signature is not checked.
  const [header, payload] = env('POPOLI_TEXT').trim().split('.')
  const claims = decode(payload)
  const dates = ['exp', 'iat', 'nbf'].filter(key => typeof claims[key] === 'number')
    .map(key => `${key}: ${new Date(claims[key] * 1000).toLocaleString()}${key === 'exp' && claims.exp * 1000 < Date.now() ? ' (expired)' : ''}`)
  return ['Header', JSON.stringify(decode(header), null, 2), '', 'Payload', JSON.stringify(claims, null, 2)]
    .concat(dates.length ? ['', ...dates] : []).join('\n')
}
