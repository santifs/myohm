import SwiftUI

/// The Myohm wordmark, drawn from design/myohm/myohm-editable.svg (1440 × 520 canvas,
/// 38-unit monoline stroke). The h is the y rotated 180° around the centre of the o.
struct MyohmLogoShape: Shape {
    static let canvas = CGSize(width: 1440, height: 520)
    static let oCenter = CGPoint(x: 710, y: 260)
    static let oRadius: CGFloat = 100
    /// Visible ink spans x 41…1379 and y 141…470 once the stroke is included.
    static let inkBounds = CGRect(x: 41, y: 141, width: 1338, height: 329)

    var includeO = true

    func path(in rect: CGRect) -> Path {
        var logo = Path()
        logo.addPath(Self.mPath())
        logo.addPath(Self.yPath())
        if includeO {
            logo.addEllipse(in: CGRect(x: 610, y: 160, width: 200, height: 200))
        }
        let rotateAroundO = CGAffineTransform(translationX: 710, y: 260).rotated(by: .pi).translatedBy(x: -710, y: -260)
        logo.addPath(Self.yPath().applying(rotateAroundO))
        logo.addPath(Self.mPath().applying(CGAffineTransform(translationX: 1020, y: 0)))

        let scale = min(rect.width / Self.canvas.width, rect.height / Self.canvas.height)
        let dx = rect.midX - Self.canvas.width * scale / 2
        let dy = rect.midY - Self.canvas.height * scale / 2
        return logo.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: dx, ty: dy))
    }

    private static func mPath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 60, y: 360))
        p.addLine(to: CGPoint(x: 60, y: 230))
        p.addCurve(to: CGPoint(x: 130, y: 160), control1: CGPoint(x: 60, y: 191.34), control2: CGPoint(x: 91.34, y: 160))
        p.addCurve(to: CGPoint(x: 200, y: 230), control1: CGPoint(x: 168.66, y: 160), control2: CGPoint(x: 200, y: 191.34))
        p.addLine(to: CGPoint(x: 200, y: 360))
        p.move(to: CGPoint(x: 200, y: 230))
        p.addCurve(to: CGPoint(x: 270, y: 160), control1: CGPoint(x: 200, y: 191.34), control2: CGPoint(x: 231.34, y: 160))
        p.addCurve(to: CGPoint(x: 340, y: 230), control1: CGPoint(x: 308.66, y: 160), control2: CGPoint(x: 340, y: 191.34))
        p.addLine(to: CGPoint(x: 340, y: 360))
        return p
    }

    private static func yPath() -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 415, y: 160))
        p.addLine(to: CGPoint(x: 415, y: 285))
        p.addCurve(to: CGPoint(x: 490, y: 360), control1: CGPoint(x: 415, y: 326.42), control2: CGPoint(x: 448.58, y: 360))
        p.addCurve(to: CGPoint(x: 565, y: 285), control1: CGPoint(x: 531.42, y: 360), control2: CGPoint(x: 565, y: 326.42))
        p.addLine(to: CGPoint(x: 565, y: 160))
        p.move(to: CGPoint(x: 565, y: 285))
        p.addLine(to: CGPoint(x: 565, y: 470))
        return p
    }
}

/// Wordmark at a given width, keeping the SVG proportions and stroke weight.
struct MyohmLogo: View {
    var width: CGFloat
    var color: Color = MyohmColor.brand

    var body: some View {
        let scale = width / MyohmLogoShape.canvas.width
        MyohmLogoShape()
            .stroke(color, style: StrokeStyle(lineWidth: 38 * scale, lineCap: .butt, lineJoin: .round))
            .frame(width: width, height: MyohmLogoShape.canvas.height * scale)
            .accessibilityLabel("Myohm")
    }
}
