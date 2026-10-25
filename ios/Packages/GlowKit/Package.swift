// swift-tools-version: 6.2
//
// GlowKit: one module per owner, so nine agents can work in parallel.
// See docs/SPEC.md ("iOS modules and owners") and docs/HANDOFFS.md (A3).
//
// Owner: A3. To add a dependency or a module, ask under A3 in docs/HANDOFFS.md
// (or open a small `cross-owner` PR). Feature modules never depend on each other:
// they move between screens by sending an AppCore `Route`.

import Foundation
import PackageDescription

// MARK: - Pinned remote packages

// Versions are exact so every agent and CI build the same code. The lockfile for the
// app build is ios/Package.resolved (scripts/sim.sh build keeps it in sync).
let remotePackages: [Package.Dependency] = [
    // OpenAPI runtime + URLSession transport for the generated client (A2 generates, A3 wraps).
    .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.3"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.4.0"),
    .package(url: "https://github.com/apple/swift-http-types", exact: "1.8.0"),
    // Supabase: the app only ever uses Auth (sign in) and Realtime (its own channels).
    // PostgREST and Storage are deliberately not linked: everything else goes through the API.
    .package(url: "https://github.com/supabase/supabase-swift", exact: "2.55.4"),
    // Snapshot tests (spec: every screen at default and largest text size).
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7"),
]

let openAPIRuntime: Target.Dependency = .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
let openAPIURLSession: Target.Dependency = .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
let httpTypes: Target.Dependency = .product(name: "HTTPTypes", package: "swift-http-types")
let supabaseAuth: Target.Dependency = .product(name: "Auth", package: "supabase-swift")
let supabaseRealtime: Target.Dependency = .product(name: "Realtime", package: "supabase-swift")
let snapshotTesting: Target.Dependency = .product(name: "SnapshotTesting", package: "swift-snapshot-testing")

// MARK: - Generated client switch

// A2's codegen writes the swift-openapi-generator output into Sources/APIClient/Generated
// (Types.swift and Client.swift). Until that lands, the wrapper compiles without it, and the
// `GlowAPI.client` / `GlowAPI.perform` glue switches on by itself once Client.swift exists.
let generatedClientPath = Context.packageDirectory + "/Sources/APIClient/Generated/Client.swift"
let hasGeneratedClient = FileManager.default.fileExists(atPath: generatedClientPath)

// MARK: - Shared settings

// Swift 6 language mode (strict concurrency) comes from the tools version.
// Warnings are errors in our own code, so "builds with no warnings" can't regress.
let glowSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

// MARK: - Modules

struct Module {
    let name: String
    var dependencies: [Target.Dependency] = []
    var testDependencies: [Target.Dependency] = []
    var swiftSettings: [SwiftSetting] = []
    var exclude: [String] = []
}

// Every module that talks to the API imports the generated client's runtime and HTTP types
// (for example `GlowAPI.send`, `Base64EncodedData`), so they're declared here rather than
// reached through APIClient by accident.
let core: [Target.Dependency] = ["AppCore", "APIClient", openAPIRuntime, httpTypes]
let feature: [Target.Dependency] = ["AppCore", "APIClient", "DesignSystem", openAPIRuntime, httpTypes]

let modules: [Module] = [
    // Foundations (A3, A2)
    Module(
        name: "APIClient",
        dependencies: [openAPIRuntime, openAPIURLSession, httpTypes],
        swiftSettings: hasGeneratedClient ? [.define("GLOW_GENERATED_CLIENT")] : [],
    ),
    Module(name: "AppCore", dependencies: ["APIClient"]),
    Module(name: "DesignSystem", testDependencies: [snapshotTesting]),
    Module(name: "LiveActivityShared"),

    // Services: each implements its protocol from AppCore/Services.
    Module(name: "Session", dependencies: core + [supabaseAuth]),
    Module(name: "Location", dependencies: core),
    Module(name: "Imaging", dependencies: core),
    Module(name: "Push", dependencies: core),
    // "Realtime" in the spec, but supabase-swift already has a target with that name.
    Module(name: "GlowRealtime", dependencies: core + [supabaseRealtime]),

    // Features: AppCore, APIClient, DesignSystem, plus the service modules their owner also owns
    // (or whose views they need). Never another feature.
    Module(name: "FeatureOnboarding", dependencies: feature + ["Session"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureSettings", dependencies: feature + ["Session"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureRooms", dependencies: feature + ["Location"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureCheckIn", dependencies: feature + ["Imaging"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureSafety", dependencies: feature, testDependencies: [snapshotTesting]),
    Module(name: "FeatureDeck", dependencies: feature + ["Imaging"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureMatch", dependencies: feature + ["Imaging"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureGlow", dependencies: feature + ["LiveActivityShared"], testDependencies: [snapshotTesting]),
    Module(name: "FeatureChat", dependencies: feature, testDependencies: [snapshotTesting]),
    // Blind mode (X2): Double Blind inside Glow.
    Module(name: "FeatureBlind", dependencies: feature, testDependencies: [snapshotTesting]),
]

// MARK: - Package

let package = Package(
    name: "GlowKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: remotePackages,
    targets: modules.flatMap { module -> [Target] in
        [
            .target(
                name: module.name,
                dependencies: module.dependencies,
                exclude: module.exclude,
                swiftSettings: glowSettings + module.swiftSettings,
            ),
            .testTarget(
                name: "\(module.name)Tests",
                dependencies: [.target(name: module.name)] + module.testDependencies,
                swiftSettings: glowSettings,
            ),
        ]
    },
)
