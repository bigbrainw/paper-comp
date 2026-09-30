import Observation
import SwiftUI

/// Live search-card model. The UIKit host sets `rootView` once per `revision`;
/// drag, streaming, and hit-testing must not replace that view.
@Observable @MainActor
final class SearchCardSession {
    private(set) var revision = ""
    var title = "Search"
    var anchor: CGRect = .zero
    var startMinimized = false
    var capture: CircleCapture?
    var marker: SearchMarker?
    var savedRecords: [SearchRecord] = []
    var onClose: () -> Void = {}
    var onAnswered: ((String, String, SearchAnswerProvenance) -> Void)?
    var onDeleteSaved: (() -> Void)?
    /// Card frame in the overlay / canvas, used so the UIKit host can hit-test without drawing.
    var interactiveFrame: CGRect = .zero

    var isPresented: Bool { capture != nil || marker != nil }

    func showCapture(
        _ capture: CircleCapture,
        anchor: CGRect,
        startMinimized: Bool = false,
        onClose: @escaping () -> Void,
        onAnswered: ((String, String, SearchAnswerProvenance) -> Void)?
    ) {
        self.capture = capture
        self.marker = nil
        self.savedRecords = []
        self.anchor = anchor
        self.title = "Search"
        self.startMinimized = startMinimized
        self.onClose = onClose
        self.onAnswered = onAnswered
        self.onDeleteSaved = nil
        interactiveFrame = .zero
        revision = "capture-\(capture.id.uuidString)"
    }

    func showMarker(
        _ marker: SearchMarker,
        records: [SearchRecord],
        anchor: CGRect,
        onClose: @escaping () -> Void,
        onDeleteSaved: @escaping () -> Void
    ) {
        self.capture = nil
        self.marker = marker
        self.savedRecords = records
        self.anchor = anchor
        self.title = "Saved answer"
        self.startMinimized = false
        self.onClose = onClose
        self.onAnswered = nil
        self.onDeleteSaved = onDeleteSaved
        revision = "marker-\(marker.pageID)-\(marker.pageRect.debugDescription)"
    }

    func dismiss() {
        revision = ""
        capture = nil
        marker = nil
        savedRecords = []
        onAnswered = nil
        onDeleteSaved = nil
        onClose = {}
        startMinimized = false
        interactiveFrame = .zero
    }
}

/// Counts host installs so tests can prove drag/stream do not replace `rootView`.
enum SearchCardHostProbe {
    nonisolated(unsafe) static var updateSearchCardCalls = 0
    nonisolated(unsafe) static var rootViewAssignments = 0

    static func reset() {
        updateSearchCardCalls = 0
        rootViewAssignments = 0
    }
}
