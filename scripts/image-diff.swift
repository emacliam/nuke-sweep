import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("usage: image-diff.swift <before.png> <after.png> [max-different-percent]")
    exit(2)
}
let aPath = CommandLine.arguments[1]
let bPath = CommandLine.arguments[2]
let maxPercent = CommandLine.arguments.count > 3 ? (Double(CommandLine.arguments[3]) ?? 0.2) : 0.2

func load(_ path: String) -> (CGImage, Int, Int)? {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return (cg, cg.width, cg.height)
}

func pixels(_ cg: CGImage) -> [UInt8]? {
    let width = cg.width, height = cg.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    return data
}

guard let (a, aw, ah) = load(aPath), let (b, bw, bh) = load(bPath) else {
    print("image-diff: could not read one of the images")
    exit(2)
}
guard aw == bw, ah == bh else {
    print("image-diff: size mismatch \(aw)x\(ah) vs \(bw)x\(bh)")
    exit(1)
}
guard let ap = pixels(a), let bp = pixels(b) else {
    print("image-diff: could not decode pixels")
    exit(2)
}
var different = 0
var maxDelta = 0
for index in stride(from: 0, to: ap.count, by: 4) {
    var changed = false
    for channel in 0..<4 {
        let delta = abs(Int(ap[index + channel]) - Int(bp[index + channel]))
        maxDelta = max(maxDelta, delta)
        if delta > 8 { changed = true }
    }
    if changed { different += 1 }
}
let total = aw * ah
let percent = total == 0 ? 0 : Double(different) * 100 / Double(total)
print(String(format: "image-diff: %.3f%% different (%d/%d px), max channel delta %d", percent, different, total, maxDelta))
exit(percent <= maxPercent ? 0 : 1)
