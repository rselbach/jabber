#!/usr/bin/env swift

// Regenerates the AppIcon appiconset from `jabber.png` (a 1024x1024 source
// PNG at the repo root). Resize-only: edit jabber.png, then re-run this.
//
// Usage: ./scripts/generate_app_icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("jabber.png")
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

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not create PNG destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write PNG: \(url.path)")
    }
}

/// Loads the 1024x1024 source PNG.
func loadSource() -> CGImage {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
        fatalError("Could not open source PNG: \(sourceURL.path)")
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Could not decode source PNG: \(sourceURL.path)")
    }
    return image
}

/// High-quality resize into a square `size`x`size` CGImage.
func resize(_ image: CGImage, to size: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Could not create bitmap context for size \(size)")
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let resized = context.makeImage() else {
        fatalError("Could not create resized image for size \(size)")
    }
    return resized
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

let source = loadSource()
for image in images {
    let out = resize(source, to: image.pixels)
    writePNG(out, to: iconSet.appendingPathComponent(image.filename))
}

print("Generated \(images.count) icons in \(iconSet.path) from jabber.png")
