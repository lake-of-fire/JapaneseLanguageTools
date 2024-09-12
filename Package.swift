// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JapaneseLanguageTools",
    platforms: [.macOS(.v13), .iOS(.v15), .watchOS(.v4)],
    products: [
        .library(
            name: "JapaneseLanguageTools",
            type: .dynamic,
            targets: ["JapaneseLanguageTools"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/RomanEsin/RealmBinary.git", from: "10.53.0"),
                .package(url: "https://github.com/realm/realm-swift.git", from: "10.53.0"),
                .package(url: "https://github.com/lake-of-fire/BigSyncKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "JapaneseLanguageTools",
            dependencies: [
//                .product(name: "Realm", package: "RealmBinary"),
//                .product(name: "RealmSwift", package: "RealmBinary"),
//                .product(name: "Realm", package: "realm-swift"),
                .product(name: "RealmSwift", package: "realm-swift"),
                .product(name: "BigSyncKit", package: "BigSyncKit"),
            ],
            resources: [
                .copy("Resources/tofugu-audio-index.realm"),
            ]
        ),
        .executableTarget(
            name: "RealmCSVImporter",
            dependencies: [
                "JapaneseLanguageTools",
//                .product(name: "Realm", package: "RealmBinary"),
//                .product(name: "RealmSwift", package: "RealmBinary"),
//                .product(name: "Realm", package: "realm-swift"),
                .product(name: "RealmSwift", package: "realm-swift"),
            ]
        )
    ]
)
