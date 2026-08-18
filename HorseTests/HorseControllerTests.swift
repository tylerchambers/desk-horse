import simd
import XCTest
@testable import Horse

final class HorseControllerTests: XCTestCase {
    func testMovementIsFrameRateIndependent() {
        var sixtyFrames = HorseController()
        var tenFrames = HorseController()
        let input = InputState(forward: 1, strafe: 1)

        for _ in 0 ..< 60 {
            sixtyFrames.update(input: input, deltaTime: 1 / 60)
        }
        for _ in 0 ..< 10 {
            tenFrames.update(input: input, deltaTime: 0.1)
        }

        XCTAssertEqual(sixtyFrames.state.position.x, tenFrames.state.position.x, accuracy: 0.0001)
        XCTAssertEqual(sixtyFrames.state.position.z, tenFrames.state.position.z, accuracy: 0.0001)
    }

    func testApproachingCameraIncreasesDepthCoordinate() {
        var controller = HorseController()

        controller.update(input: InputState(forward: -1), deltaTime: 0.5)

        XCTAssertGreaterThan(controller.state.position.z, 0)
    }

    func testMovingAwayDecreasesDepthCoordinate() {
        var controller = HorseController()

        controller.update(input: InputState(forward: 1), deltaTime: 0.5)

        XCTAssertLessThan(controller.state.position.z, 0)
    }

    func testDiagonalMovementIsNotFaster() {
        var straight = HorseController()
        var diagonal = HorseController()

        straight.update(input: InputState(forward: 1), deltaTime: 0.1)
        diagonal.update(input: InputState(forward: 1, strafe: 1), deltaTime: 0.1)

        XCTAssertEqual(
            simd_length(straight.state.velocity),
            simd_length(diagonal.state.velocity),
            accuracy: 0.0001
        )
    }

    func testHorseFacesCardinalMovementDirection() {
        var controller = HorseController()

        controller.update(input: InputState(strafe: 1), deltaTime: 0.1)
        XCTAssertEqual(controller.state.yaw, 0, accuracy: 0.0001)

        controller.update(input: InputState(forward: 1), deltaTime: 0.1)
        XCTAssertEqual(controller.state.yaw, .pi / 2, accuracy: 0.0001)
    }

    func testPositionCannotLeaveReachableWorldBounds() {
        var controller = HorseController()
        let towardCamera = InputState(forward: -1, strafe: 1, mouseDelta: SIMD2<Float>(0, 10_000))

        for _ in 0 ..< 1_000 {
            controller.update(input: towardCamera, deltaTime: 0.1)
        }

        XCTAssertEqual(controller.state.position.x, 7, accuracy: 0.0001)
        XCTAssertEqual(controller.state.position.y, 1.75, accuracy: 0.0001)
        XCTAssertEqual(controller.state.position.z, 5.8, accuracy: 0.0001)
    }

    func testMouseSteeringRotatesAndMovesVerticallyWhileIdle() {
        var controller = HorseController()

        controller.update(
            input: InputState(mouseDelta: SIMD2<Float>(20, -10)),
            deltaTime: 1 / 60
        )

        XCTAssertEqual(controller.state.yaw, 0.16, accuracy: 0.0001)
        XCTAssertEqual(controller.state.position.y, -0.06, accuracy: 0.0001)
    }

    func testResetRestoresInitialState() {
        var controller = HorseController()
        controller.update(input: InputState(forward: 1, strafe: 1), deltaTime: 0.1)

        controller.reset()

        XCTAssertEqual(controller.state, HorseController.initialState)
    }
}
