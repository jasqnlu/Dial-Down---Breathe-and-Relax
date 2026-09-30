import CoreGraphics
import SwiftUI
import Testing
@testable import BreathRelaxStretch

@Suite("DialDownMark geometry")
struct DialDownMarkGeometryTests {
    let rect = CGRect(x: 0, y: 0, width: 144, height: 170)

    @Test func boxCornersMapToRectCorners() {
        let g = DialDownMarkGeometry.self
        #expect(g.map(CGPoint(x: g.box.minX, y: g.box.minY), in: rect) == CGPoint(x: 0, y: 0))
        #expect(g.map(CGPoint(x: g.box.maxX, y: g.box.maxY), in: rect) == CGPoint(x: 144, y: 170))
    }

    @Test func mirroringReflectsAboutTheCentreLine() {
        let g = DialDownMarkGeometry.self
        let p = CGPoint(x: 74, y: 88)
        let left = g.map(p, in: rect)
        let right = g.map(p, in: rect, mirrored: true)
        #expect(abs((left.x + right.x) / 2 - rect.midX) < 0.001)
        #expect(left.y == right.y)
    }

    @Test func lobeBasesAreSymmetricAndOnTheBottomEdge() {
        let g = DialDownMarkGeometry.self
        let left = g.lobeBase(mirrored: false)
        let right = g.lobeBase(mirrored: true)
        #expect(left.y == 1 && right.y == 1)
        #expect(abs(left.x + right.x - 1) < 0.001)
    }

    @Test func lobeIsClosedAndStaysInsideTheBox() {
        let g = DialDownMarkGeometry.self
        #expect(g.lobe.first?.0 == g.lobe.last?.3)
        for seg in g.lobe {
            for p in [seg.0, seg.3] {
                #expect(g.box.insetBy(dx: -0.001, dy: -0.001).contains(p))
            }
        }
    }
}
