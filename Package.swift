// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OwnID",
    defaultLocalization: "en",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "OwnIDCore", targets: ["OwnIDCore"]),
        .library(name: "OwnIDSwiftUI", targets: ["OwnIDSwiftUI"]),
    ],
    targets: [
        .target(
            name: "OwnIDCore",
            path: "OwnIDCore",
            exclude: ["Tests", "OpenApi", "api"],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "OwnIDModuleVersion")]
        ),
        .target(
            name: "OwnIDSwiftUI",
            dependencies: ["OwnIDCore"],
            path: "OwnIDSwiftUI/Sources",
            plugins: [.plugin(name: "OwnIDModuleVersion")]
        ),
        .plugin(name: "OwnIDModuleVersion", capability: .buildTool()),
        .testTarget(name: "OwnIDCoreTests", dependencies: ["OwnIDCore"], path: "OwnIDCore/Tests"),
        .testTarget(name: "OwnIDSwiftUITests", dependencies: ["OwnIDSwiftUI"], path: "OwnIDSwiftUI/Tests"),
    ],
    swiftLanguageModes: [.v6]
)
