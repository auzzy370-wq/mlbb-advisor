// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HayaAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "HayaAI", targets: ["HayaAI"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0"),
        .package(url: "https://github.com/supabase-community/supabase-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "HayaAI",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "OpenAI", package: "OpenAI")
            ],
            path: "HayaAI",
            resources: [
                .process("HeroDatabase/JSON"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HayaAITests",
            dependencies: ["HayaAI"],
            path: "HayaAITests"
        )
    ]
)
