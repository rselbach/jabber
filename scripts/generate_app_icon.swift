#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Sources/Jabber/Assets.xcassets/AppIcon.appiconset")

struct IconImage {
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(filename: "icon_16x16.png", pixels: 16),
    IconImage(filename: "icon_16x16@2x.png", pixels: 32),
    IconImage(filename: "icon_32x32.png", pixels: 32),
    IconImage(filename: "icon_32x32@2x.png", pixels: 64),
    IconImage(filename: "icon_128x128.png", pixels: 128),
    IconImage(filename: "icon_128x128@2x.png", pixels: 256),
    IconImage(filename: "icon_256x256.png", pixels: 256),
    IconImage(filename: "icon_256x256@2x.png", pixels: 512),
    IconImage(filename: "icon_512x512.png", pixels: 512),
    IconImage(filename: "icon_512x512@2x.png", pixels: 1024),
]

func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255
    let g = CGFloat((hex >> 8) & 0xff) / 255
    let b = CGFloat(hex & 0xff) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func speechWavePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 186, y: 512))
    path.addLine(to: CGPoint(x: 332, y: 512))
    path.addLine(to: CGPoint(x: 400, y: 356))
    path.addLine(to: CGPoint(x: 498, y: 704))
    path.addLine(to: CGPoint(x: 594, y: 296))
    path.addLine(to: CGPoint(x: 676, y: 628))
    path.addLine(to: CGPoint(x: 730, y: 472))
    path.addLine(to: CGPoint(x: 784, y: 512))
    path.addLine(to: CGPoint(x: 850, y: 512))
    return path
}

func renderIcon(size: Int) -> CGImage {
    let width = size
    let height = size
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create bitmap context")
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let iconRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let iconPath = roundedRect(iconRect, radius: 206)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -26), blur: 46, color: cgColor(0x000000, alpha: 0.30))
    context.setFillColor(cgColor(0x081822))
    context.addPath(iconPath)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.clip()

    let baseGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            cgColor(0x0a1924),
            cgColor(0x103b48),
            cgColor(0x0f8f8d),
        ] as CFArray,
        locations: [0.0, 0.54, 1.0]
    )!
    context.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: 132, y: 146),
        end: CGPoint(x: 892, y: 908),
        options: []
    )

    let warmGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            cgColor(0xff9f45, alpha: 0.82),
            cgColor(0xff9f45, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawRadialGradient(
        warmGlow,
        startCenter: CGPoint(x: 790, y: 748),
        startRadius: 0,
        endCenter: CGPoint(x: 790, y: 748),
        endRadius: 420,
        options: [.drawsAfterEndLocation]
    )

    let coolGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            cgColor(0x55f0d3, alpha: 0.45),
            cgColor(0x55f0d3, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawRadialGradient(
        coolGlow,
        startCenter: CGPoint(x: 270, y: 278),
        startRadius: 0,
        endCenter: CGPoint(x: 270, y: 278),
        endRadius: 430,
        options: [.drawsAfterEndLocation]
    )

    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.setStrokeColor(cgColor(0xffffff, alpha: 0.18))
    context.setLineWidth(8)
    context.strokePath()
    context.restoreGState()

    let glyphPath = speechWavePath()

    context.saveGState()
    context.addPath(glyphPath)
    context.setLineWidth(88)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(cgColor(0x001016, alpha: 0.36))
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 22, color: cgColor(0x000000, alpha: 0.42))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(glyphPath)
    context.setLineWidth(70)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(cgColor(0xf7fbff))
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    let cursor = roundedRect(CGRect(x: 854, y: 384, width: 48, height: 256), radius: 24)
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 18, color: cgColor(0x000000, alpha: 0.36))
    context.addPath(cursor)
    context.setFillColor(cgColor(0xffbd55))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(roundedRect(CGRect(x: 868, y: 536, width: 20, height: 76), radius: 10))
    context.setFillColor(cgColor(0xffefc7, alpha: 0.78))
    context.fillPath()
    context.restoreGState()

    guard let image = context.makeImage() else {
        fatalError("Could not create image")
    }

    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create PNG destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write PNG: \(url.path)")
    }
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

for image in images {
    writePNG(renderIcon(size: image.pixels), to: iconSet.appendingPathComponent(image.filename))
}

writePNG(renderIcon(size: 1024), to: root.appendingPathComponent("jabber.png"))
