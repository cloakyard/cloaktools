#!/bin/zsh
# Create only synthetic media. Existing fixture files are never overwritten.
set -euo pipefail
cd "${0:A:h}/.."
fixture_build=$(mktemp -d /tmp/CloakTools-MediaFixtureBuild.XXXXXX)
trap 'rm -rf "$fixture_build"' EXIT
cat > "$fixture_build/Main.swift" <<'SWIFT'
import Foundation
import AVFoundation
@main struct Main {
    static func main() async throws {
        let folder = URL(fileURLWithPath: "/tmp/CloakTools-Media-Verification", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let movie = folder.appendingPathComponent("Motion study.mov"), audio = folder.appendingPathComponent("Tone.wav")
        if !FileManager.default.fileExists(atPath: movie.path) { try await MediaFixtures.movie(movie, width: 1920, height: 1080, seconds: 12) }
        if !FileManager.default.fileExists(atPath: audio.path) { try MediaFixtures.audio(audio, seconds: 12) }
        let combined = folder.appendingPathComponent("Motion and tone.mov")
        if !FileManager.default.fileExists(atPath: combined.path) { try await MediaFixtures.combine(video: movie, audio: audio, output: combined) }
        let portrait = folder.appendingPathComponent("Portrait HEVC.mov")
        if !FileManager.default.fileExists(atPath: portrait.path) { try await MediaFixtures.movie(portrait, width: 1280, height: 720, seconds: 4, codec: .hevc, rotated: true) }
        print(folder.path)
    }
}
SWIFT
swiftc -swift-version 6 -parse-as-library apps/macos/Packages/CloakToolsCore/Tests/CloakToolsCoreTests/Support/MediaFixtures.swift "$fixture_build/Main.swift" -o "$fixture_build/make-fixtures"
"$fixture_build/make-fixtures"
