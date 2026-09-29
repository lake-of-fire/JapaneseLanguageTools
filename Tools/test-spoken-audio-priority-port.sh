#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/spoken-audio-priority.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/Sources/JapaneseLanguageTools" "$work/Tests/JapaneseLanguageToolsTests"
cp "$root/Sources/JapaneseLanguageTools/SpokenAudioSession.swift"    "$work/Sources/JapaneseLanguageTools/SpokenAudioSession.swift"
cp "$root/Tests/JapaneseLanguageToolsTests/SpokenAudioSessionPriorityTests.swift"    "$work/Tests/JapaneseLanguageToolsTests/SpokenAudioSessionPriorityTests.swift"

cat > "$work/Package.swift" <<'MANIFEST'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JapaneseLanguageToolsPriorityContract",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JapaneseLanguageTools", targets: ["JapaneseLanguageTools"]),
    ],
    targets: [
        .target(name: "JapaneseLanguageTools"),
        .testTarget(
            name: "JapaneseLanguageToolsTests",
            dependencies: ["JapaneseLanguageTools"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
MANIFEST

swift --version
swift test   --package-path "$work"   -c debug   --filter SpokenAudioSessionPriorityTests   -Xswiftc -warnings-as-errors

swift build   --package-path "$work"   -c release   -Xswiftc -warnings-as-errors
