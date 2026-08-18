import AppKit
import Observation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class HorseScene {
    var pixelatedRendering = true

    @ObservationIgnored private var horseEntity: Entity?
    @ObservationIgnored private var latestState = HorseController.initialState

    func install(in content: inout RealityViewCameraContent) async {
        let root = Entity()
        root.name = "HorseWorld"

        do {
            let horse = try await HorseAssetLoader.load()
            horse.name = "QuaterniusFarmHorse"

            let modelBounds = horse.visualBounds(relativeTo: horse)
            let modelScale = 2.5 / modelBounds.extents.y
            let modelRotation = simd_quatf(
                angle: .pi / 2,
                axis: SIMD3<Float>(0, 1, 0)
            )
            let modelCenter = (modelBounds.min + modelBounds.max) / 2
            let rotatedCenter = modelRotation.act(modelCenter * modelScale)

            horse.scale = SIMD3<Float>(repeating: modelScale)
            horse.orientation = modelRotation
            horse.position = SIMD3<Float>(
                -rotatedCenter.x,
                -modelBounds.min.y * modelScale,
                -rotatedCenter.z
            )

            let motionRoot = Entity()
            motionRoot.name = "HorseMotionRoot"
            motionRoot.addChild(horse)
            root.addChild(motionRoot)
            horseEntity = motionRoot
        } catch {
            root.addChild(makeLoadingFailureMarker())
            NSLog("Horse failed to load: %@", error.localizedDescription)
        }

        let light = DirectionalLight()
        light.name = "CheapSun"
        light.light.intensity = 3_000
        light.shadow = nil
        light.orientation = simd_quatf(angle: -.pi / 3, axis: SIMD3<Float>(1, 0.25, 0))
        root.addChild(light)

        let camera = PerspectiveCamera()
        camera.name = "FixedCamera"
        camera.camera = PerspectiveCameraComponent(
            near: 0.05,
            far: 50,
            fieldOfViewInDegrees: 48
        )
        camera.look(
            at: SIMD3<Float>(0, 1.15, -1),
            from: SIMD3<Float>(0, 2.1, 8),
            relativeTo: nil
        )
        root.addChild(camera)

        content.add(root)
        content.camera = .virtual
        content.cameraTarget = camera
        configureRendering(&content)
        apply(latestState)
    }

    func configureRendering(_ content: inout RealityViewCameraContent) {
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.renderingEffects.antialiasing = pixelatedRendering ? .none : .multisample4X
    }

    func apply(_ state: HorseState) {
        latestState = state
        horseEntity?.position = state.position
        horseEntity?.orientation = simd_quatf(angle: state.yaw, axis: SIMD3<Float>(0, 1, 0))
    }

    private func makeLoadingFailureMarker() -> Entity {
        let mesh = MeshResource.generateBox(size: SIMD3<Float>(1.5, 1.5, 1.5))
        let material = UnlitMaterial(color: .magenta)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.name = "MissingHorseAsset"
        marker.position = SIMD3<Float>(0, 1, 0)
        return marker
    }
}
