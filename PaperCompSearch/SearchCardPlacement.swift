import CoreGraphics
import Foundation

/// Pure placement math for `FloatingSearchCard`. All rects share the overlay's coordinate space.
enum SearchCardPlacement {
    static let cardWidth: CGFloat = 420
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 640
    static let minHeight: CGFloat = 200
    static let defaultHeightFraction: CGFloat = 0.60
    static let maxHeightFraction: CGFloat = 0.85
    static let expandedWidthFraction: CGFloat = 0.45
    static let bubbleSize: CGFloat = 56
    static let gap: CGFloat = 12
    static let margin: CGFloat = 8
    /// Back / tools / more capsules sit in a row under the safe-area inset.
    static let chromeRowHeight: CGFloat = 52
    static let chromeClearance: CGFloat = 12

    /// Lowest y the card’s top may use so it never sits under the floating chrome.
    static func chromeFloor(safeTop: CGFloat) -> CGFloat {
        safeTop + chromeRowHeight + chromeClearance
    }

    enum Side: Equatable, Sendable { case right, left, below, above }

    /// Container bounds minus safe-area insets and a small margin.
    static func safeBounds(size: CGSize, top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> CGRect {
        let minY = chromeFloor(safeTop: top)
        return CGRect(x: leading + margin, y: minY,
                      width: max(0, size.width - leading - trailing - 2 * margin),
                      height: max(0, size.height - minY - bottom - margin))
    }

    static func defaultSize(in bounds: CGRect) -> CGSize {
        clampSize(CGSize(width: cardWidth, height: bounds.height * defaultHeightFraction), in: bounds)
    }

    static func expandedSize(in bounds: CGRect) -> CGSize {
        CGSize(width: max(minWidth, bounds.width * expandedWidthFraction), height: bounds.height)
    }

    static func expandedOrigin(size: CGSize, in bounds: CGRect) -> CGPoint {
        clamp(CGPoint(x: bounds.maxX - size.width, y: bounds.minY), size: size, in: bounds)
    }

    static func clampSize(_ size: CGSize, in bounds: CGRect) -> CGSize {
        CGSize(
            width: min(max(size.width, minWidth), min(maxWidth, max(minWidth, bounds.width))),
            height: min(max(size.height, minHeight), max(minHeight, bounds.height * maxHeightFraction))
        )
    }

    /// Next to `anchor` without covering it: right, then left, then below, then above.
    /// `maxHeight` is the tallest the card may grow; below/above only count if that fits, so a
    /// streaming answer can't grow over the circle. Returns nil when no side has room.
    static func place(anchor: CGRect, cardSize: CGSize, maxHeight: CGFloat, in bounds: CGRect) -> (origin: CGPoint, side: Side)? {
        guard !anchor.isNull, !anchor.isEmpty else { return nil }
        let width = cardSize.width
        let height = cardSize.height
        let tallest = max(height, maxHeight)

        let rightX = anchor.maxX + gap
        if rightX + width <= bounds.maxX {
            return (clamp(CGPoint(x: rightX, y: anchor.minY), size: cardSize, in: bounds), .right)
        }
        let leftX = anchor.minX - gap - width
        if leftX >= bounds.minX {
            return (clamp(CGPoint(x: leftX, y: anchor.minY), size: cardSize, in: bounds), .left)
        }
        let centeredX = anchor.midX - width / 2
        let belowY = anchor.maxY + gap
        if belowY + tallest <= bounds.maxY {
            return (clamp(CGPoint(x: centeredX, y: belowY), size: cardSize, in: bounds), .below)
        }
        if anchor.minY - gap - tallest >= bounds.minY {
            return (clamp(CGPoint(x: centeredX, y: anchor.minY - gap - height), size: cardSize, in: bounds), .above)
        }
        return nil
    }

    /// Keeps a box of `size` at `origin` fully inside `bounds` (top-left wins if it's too big).
    static func clamp(_ origin: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        CGPoint(x: max(bounds.minX, min(origin.x, bounds.maxX - size.width)),
                y: max(bounds.minY, min(origin.y, bounds.maxY - size.height)))
    }

    /// Where a card opens. A fresh anchor wins when there is room beside it; the remembered spot
    /// (last drag in this orientation) is used when there's no room or no anchor; otherwise top-right.
    static func initialOrigin(anchor: CGRect, cardSize: CGSize, maxHeight: CGFloat,
                              bounds: CGRect, remembered: CGPoint?) -> CGPoint {
        if let placed = place(anchor: anchor, cardSize: cardSize, maxHeight: maxHeight, in: bounds) {
            return placed.origin
        }
        if let remembered { return clamp(remembered, size: cardSize, in: bounds) }
        return clamp(CGPoint(x: bounds.maxX - cardSize.width, y: bounds.minY), size: cardSize, in: bounds)
    }

    static func storageKey(for containerSize: CGSize) -> String {
        containerSize.width > containerSize.height ? "searchCardPos.landscape" : "searchCardPos.portrait"
    }

    static func sizeStorageKey(for containerSize: CGSize) -> String {
        containerSize.width > containerSize.height ? "searchCardSize.landscape" : "searchCardSize.portrait"
    }

    /// Stored as fractions of the bounds so it survives size changes (split view, rotation).
    static func encode(_ origin: CGPoint, in bounds: CGRect) -> String {
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let x = (origin.x - bounds.minX) / bounds.width
        let y = (origin.y - bounds.minY) / bounds.height
        return String(format: "%.4f,%.4f", x, y)
    }

    static func encodeSize(_ size: CGSize) -> String {
        String(format: "%.1f,%.1f", size.width, size.height)
    }

    static func decodeSize(_ string: String) -> CGSize? {
        let parts = string.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts.allSatisfy(\.isFinite) else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    /// Hit-testing frame for the expanded card (ignores drag offset and minimized bubble).
    static func estimatedExpandedFrame(anchor: CGRect, containerSize: CGSize,
                                       safeTop: CGFloat = 0, safeLeading: CGFloat = 0,
                                       safeBottom: CGFloat = 0, safeTrailing: CGFloat = 0) -> CGRect {
        let bounds = safeBounds(size: containerSize, top: safeTop, leading: safeLeading,
                                bottom: safeBottom, trailing: safeTrailing)
        let cardSize = defaultSize(in: bounds)
        let origin = initialOrigin(anchor: anchor, cardSize: cardSize, maxHeight: cardSize.height,
                                   bounds: bounds, remembered: nil)
        return CGRect(origin: origin, size: cardSize)
    }

    static func decode(_ string: String, in bounds: CGRect) -> CGPoint? {
        let parts = string.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts.allSatisfy(\.isFinite) else { return nil }
        return CGPoint(x: bounds.minX + CGFloat(parts[0]) * bounds.width,
                       y: bounds.minY + CGFloat(parts[1]) * bounds.height)
    }
}
