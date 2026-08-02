// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushFire",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PushFire", targets: ["PushFire"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "PushFire",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PushFireTests",
            dependencies: ["PushFire"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
