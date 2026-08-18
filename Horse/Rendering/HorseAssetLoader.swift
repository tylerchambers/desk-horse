import Foundation
import RealityKit

@MainActor
enum HorseAssetLoader {
    enum LoadingError: LocalizedError {
        case missingResource

        var errorDescription: String? {
            "horse.usdz is missing from the application bundle"
        }
    }

    static func load() async throws -> Entity {
        guard let assetURL = Bundle.main.url(forResource: "horse", withExtension: "usdz") else {
            throw LoadingError.missingResource
        }

        return try await Entity(contentsOf: assetURL)
    }
}
