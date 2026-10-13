#!/usr/bin/osascript -l JavaScript
// name: Base64
// icon: textformat.abc
// group: Decode
// match: ^\s*[A-Za-z0-9+/_-]{8,}={0,2}\s*$

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

function run() {
  // Also takes the URL-safe alphabet and missing padding.
  let text = env('POPOLI_TEXT').trim().replace(/-/g, '+').replace(/_/g, '/')
  while (text.length % 4) text += '='
  const data = $.NSData.alloc.initWithBase64EncodedStringOptions($(text), 0)
  if (data.isNil()) fail('Not Base64')
  const decoded = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
  if (decoded.isNil()) fail('Not text: the Base64 holds binary data')
  return ObjC.unwrap(decoded)
}
