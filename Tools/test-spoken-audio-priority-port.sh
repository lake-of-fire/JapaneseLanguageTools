#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/spoken-audio-priority.XXXXXX")"
cleanup() {
    if [[ "$(uname -s)" == "Darwin" && -d "$HOME/.Trash" ]]; then
        local trashDestination
        trashDestination="$(mktemp -d "$HOME/.Trash/spoken-audio-priority.XXXXXX")"
        mv "$work" "$trashDestination/"
    fi
    # Without a Darwin Trash directory, retain the fresh scratch directory.
}
trap cleanup EXIT

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

if [[ "$(uname -s)" == "Darwin" ]]; then
    swiftCommand=(xcrun swift)
else
    swiftCommand=(swift)
fi

"${swiftCommand[@]}" --version
"${swiftCommand[@]}" test   --package-path "$work"   -c debug   --filter SpokenAudioSessionPriorityTests   -Xswiftc -warnings-as-errors

"${swiftCommand[@]}" build   --package-path "$work"   -c release   -Xswiftc -warnings-as-errors
