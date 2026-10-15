#!/usr/bin/osascript -l JavaScript
// name: Slug
// icon: link
// group: Case
// after: paste
// match: ^[^\n]{1,100}(\n[^\n]{0,100})*\n?$
// description: Makes a URL slug: “Crème brûlée, s’il vous plaît!” → creme-brulee-s-il-vous-plait

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

// Letters that don't break down into a base letter and an accent.
const special = { ı: 'i', ß: 'ss', æ: 'ae', ø: 'o', œ: 'oe', đ: 'd', ð: 'd', ł: 'l', þ: 'th' }

function slug(line) {
  return line.toLowerCase()
    .replace(/[ıßæøœđðłþ]/g, letter => special[letter])
    .normalize('NFD').replace(/\p{M}/gu, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

function run() {
  const lines = env('POPOLI_TEXT').split('\n').map(line => line.trim() ? slug(line) : line)
  if (!lines.some(Boolean)) fail('No Latin letters or digits to make a slug from')
  return lines.join('\n')
}
