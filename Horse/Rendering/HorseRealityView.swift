import RealityKit
import SwiftUI

struct HorseRealityView: View {
    @Bindable var scene: HorseScene

    var body: some View {
        RealityView { content in
            await scene.install(in: &content)
        } update: { content in
            scene.configureRendering(&content)
        }
        .allowsHitTesting(false)
        .background(Color.clear)
    }
}
