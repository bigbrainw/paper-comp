import PDFKit
import PencilKit
import SwiftData
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct InputSettingsTests {
    private func makePDFView() -> PDFView {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Page one" as NSString).draw(at: CGPoint(x: 72, y: 72), withAttributes: nil)
        }
        let pdfView = PDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        pdfView.document = PDFDocument(data: data)
        pdfView.layoutIfNeeded()
        return pdfView
    }

    private func makeProvider(allowFinger: Bool, toolState: ToolState = ToolState()) throws -> PageOverlayProvider {
        let container = try ModelContainer(
            for: PaperDocument.self, PageDrawing.self, SearchRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = DrawingStore(context: ModelContext(container), documentID: UUID())
        return PageOverlayProvider(store: store, toolState: toolState, allowFingerDrawing: allowFinger)
    }

    @Test func sharedKeyAndDefault() {
        #expect(InputSettings.allowFingerDrawingKey == "allowFingerDrawing")
        #if targetEnvironment(simulator)
        #expect(InputSettings.allowFingerDrawingDefault)
        #else
        #expect(!InputSettings.allowFingerDrawingDefault)
        #endif
    }

    @Test(arguments: [false, true])
    func policyMapping(allowFinger: Bool) {
        #expect(InputSettings.drawingPolicy(allowFinger: allowFinger) == (allowFinger ? .anyInput : .pencilOnly))
        #expect(InputSettings.scrollPanMinimumTouches(allowFinger: allowFinger) == (allowFinger ? 2 : 1))
        #expect(InputSettings.scrollPanMinimumTouches(allowFinger: allowFinger, isCircleSearch: true) == 2)
        // Search always takes a finger, whatever "Draw with finger" says.
        #expect(InputSettings.selectionTouchTypes(allowFinger: allowFinger) == [.direct, .pencil])
        #expect(InputSettings.scrollPanTouchTypes(allowFinger: allowFinger, isCircleSearch: false) == nil)
    }

    @Test func fingerWithSearchToolIsAccepted() {
        #expect(InputSettings.accepts(.direct, for: .circleSearch, allowFinger: false))
        #expect(InputSettings.accepts(.direct, for: .circleSearch, allowFinger: true))
    }

    @Test(arguments: [ReaderTool.pen, .highlighter, .eraser])
    func fingerWithInkToolNeedsDrawWithFinger(tool: ReaderTool) {
        #expect(!InputSettings.accepts(.direct, for: tool, allowFinger: false))
        #expect(InputSettings.accepts(.direct, for: tool, allowFinger: true))
        #expect(InputSettings.acceptedTouchTypes(for: tool, allowFinger: false) == [.pencil])
    }

    @Test(arguments: ReaderTool.allCases, [false, true])
    func pencilAlwaysAcceptedOtherInputNever(tool: ReaderTool, allowFinger: Bool) {
        #expect(InputSettings.accepts(.pencil, for: tool, allowFinger: allowFinger))
        #expect(!InputSettings.accepts(.indirect, for: tool, allowFinger: allowFinger))
    }

    @Test func secondFingerCancelsOnlyAFingerBoxInProgress() {
        #expect(BoxGestureRecognizer.secondTouchCancels(trackedType: .direct, state: .changed))
        #expect(BoxGestureRecognizer.secondTouchCancels(trackedType: .direct, state: .began))
        #expect(!BoxGestureRecognizer.secondTouchCancels(trackedType: .pencil, state: .changed)) // palm rest
        #expect(!BoxGestureRecognizer.secondTouchCancels(trackedType: .direct, state: .possible))
    }

    @Test func pencilOnlyLassoLeavesScrollingToFinger() {
        #expect(InputSettings.scrollPanTouchTypes(allowFinger: false, isCircleSearch: true) == [.direct])
        #expect(InputSettings.scrollPanTouchTypes(allowFinger: true, isCircleSearch: true) == nil)
    }

    @Test func togglingUpdatesExistingCanvas() throws {
        let pdfView = makePDFView()
        let provider = try makeProvider(allowFinger: false)
        let page = try #require(pdfView.document?.page(at: 0))
        let canvas = try #require(provider.pdfView(pdfView, overlayViewFor: page) as? PageCanvasView)
        #expect(canvas.drawingPolicy == .pencilOnly)

        provider.allowFingerDrawing = true
        #expect(canvas.drawingPolicy == .anyInput)
        provider.allowFingerDrawing = false
        #expect(canvas.drawingPolicy == .pencilOnly)
    }

    @Test func coordinatorAppliesScrollAndLassoInput() throws {
        let pdfView = makePDFView()
        let toolState = ToolState()
        let provider = try makeProvider(allowFinger: false, toolState: toolState)
        let captureView = CircleCaptureView(frame: pdfView.bounds)
        pdfView.addSubview(captureView)
        pdfView.addGestureRecognizer(captureView.lassoRecognizer)
        pdfView.addGestureRecognizer(captureView.boxRecognizer)

        let coordinator = PDFKitView.Coordinator(paper: PaperDocument(title: "T", fileName: "t.pdf"), toolState: toolState)
        coordinator.pdfView = pdfView
        coordinator.provider = provider
        coordinator.captureView = captureView
        let pan = try #require(PDFKitView.Coordinator.scrollView(in: pdfView)).panGestureRecognizer
        let defaultTypes = pan.allowedTouchTypes

        coordinator.applyInput(allowFinger: true)
        #expect(pan.minimumNumberOfTouches == 2)
        #expect(provider.allowFingerDrawing)
        #expect(captureView.boxRecognizer.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue)))
        #expect(!captureView.boxRecognizer.isEnabled)

        toolState.tool = .circleSearch
        coordinator.applyInput(allowFinger: false)
        // One finger boxes, two fingers scroll; the Pencil never scrolls while searching.
        #expect(pan.minimumNumberOfTouches == 2)
        #expect(captureView.boxRecognizer.isEnabled)
        #expect(captureView.isHidden) // overlay hidden until the user starts a drag
        #expect(captureView.boxRecognizer.allowedTouchTypes == [UITouch.TouchType.direct, .pencil].asAllowedTouchTypes)
        #expect(captureView.lassoRecognizer.allowedTouchTypes == [UITouch.TouchType.direct, .pencil].asAllowedTouchTypes)
        #expect(pan.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.direct.rawValue)])

        toolState.tool = .pen
        coordinator.applyInput(allowFinger: false)
        #expect(pan.minimumNumberOfTouches == 1)
        #expect(pan.allowedTouchTypes == defaultTypes)
        #expect(captureView.isHidden)
    }

    @Test func containerOwnsPencilInteraction() {
        let container = ReaderCanvasContainer(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let toolState = ToolState()
        let coordinator = PDFKitView.Coordinator(
            paper: PaperDocument(title: "T", fileName: "t.pdf"),
            toolState: toolState
        )
        container.installPencilInteraction(delegate: coordinator)
        let pencils = container.interactions.compactMap { $0 as? UIPencilInteraction }
        #expect(pencils.count == 1)
        #expect(container.pdfView.interactions.contains(where: { $0 is UIPencilInteraction }) == false)
        container.removePencilInteraction()
        #expect(container.interactions.contains(where: { $0 is UIPencilInteraction }) == false)
    }
}
