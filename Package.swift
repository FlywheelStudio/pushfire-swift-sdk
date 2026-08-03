// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushFire",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PushFire", targets: ["PushFire"]),
        .library(name: "PushFireFirebaseAuth", targets: ["PushFireFirebaseAuth"]),
        .library(name: "PushFireSupabaseAuth", targets: ["PushFireSupabaseAuth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.50.0"),
    ],
    targets: [
        .target(
            name: "PushFire",
            dependencies: [
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PushFireFirebaseAuth",
            dependencies: [
                "PushFire",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PushFireSupabaseAuth",
            dependencies: [
                "PushFire",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PushFireTests",
            dependencies: ["PushFire"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PushFireSupabaseAuthTests",
            dependencies: [
                "PushFireSupabaseAuth",
                "PushFire",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
