import Foundation
import AppKit

let fileManager = FileManager.default
let currentDir = fileManager.currentDirectoryPath
let svgURL = URL(fileURLWithPath: "\(currentDir)/assets/AppIcon.svg")

guard fileManager.fileExists(atPath: svgURL.path) else {
    print("Error: AppIcon.svg not found at \(svgURL.path)")
    exit(1)
}

guard let svgData = try? Data(contentsOf: svgURL),
      let svgImage = NSImage(data: svgData) else {
    print("Error: Unable to initialize NSImage from SVG")
    exit(1)
}

let iconsetDir = URL(fileURLWithPath: "\(currentDir)/assets/AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    let destURL = iconsetDir.appendingPathComponent(item.name)
    let targetRect = NSRect(x: 0, y: 0, width: item.size, height: item.size)
    
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: item.size,
        pixelsHigh: item.size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = ctx
    ctx?.imageInterpolation = .high
    
    svgImage.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    
    NSGraphicsContext.restoreGraphicsState()
    
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: destURL)
    }
}

// Top level 1024x1024 png
let topPng = URL(fileURLWithPath: "\(currentDir)/assets/AppIcon.png")
if let highRes = try? Data(contentsOf: iconsetDir.appendingPathComponent("icon_512x512@2x.png")) {
    try? highRes.write(to: topPng)
}

print("✔ Rendered SVG to all macOS iconset resolutions.")
