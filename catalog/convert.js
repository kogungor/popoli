#!/usr/bin/osascript -l JavaScript
// name: Convert
// icon: arrow.left.arrow.right
// match: (?i)^\s*-?[0-9][0-9.,]*\s*[^\s0-9]+\s+(to|in)\s+[^\s0-9]+\s*$

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

// "10 km to mi", "70 F in C", "100 USD to EUR": units with macOS's units tool, temperatures
// by formula, currencies with the European Central Bank's rates (frankfurter.dev).
const symbols = { '$': 'USD', '€': 'EUR', '£': 'GBP', '¥': 'JPY', '₺': 'TRY', 'tl': 'TRY' }
const temperatures = { c: 'C', '°c': 'C', celsius: 'C', f: 'F', '°f': 'F', fahrenheit: 'F', k: 'K', kelvin: 'K' }

function number(n) { return String(parseFloat(n.toPrecision(8))) }

function temperature(value, from, to) {
  const celsius = from === 'C' ? value : from === 'F' ? (value - 32) * 5 / 9 : value - 273.15
  return to === 'C' ? celsius : to === 'F' ? celsius * 9 / 5 + 32 : celsius + 273.15
}

function currency(value, from, to) {
  const url = `https://api.frankfurter.dev/v1/latest?base=${from}&symbols=${to}`
  const data = $.NSData.dataWithContentsOfURL($.NSURL.URLWithString(url))
  if (data.isNil()) fail('Couldn’t get exchange rates')
  const rate = JSON.parse(ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding))).rates?.[to]
  if (!rate) fail(`No rate for ${from} → ${to}`)
  return value * rate
}

function run() {
  const [, amount, fromText, toText] = env('POPOLI_TEXT').trim().match(/^(-?[0-9][0-9.,]*)\s*(\S+)\s+(?:to|in)\s+(\S+)$/i)
  const value = parseFloat(amount.includes('.') ? amount.replace(/,/g, '') : amount.replace(/,/g, '.'))
  const from = fromText.toLowerCase(), to = toText.toLowerCase()
  if (temperatures[from] && temperatures[to]) {
    return `${amount} °${temperatures[from]} = ${number(temperature(value, temperatures[from], temperatures[to]))} °${temperatures[to]}`
  }
  const fromCode = symbols[from] ?? fromText.toUpperCase(), toCode = symbols[to] ?? toText.toUpperCase()
  if (/^[A-Z]{3}$/.test(fromCode) && /^[A-Z]{3}$/.test(toCode) && (symbols[from] || symbols[to] || fromCode === fromText)) {
    return `${amount} ${fromCode} = ${number(currency(value, fromCode, toCode))} ${toCode}`
  }
  const app = Application.currentApplication()
  app.includeStandardAdditions = true
  let result
  try {
    result = app.doShellScript(`/usr/bin/units -t ${quoted(value + ' ' + fromText)} ${quoted(toText)}`)
  } catch (e) {
    fail(`Can’t convert ${fromText} to ${toText}`)
  }
  if (!/^-?[0-9.e+-]+$/i.test(result.trim())) fail(`Can’t convert ${fromText} to ${toText}`)
  return `${amount} ${fromText} = ${number(parseFloat(result))} ${toText}`
}

function quoted(text) { return "'" + text.replace(/'/g, "'\\''") + "'" }
