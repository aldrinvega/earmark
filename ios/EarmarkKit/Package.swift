// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Same split as Glasswing: the SwiftData `Store` target needs Xcode (its @Model macros ship with Xcode, not with the
// swift.org toolchain). Local runs on this Mac set EARMARK_NO_SWIFTDATA=1 (ios/test-local.sh); CI builds everything.
let withSwiftData = ProcessInfo.processInfo.environment["EARMARK_NO_SWIFTDATA"] == nil

var targets: [Target] = [
    // Value types shared by every module (SentenceID, …). Foundation only.
    .target(name: "Models"),
    // Text ↔ audio alignment on value types: normaliser, aligner, AlignmentMap. No Speech/AVFoundation.
    .target(name: "ReadAlongCore", dependencies: ["Models"]),
    // One XHTML chapter → paragraphs → sentences with stable IDs, the input the aligner consumes. Foundation only.
    .target(name: "EPUBCore", dependencies: ["Models", "ReadAlongCore"]),
    // View models and UI logic for the app (Diagnostics first), testable without Xcode. Foundation + Observation only.
    .target(name: "AppFeatures", dependencies: ["Models", "ReadAlongCore", "EPUBCore"]),
    // Public-domain fixtures and test helpers (never shipped in the app).
    .target(name: "EarmarkTestSupport", resources: [.copy("Fixtures")]),
    .testTarget(name: "ModelsTests", dependencies: ["Models", "EarmarkTestSupport"]),
    .testTarget(name: "ReadAlongCoreTests", dependencies: ["ReadAlongCore", "Models"]),
    .testTarget(name: "AppFeaturesTests", dependencies: ["AppFeatures", "Models", "ReadAlongCore", "EPUBCore", "EarmarkTestSupport"]),
    .testTarget(name: "EPUBCoreTests", dependencies: ["EPUBCore", "Models", "ReadAlongCore", "EarmarkTestSupport"]),
]
var products: [Product] = [
    .library(name: "Models", targets: ["Models"]),
    .library(name: "ReadAlongCore", targets: ["ReadAlongCore"]),
    .library(name: "EPUBCore", targets: ["EPUBCore"]),
    .library(name: "AppFeatures", targets: ["AppFeatures"]),
]
if withSwiftData {
    // On-device library store (SPEC-library). Depends on Models only, never on a network client.
    targets += [
        .target(name: "Store", dependencies: ["Models"]),
        .testTarget(name: "StoreTests", dependencies: ["Store"]),
    ]
    products += [.library(name: "Store", targets: ["Store"])]
}

let package = Package(
    name: "EarmarkKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v6]
)
