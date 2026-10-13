#!/usr/bin/osascript -l JavaScript
// name: Calendar
// icon: calendar.badge.plus
// group: Add to
// after: none

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

ObjC.import('AppKit')

// Finds a date in the selection ("lunch next Friday at 1pm") and opens an event for it in
// Calendar, which asks which calendar to add it to. No Automation permission is needed.
function stamp(date) { return date.toISOString().replace(/[-:]/g, '').replace(/\.[0-9]{3}/, '') }

function run() {
  const text = env('POPOLI_TEXT').trim()
  const detector = $.NSDataDetector.dataDetectorWithTypesError($.NSTextCheckingTypeDate, null)
  const match = detector.firstMatchInStringOptionsRange($(text), 0, $.NSMakeRange(0, text.length))
  if (match.isNil()) fail('No date or time found')
  const start = new Date(ObjC.unwrap(match.date.timeIntervalSince1970) * 1000)
  const seconds = ObjC.unwrap(match.duration)
  const end = new Date(start.getTime() + (seconds > 0 ? seconds : 3600) * 1000)
  const title = text.replace(/\s+/g, ' ').slice(0, 120).replace(/[\\;,]/g, c => '\\' + c)
  const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Popoli//Calendar//EN', 'BEGIN:VEVENT',
    'UID:' + ObjC.unwrap($.NSUUID.UUID.UUIDString) + '@popoli', 'DTSTAMP:' + stamp(new Date()),
    'DTSTART:' + stamp(start), 'DTEND:' + stamp(end), 'SUMMARY:' + title, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n')
  const file = ObjC.unwrap($.NSTemporaryDirectory()) + 'Popoli Event.ics'
  $(ics).writeToFileAtomicallyEncodingError(file, true, $.NSUTF8StringEncoding, null)
  $.NSWorkspace.sharedWorkspace.openURLsWithApplicationAtURLConfigurationCompletionHandler(
    $([$.NSURL.fileURLWithPath(file)]), $.NSURL.fileURLWithPath('/System/Applications/Calendar.app'),
    $.NSWorkspaceOpenConfiguration.configuration, null)
}
