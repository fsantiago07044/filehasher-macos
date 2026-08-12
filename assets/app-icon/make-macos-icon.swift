import AppKit
import CoreGraphics

// Compose a macOS Big Sur-style app icon: the original full-bleed artwork
// clipped into the standard 824x824 rounded-rect tile centered on a 1024
// canvas, with Apple's subtle baked-in drop shadow.
//
// Usage: swift make-macos-icon.swift <input-1024.png> <output-1024.png>

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-macos-icon <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

guard let src = NSImage(contentsOfFile: args[1]),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(args[1])\n".data(using: .utf8)!)
    exit(1)
}

let canvas = 1024
let tile   = CGRect(x: 100, y: 100, width: 824, height: 824)   // Apple icon grid
let radius: CGFloat = 185.4                                     // Apple template corner radius

let ctx = CGContext(data: nil, width: canvas, height: canvas,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Pass 1: the tile silhouette with the standard soft shadow. Fill color is
// irrelevant (the gradient paints over it); it only exists to cast the shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Pass 2: gradient tile background in the hexagon's own dark-navy family,
// slightly lighter at the top — the standard macOS tile treatment.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [CGColor(red: 0x1B/255.0, green: 0x35/255.0, blue: 0x47/255.0, alpha: 1),
              CGColor(red: 0x0B/255.0, green: 0x18/255.0, blue: 0x20/255.0, alpha: 1)]
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 512, y: tile.maxY),
                       end:   CGPoint(x: 512, y: tile.minY),
                       options: [])

// Pass 3: the original hexagon artwork centered in the tile. It keeps its
// transparent surround, so the gradient shows through around it and its
// glow blends on top.
ctx.interpolationQuality = .high
ctx.draw(srcCG, in: tile)
ctx.restoreGState()

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
