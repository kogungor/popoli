#!/usr/bin/osascript -l JavaScript
// name: snake_case
// group: Case
// after: paste
// match: ^[^\n]{1,100}(\n[^\n]{0,100})*\n?$
// description: Turns words or another identifier style into snake_case; ⇧-click for CONSTANT_CASE

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
// Turkish and Azerbaijani text (it has one of their own letters) gets their i/ı rules.
const locale = text => /[ğĞşŞıİəƏ]/.test(text) ? 'tr' : undefined
// "fooBar", "HTTPServer", "two words", "snake_case" → their words.
const words = line => line
  .replace(/([\p{Ll}\p{N}])(\p{Lu})/gu, '$1 $2')
  .replace(/(\p{Lu})(\p{Lu}\p{Ll})/gu, '$1 $2')
  .split(/[^\p{L}\p{N}]+/u)
  .filter(Boolean)
// Each line on its own, so a list of names converts in one go.
const eachLine = (text, convert) => text.split('\n').map(line => line.trim() ? convert(line) : line).join('\n')

function run() {
  const constant = env('POPOLI_SHIFT') === '1', text = env('POPOLI_TEXT'), lang = locale(text)
  return eachLine(text, line =>
    words(line).map(word => constant ? word.toLocaleUpperCase(lang) : word.toLocaleLowerCase(lang)).join('_'))
}
