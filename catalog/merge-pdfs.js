#!/usr/bin/osascript -l JavaScript
// name: Merge PDFs
// icon: doc.on.doc
// for: files
// description: Joins the selected PDFs into Merged.pdf

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

ObjC.import('PDFKit')

// Joins the selected PDFs in name order into "Merged.pdf" next to the first one.
function run() {
  const paths = env('POPOLI_FILES').split('\n').filter(Boolean).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
  if (paths.length < 2) fail('Select two or more PDFs')
  const merged = $.PDFDocument.alloc.init
  for (const path of paths) {
    const document = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(path))
    if (document.isNil()) fail(path.split('/').pop() + ' is not a PDF')
    for (let i = 0; i < document.pageCount; i++) merged.insertPageAtIndex(document.pageAtIndex(i), merged.pageCount)
  }
  const folder = paths[0].replace(/\/[^/]*$/, '')
  let out = folder + '/Merged.pdf', n = 2
  while ($.NSFileManager.defaultManager.fileExistsAtPath(out)) out = folder + `/Merged ${n++}.pdf`
  if (!merged.writeToFile(out)) fail('Couldn’t save ' + out.split('/').pop())
  return `Created ${out.split('/').pop()} (${merged.pageCount} pages)`
}
