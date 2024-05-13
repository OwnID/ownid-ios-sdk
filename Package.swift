// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "OwnID",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "OwnIDCoreSDK",
            targets: ["OwnIDCoreSDK"]
        ),
        .library(
            name: "OwnIDGigyaSDK",
            targets: ["OwnIDGigyaSDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SAP/gigya-swift-sdk.git", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "OwnIDCoreSDK",
            dependencies: [],
            path: "ownid-core-ios-sdk"
        ),
        .target(
            name: "OwnIDGigyaSDK",
            dependencies: [
                "OwnIDCoreSDK", 
                .product(name: "Gigya", package: "gigya-swift-sdk")
            ],
            path: "ownid-gigya-ios-sdk"
        ),
    ]
)
