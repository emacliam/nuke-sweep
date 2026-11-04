import SwiftUI

/// Approved Nuke Sweep geometry, shared by the app, menu bar and widgets.
public struct SweepSymbol: Shape {
    public let orangePart: Bool
    public init(orangePart: Bool) { self.orangePart = orangePart }
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        if orangePart {
            p.move(to: CGPoint(x: 370, y: 222))
            p.addLine(to: CGPoint(x: 370, y: 52))
            p.addCurve(to: CGPoint(x: 422, y: 0), control1: CGPoint(x: 370, y: 23), control2: CGPoint(x: 393, y: 0))
            p.addLine(to: CGPoint(x: 548, y: 0))
            p.addCurve(to: CGPoint(x: 600, y: 52), control1: CGPoint(x: 577, y: 0), control2: CGPoint(x: 600, y: 23))
            p.addCurve(to: CGPoint(x: 370, y: 222), control1: CGPoint(x: 600, y: 132), control2: CGPoint(x: 490, y: 194))
        } else {
            p.move(to: CGPoint(x: 0, y: 398))
            p.addLine(to: CGPoint(x: 0, y: 52))
            p.addCurve(to: CGPoint(x: 52, y: 0), control1: CGPoint(x: 0, y: 23), control2: CGPoint(x: 23, y: 0))
            p.addLine(to: CGPoint(x: 182, y: 0))
            p.addCurve(to: CGPoint(x: 216, y: 14), control1: CGPoint(x: 195, y: 0), control2: CGPoint(x: 206, y: 5))
            p.addLine(to: CGPoint(x: 370, y: 168))
            p.addLine(to: CGPoint(x: 370, y: 222))
            p.addCurve(to: CGPoint(x: 8, y: 402), control1: CGPoint(x: 200, y: 253), control2: CGPoint(x: 69, y: 287))
            p.addCurve(to: CGPoint(x: 0, y: 398), control1: CGPoint(x: 4, y: 409), control2: CGPoint(x: 0, y: 405))
            p.closeSubpath()
            p.move(to: CGPoint(x: 0, y: 452))
            p.addCurve(to: CGPoint(x: 52, y: 500), control1: CGPoint(x: 0, y: 480), control2: CGPoint(x: 23, y: 500))
            p.addLine(to: CGPoint(x: 168, y: 500))
            p.addCurve(to: CGPoint(x: 220, y: 448), control1: CGPoint(x: 197, y: 500), control2: CGPoint(x: 220, y: 477))
            p.addLine(to: CGPoint(x: 220, y: 357))
            p.addCurve(to: CGPoint(x: 230, y: 353), control1: CGPoint(x: 220, y: 350), control2: CGPoint(x: 225, y: 348))
            p.addLine(to: CGPoint(x: 362, y: 486))
            p.addCurve(to: CGPoint(x: 396, y: 500), control1: CGPoint(x: 372, y: 495), control2: CGPoint(x: 383, y: 500))
            p.addLine(to: CGPoint(x: 548, y: 500))
            p.addCurve(to: CGPoint(x: 600, y: 448), control1: CGPoint(x: 577, y: 500), control2: CGPoint(x: 600, y: 477))
            p.addLine(to: CGPoint(x: 600, y: 163))
            p.addCurve(to: CGPoint(x: 591, y: 161), control1: CGPoint(x: 600, y: 156), control2: CGPoint(x: 594, y: 155))
            p.addCurve(to: CGPoint(x: 266, y: 315), control1: CGPoint(x: 553, y: 258), control2: CGPoint(x: 400, y: 290))
            p.addCurve(to: CGPoint(x: 0, y: 452), control1: CGPoint(x: 130, y: 342), control2: CGPoint(x: 19, y: 389))
        }
        p.closeSubpath(); return p.applying(CGAffineTransform(scaleX: rect.width / 600, y: rect.height / 500).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

public struct SweepMark: View {
    private let monochrome: Bool
    public init(monochrome: Bool = false) { self.monochrome = monochrome }
    public var body: some View {
        ZStack {
            SweepSymbol(orangePart: false).fill(monochrome ? Color.primary : Color(red: 38/255, green: 43/255, blue: 43/255))
            SweepSymbol(orangePart: true).fill(monochrome ? Color.primary : Color(red: 194/255, green: 69/255, blue: 33/255))
        }
        .aspectRatio(1.2, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
