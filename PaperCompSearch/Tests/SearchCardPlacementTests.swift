import CoreGraphics
import XCTest
@testable import PaperComp

final class SearchCardPlacementTests: XCTestCase {
    func testPrefersRightOfAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let anchor = CGRect(x: 100, y: 200, width: 80, height: 40)
        let card = CGSize(width: SearchCardPlacement.cardWidth, height: 200)
        let placed = SearchCardPlacement.place(anchor: anchor, cardSize: card, maxHeight: 270, in: bounds)
        XCTAssertEqual(placed?.side, .right)
        XCTAssertEqual(placed?.origin.x, anchor.maxX + SearchCardPlacement.gap)
    }

    func testClampKeepsCardInsideBoundsWhenCardFits() {
        let bounds = CGRect(x: 10, y: 10, width: 400, height: 400)
        let size = CGSize(width: 340, height: 200)
        let origin = SearchCardPlacement.clamp(CGPoint(x: -50, y: 400), size: size, in: bounds)
        XCTAssertGreaterThanOrEqual(origin.x, bounds.minX)
        XCTAssertLessThanOrEqual(origin.x + size.width, bounds.maxX)
        XCTAssertGreaterThanOrEqual(origin.y, bounds.minY)
        XCTAssertLessThanOrEqual(origin.y + size.height, bounds.maxY)
    }

    func testClampPinsOversizedCardToLeadingEdge() {
        let bounds = CGRect(x: 10, y: 10, width: 300, height: 300)
        let size = CGSize(width: SearchCardPlacement.cardWidth, height: 200)
        let origin = SearchCardPlacement.clamp(CGPoint(x: -50, y: 400), size: size, in: bounds)
        XCTAssertEqual(origin.x, bounds.minX)
        XCTAssertEqual(origin.y, bounds.maxY - size.height)
    }

    func testEncodeDecodeRoundTrip() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let point = CGPoint(x: 120, y: 340)
        let encoded = SearchCardPlacement.encode(point, in: bounds)
        let decoded = SearchCardPlacement.decode(encoded, in: bounds)!
        XCTAssertEqual(decoded.x, point.x, accuracy: 0.5)
        XCTAssertEqual(decoded.y, point.y, accuracy: 0.5)
    }

    func testStorageKeyUsesOrientation() {
        XCTAssertEqual(SearchCardPlacement.storageKey(for: CGSize(width: 800, height: 600)), "searchCardPos.landscape")
        XCTAssertEqual(SearchCardPlacement.storageKey(for: CGSize(width: 600, height: 800)), "searchCardPos.portrait")
    }

    func testDefaultSizeUses420AndSixtyPercentHeight() {
        XCTAssertEqual(SearchCardPlacement.cardWidth, 420)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = SearchCardPlacement.defaultSize(in: bounds)
        XCTAssertEqual(size.width, 420)
        XCTAssertEqual(size.height, 480, accuracy: 0.5)
    }

    func testClampSizeRespectsMinMax() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let tiny = SearchCardPlacement.clampSize(CGSize(width: 100, height: 50), in: bounds)
        XCTAssertEqual(tiny.width, 320)
        XCTAssertEqual(tiny.height, 200)
        let huge = SearchCardPlacement.clampSize(CGSize(width: 900, height: 900), in: bounds)
        XCTAssertEqual(huge.width, 640)
        XCTAssertEqual(huge.height, 680, accuracy: 0.5)
    }

    func testExpandedSizeIsSideSheet() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = SearchCardPlacement.expandedSize(in: bounds)
        XCTAssertEqual(size.width, 450, accuracy: 0.5)
        XCTAssertEqual(size.height, 800)
        let origin = SearchCardPlacement.expandedOrigin(size: size, in: bounds)
        XCTAssertEqual(origin.x, 550, accuracy: 0.5)
    }

    func testChromeFloorKeepsCardBelowCapsuleRow() {
        let safeTop: CGFloat = 24
        let floor = SearchCardPlacement.chromeFloor(safeTop: safeTop)
        XCTAssertEqual(floor, safeTop + SearchCardPlacement.chromeRowHeight + SearchCardPlacement.chromeClearance)
        let bounds = SearchCardPlacement.safeBounds(size: CGSize(width: 800, height: 1000),
                                                    top: safeTop, leading: 0, bottom: 20, trailing: 0)
        XCTAssertEqual(bounds.minY, floor)
        let size = CGSize(width: 420, height: 300)
        let origin = SearchCardPlacement.clamp(CGPoint(x: 100, y: 0), size: size, in: bounds)
        XCTAssertGreaterThanOrEqual(origin.y, floor)
    }
}
