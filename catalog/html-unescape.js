#!/usr/bin/osascript -l JavaScript
// name: HTML Unescape
// icon: chevron.left.forwardslash.chevron.right
// group: Decode
// match: &(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);

ObjC.import('Foundation'); ObjC.import('stdlib'); ObjC.import('AppKit')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

// Less common names (&eacute;, &euro;…) are looked up with the system's HTML reader.
function other(name) {
  const data = $('&' + name + ';').dataUsingEncoding($.NSUTF8StringEncoding)
  const decoded = $.NSAttributedString.alloc.initWithHTMLDocumentAttributes(data, null)
  const text = decoded.isNil() ? '' : ObjC.unwrap(decoded.string)
  return text && text !== '&' + name + ';' ? text : undefined
}

function run() {
  const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0', copy: '©', reg: '®', hellip: '…', mdash: '—', ndash: '–' }
  return env('POPOLI_TEXT').replace(/&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);/g, (whole, code) => {
    if (code[0] !== '#') return named[code] ?? other(code) ?? whole
    const number = code[1] === 'x' || code[1] === 'X' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10)
    return String.fromCodePoint(number)
  })
}
