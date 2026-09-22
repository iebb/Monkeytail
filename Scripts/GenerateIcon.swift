import AppKit
import ImageIO

// Package the approved artwork without changing its design.
let source = URL(fileURLWithPath: "docs/brand/monkeytail-icon-source.png")
let input = CGImageSourceCreateWithURL(source as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(input, 0, nil)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.interpolationQuality = .high
context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to:
    URL(fileURLWithPath: "Monkeytail/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
