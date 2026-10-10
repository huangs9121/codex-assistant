import CodexQuotaUI
import Foundation

enum IslandShapeTests {
    static var all: [(name: String, run: () -> Bool)] { [
        ("collapsed island ignores transparent panel below and beside it", testCollapsedTransparentPanel),
        ("collapsed island excludes rounded lower corners", testCollapsedCorners),
        ("expanded island excludes shoulder transparency and accepts visible body", testExpandedShape),
        ("island hit region follows built-in and external neck sizes", testDifferentNecks),
        ("island hit region shrinks again after collapse", testExpansionThenCollapse)
    ] }

    private static let window = CGSize(width: 600, height: 350)

    private static func testCollapsedTransparentPanel() -> Bool {
        let shape = IslandShape(neckWidth: 340, neckHeight: 32)
        let island = CGSize(width: 340, height: 32)
        return shape.contains(CGPoint(x: 300, y: 15), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 300, y: 100), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 300, y: 349), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 80, y: 15), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 520, y: 15), inWindowOfSize: window, islandSize: island)
    }

    private static func testCollapsedCorners() -> Bool {
        let shape = IslandShape(neckWidth: 340, neckHeight: 32)
        let island = CGSize(width: 340, height: 32)
        return !shape.contains(CGPoint(x: 131, y: 30), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 469, y: 30), inWindowOfSize: window, islandSize: island)
            && shape.contains(CGPoint(x: 150, y: 20), inWindowOfSize: window, islandSize: island)
    }

    private static func testExpandedShape() -> Bool {
        let shape = IslandShape(neckWidth: 340, neckHeight: 32)
        let island = CGSize(width: 600, height: 320)
        return !shape.contains(CGPoint(x: 50, y: 10), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 550, y: 10), inWindowOfSize: window, islandSize: island)
            && shape.contains(CGPoint(x: 300, y: 10), inWindowOfSize: window, islandSize: island)
            && shape.contains(CGPoint(x: 50, y: 80), inWindowOfSize: window, islandSize: island)
            && shape.contains(CGPoint(x: 300, y: 200), inWindowOfSize: window, islandSize: island)
            && !shape.contains(CGPoint(x: 300, y: 340), inWindowOfSize: window, islandSize: island)
    }

    private static func testDifferentNecks() -> Bool {
        let builtIn = IslandShape(neckWidth: 340, neckHeight: 32)
        let external = IslandShape(neckWidth: 240, neckHeight: 28)
        return builtIn.contains(CGPoint(x: 150, y: 12), inWindowOfSize: window,
                                islandSize: CGSize(width: 340, height: 32))
            && !external.contains(CGPoint(x: 150, y: 12), inWindowOfSize: window,
                                  islandSize: CGSize(width: 240, height: 28))
            && external.contains(CGPoint(x: 300, y: 20), inWindowOfSize: window,
                                 islandSize: CGSize(width: 240, height: 28))
            && !external.contains(CGPoint(x: 300, y: 30), inWindowOfSize: window,
                                  islandSize: CGSize(width: 240, height: 28))
    }

    private static func testExpansionThenCollapse() -> Bool {
        let shape = IslandShape(neckWidth: 340, neckHeight: 32)
        let location = CGPoint(x: 300, y: 100)
        return shape.contains(location, inWindowOfSize: window, islandSize: CGSize(width: 600, height: 320))
            && !shape.contains(location, inWindowOfSize: window, islandSize: CGSize(width: 340, height: 32))
    }
}
