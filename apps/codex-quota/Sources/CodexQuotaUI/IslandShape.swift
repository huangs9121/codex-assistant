import SwiftUI

/// One outline for every size, so opening is a continuous grow instead of a swap between shapes.
/// A neck fills the menu bar around the notch and a body hangs below the menu bar; the top edge is
/// always flush with the screen and the body's top corners are square, so the island stays attached.
/// At the neck's width it is simply the collapsed island: square top, rounded bottom.
public struct IslandShape: Shape {
    public var neckWidth: CGFloat
    public var neckHeight: CGFloat

    public init(neckWidth: CGFloat, neckHeight: CGFloat) {
        self.neckWidth = neckWidth
        self.neckHeight = neckHeight
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let side = max(0, (w - neckWidth) / 2)
        let bottom = min(10 + 10 * min(1, side / 24), w / 2, h / 2)
        // While the island is still short, the body's top rises with its bottom corners.
        let join = max(0, min(neckHeight, h - bottom))
        let flare = min(12, side, join / 2)
        let shoulder = min(20, side, join - flare)
        let left = side, right = w - side
        var p = Path()
        p.move(to: CGPoint(x: left - shoulder, y: 0))
        p.addLine(to: CGPoint(x: right + shoulder, y: 0))
        if side > 0 {
            p.addQuadCurve(to: CGPoint(x: right, y: shoulder), control: CGPoint(x: right, y: 0))
            p.addLine(to: CGPoint(x: right, y: join - flare))
            p.addQuadCurve(to: CGPoint(x: right + flare, y: join), control: CGPoint(x: right, y: join))
            p.addLine(to: CGPoint(x: w, y: join))
        }
        p.addLine(to: CGPoint(x: w, y: h - bottom))
        p.addQuadCurve(to: CGPoint(x: w - bottom, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: bottom, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - bottom), control: CGPoint(x: 0, y: h))
        if side > 0 {
            p.addLine(to: CGPoint(x: 0, y: join))
            p.addLine(to: CGPoint(x: left - flare, y: join))
            p.addQuadCurve(to: CGPoint(x: left, y: join - flare), control: CGPoint(x: left, y: join))
            p.addLine(to: CGPoint(x: left, y: shoulder))
            p.addQuadCurve(to: CGPoint(x: left - shoulder, y: 0), control: CGPoint(x: left, y: 0))
        }
        p.closeSubpath()
        return p
    }

    /// Hit-tests a top-aligned island centered inside its full-size, transparent panel.
    /// Coordinates use SwiftUI's top-left origin in the panel's hosting view.
    public func contains(_ point: CGPoint, inWindowOfSize windowSize: CGSize, islandSize: CGSize) -> Bool {
        guard windowSize.width > 0, windowSize.height > 0,
              islandSize.width > 0, islandSize.height > 0 else { return false }
        let originX = (windowSize.width - islandSize.width) / 2
        let local = CGPoint(x: point.x - originX, y: point.y)
        let bounds = CGRect(origin: .zero, size: islandSize)
        return bounds.contains(local) && path(in: bounds).contains(local)
    }
}
