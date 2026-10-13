#!/usr/bin/osascript -l JavaScript
// name: QR Code
// icon: qrcode
// group: Encode
// output: html
// description: Shows a QR code of the text

ObjC.import('Foundation'); ObjC.import('stdlib')
const env = name => ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(name)) ?? ''
function fail(message) {
  $.NSFileHandle.fileHandleWithStandardError.writeData($(message + '\n').dataUsingEncoding($.NSUTF8StringEncoding))
  $.exit(1)
}

ObjC.import('CoreImage'); ObjC.import('AppKit')

function run() {
  const text = env('POPOLI_TEXT')
  if (text.length > 1500) fail('Too long for a QR code')
  const filter = $.CIFilter.filterWithName('CIQRCodeGenerator')
  filter.setValueForKey($(text).dataUsingEncoding($.NSUTF8StringEncoding), 'inputMessage')
  filter.setValueForKey($('M'), 'inputCorrectionLevel')
  // Scale the tiny code up without blurring.
  const image = filter.outputImage.imageByApplyingTransform($.CGAffineTransformMakeScale(8, 8))
  const rep = $.NSBitmapImageRep.alloc.initWithCIImage(image)
  const png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}))
  const data = ObjC.unwrap(png.base64EncodedStringWithOptions(0))
  return `<div style="text-align:center"><img src="data:image/png;base64,${data}" style="width:200px;height:200px;image-rendering:pixelated;background:white;padding:10px;border-radius:8px"></div>`
}
