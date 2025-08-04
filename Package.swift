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
//        .package(url: "https://github.com/lake-of-fire/RealmBinary.git", branch: "main"),
        .package(url: "https://github.com/realm/realm-swift.git", from: "20.0.3"),
        .package(url: "https://github.com/lake-of-fire/Mute.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "JapaneseLanguageTools",
            dependencies: [
                //.product(name: "RealmSwift", package: "RealmBinary"),
                .product(name: "RealmSwift", package: "realm-swift"),
                .product(name: "Mute", package: "Mute"),
            ],
            resources: [
                .copy("Resources/tofugu-audio-index.realm"),
            ]
        ),
        .executableTarget(
            name: "RealmCSVImporter",
            dependencies: [
                "JapaneseLanguageTools",
//                .product(name: "RealmSwift", package: "RealmBinary"),
                .product(name: "RealmSwift", package: "realm-swift"),
            ]
        )
    ]
)
