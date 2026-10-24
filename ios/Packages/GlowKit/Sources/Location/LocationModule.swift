import AppCore
import Foundation

// Owner: B2. The app target calls `LocationModule.live` in AppComposition; keep its signature.

public enum LocationModule {
    /// The location service the app runs on: CoreLocation, one precise fix per room check.
    public static func live(_: ServiceContext) -> any LocationService {
        LiveLocationService()
    }
}
