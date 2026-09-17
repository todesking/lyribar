#!/usr/bin/env swift
// Draws the app icon: the music.note.list symbol on a solid rounded square.
// usage: generate-icon.swift <output.png> [size]

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: \(arguments[0]) <output.png> [size]\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])
let size = arguments.count >= 3 ? Int(arguments[2]) ?? 1024 : 1024

let background = NSColor(srgbRed: 0.42, green: 0.27, blue: 0.80, alpha: 1)
// Proportions of the macOS app icon grid: the artwork fills 824 of 1024 pt, corner radius 185.
let inset = CGFloat(size) * 100 / 1024
let cornerRadius = CGFloat(size) * 185 / 1024
let symbolFraction: CGFloat = 0.52

guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else {
    FileHandle.standardError.write(Data("could not create the bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill()
background.setFill()
NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)
    .fill()

let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * symbolFraction, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard
    let symbol = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyribar")?
        .withSymbolConfiguration(configuration)
else {
    FileHandle.standardError.write(Data("could not load the symbol\n".utf8))
    exit(1)
}

let symbolSize = symbol.size
let origin = NSPoint(x: (CGFloat(size) - symbolSize.width) / 2, y: (CGFloat(size) - symbolSize.height) / 2)
symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the PNG\n".utf8))
    exit(1)
}
do {
    try data.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("could not write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
