// Draws the placeholder app icon (1024×1024, opaque): an open book in gold on plum, with sound bars on the right page.
// Run from the repo root:  swift ios/tools/make-icon.swift ios/Earmark/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }

// Background: plum with a soft lighter glow at the top left (no transparency; iOS masks the corners).
ctx.setFillColor(rgb(0x4A2140))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x7A3566), rgb(0x4A2140)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 300, y: 760), endRadius: 760, options: [])

let gold = rgb(0xE8C77A)
ctx.setStrokeColor(gold)
ctx.setFillColor(gold)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Open book: two pages meeting at the spine (y grows upwards in CoreGraphics).
let spineTop = CGPoint(x: 512, y: 700), spineBottom = CGPoint(x: 512, y: 300)
let left = CGMutablePath()
left.move(to: spineBottom)
left.addLine(to: spineTop)
left.addQuadCurve(to: CGPoint(x: 210, y: 730), control: CGPoint(x: 370, y: 770))
left.addLine(to: CGPoint(x: 210, y: 330))
left.addQuadCurve(to: spineBottom, control: CGPoint(x: 370, y: 370))
ctx.addPath(left)
let right = CGMutablePath()
right.move(to: spineBottom)
right.addLine(to: spineTop)
right.addQuadCurve(to: CGPoint(x: 814, y: 730), control: CGPoint(x: 654, y: 770))
right.addLine(to: CGPoint(x: 814, y: 330))
right.addQuadCurve(to: spineBottom, control: CGPoint(x: 654, y: 370))
ctx.addPath(right)
ctx.strokePath()

// Text lines on the left page, sound bars on the right page.
ctx.setLineWidth(26)
for (i, y) in [600, 530, 460].enumerated() {
    ctx.move(to: CGPoint(x: 280, y: y))
    ctx.addLine(to: CGPoint(x: i == 2 ? 380 : 440, y: y))
}
ctx.strokePath()
for (x, h) in [(590, 110), (650, 220), (710, 150), (770, 70)] {
    ctx.move(to: CGPoint(x: x, y: 530 - h / 2))
    ctx.addLine(to: CGPoint(x: x, y: 530 + h / 2))
}
ctx.strokePath()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("cannot write \(out)") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(out)") }
print("wrote \(out)")
