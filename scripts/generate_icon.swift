#!/usr/bin/env swift
// Generates AppIcon.iconset (all sizes) from drawn vector shapes — no external
// image assets needed. Run via generate_icon.sh, which also builds the .icns.
import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

struct Spec { let name: String; let size: CGFloat }
let specs: [Spec] = [
    Spec(name: "icon_16x16", size: 16),
    Spec(name: "icon_16x16@2x", size: 32),
    Spec(name: "icon_32x32", size: 32),
    Spec(name: "icon_32x32@2x", size: 64),
    Spec(name: "icon_128x128", size: 128),
    Spec(name: "icon_128x128@2x", size: 256),
    Spec(name: "icon_256x256", size: 256),
    Spec(name: "icon_256x256@2x", size: 512),
    Spec(name: "icon_512x512", size: 512),
    Spec(name: "icon_512x512@2x", size: 1024),
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225 // macOS "squircle-ish" rounded square
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Background: deep blue-to-teal gradient, matching a "device control" feel.
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        CGColor(red: 0.09, green: 0.15, blue: 0.27, alpha: 1),
        CGColor(red: 0.05, green: 0.35, blue: 0.45, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: size, y: 0),
            options: []
        )
    }
    ctx.restoreGState()

    // TV body
    let tvMarginX = size * 0.16
    let tvTop = size * 0.30
    let tvBottom = size * 0.68
    let tvRect = CGRect(x: tvMarginX, y: tvTop, width: size - tvMarginX * 2, height: tvBottom - tvTop)
    let tvCorner = size * 0.05
    let tvPath = CGPath(roundedRect: tvRect, cornerWidth: tvCorner, cornerHeight: tvCorner, transform: nil)

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.addPath(tvPath)
    ctx.fillPath()

    // Screen inset (dark), suggesting an active display
    let inset = size * 0.035
    let screenRect = tvRect.insetBy(dx: inset, dy: inset)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: tvCorner * 0.6, cornerHeight: tvCorner * 0.6, transform: nil)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 1))
    ctx.addPath(screenPath)
    ctx.fillPath()

    // Screen "signal wave" glyph
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.85, blue: 0.75, alpha: 1))
    let waveWidth = size * 0.014
    ctx.setLineWidth(waveWidth)
    ctx.setLineCap(.round)
    let midY = screenRect.midY
    let waveStartX = screenRect.minX + screenRect.width * 0.18
    let waveEndX = screenRect.maxX - screenRect.width * 0.18
    let radii: [CGFloat] = [0.14, 0.24, 0.34]
    for r in radii {
        let radius = screenRect.width * r
        let arcRect = CGRect(x: waveStartX - radius, y: midY - radius, width: radius * 2, height: radius * 2)
        ctx.addArc(
            center: CGPoint(x: waveStartX, y: midY),
            radius: radius,
            startAngle: -.pi / 3.4,
            endAngle: .pi / 3.4,
            clockwise: false
        )
        ctx.strokePath()
        _ = arcRect
    }
    ctx.setFillColor(CGColor(red: 0.35, green: 0.85, blue: 0.75, alpha: 1))
    let dotRadius = size * 0.018
    ctx.addEllipse(in: CGRect(x: waveStartX - dotRadius, y: midY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    ctx.fillPath()
    _ = waveEndX

    // TV stand — attaches below the screen's visual bottom edge (tvRect.minY,
    // since this context has a bottom-left origin with y increasing upward).
    let standWidth = size * 0.30
    let standHeight = size * 0.045
    let standGap = size * 0.01
    let standRect = CGRect(x: size / 2 - standWidth / 2, y: tvRect.minY - standGap - standHeight, width: standWidth, height: standHeight)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.addPath(CGPath(roundedRect: standRect, cornerWidth: standHeight / 2, cornerHeight: standHeight / 2, transform: nil))
    ctx.fillPath()
    let baseWidth = size * 0.46
    let baseHeight = size * 0.035
    let baseRect = CGRect(x: size / 2 - baseWidth / 2, y: standRect.minY - baseHeight, width: baseWidth, height: baseHeight)
    ctx.addPath(CGPath(roundedRect: baseRect, cornerWidth: baseHeight / 2, cornerHeight: baseHeight / 2, transform: nil))
    ctx.fillPath()

    image.unlockFocus()
    return image
}

for spec in specs {
    let image = drawIcon(size: spec.size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(spec.name)\n".data(using: .utf8)!)
        continue
    }
    let path = (outputDir as NSString).appendingPathComponent("\(spec.name).png")
    try? png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}
