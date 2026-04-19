#!/usr/bin/env swift
// 从 tools/icon-source.png（1024×1024 master）生成完整 iconset。
// 用法：swift tools/generate_icon.swift <output_dir>

import AppKit
import Foundation

let argOut = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let outputDir = URL(fileURLWithPath: argOut)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sourceURL = URL(fileURLWithPath: "tools/icon-source.png")
guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write("error: tools/icon-source.png not found\n".data(using: .utf8)!)
    exit(1)
}

struct IconSize { let side: Int; let filename: String }
let sizes: [IconSize] = [
    .init(side: 16,   filename: "icon_16x16.png"),
    .init(side: 32,   filename: "icon_16x16@2x.png"),
    .init(side: 32,   filename: "icon_32x32.png"),
    .init(side: 64,   filename: "icon_32x32@2x.png"),
    .init(side: 128,  filename: "icon_128x128.png"),
    .init(side: 256,  filename: "icon_128x128@2x.png"),
    .init(side: 256,  filename: "icon_256x256.png"),
    .init(side: 512,  filename: "icon_256x256@2x.png"),
    .init(side: 512,  filename: "icon_512x512.png"),
    .init(side: 1024, filename: "icon_512x512@2x.png"),
]

func resize(_ image: NSImage, to side: Int) -> NSImage {
    let s = CGFloat(side)
    let out = NSImage(size: NSSize(width: s, height: s))
    out.lockFocus()
    defer { out.unlockFocus() }
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: s, height: s),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    return out
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1)
    }
    try png.write(to: url)
}

for size in sizes {
    let resized = resize(source, to: size.side)
    let url = outputDir.appendingPathComponent(size.filename)
    try writePNG(resized, to: url)
    print("wrote \(size.filename) (\(size.side)×\(size.side))")
}
print("done: \(outputDir.path)")
