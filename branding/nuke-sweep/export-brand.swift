import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let ink = NSColor(srgbRed: 38/255, green: 43/255, blue: 43/255, alpha: 1)
let orange = NSColor(srgbRed: 194/255, green: 69/255, blue: 33/255, alpha: 1)
let paper = NSColor(srgbRed: 251/255, green: 250/255, blue: 247/255, alpha: 1)
func shape(_ orangePart: Bool) -> NSBezierPath {
    let p = NSBezierPath()
    if orangePart {
        p.move(to: NSPoint(x: 370, y: 222))
        p.line(to: NSPoint(x: 370, y: 52))
        p.curve(to: NSPoint(x: 422, y: 0), controlPoint1: NSPoint(x: 370, y: 23), controlPoint2: NSPoint(x: 393, y: 0))
        p.line(to: NSPoint(x: 548, y: 0))
        p.curve(to: NSPoint(x: 600, y: 52), controlPoint1: NSPoint(x: 577, y: 0), controlPoint2: NSPoint(x: 600, y: 23))
        p.curve(to: NSPoint(x: 370, y: 222), controlPoint1: NSPoint(x: 600, y: 132), controlPoint2: NSPoint(x: 490, y: 194))
    } else {
        p.move(to: NSPoint(x: 0, y: 398))
        p.line(to: NSPoint(x: 0, y: 52))
        p.curve(to: NSPoint(x: 52, y: 0), controlPoint1: NSPoint(x: 0, y: 23), controlPoint2: NSPoint(x: 23, y: 0))
        p.line(to: NSPoint(x: 182, y: 0))
        p.curve(to: NSPoint(x: 216, y: 14), controlPoint1: NSPoint(x: 195, y: 0), controlPoint2: NSPoint(x: 206, y: 5))
        p.line(to: NSPoint(x: 370, y: 168))
        p.line(to: NSPoint(x: 370, y: 222))
        p.curve(to: NSPoint(x: 8, y: 402), controlPoint1: NSPoint(x: 200, y: 253), controlPoint2: NSPoint(x: 69, y: 287))
        p.curve(to: NSPoint(x: 0, y: 398), controlPoint1: NSPoint(x: 4, y: 409), controlPoint2: NSPoint(x: 0, y: 405))
        p.close()
        p.move(to: NSPoint(x: 0, y: 452))
        p.curve(to: NSPoint(x: 52, y: 500), controlPoint1: NSPoint(x: 0, y: 480), controlPoint2: NSPoint(x: 23, y: 500))
        p.line(to: NSPoint(x: 168, y: 500))
        p.curve(to: NSPoint(x: 220, y: 448), controlPoint1: NSPoint(x: 197, y: 500), controlPoint2: NSPoint(x: 220, y: 477))
        p.line(to: NSPoint(x: 220, y: 357))
        p.curve(to: NSPoint(x: 230, y: 353), controlPoint1: NSPoint(x: 220, y: 350), controlPoint2: NSPoint(x: 225, y: 348))
        p.line(to: NSPoint(x: 362, y: 486))
        p.curve(to: NSPoint(x: 396, y: 500), controlPoint1: NSPoint(x: 372, y: 495), controlPoint2: NSPoint(x: 383, y: 500))
        p.line(to: NSPoint(x: 548, y: 500))
        p.curve(to: NSPoint(x: 600, y: 448), controlPoint1: NSPoint(x: 577, y: 500), controlPoint2: NSPoint(x: 600, y: 477))
        p.line(to: NSPoint(x: 600, y: 163))
        p.curve(to: NSPoint(x: 591, y: 161), controlPoint1: NSPoint(x: 600, y: 156), controlPoint2: NSPoint(x: 594, y: 155))
        p.curve(to: NSPoint(x: 266, y: 315), controlPoint1: NSPoint(x: 553, y: 258), controlPoint2: NSPoint(x: 400, y: 290))
        p.curve(to: NSPoint(x: 0, y: 452), controlPoint1: NSPoint(x: 130, y: 342), controlPoint2: NSPoint(x: 19, y: 389))
    }
    p.close(); return p
}
func mark(x: CGFloat, y: CGFloat, width: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current!.cgContext.translateBy(x: x, y: y)
    NSGraphicsContext.current!.cgContext.scaleBy(x: width/600, y: width/600)
    ink.setFill(); shape(false).fill()
    orange.setFill(); shape(true).fill()
    NSGraphicsContext.restoreGraphicsState()
}
func render(name: String, size: Int, draw: () -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.translateBy(x: 0, y: CGFloat(size))
    ctx.cgContext.scaleBy(x: CGFloat(size)/1024, y: -CGFloat(size)/1024)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
try render(name: "nuke-sweep-logo-transparent.png", size: 2048) {
    mark(x: 212, y: 170, width: 600)
    let font = NSFont.systemFont(ofSize: 95, weight: .medium)
    let text = NSAttributedString(string: "Nuke Sweep", attributes: [.font: font, .foregroundColor: ink])
    let width = text.size().width
    // Draw AppKit text in an unflipped local coordinate system.
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: (1024-width)/2, y: 850)
    ctx.scaleBy(x: 1, y: -1)
    text.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
}
let iconset = output.appendingPathComponent("NukeSweep.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(name: "icon-\(size).png", size: size) {
        paper.setFill()
        NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190).fill()
        mark(x: 222, y: 270, width: 580)
    }
}
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let src = output.appendingPathComponent("icon-\(base*scale).png")
        let dst = iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png")
        if FileManager.default.fileExists(atPath: dst.path) { try FileManager.default.removeItem(at: dst) }
        try FileManager.default.copyItem(at: src, to: dst)
    }
}
print("Exported transparent logo, seven icon sizes, and macOS iconset")
func svgPath(_ p: NSBezierPath) -> String {
    let pts = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
    defer { pts.deallocate() }
    var d = ""
    func xy(_ p: NSPoint) -> String { "\(Int(p.x)) \(Int(p.y))" }
    for i in 0..<p.elementCount {
        switch p.element(at: i, associatedPoints: pts) {
        case .moveTo: d += "M\(xy(pts[0])) "
        case .lineTo: d += "L\(xy(pts[0])) "
        case .curveTo: d += "C\(xy(pts[0])) \(xy(pts[1])) \(xy(pts[2])) "
        case .closePath: d += "Z "
        @unknown default: break
        }
    }
    return d
}
let paths = "<path fill=\"#262B2B\" d=\"\(svgPath(shape(false)))\"/><path fill=\"#C24521\" d=\"\(svgPath(shape(true)))\"/>"
let symbol = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 500\">\(paths)</svg>"
try symbol.write(to: output.appendingPathComponent("nuke-sweep-symbol.svg"), atomically: true, encoding: .utf8)
let logo = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\"><g transform=\"translate(212 170)\">\(paths)</g><text x=\"512\" y=\"825\" text-anchor=\"middle\" font-family=\"-apple-system, Helvetica Neue, sans-serif\" font-size=\"95\" font-weight=\"500\" fill=\"#262B2B\">Nuke Sweep</text></svg>"
try logo.write(to: output.appendingPathComponent("nuke-sweep-logo.svg"), atomically: true, encoding: .utf8)
// Small-size comparison preview, rendered at actual pixel dimensions.
try render(name: "icon-size-check.png", size: 1024) {
    paper.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    for (i, size) in [16, 32, 64, 128, 256].enumerated() {
        let image = NSImage(contentsOf: output.appendingPathComponent("icon-\(size).png"))!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: 80 + CGFloat(i)*180, y: 560 + CGFloat(size)/2)
        ctx.scaleBy(x: 1, y: -1)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
    }
}
