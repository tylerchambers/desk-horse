import simd

struct HorseState: Equatable, Sendable {
    var position = SIMD3<Float>(0, 0, 0)
    var yaw: Float = 0
    var velocity = SIMD3<Float>.zero
}

struct InputState: Equatable, Sendable {
    var forward: Float = 0
    var strafe: Float = 0
    var mouseDelta = SIMD2<Float>.zero
}

struct HorseController: Sendable {
    static let initialState = HorseState()

    private(set) var state = HorseController.initialState

    private let movementSpeed: Float = 3.5
    private let yawSensitivity: Float = 0.008
    private let verticalSensitivity: Float = 0.006
    private let horizontalBounds: ClosedRange<Float> = -7 ... 7
    private let verticalBounds: ClosedRange<Float> = -0.25 ... 1.75
    private let depthBounds: ClosedRange<Float> = -10 ... 5.8

    mutating func update(input: InputState, deltaTime: Float) {
        let safeDeltaTime = min(max(deltaTime, 0), 0.1)
        var planarDirection = SIMD2<Float>(input.strafe, -input.forward)

        if simd_length_squared(planarDirection) > 1 {
            planarDirection = simd_normalize(planarDirection)
        }

        let velocity = SIMD3<Float>(
            planarDirection.x * movementSpeed,
            0,
            planarDirection.y * movementSpeed
        )
        state.velocity = velocity
        state.position += velocity * safeDeltaTime
        state.position.y += input.mouseDelta.y * verticalSensitivity

        if simd_length_squared(planarDirection) > 0.0001 {
            state.yaw = atan2(-planarDirection.y, planarDirection.x)
        } else {
            state.yaw += input.mouseDelta.x * yawSensitivity
        }

        state.position.x = state.position.x.clamped(to: horizontalBounds)
        state.position.y = state.position.y.clamped(to: verticalBounds)
        state.position.z = state.position.z.clamped(to: depthBounds)
    }

    mutating func reset() {
        state = Self.initialState
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
