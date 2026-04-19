#!/usr/bin/env swift
// 生成 Orbit 应用图标：
//   - 深色 squircle 渐变背景（夜空）
//   - 中心实心圆（星球）
//   - 绕着它的虚线椭圆（轨道）
//   - 轨道上一颗亮点（卫星 = 代表远程监控的那台机器）
//
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

    // 背景：深蓝紫渐变（夜空 / 深空）
    let bgColors = [
        NSColor(red: 0.09, green: 0.11, blue: 0.22, alpha: 1.0).cgColor,  // 底部 深蓝
        NSColor(red: 0.17, green: 0.15, blue: 0.34, alpha: 1.0).cgColor,  // 顶部 深紫
    ] as CFArray
    let bg = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: bgColors,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])

    // 几何（按 side 比例缩放，保证所有尺寸下视觉一致）
    let cx = s / 2
    let cy = s / 2
    let planetRadius = s * 0.14
    let orbitRadiusX = s * 0.34
    let orbitRadiusY = s * 0.20   // 椭圆轨道（斜看视角）
    let orbitStroke  = s * 0.018
    let satRadius    = s * 0.07

    // 轨道：倾斜 -25° 的椭圆虚线
    let orbitDash: [CGFloat] = [s * 0.03, s * 0.03]
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -25 * .pi / 180)
    ctx.setLineWidth(orbitStroke)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.45).cgColor)
    ctx.setLineDash(phase: 0, lengths: orbitDash)
    ctx.strokeEllipse(in: CGRect(
        x: -orbitRadiusX, y: -orbitRadiusY,
        width: orbitRadiusX * 2, height: orbitRadiusY * 2
    ))
    ctx.restoreGState()

    // 星球（中心实心圆 + 柔和径向高光）
    let planetRect = CGRect(
        x: cx - planetRadius, y: cy - planetRadius,
        width: planetRadius * 2, height: planetRadius * 2
    )
    let planetGrad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(red: 0.35, green: 0.88, blue: 0.64, alpha: 1.0).cgColor, // 亮绿
            NSColor(red: 0.18, green: 0.65, blue: 0.48, alpha: 1.0).cgColor, // 暗绿
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addEllipse(in: planetRect)
    ctx.clip()
    ctx.drawRadialGradient(
        planetGrad,
        startCenter: CGPoint(x: cx - planetRadius * 0.3, y: cy + planetRadius * 0.4),
        startRadius: 0,
        endCenter: CGPoint(x: cx, y: cy),
        endRadius: planetRadius,
        options: []
    )
    ctx.restoreGState()

    // 卫星：放在轨道上（右上位置，倾斜角度匹配）
    let angle: CGFloat = -25 * .pi / 180     // 轨道倾角
    let t: CGFloat = 0.35 * .pi              // 在椭圆上的参数位置（约 63°）
    // 椭圆参数方程 + 旋转
    let ex = orbitRadiusX * cos(t)
    let ey = orbitRadiusY * sin(t)
    let sx = cx + ex * cos(angle) - ey * sin(angle)
    let sy = cy + ex * sin(angle) + ey * cos(angle)

    let satRect = CGRect(x: sx - satRadius, y: sy - satRadius, width: satRadius * 2, height: satRadius * 2)
    // 卫星柔光环
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.8).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: satRect)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

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
