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
        .package(url: "https://github.com/lake-of-fire/Mute.git", branch: "master"),
        .package(url: "https://github.com/pointfreeco/sqlite-data.git", exact: "1.4.1"),
    ],
    targets: [
        .target(
            name: "JapaneseLanguageTools",
            dependencies: [
                .product(name: "Mute", package: "Mute"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ],
            resources: [
                .copy("Resources/tofugu-audio-index.sqlite"),
            ],
            linkerSettings: []
        ),
        .testTarget(
            name: "JapaneseLanguageToolsTests",
            dependencies: ["JapaneseLanguageTools"]
        ),
        .executableTarget(
            name: "TofuguAudioIndexSQLiteBuilder",
            dependencies: [],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
