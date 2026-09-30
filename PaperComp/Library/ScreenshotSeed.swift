#if DEBUG
import CoreText
import PDFKit
import PencilKit
import SwiftData
import UIKit

/// DEBUG-only library contents for `-PCScreenshot…` launches (scratch library only).
/// Uses the real import, note-page, notebook, and drawing models; only the ink strokes are synthesized.
@MainActor
enum ScreenshotSeed {
    /// Seeds the scratch library and returns the document to open, if the scenario opens one.
    static func seedIfRequested(into context: ModelContext) -> PaperDocument? {
        guard ScreenshotMode.isActive, DocumentStore.usesScratchLibrary else { return nil }
        guard let paper = try? DocumentStore.importSamplePaper(into: context) else { return nil }

        if let scenario = ScreenshotMode.answerScenario {
            paper.lastPageIndex = scenario.pageIndex
            try? context.save()
            return paper
        }
        if ScreenshotMode.ink {
            seedInk(on: paper, context: context)
            return paper
        }
        if ScreenshotMode.library {
            seedInk(on: paper, context: context)
            seedNotebooks(into: context)
        }
        return nil
    }

    // MARK: - Paper ink + note page

    private static func seedInk(on paper: PaperDocument, context: ModelContext) {
        guard let pdf = PDFDocument(url: paper.fileURL), let page0 = pdf.page(at: 0) else { return }
        var pages = paper.pages
        guard let firstID = pages.first?.id else { return }
        // Same insertion the "Add page → after" sheet does: a lined note page after page 1.
        let note = PageRef(kind: .note(template: .linedCollege, size: .matching, color: .rice))
        if !pages.contains(where: { if case .note = $0.kind { true } else { false } }) {
            pages.insert(note, at: 1)
            paper.pages = pages
        }
        let noteID = paper.pages.first { if case .note = $0.kind { true } else { false } }?.id ?? note.id
        paper.lastPageIndex = ScreenshotMode.notePage ? 1 : 0

        let pageHeight = page0.bounds(for: .cropBox).height
        context.insert(PageDrawing(documentID: paper.id, pageID: firstID, pageIndex: 0,
                                   drawingData: paperPageDrawing(pdf: pdf, pageHeight: pageHeight).dataRepresentation()))
        context.insert(PageDrawing(documentID: paper.id, pageID: noteID, pageIndex: 1,
                                   drawingData: notePageDrawing().dataRepresentation()))
        try? context.save()
    }

    /// Page 1 of the GQA paper: highlight, circle, underline, margin notes.
    private static func paperPageDrawing(pdf: PDFDocument, pageHeight: CGFloat) -> PKDrawing {
        var ink = InkWriter(seed: 11)
        let sumi = InkSwatch.all[0].color, indigo = InkSwatch.all[1].color
        let vermilion = InkSwatch.all[2].color, saffron = InkSwatch.all[5].color

        func rect(_ text: String, where accept: (CGRect) -> Bool = { _ in true }) -> CGRect? {
            for selection in pdf.findString(text, withOptions: []) {
                guard let page = selection.pages.first, pdf.index(for: page) == 0 else { continue }
                let r = selection.bounds(for: page)
                if accept(r) {
                    return CGRect(x: r.minX, y: pageHeight - r.maxY, width: r.width, height: r.height)
                }
            }
            return nil
        }

        // Highlighter over the abstract's result sentence.
        for line in ["We show that uptrained GQA achieves quality", "close to multi-head attention with comparable",
                     "speed to MQA."] {
            if let r = rect(line, where: { $0.minX < 300 }) {
                ink.highlight(from: CGPoint(x: r.minX - 1, y: r.midY), to: CGPoint(x: r.maxX + 1, y: r.midY),
                              height: r.height + 2, color: saffron)
            }
        }
        // Circle "5%" in the abstract.
        if let r = rect("5%", where: { $0.minX < 300 }) {
            ink.loop(around: r.insetBy(dx: -4, dy: -4.5), color: vermilion, width: 1.6)
        }
        // Wavy underline under "grouped-query attention" in the right column (measured from the bundled PDF;
        // iOS findString returns a two-line box for this hyphenated phrase).
        let proposal = CGRect(x: 415.3, y: pageHeight - 544.3, width: 109.1, height: 9.8)
        ink.wave(from: CGPoint(x: proposal.minX - 2, y: proposal.maxY + 0.8),
                 to: CGPoint(x: proposal.maxX + 2, y: proposal.maxY + 0.8), color: indigo, width: 1.3)
        // Bracket + note in the right margin next to that paragraph.
        if let top = rect("Second, we propose", where: { $0.minX > 300 }),
           let bottom = rect("query attention.", where: { $0.minX > 300 }) {
            let x: CGFloat = 532
            ink.bracket(x: x, top: top.minY, bottom: bottom.maxY, color: indigo, width: 1.2)
            ink.write("key", at: CGPoint(x: x + 8, y: (top.minY + bottom.maxY) / 2 - 3), size: 15, color: indigo)
            ink.write("idea!", at: CGPoint(x: x + 7, y: (top.minY + bottom.maxY) / 2 + 13), size: 15, color: indigo)
        }
        // Star beside the Introduction heading.
        if let r = rect("Introduction") {
            ink.star(center: CGPoint(x: 54, y: r.midY), radius: 6, color: vermilion, width: 1.2)
        }
        // Underline "multi-query attention" in the intro.
        if let r = rect("multi-query attention", where: { $0.minX < 300 && pageHeight - $0.maxY > 500 }) {
            ink.line(from: CGPoint(x: r.minX, y: r.maxY + 2), to: CGPoint(x: r.maxX, y: r.maxY + 1.5),
                     color: sumi, width: 1.1)
        }
        // Note in the space right of the affiliation.
        ink.write("→ see Fig. 2 on p. 2", at: CGPoint(x: 392, y: 197), size: 14, color: sumi)
        return ink.drawing
    }

    /// The lined note page: handwritten summary plus a small sketch of grouped heads.
    private static func notePageDrawing() -> PKDrawing {
        var ink = InkWriter(seed: 7)
        let sumi = InkSwatch.all[0].color, indigo = InkSwatch.all[1].color
        let vermilion = InkSwatch.all[2].color, moss = InkSwatch.all[3].color
        let spacing = NotePageRenderer.mmToPoints(NotePageRenderer.collegeRuleMM)
        func baseline(_ n: Int) -> CGFloat { 36 + spacing * CGFloat(n + 1) - 3 }

        ink.write("GQA — reading notes", at: CGPoint(x: 60, y: baseline(2)), size: 22, color: indigo)
        ink.line(from: CGPoint(x: 58, y: baseline(2) + 6), to: CGPoint(x: 262, y: baseline(2) + 5), color: indigo, width: 1.4)
        let lines = [
            "• H query heads → G groups, one K/V head per group",
            "• G = 1 is MQA,  G = H is ordinary MHA",
            "• fewer K/V heads → smaller KV cache, less bandwidth",
            "• uptrain T5 checkpoints with ~5% of pre-training",
            "• new K/V head = mean-pool of the heads in its group",
            "• uptrained GQA-8: quality near MHA, speed near MQA",
        ]
        for (index, text) in lines.enumerated() {
            ink.write(text, at: CGPoint(x: 64, y: baseline(4 + index)), size: 15, color: sumi)
        }
        ink.loop(around: CGRect(x: 70, y: baseline(5) - 15, width: 104, height: 21), color: vermilion, width: 1.3)
        ink.line(from: CGPoint(x: 72, y: baseline(9) + 4), to: CGPoint(x: 400, y: baseline(9) + 3), color: moss, width: 1.2)

        // Sketch: 8 query heads sharing 4 key/value heads.
        let top = baseline(12)
        ink.write("sketch: GQA-4", at: CGPoint(x: 64, y: top), size: 15, color: moss)
        let startX: CGFloat = 170
        for group in 0..<4 {
            let kx = startX + CGFloat(group) * 64 + 14
            ink.box(CGRect(x: kx, y: top + 8, width: 12, height: 26), color: vermilion, width: 1.2)
            for q in 0..<2 {
                let qx = startX + CGFloat(group) * 64 + CGFloat(q) * 26
                ink.box(CGRect(x: qx, y: top + 66, width: 12, height: 26), color: indigo, width: 1.2)
                ink.line(from: CGPoint(x: qx + 6, y: top + 64), to: CGPoint(x: kx + 6, y: top + 37), color: sumi, width: 0.9)
            }
        }
        ink.write("K/V", at: CGPoint(x: startX + 262, y: top + 26), size: 15, color: vermilion)
        ink.write("Q", at: CGPoint(x: startX + 262, y: top + 84), size: 15, color: indigo)

        ink.write("MHA (G = H)  ←—  GQA  —→  MQA (G = 1)", at: CGPoint(x: 120, y: baseline(19)), size: 15, color: indigo)
        ink.write("more quality", at: CGPoint(x: 118, y: baseline(20)), size: 13, color: sumi)
        ink.write("more speed", at: CGPoint(x: 330, y: baseline(20)), size: 13, color: sumi)

        ink.write("Q: which G is the sweet spot for our model size?", at: CGPoint(x: 64, y: baseline(23)), size: 15, color: vermilion)
        ink.star(center: CGPoint(x: 52, y: baseline(23) - 5), radius: 6, color: vermilion, width: 1.2)
        return ink.drawing
    }

    // MARK: - Notebooks

    private static func seedNotebooks(into context: ModelContext) {
        let specs: [(String, NoteTemplate, NotePaperColor, NotePaperColor, Int)] = [
            ("Reading notes — Transformers", .linedCollege, .rice, .rice, 1),
            ("Lab meeting", .grid, .white, .white, 3),
            ("Thesis ideas", .dotted, .rice, .dark, 6),
        ]
        for (title, template, paperColor, cover, daysAgo) in specs {
            let notebook = DocumentStore.createNotebook(title: title, template: template, color: paperColor,
                                                        size: .a4, cover: cover, into: context)
            notebook.addedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            if let pageID = notebook.pages.first?.id {
                var ink = InkWriter(seed: UInt64(daysAgo) + 3)
                ink.write(title, at: CGPoint(x: 60, y: 90), size: 24, color: InkSwatch.all[1].color)
                ink.write("• \(title == "Lab meeting" ? "results: GQA-8 vs MQA" : "questions to follow up")",
                          at: CGPoint(x: 64, y: 140), size: 16, color: InkSwatch.all[0].color)
                context.insert(PageDrawing(documentID: notebook.id, pageID: pageID, pageIndex: 0,
                                           drawingData: ink.drawing.dataRepresentation()))
            }
        }
        try? context.save()
    }
}

/// Builds hand-drawn-looking PencilKit strokes in page space (points, top-left origin).
private struct InkWriter {
    private(set) var strokes: [PKStroke] = []
    private var state: UInt64
    private var time: TimeInterval = 0

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    var drawing: PKDrawing { PKDrawing(strokes: strokes) }

    /// Deterministic jitter in [-1, 1].
    private mutating func jitter() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 11) / Double(1 << 53)) * 2 - 1
    }

    private mutating func add(_ points: [CGPoint], ink: PKInk, width: CGFloat, height: CGFloat? = nil) {
        guard points.count > 1 else { return }
        // PencilKit drops very thin synthesized strokes, so build at 4x and scale the stroke back down.
        let k: CGFloat = 4
        var offset: TimeInterval = 0
        let strokePoints = points.map { point -> PKStrokePoint in
            offset += 0.008
            return PKStrokePoint(location: CGPoint(x: point.x * k, y: point.y * k), timeOffset: offset,
                                 size: CGSize(width: width * k, height: (height ?? width) * k),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: strokePoints, creationDate: Date(timeIntervalSince1970: time))
        time += 1
        strokes.append(PKStroke(ink: ink, path: path, transform: CGAffineTransform(scaleX: 1 / k, y: 1 / k)))
    }

    mutating func line(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat) {
        let steps = max(4, Int(hypot(b.x - a.x, b.y - a.y) / 6))
        var points: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let wobble = sin(t * .pi) * jitter() * 0.6
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + wobble))
        }
        add(points, ink: PKInk(.pen, color: color), width: width)
    }

    mutating func highlight(from a: CGPoint, to b: CGPoint, height: CGFloat, color: UIColor) {
        let steps = max(4, Int((b.x - a.x) / 8))
        let points = (0...steps).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + jitter() * 0.3)
        }
        add(points, ink: PKInk(.marker, color: color.withAlphaComponent(0.35)), width: height)
    }

    /// An open, slightly overshooting hand-drawn ellipse.
    mutating func loop(around rect: CGRect, color: UIColor, width: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = -CGFloat.pi * 0.8
        let steps = 48
        var points: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let angle = start + t * (2 * .pi + 0.45)
            let grow = 1 + t * 0.08 + jitter() * 0.015
            points.append(CGPoint(x: center.x + cos(angle) * rect.width / 2 * grow,
                                  y: center.y + sin(angle) * rect.height / 2 * grow))
        }
        add(points, ink: PKInk(.pen, color: color), width: width)
    }

    mutating func wave(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat) {
        let length = b.x - a.x
        let steps = max(8, Int(length / 2))
        let points = (0...steps).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + length * t, y: a.y + (b.y - a.y) * t + sin(t * length / 3.2) * 1.0)
        }
        add(points, ink: PKInk(.pen, color: color), width: width)
    }

    mutating func bracket(x: CGFloat, top: CGFloat, bottom: CGFloat, color: UIColor, width: CGFloat) {
        let mid = (top + bottom) / 2
        let points = [
            CGPoint(x: x - 4, y: top), CGPoint(x: x, y: top + 3), CGPoint(x: x, y: mid - 4),
            CGPoint(x: x + 4, y: mid), CGPoint(x: x, y: mid + 4), CGPoint(x: x, y: bottom - 3),
            CGPoint(x: x - 4, y: bottom),
        ]
        var dense: [CGPoint] = []
        for (p, q) in zip(points, points.dropFirst()) {
            for i in 0..<6 {
                let t = CGFloat(i) / 6
                dense.append(CGPoint(x: p.x + (q.x - p.x) * t + jitter() * 0.3, y: p.y + (q.y - p.y) * t))
            }
        }
        dense.append(points.last!)
        add(dense, ink: PKInk(.pen, color: color), width: width)
    }

    mutating func star(center: CGPoint, radius: CGFloat, color: UIColor, width: CGFloat) {
        let points = (0...5).map { i -> CGPoint in
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 4 * .pi / 5
            return CGPoint(x: center.x + cos(angle) * radius + jitter() * 0.4,
                           y: center.y + sin(angle) * radius + jitter() * 0.4)
        }
        var dense: [CGPoint] = []
        for (p, q) in zip(points, points.dropFirst()) {
            for i in 0..<5 { let t = CGFloat(i) / 5; dense.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)) }
        }
        dense.append(points.last!)
        add(dense, ink: PKInk(.pen, color: color), width: width)
    }

    mutating func box(_ rect: CGRect, color: UIColor, width: CGFloat) {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                       CGPoint(x: rect.minX + 0.5, y: rect.minY - 0.5)]
        var dense: [CGPoint] = []
        for (p, q) in zip(corners, corners.dropFirst()) {
            for i in 0..<5 {
                let t = CGFloat(i) / 5
                dense.append(CGPoint(x: p.x + (q.x - p.x) * t + jitter() * 0.3, y: p.y + (q.y - p.y) * t + jitter() * 0.3))
            }
        }
        dense.append(corners.last!)
        add(dense, ink: PKInk(.pen, color: color), width: width)
    }

    /// Handwriting from a script font's glyph outlines, traced with a fine pen. `origin` is the baseline start.
    mutating func write(_ text: String, at origin: CGPoint, size: CGFloat, color: UIColor) {
        let font = UIFont(name: "BradleyHandITCTT-Bold", size: size)
            ?? UIFont(name: "Noteworthy-Light", size: size) ?? .italicSystemFont(ofSize: size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let slant = jitter() * 0.02
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return }
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName as String].map { $0 as! CTFont } ?? (font as CTFont)
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                guard let path = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                let dy = jitter() * size * 0.03
                let map: (CGPoint) -> CGPoint = { p in
                    CGPoint(x: origin.x + position.x + p.x + p.y * slant, y: origin.y - p.y + dy)
                }
                for polyline in Self.flatten(path) {
                    add(polyline.map(map), ink: PKInk(.monoline, color: color), width: max(0.8, size * 0.06))
                }
            }
        }
    }

    private static func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> [CGPoint] {
        (1...6).map { i -> CGPoint in
            let t = CGFloat(i) / 6
            let u: CGFloat = 1 - t
            let a: CGFloat = u * u, b: CGFloat = 2 * u * t, d: CGFloat = t * t
            return CGPoint(x: a * p0.x + b * c.x + d * p1.x, y: a * p0.y + b * c.y + d * p1.y)
        }
    }

    private static func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) -> [CGPoint] {
        (1...8).map { i -> CGPoint in
            let t = CGFloat(i) / 8
            let u: CGFloat = 1 - t
            let a: CGFloat = u * u * u, b: CGFloat = 3 * u * u * t
            let c: CGFloat = 3 * u * t * t, d: CGFloat = t * t * t
            let x: CGFloat = a * p0.x + b * c1.x + c * c2.x + d * p1.x
            let y: CGFloat = a * p0.y + b * c1.y + c * c2.y + d * p1.y
            return CGPoint(x: x, y: y)
        }
    }

    private static func flatten(_ path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var last = CGPoint.zero
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                if current.count > 1 { result.append(current) }
                current = [e.points[0]]
                last = e.points[0]
            case .addLineToPoint:
                current.append(e.points[0])
                last = e.points[0]
            case .addQuadCurveToPoint:
                let end = e.points[1]
                current += quad(last, e.points[0], end)
                last = end
            case .addCurveToPoint:
                let end = e.points[2]
                current += cubic(last, e.points[0], e.points[1], end)
                last = end
            case .closeSubpath:
                if let first = current.first { current.append(first) }
            @unknown default:
                break
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
#endif
