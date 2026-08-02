// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushFire",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PushFire", targets: ["PushFire"]),
        .library(name: "PushFireFirebaseAuth", targets: ["PushFireFirebaseAuth"]),
        .library(name: "PushFireSupabaseAuth", targets: ["PushFireSupabaseAuth"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0"),
        // Capped below 2.50.0 deliberately: supabase-swift 2.50.0 raises its own iOS
        // floor to 16.0, which is incompatible with this package's iOS 15 floor. Do not
        // widen this range without also raising `platforms` above.
        .package(url: "https://github.com/supabase/supabase-swift.git", "2.0.0"..<"2.50.0"),
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
            dependencies: ["PushFireSupabaseAuth"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
