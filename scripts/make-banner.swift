#!/usr/bin/env swift
// make-banner.swift — renders the promotional banner used at the top of the
// README and the landing page.
//
// This is deliberately designed artwork, not a screenshot: real screenshots of
// the app go in docs/assets/screenshot-*.png and must be captured by hand.
//
// Usage: swift scripts/make-banner.swift [output-dir]

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let W: CGFloat = 1600, H: CGFloat = 620

/// The app mark, reused from the icon so the banner and the icon agree.
func drawMark(in ctx: CGContext, center: CGPoint, size: CGFloat) {
    let radius = size * 0.34
    let lineWidth = size * 0.14
    ctx.saveGState()
    ctx.setLineCap(.round)

    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.26).cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: radius,
               startAngle: .pi * 0.72, endAngle: .pi * 0.28, clockwise: false)
    ctx.strokePath()

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: radius,
               startAngle: .pi * 0.72, endAngle: .pi * 1.62, clockwise: false)
    ctx.strokePath()

    let a = size * 0.105
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(size * 0.066)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: center.x, y: center.y + a * 1.15))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - a * 0.55))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: center.x - a * 0.82, y: center.y + a * 0.05))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - a * 0.85))
    ctx.addLine(to: CGPoint(x: center.x + a * 0.82, y: center.y + a * 0.05))
    ctx.strokePath()
    ctx.restoreGState()
}

func text(_ s: String, _ font: NSFont, _ color: NSColor,
          center x: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let size = str.size()
    str.draw(at: NSPoint(x: x - size.width / 2, y: y))
}

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.setShouldAntialias(true)

// Background: near-black with an indigo bloom behind the mark.
ctx.setFillColor(NSColor(srgbRed: 0.043, green: 0.047, blue: 0.078, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let bloom = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.33, green: 0.31, blue: 0.95, alpha: 0.55).cgColor,
        NSColor(srgbRed: 0.33, green: 0.31, blue: 0.95, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    bloom,
    startCenter: CGPoint(x: W / 2, y: H * 0.92), startRadius: 0,
    endCenter: CGPoint(x: W / 2, y: H * 0.92), endRadius: W * 0.52, options: [])

// The mark, on its own gradient squircle.
let plateSize: CGFloat = 168
let plate = CGRect(x: W / 2 - plateSize / 2, y: H - 120 - plateSize,
                   width: plateSize, height: plateSize)
ctx.saveGState()
let corner = plateSize * 0.2237
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner,
                   cornerHeight: corner, transform: nil))
ctx.clip()
let plateGrad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 0.24, green: 0.36, blue: 0.96, alpha: 1).cgColor,
        NSColor(srgbRed: 0.36, green: 0.22, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    plateGrad, start: CGPoint(x: plate.minX, y: plate.maxY),
    end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
ctx.restoreGState()
drawMark(in: ctx, center: CGPoint(x: plate.midX, y: plate.midY), size: plateSize)

// Wordmark and tagline.
text("Disk Spacer",
     .systemFont(ofSize: 92, weight: .bold), .white,
     center: W / 2, y: H - 400)
text("See what is using your disk. Clean it safely.",
     .systemFont(ofSize: 36, weight: .regular),
     NSColor(srgbRed: 0.72, green: 0.75, blue: 0.85, alpha: 1),
     center: W / 2, y: H - 462)
text("Free · Open source · macOS 14+",
     .systemFont(ofSize: 26, weight: .medium),
     NSColor(srgbRed: 0.45, green: 0.48, blue: 0.62, alpha: 1),
     center: W / 2, y: H - 530)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode banner")
}
let path = (outDir as NSString).appendingPathComponent("hero.png")
FileManager.default.createFile(atPath: path, contents: data)
print("wrote \(path)")
