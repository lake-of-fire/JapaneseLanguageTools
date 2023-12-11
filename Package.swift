// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JapaneseLanguageTools",
    platforms: [.macOS(.v12), .iOS(.v15), .watchOS(.v4)],
    products: [
        .library(
            name: "JapaneseLanguageTools",
            targets: ["JapaneseLanguageTools"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/lake-of-fire/RealmBinary.git", branch: "main"),
        .product(name: "RealmSwift", package: "realm-swift"),
    ],
    targets: [
        .target(
            name: "JapaneseLanguageTools",
            dependencies: [
//                .product(name: "RealmSwift", package: "RealmBinary"),
                .product(name: "Realm", package: "realm-swift"),
                .product(name: "RealmSwift", package: "realm-swift"),
            ],
            resources: [
                .copy("Resources/tofugu-audio-index.realm"),
            ]
        ),
        .executableTarget(
            name: "RealmCSVImporter",
            dependencies: [
                "JapaneseLanguageTools",
                .product(name: "RealmSwift", package: "RealmBinary")
            ]
        )
    ]
)
