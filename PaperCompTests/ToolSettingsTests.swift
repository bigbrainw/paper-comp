import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaperComp

@MainActor
struct ToolSettingsTests {
    private func isolatedDefaults() throws -> UserDefaults {
        let name = "PaperCompTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func eraserModeParsing() {
        #expect(EraserMode(parsing: "stroke") == .stroke)
        #expect(EraserMode(parsing: "pixel") == .pixel)
        #expect(EraserMode(parsing: "Vector!") == .pixel)
        #expect(EraserMode(parsing: nil) == .pixel)
        #expect(EraserWidth(parsing: "huge") == .medium)
        #expect(EraserWidth.allCases.map(\.points) == [8, 20, 40])
    }

    @Test func eraserToolMapping() throws {
        let state = ToolState(defaults: try isolatedDefaults())
        state.tool = .eraser

        state.eraserMode = .stroke
        #expect((state.pkTool as? PKEraserTool)?.eraserType == .vector)

        state.eraserMode = .pixel
        state.eraserWidth = .large
        let bitmap = try #require(state.pkTool as? PKEraserTool)
        #expect(bitmap.eraserType == .fixedWidthBitmap)
        #expect(bitmap.width == 40)
    }

    @Test func eraserModeIsRememberedInSharedKey() throws {
        let defaults = try isolatedDefaults()
        ToolState(defaults: defaults).eraserMode = .stroke
        #expect(defaults.string(forKey: "eraserMode") == "stroke")
        #expect(ToolState(defaults: defaults).eraserMode == .stroke)
    }

    @Test(arguments: [
        (PenType.ballpoint, PKInkingTool.InkType.monoline.rawValue),
        (.fountain, PKInkingTool.InkType.fountainPen.rawValue),
        (.pen, PKInkingTool.InkType.pen.rawValue),
        (.pencil, PKInkingTool.InkType.pencil.rawValue),
        (.brush, PKInkingTool.InkType.watercolor.rawValue),
        (.crayon, PKInkingTool.InkType.crayon.rawValue),
    ])
    func penTypeMapping(type: PenType, inkRawValue: String) throws {
        let ink = PKInkingTool.InkType(rawValue: inkRawValue)
        #expect(type.inkType == ink)
        let state = ToolState(defaults: try isolatedDefaults())
        state.pen.penType = type
        #expect((state.pkTool as? PKInkingTool)?.inkType == ink)
    }

    @Test func highlighterAlwaysUsesMarker() throws {
        let state = ToolState(defaults: try isolatedDefaults())
        state.pen.penType = .crayon
        state.tool = .highlighter
        #expect((state.pkTool as? PKInkingTool)?.inkType == .marker)
    }

    @Test func perToolPresetsRoundTrip() throws {
        let defaults = try isolatedDefaults()
        let state = ToolState(defaults: defaults)
        state.pen = InkPreset(penType: .fountain, swatch: InkSwatch.all[1], width: .thick)
        state.tool = .highlighter
        state.activeInk.swatch = InkSwatch.all[3]
        state.activeInk.width = .thin
        state.eraserWidth = .small

        let reloaded = ToolState(defaults: defaults)
        #expect(reloaded.pen == InkPreset(penType: .fountain, swatch: InkSwatch.all[1], width: .thick))
        #expect(reloaded.highlighter.swatch == InkSwatch.all[3])
        #expect(reloaded.highlighter.width == .thin)
        #expect(reloaded.eraserWidth == .small)
    }

    @Test func corruptPresetFallsBackToDefaults() throws {
        let defaults = try isolatedDefaults()
        defaults.set("quill", forKey: "pen.inkType")
        defaults.set("Neon Pink", forKey: "pen.color")
        defaults.set("enormous", forKey: "pen.width")
        #expect(ToolState(defaults: defaults).pen == .penDefault)
    }

    @Test func toolbarPositionParsing() {
        #expect(ToolbarPosition(parsing: "left") == .left)
        #expect(ToolbarPosition(parsing: "top") == .top)
        #expect(ToolbarPosition(parsing: "bottom") == .top)
        #expect(ToolbarPosition(parsing: nil) == .top)
    }

    @Test func pencilPreferredActionMapping() {
        #expect(PencilTapResponse(.switchEraser) == .toggleEraser)
        #expect(PencilTapResponse(.switchPrevious) == .switchToPrevious)
        #expect(PencilTapResponse(.showColorPalette) == .showInkOptions)
        #expect(PencilTapResponse(.showInkAttributes) == .showInkOptions)
        #expect(PencilTapResponse(.ignore) == .toggleCircleSearch)
    }

    @Test func handlePencilTapToggleEraserUpdatesToolbarToolState() throws {
        let toolState = ToolState(defaults: try isolatedDefaults())
        toolState.tool = .pen
        let coordinator = PDFKitView.Coordinator(
            paper: PaperDocument(title: "T", fileName: "t.pdf"),
            toolState: toolState
        )
        let toolbarState = coordinator.toolState
        #expect(ObjectIdentifier(toolbarState) == ObjectIdentifier(toolState))
        coordinator.toolState.handlePencilTap(.toggleEraser)
        #expect(toolState.tool == .eraser)
        #expect(toolbarState.tool == .eraser)
        toolbarState.handlePencilTap(.toggleEraser)
        #expect(coordinator.toolState.tool == .pen)
    }

    @Test func pencilTapActions() throws {
        let state = ToolState(defaults: try isolatedDefaults())
        state.tool = .highlighter
        state.handlePencilTap(.toggleEraser)
        #expect(state.tool == .eraser)
        state.handlePencilTap(.toggleEraser)
        #expect(state.tool == .highlighter)

        state.tool = .pen
        state.handlePencilTap(.switchToPrevious)
        #expect(state.tool == .highlighter)

        state.tool = .eraser
        state.handlePencilTap(.showInkOptions)
        #expect(state.tool == .highlighter && state.isShowingInkOptions)

        state.handlePencilTap(.toggleCircleSearch)
        #expect(state.tool == .circleSearch && !state.isShowingInkOptions)
        state.handlePencilTap(.toggleCircleSearch)
        #expect(state.tool == .highlighter)
    }
}
