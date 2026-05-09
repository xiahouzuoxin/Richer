// Generates Richer's app-icon PNGs into the AppIcon.appiconset.
// Run from the repo root:
//     swift tools/GenerateIcon.swift
//
// Design: squircle background with a pink → purple gradient, a tilted "magic wand"
// stroke, and three 4-pointed sparkle stars sprinkled around it.

import AppKit
import CoreGraphics

let outputDir = "Richer/Resources/Assets.xcassets/AppIcon.appiconset"

struct IconSize { let name: String; let px: Int }

let sizes: [IconSize] = [
    IconSize(name: "icon_16x16.png",     px: 16),
    IconSize(name: "icon_16x16@2x.png",  px: 32),
    IconSize(name: "icon_32x32.png",     px: 32),
    IconSize(name: "icon_32x32@2x.png",  px: 64),
    IconSize(name: "icon_128x128.png",   px: 128),
    IconSize(name: "icon_128x128@2x.png", px: 256),
    IconSize(name: "icon_256x256.png",   px: 256),
    IconSize(name: "icon_256x256@2x.png", px: 512),
    IconSize(name: "icon_512x512.png",   px: 512),
    IconSize(name: "icon_512x512@2x.png", px: 1024),
]

func drawIcon(size px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Squircle clip (Apple's continuous corner ratio is roughly 22.37% of side).
    let cornerRadius = s * 0.2237
    let bgPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Diagonal pink → purple gradient (top-left lighter, bottom-right deeper).
    let topLeft  = CGColor(red: 1.00, green: 0.45, blue: 0.65, alpha: 1.0)
    let bottomRt = CGColor(red: 0.42, green: 0.16, blue: 0.92, alpha: 1.0)
    let gradient = CGGradient(colorsSpace: cs,
                              colors: [topLeft, bottomRt] as CFArray,
                              locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])

    // Soft top-edge highlight for a subtle 3D feel.
    let hi1 = CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)
    let hi2 = CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    let highlight = CGGradient(colorsSpace: cs,
                               colors: [hi1, hi2] as CFArray,
                               locations: [0.0, 1.0])!
    ctx.drawLinearGradient(highlight,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: s * 0.55),
                           options: [])

    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1.0)
    let softWhite = CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
    let stroke = max(s * 0.055, 1)

    // Wand shaft: from lower-left to upper-right.
    let cx = s / 2
    let cy = s / 2
    let length = s * 0.55
    let angle: CGFloat = 38 * .pi / 180
    let dx = cos(angle) * length / 2
    let dy = sin(angle) * length / 2

    let tailX = cx - dx
    let tailY = cy - dy
    let headX = cx + dx
    let headY = cy + dy

    ctx.setStrokeColor(white)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: tailX, y: tailY))
    ctx.addLine(to: CGPoint(x: headX - dx * 0.18, y: headY - dy * 0.18))
    ctx.strokePath()

    // 4-pointed sparkle "+" with concave diamond fill.
    func drawSparkle(at p: CGPoint, radius r: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.setFillColor(color)
        // Concave 4-pointed star: 4 outer cardinal points pulled in by inner control points.
        let path = CGMutablePath()
        let inner = r * 0.22
        path.move   (to: CGPoint(x: p.x,         y: p.y + r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y),
                          control: CGPoint(x: p.x + inner, y: p.y + inner))
        path.addQuadCurve(to: CGPoint(x: p.x,    y: p.y - r),
                          control: CGPoint(x: p.x + inner, y: p.y - inner))
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y),
                          control: CGPoint(x: p.x - inner, y: p.y - inner))
        path.addQuadCurve(to: CGPoint(x: p.x,    y: p.y + r),
                          control: CGPoint(x: p.x - inner, y: p.y + inner))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Main star at the wand tip.
    drawSparkle(at: CGPoint(x: headX, y: headY), radius: s * 0.165, color: white)

    // Two small accent sparkles.
    drawSparkle(at: CGPoint(x: cx + dx * 0.10, y: cy - dy * 0.55),
                radius: s * 0.07, color: softWhite)
    drawSparkle(at: CGPoint(x: cx - dx * 0.55, y: cy + dy * 0.55),
                radius: s * 0.05, color: softWhite)

    ctx.restoreGState()

    let cgImage = ctx.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])!
}

// Menu-bar template icon: just the wand glyph in alpha, no squircle background.
// macOS tints template images automatically based on appearance.
func drawMenuBarIcon(size px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let opaque = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let stroke = max(s * 0.10, 1.5)
    ctx.setStrokeColor(opaque)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setFillColor(opaque)

    let cx = s / 2
    let cy = s / 2
    let length = s * 0.78
    let angle: CGFloat = 38 * .pi / 180
    let dx = cos(angle) * length / 2
    let dy = sin(angle) * length / 2
    let tailX = cx - dx
    let tailY = cy - dy
    let headX = cx + dx
    let headY = cy + dy

    // Wand shaft (stop short of the tip; the sparkle covers the gap).
    ctx.beginPath()
    ctx.move(to: CGPoint(x: tailX, y: tailY))
    ctx.addLine(to: CGPoint(x: headX - dx * 0.22, y: headY - dy * 0.22))
    ctx.strokePath()

    // 4-point sparkle helper.
    func sparkle(at p: CGPoint, radius r: CGFloat) {
        let path = CGMutablePath()
        let inner = r * 0.22
        path.move(to: CGPoint(x: p.x, y: p.y + r))
        path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y),
                          control: CGPoint(x: p.x + inner, y: p.y + inner))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r),
                          control: CGPoint(x: p.x + inner, y: p.y - inner))
        path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y),
                          control: CGPoint(x: p.x - inner, y: p.y - inner))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r),
                          control: CGPoint(x: p.x - inner, y: p.y + inner))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    sparkle(at: CGPoint(x: headX, y: headY), radius: s * 0.22)
    sparkle(at: CGPoint(x: cx - dx * 0.65, y: cy + dy * 0.55), radius: s * 0.10)

    let cgImage = ctx.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    return bitmap.representation(using: .png, properties: [:])!
}

let menuBarDir = "Richer/Resources/Assets.xcassets/MenuBarIcon.imageset"

let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)

for entry in sizes {
    let data = drawIcon(size: entry.px)
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(entry.name)
    try data.write(to: url)
    print("Wrote \(url.path) (\(entry.px)x\(entry.px))")
}

// Menu bar: 18x18 @1x and 36x36 @2x are the standard sizes.
struct MenuSize { let name: String; let px: Int }
let menuSizes: [MenuSize] = [
    MenuSize(name: "menubar_18.png",     px: 18),
    MenuSize(name: "menubar_18@2x.png",  px: 36),
]
for entry in menuSizes {
    let data = drawMenuBarIcon(size: entry.px)
    let url = URL(fileURLWithPath: menuBarDir).appendingPathComponent(entry.name)
    try data.write(to: url)
    print("Wrote \(url.path) (\(entry.px)x\(entry.px))")
}

// Write Contents.json for menu bar imageset (template rendering).
let menuContents = """
{
  "images" : [
    { "filename" : "menubar_18.png",    "idiom" : "universal", "scale" : "1x" },
    { "filename" : "menubar_18@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "template"
  }
}
"""
try menuContents.write(
    toFile: "\(menuBarDir)/Contents.json",
    atomically: true,
    encoding: .utf8
)

print("Done.")
