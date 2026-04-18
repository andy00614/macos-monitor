#!/usr/bin/env swift
// 生成 MacosMonitor 应用图标：绿色 squircle 背景 + 白色 SF Symbol "cpu.fill"
// 用法：swift tools/generate_icon.swift <output_dir>  （默认 AppIcon.iconset）

import AppKit
import Foundation

let argOut = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let outputDir = URL(fileURLWithPath: argOut)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// macOS iconset 需要这些尺寸（@2x 和 @1x）
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

func renderIcon(side: Int) -> NSImage {
    let s = CGFloat(side)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // squircle 蒙版（macOS 11+ 默认图标圆角约 22.37% of side）
    let cornerRadius = s * 0.2237
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.addPath(path)
    ctx.clip()

    // 渐变背景：深绿 → 亮绿（+ 一点点薄荷感）
    let colors = [
        NSColor(red: 0.18, green: 0.78, blue: 0.42, alpha: 1.0).cgColor,  // 底部
        NSColor(red: 0.24, green: 0.90, blue: 0.56, alpha: 1.0).cgColor,  // 顶部
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 0, y: s),
        options: []
    )

    // SF Symbol 前景：cpu.fill 白色，占 ~55% 区域，微微偏上
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.6, weight: .semibold)
    guard let symbol = NSImage(systemSymbolName: "cpu.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        return image
    }

    let glyphSize = symbol.size
    // 白色着色
    let tinted = NSImage(size: glyphSize, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }

    let x = (s - glyphSize.width) / 2
    let y = (s - glyphSize.height) / 2
    tinted.draw(in: NSRect(x: x, y: y, width: glyphSize.width, height: glyphSize.height))

    return image
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
    let image = renderIcon(side: size.side)
    let url = outputDir.appendingPathComponent(size.filename)
    try writePNG(image, to: url)
    print("wrote \(size.filename) (\(size.side)×\(size.side))")
}
print("done: \(outputDir.path)")
