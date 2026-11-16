// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 230, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 64).frame(width: 470, height: 470)
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 470, height: 470)
            Circle()
                .fill(Color(red: 0.98, green: 0.70, blue: 0.24))
                .frame(width: 64, height: 64)
                .offset(y: -235)
                .rotationEffect(.degrees(0.72 * 360))
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func render() throws {
    let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let r = ImageRenderer(content: Icon().scaleEffect(CGFloat(size * scale) / 1024)
                .frame(width: CGFloat(size * scale), height: CGFloat(size * scale)))
            r.scale = 1
            guard let cg = r.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }
}

try MainActor.assumeIsolated { try render() }
