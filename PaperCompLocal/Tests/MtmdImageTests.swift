import UIKit
import XCTest
@testable import PaperComp

final class MtmdImageTests: XCTestCase {
    func testDownscalesLongSideTo896AndEmitsRGB() throws {
        let image = solidImage(width: 2000, height: 1000, color: .red)
        let prepared = try XCTUnwrap(MtmdImagePrep.prepare(image))
        XCTAssertEqual(prepared.width, 896)
        XCTAssertEqual(prepared.height, 448)
        XCTAssertEqual(prepared.rgb.count, 896 * 448 * 3)
        XCTAssertEqual(prepared.byteCount, prepared.rgb.count)
        XCTAssertEqual(prepared.rgb[0], 255)
        XCTAssertEqual(prepared.rgb[1], 0)
        XCTAssertEqual(prepared.rgb[2], 0)
    }

    func testLeavesSmallImagesUnscaled() throws {
        let image = solidImage(width: 64, height: 32, color: .blue)
        let prepared = try XCTUnwrap(MtmdImagePrep.prepare(image))
        XCTAssertEqual(prepared.width, 64)
        XCTAssertEqual(prepared.height, 32)
        XCTAssertEqual(prepared.rgb.count, 64 * 32 * 3)
        XCTAssertEqual(prepared.rgb[0], 0)
        XCTAssertEqual(prepared.rgb[1], 0)
        XCTAssertEqual(prepared.rgb[2], 255)
    }

    private func solidImage(width: Int, height: Int, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
