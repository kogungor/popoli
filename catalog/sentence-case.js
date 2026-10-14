#!/usr/bin/osascript -l JavaScript
// name: Sentence case
// group: Case
// after: paste
// match: \p{L}
// description: Lowercases the text and capitalizes the first letter of each sentence and line

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
// Turkish and Azerbaijani text (it has one of their own letters) gets their i/ı rules.
const locale = text => /[ğĞşŞıİəƏ]/.test(text) ? 'tr' : undefined

function run() {
  const text = env('POPOLI_TEXT'), lang = locale(text)
  return text
    .toLocaleLowerCase(lang)
    .replace(/(^|[.!?…]\s+|\n\s*)(\p{Ll})/gu, (_, before, letter) => before + letter.toLocaleUpperCase(lang))
}
