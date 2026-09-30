import SwiftUI
import UIKit

enum LlamaLifecycle {
    @MainActor
    static func install() {
        ModelManager.shared.prepareAtLaunch()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .llamaMemoryPressure, object: nil)
            Task { await LlamaRunner.shared.handleMemoryPressure() }
        }
    }
}

struct LlamaScenePhaseObserver: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await LlamaRunner.shared.unload() }
            }
        }
    }
}

extension View {
    func observeLlamaLifecycle() -> some View {
        modifier(LlamaScenePhaseObserver())
    }
}
