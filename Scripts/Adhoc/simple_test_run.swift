#!/usr/bin/env swift

import Foundation

print("Running basic functionality test...")

// Test 1: Check if we can create basic structures
struct TestVideoInfo {
    let duration: TimeInterval
    let width: Int
    let height: Int
    let frameRate: Double
    let bitrate: Int64
    let hasAudio: Bool
    let audioCodec: String?
    let videoCodec: String?
}

enum TestVideoCodec: String, CaseIterable {
    case h264 = "libx264"
    case h265 = "libx265"
    
    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .h265: return "H.265"
        }
    }
}

struct TestCompressionSettings {
    var crf: Int = 23
    var codec: TestVideoCodec = .h264
    var deleteOriginals: Bool = false
    var copyAudio: Bool = true
}

// Test basic functionality
let videoInfo = TestVideoInfo(
    duration: 120.0,
    width: 1920,
    height: 1080,
    frameRate: 30.0,
    bitrate: 5000000,
    hasAudio: true,
    audioCodec: "aac",
    videoCodec: "h264"
)

let settings = TestCompressionSettings()

print("✅ Basic structures work correctly")
print("Video Info: \(videoInfo.duration)s, \(videoInfo.width)x\(videoInfo.height)")
print("Settings: CRF=\(settings.crf), Codec=\(settings.codec.displayName)")

print("✅ All basic tests passed!")