// swift-tools-version:5.9
//
// SwiftPM manifest for the Sync Engine CORE only (Foundation-only sources that
// the app target compiles directly from RentnKing/Sync/Core). It exists so the
// core is unit-testable on macOS without booting the iOS app:
//
//     swift test                      (Xcode license accepted)
//     Scripts/test-sync-core.sh       (works even when xcodebuild is unavailable)
//
// The Xcode project does NOT depend on this package; the same files are members
// of the RentnKing target. UIKit-dependent code lives in RentnKing/Sync/App and
// is deliberately outside this package.
//
import PackageDescription

let package = Package(
    name: "KabbaSyncCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "KabbaSyncCore", targets: ["KabbaSyncCore"]),
    ],
    targets: [
        .target(
            name: "KabbaSyncCore",
            path: "RentnKing/Sync/Core"
        ),
        .testTarget(
            name: "KabbaSyncCoreTests",
            dependencies: ["KabbaSyncCore"],
            path: "RentnKingTests/KabbaSyncCore"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
