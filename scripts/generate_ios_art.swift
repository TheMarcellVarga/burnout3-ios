import AppKit
let root = CommandLine.arguments[1]
func render(_ size: Int, to path: String) {
 let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
 let ctx = NSGraphicsContext.current!.cgContext
 ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 NSColor(calibratedRed:1,green:0.29,blue:0.06,alpha:1).setFill()
 NSRect(x:0,y:0,width:1024,height:1024).fill()
 let cut = NSBezierPath()
 cut.move(to:NSPoint(x:0,y:80));cut.line(to:NSPoint(x:1024,y:310));cut.line(to:NSPoint(x:1024,y:0));cut.line(to:NSPoint(x:0,y:0));cut.close()
 NSColor(calibratedWhite:0.035,alpha:1).setFill();cut.fill()
 let font = NSFont(name:"HelveticaNeue-CondensedBlack",size:670) ?? NSFont.boldSystemFont(ofSize:670)
 let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor(calibratedWhite:0.035,alpha:1)]
 ctx.saveGState(); ctx.concatenate(CGAffineTransform(a:1,b:0,c:0.15,d:1,tx:0,ty:0))
 ("B3" as NSString).draw(at:NSPoint(x:96,y:205),withAttributes:attributes)
 ctx.restoreGState()
 NSColor.white.setFill()
 for i in 0..<3 { NSRect(x:CGFloat(132+i*48),y:155,width:24,height:35).fill() }
 let word: [NSAttributedString.Key:Any] = [.font:NSFont(name:"HelveticaNeue-CondensedBold",size:52)!, .foregroundColor:NSColor.white, .kern:8]
 ("TAKEDOWN" as NSString).draw(at:NSPoint(x:338,y:135),withAttributes:word)
 NSGraphicsContext.restoreGraphicsState()
 let opaque = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 for y in 0..<size { for x in 0..<size {
  let src = rep.bitmapData! + y * rep.bytesPerRow + x * 4
  let dst = opaque.bitmapData! + y * opaque.bytesPerRow + x * 3
  dst[0] = src[0]; dst[1] = src[1]; dst[2] = src[2]
 }}
 try! opaque.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
}
render(1024,to:root+"/AppIcon.appiconset/AppIcon.png")
