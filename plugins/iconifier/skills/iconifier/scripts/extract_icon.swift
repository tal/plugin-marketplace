#!/usr/bin/env swift
//
// Render a file or folder's current Finder icon to a PNG.
//
// Usage:
//     swift extract_icon.swift <path> <out.png> [size]
//
// We use NSWorkspace.shared.icon(forFile:) so this works regardless of
// where the custom icon is stored — Icon\r file, the folder's own
// resource fork (the path third-party tools like `fileicon` use), or
// the macOS stock fallback. Callers that don't want the stock fallback
// must check `has_custom_icon` themselves before invoking this.
//
// Default size is 512px square. The icon is composed onto a transparent
// canvas at the requested size and saved as PNG.
//
// Exits 0 on success. Prints "ok <out>" to stdout. On failure prints
// "err: <reason>" to stderr and exits non-zero.

import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count == 3 || args.count == 4 else {
    FileHandle.standardError.write("usage: swift extract_icon.swift <path> <out.png> [size]\n".data(using: .utf8)!)
    exit(2)
}

let inputPath = args[1]
let outputPath = args[2]
let size: CGFloat = args.count == 4 ? CGFloat(Int(args[3]) ?? 512) : 512

guard FileManager.default.fileExists(atPath: inputPath) else {
    FileHandle.standardError.write("err: input path does not exist: \(inputPath)\n".data(using: .utf8)!)
    exit(2)
}

let icon = NSWorkspace.shared.icon(forFile: inputPath)
icon.size = NSSize(width: size, height: size)

let canvas = NSImage(size: NSSize(width: size, height: size))
canvas.lockFocus()
icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
          from: .zero,
          operation: .copy,
          fraction: 1.0)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("err: failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("ok \(outputPath)")
} catch {
    FileHandle.standardError.write("err: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
