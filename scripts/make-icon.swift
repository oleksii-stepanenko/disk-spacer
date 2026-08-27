#!/usr/bin/env swift
// make-icon.swift — renders the Disk Spacer app icon and writes AppIcon.icns
// plus the PNGs used by the README and landing page.
//
// The generated .icns is committed, so CI never has to render it.
//
// Usage: swift scripts/make-icon.swift [output-dir]

import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

/// Draws the icon at an arbitrary size.
///
/// The mark is a ring gauge — the shape everyone already reads as "disk space"
/// — drawn mostly full, with a bright wedge showing the part being reclaimed
/// and a gap where it has been cleared.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus(); return image
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS icons sit on a squircle with a little breathing room.
    let inset = size * 0.055
    let plate = rect.insetBy(dx: inset, dy: inset)
    let corner = plate.width * 0.2237          // Apple's continuous-corner ratio
    let squircle = CGPath(roundedRect: plate,
                          cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Background: deep indigo → blue, top-left to bottom-right.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.24, green: 0.36, blue: 0.96, alpha: 1).cgColor,
            NSColor(srgbRed: 0.36, green: 0.22, blue: 0.86, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        bg, start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY), options: [])

    // Soft highlight so the plate doesn't read flat at large sizes.
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 1, alpha: 0.22).cgColor,
            NSColor(white: 1, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: plate.midX, y: plate.maxY), startRadius: 0,
        endCenter: CGPoint(x: plate.midX, y: plate.maxY), endRadius: plate.width * 0.85,
        options: [])
    ctx.restoreGState()

    // The gauge.
    let center = CGPoint(x: plate.midX, y: plate.midY)
    let radius = plate.width * 0.283
    let lineWidth = plate.width * 0.115
    ctx.setLineCap(.round)

    // Track: the space still in use.
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.28).cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: radius,
               startAngle: .pi * 0.72, endAngle: .pi * 0.28,
               clockwise: false)
    ctx.strokePath()

    // Reclaimed arc: bright, sweeping back from the top.
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: center, radius: radius,
               startAngle: .pi * 0.72, endAngle: .pi * 1.62,
               clockwise: false)
    ctx.strokePath()

    // Downward arrow in the middle: space coming back.
    let a = plate.width * 0.088
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setLineWidth(plate.width * 0.055)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineJoin(.round)

    ctx.move(to: CGPoint(x: center.x, y: center.y + a * 1.15))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - a * 0.55))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: center.x - a * 0.82, y: center.y + a * 0.05))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y - a * 0.85))
    ctx.addLine(to: CGPoint(x: center.x + a * 0.82, y: center.y + a * 0.05))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, size: CGFloat) -> Data {
    // Re-render at the exact pixel size rather than scaling, so small sizes
    // stay crisp instead of turning to mush.
    let img = drawIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("failed to encode PNG at \(size)")
    }
    return data
}

let fm = FileManager.default
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// iconutil requires these exact filenames.
let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024),
]
for (name, size) in variants {
    let data = png(drawIcon(size: size), size: size)
    fm.createFile(atPath: (iconset as NSString).appendingPathComponent(name), contents: data)
}
print("wrote \(iconset)")

// A standalone 1024 for the README and landing page.
let logoPath = (outDir as NSString).appendingPathComponent("logo.png")
fm.createFile(atPath: logoPath, contents: png(drawIcon(size: 1024), size: 1024))
print("wrote \(logoPath)")
