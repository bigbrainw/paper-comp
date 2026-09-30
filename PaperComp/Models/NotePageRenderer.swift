import CoreGraphics
import PDFKit
import UIKit

/// Vector note pages. Lines live on the PDF page, never in the PencilKit layer.
enum NotePageRenderer {
    static let a4 = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    static let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

    static let collegeRuleMM: CGFloat = 7.1
    static let narrowRuleMM: CGFloat = 6
    static let wideRuleMM: CGFloat = 8.7
    static let gridMM: CGFloat = 5
    static let crossArmMM: CGFloat = 1.2
    static let hexSideMM: CGFloat = 4
    static let handwritingGroupMM: CGFloat = 9
    static let handwritingGapMM: CGFloat = 6
    static let staffLineMM: CGFloat = 2
    static let staffGapMM: CGFloat = 14
    static let checklistRowMM: CGFloat = 9
    static let checklistBoxMM: CGFloat = 4
    static let lineAlpha: CGFloat = 0.12
    static let majorLineAlpha: CGFloat = 0.22

    static func bounds(for size: NotePageSize, matching neighbor: CGRect? = nil) -> CGRect {
        switch size {
        case .a4: a4
        case .letter: letter
        case .matching: neighbor ?? a4
        }
    }

    static func mmToPoints(_ mm: CGFloat) -> CGFloat {
        mm * 72 / 25.4
    }

    static func paperColor(_ color: NotePaperColor) -> UIColor {
        switch color {
        case .white: .white
        case .rice: UIColor(red: 246 / 255, green: 241 / 255, blue: 231 / 255, alpha: 1)
        case .dark: UIColor(red: 42 / 255, green: 37 / 255, blue: 31 / 255, alpha: 1)
        }
    }

    static func lineColor(_ color: NotePaperColor) -> UIColor {
        let base: UIColor = color == .dark ? .white : .black
        return base.withAlphaComponent(lineAlpha)
    }

    static func majorLineColor(_ color: NotePaperColor) -> UIColor {
        let base: UIColor = color == .dark ? .white : .black
        return base.withAlphaComponent(majorLineAlpha)
    }

    static func makePDFData(
        template: NoteTemplate,
        size: NotePageSize,
        color: NotePaperColor,
        matching neighbor: CGRect? = nil
    ) -> Data {
        let bounds = bounds(for: size, matching: neighbor)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            renderer.beginPage()
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            paperColor(color).setFill()
            ctx.fill(bounds)
            draw(template, in: bounds, color: color, context: ctx)
        }
    }

    static func makePage(
        template: NoteTemplate,
        size: NotePageSize,
        color: NotePaperColor,
        matching neighbor: CGRect? = nil
    ) -> PDFPage? {
        let data = makePDFData(template: template, size: size, color: color, matching: neighbor)
        return PDFDocument(data: data)?.page(at: 0)
    }

    /// Renders a small preview image for the picker.
    /// Goes through `makePage` (same `draw` path as real note pages) so hairlines stay visible when downscaled.
    static func thumbnail(template: NoteTemplate, color: NotePaperColor, size: CGSize) -> UIImage {
        if let page = makePage(template: template, size: .a4, color: color) {
            return page.thumbnail(of: size, for: .mediaBox)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            paperColor(color).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func draw(_ template: NoteTemplate, in bounds: CGRect, color: NotePaperColor, context: CGContext) {
        let stroke = lineColor(color)
        stroke.setStroke()
        context.setLineWidth(0.6)
        context.setLineDash(phase: 0, lengths: [])
        let inset: CGFloat = 36
        switch template {
        case .blank:
            break
        case .linedCollege:
            drawLines(in: bounds, spacing: mmToPoints(collegeRuleMM), inset: inset, context: context)
        case .linedNarrow:
            drawLines(in: bounds, spacing: mmToPoints(narrowRuleMM), inset: inset, context: context)
        case .wideRuled:
            drawLines(in: bounds, spacing: mmToPoints(wideRuleMM), inset: inset, context: context)
        case .grid:
            drawGrid(in: bounds, spacing: mmToPoints(gridMM), inset: inset, context: context)
        case .graph:
            drawGraph(in: bounds, spacing: mmToPoints(gridMM), inset: inset, color: color, context: context)
        case .crossGrid:
            drawCrossGrid(in: bounds, spacing: mmToPoints(gridMM), inset: inset, context: context)
        case .dotted:
            drawDots(in: bounds, spacing: mmToPoints(gridMM), inset: inset, color: color, context: context)
        case .isometricDot:
            drawIsometricDots(in: bounds, spacing: mmToPoints(gridMM), inset: inset, color: color, context: context)
        case .hexagon:
            drawHexagons(in: bounds, side: mmToPoints(hexSideMM), inset: inset, context: context)
        case .cornell:
            drawCornell(in: bounds, inset: inset, context: context)
        case .handwriting:
            drawHandwriting(in: bounds, inset: inset, context: context)
        case .musicStaff:
            drawMusicStaff(in: bounds, inset: inset, context: context)
        case .checklist:
            drawChecklist(in: bounds, inset: inset, context: context)
        }
        context.setLineDash(phase: 0, lengths: [])
    }

    static func lineYs(in bounds: CGRect, spacing: CGFloat, inset: CGFloat) -> [CGFloat] {
        guard spacing > 0 else { return [] }
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        var ys: [CGFloat] = []
        var y = top + spacing
        while y < bottom - 2 {
            ys.append(y)
            y += spacing
        }
        return ys
    }

    private static func drawLines(in bounds: CGRect, spacing: CGFloat, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        for y in lineYs(in: bounds, spacing: spacing, inset: inset) {
            context.move(to: CGPoint(x: left, y: y))
            context.addLine(to: CGPoint(x: right, y: y))
        }
        context.strokePath()
    }

    private static func drawGrid(in bounds: CGRect, spacing: CGFloat, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        var x = left
        while x <= right + 0.5 {
            context.move(to: CGPoint(x: x, y: top))
            context.addLine(to: CGPoint(x: x, y: bottom))
            x += spacing
        }
        var y = top
        while y <= bottom + 0.5 {
            context.move(to: CGPoint(x: left, y: y))
            context.addLine(to: CGPoint(x: right, y: y))
            y += spacing
        }
        context.strokePath()
    }

    private static func drawGraph(
        in bounds: CGRect,
        spacing: CGFloat,
        inset: CGFloat,
        color: NotePaperColor,
        context: CGContext
    ) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset

        lineColor(color).setStroke()
        context.setLineWidth(0.4)
        var x = left
        var col = 0
        while x <= right + 0.5 {
            if col % 5 != 0 {
                context.move(to: CGPoint(x: x, y: top))
                context.addLine(to: CGPoint(x: x, y: bottom))
            }
            x += spacing
            col += 1
        }
        var y = top
        var row = 0
        while y <= bottom + 0.5 {
            if row % 5 != 0 {
                context.move(to: CGPoint(x: left, y: y))
                context.addLine(to: CGPoint(x: right, y: y))
            }
            y += spacing
            row += 1
        }
        context.strokePath()

        majorLineColor(color).setStroke()
        context.setLineWidth(0.9)
        x = left
        col = 0
        while x <= right + 0.5 {
            if col % 5 == 0 {
                context.move(to: CGPoint(x: x, y: top))
                context.addLine(to: CGPoint(x: x, y: bottom))
            }
            x += spacing
            col += 1
        }
        y = top
        row = 0
        while y <= bottom + 0.5 {
            if row % 5 == 0 {
                context.move(to: CGPoint(x: left, y: y))
                context.addLine(to: CGPoint(x: right, y: y))
            }
            y += spacing
            row += 1
        }
        context.strokePath()
        context.setLineWidth(0.6)
        lineColor(color).setStroke()
    }

    private static func drawCrossGrid(in bounds: CGRect, spacing: CGFloat, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let arm = mmToPoints(crossArmMM)
        var y = top
        while y <= bottom + 0.5 {
            var x = left
            while x <= right + 0.5 {
                context.move(to: CGPoint(x: x - arm, y: y))
                context.addLine(to: CGPoint(x: x + arm, y: y))
                context.move(to: CGPoint(x: x, y: y - arm))
                context.addLine(to: CGPoint(x: x, y: y + arm))
                x += spacing
            }
            y += spacing
        }
        context.strokePath()
    }

    private static func drawDots(
        in bounds: CGRect,
        spacing: CGFloat,
        inset: CGFloat,
        color: NotePaperColor,
        context: CGContext
    ) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        context.setFillColor(lineColor(color).cgColor)
        var y = top
        while y <= bottom + 0.5 {
            var x = left
            while x <= right + 0.5 {
                context.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                x += spacing
            }
            y += spacing
        }
    }

    private static func drawIsometricDots(
        in bounds: CGRect,
        spacing: CGFloat,
        inset: CGFloat,
        color: NotePaperColor,
        context: CGContext
    ) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let rowPitch = spacing * CGFloat(3).squareRoot() / 2
        context.setFillColor(lineColor(color).cgColor)
        var row = 0
        var y = top
        while y <= bottom + 0.5 {
            let offset = row.isMultiple(of: 2) ? 0 : spacing / 2
            var x = left + offset
            while x <= right + 0.5 {
                context.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                x += spacing
            }
            y += rowPitch
            row += 1
        }
    }

    private static func drawHexagons(in bounds: CGRect, side: CGFloat, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let colPitch = side * 1.5
        let rowPitch = side * CGFloat(3).squareRoot()
        var row = 0
        var cy = top + rowPitch / 2
        while cy <= bottom + side {
            let rowOffset = row.isMultiple(of: 2) ? 0 : colPitch / 2
            var cx = left + side + rowOffset
            while cx <= right + side {
                addFlatTopHex(center: CGPoint(x: cx, y: cy), side: side, context: context)
                cx += colPitch
            }
            cy += rowPitch
            row += 1
        }
        context.strokePath()
    }

    private static func addFlatTopHex(center: CGPoint, side: CGFloat, context: CGContext) {
        let points: [CGPoint] = (0..<6).map { i in
            let angle = CGFloat(i) * .pi / 3
            return CGPoint(x: center.x + side * cos(angle), y: center.y + side * sin(angle))
        }
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.closePath()
    }

    private static func drawHandwriting(in bounds: CGRect, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let groupH = mmToPoints(handwritingGroupMM)
        let gap = mmToPoints(handwritingGapMM)
        let midOffset = groupH / 2

        var y = top
        while y + groupH <= bottom + 0.5 {
            let baseY = y + groupH
            context.move(to: CGPoint(x: left, y: y))
            context.addLine(to: CGPoint(x: right, y: y))
            context.move(to: CGPoint(x: left, y: baseY))
            context.addLine(to: CGPoint(x: right, y: baseY))
            y += groupH + gap
        }
        context.strokePath()

        context.setLineDash(phase: 0, lengths: [1.5, 1.5])
        y = top
        while y + groupH <= bottom + 0.5 {
            let midY = y + midOffset
            context.move(to: CGPoint(x: left, y: midY))
            context.addLine(to: CGPoint(x: right, y: midY))
            y += groupH + gap
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }

    private static func drawMusicStaff(in bounds: CGRect, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let lineGap = mmToPoints(staffLineMM)
        let staffGap = mmToPoints(staffGapMM)
        let staffHeight = lineGap * 4
        var staffTop = top + lineGap
        while staffTop + staffHeight <= bottom {
            for i in 0..<5 {
                let y = staffTop + CGFloat(i) * lineGap
                context.move(to: CGPoint(x: left, y: y))
                context.addLine(to: CGPoint(x: right, y: y))
            }
            staffTop += staffHeight + staffGap
        }
        context.strokePath()
    }

    private static func drawChecklist(in bounds: CGRect, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let box = mmToPoints(checklistBoxMM)
        let row = mmToPoints(checklistRowMM)
        for y in lineYs(in: bounds, spacing: row, inset: inset) {
            let boxY = y - box / 2
            context.addRect(CGRect(x: left, y: boxY, width: box, height: box))
            let lineLeft = left + box + mmToPoints(3)
            context.move(to: CGPoint(x: lineLeft, y: y))
            context.addLine(to: CGPoint(x: right, y: y))
        }
        context.strokePath()
    }

    private static func drawCornell(in bounds: CGRect, inset: CGFloat, context: CGContext) {
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let top = bounds.minY + inset
        let bottom = bounds.maxY - inset
        let cueWidth = (right - left) * 0.28
        let summaryHeight = mmToPoints(50)
        let cueX = left + cueWidth
        let summaryY = bottom - summaryHeight
        context.move(to: CGPoint(x: cueX, y: top))
        context.addLine(to: CGPoint(x: cueX, y: summaryY))
        context.move(to: CGPoint(x: left, y: summaryY))
        context.addLine(to: CGPoint(x: right, y: summaryY))
        context.strokePath()
        drawLines(
            in: CGRect(x: cueX, y: top, width: right - cueX, height: summaryY - top),
            spacing: mmToPoints(collegeRuleMM),
            inset: 8,
            context: context
        )
    }
}
