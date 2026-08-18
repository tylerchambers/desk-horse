import AppKit
import SwiftUI

@MainActor
final class HorseOverlayView: NSHostingView<HorseRealityView> {
    init(scene: HorseScene) {
        super.init(rootView: HorseRealityView(scene: scene))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init(rootView: HorseRealityView) {
        fatalError("Use init(scene:)")
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}
