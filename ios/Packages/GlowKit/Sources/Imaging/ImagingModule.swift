import APIClient
import AppCore
import Foundation

/// The Imaging module (B3): the on-device blur pipeline and the private image loader.
public enum ImagingModule {
    /// The imaging service the app runs on. `ios/Glow/AppComposition.swift` calls this.
    public static func live(_ context: ServiceContext) -> any ImagingService {
        LiveImagingService(pipeline: CardPhotoPipeline(), loader: PrivateImageLoader(api: context.api))
    }
}

/// Vision and Core Image on the phone for check-in photos, the API for private images.
public struct LiveImagingService: ImagingService {
    private let pipeline: CardPhotoPipeline
    private let loader: PrivateImageLoader

    public init(pipeline: CardPhotoPipeline, loader: PrivateImageLoader) {
        self.pipeline = pipeline
        self.loader = loader
    }

    public func prepareCardPhoto(from original: Data) async throws -> PreparedCardPhoto {
        let pipeline = pipeline
        // Vision and Core Image are synchronous and heavy: keep them off the main actor.
        return try await Task.detached(priority: .userInitiated) {
            try pipeline.prepare(original)
        }.value
    }

    public func loadPrivateImage(_ source: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage {
        try await loader.load(source)
    }
}
