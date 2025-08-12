import XCTest
import Foundation
import SwiftUI
@testable import VideoSzhimaka

// MARK: - Mock Services

class MockFFmpegService: FFmpegServiceProtocol {
    var shouldSucceed = true
    var mockError: VideoCompressionError?
    var compressionError: VideoCompressionError?
    var shouldFailOnFile: URL?
    var videoInfoResult: Result<VideoInfo, Error>?
    var compressionResult: Result<Void, Error>?
    var shouldFailCompression = false
    var failOnlyFirstFile = false
    var failOnlyFirstAttempt = false
    var mockVideoInfo = VideoInfo(
        duration: 120.0,
        width: 1920,
        height: 1080,
        frameRate: 30.0,
        bitrate: 5000000,
        hasAudio: true,
        audioCodec: "aac",
        videoCodec: "h264"
    )
    
    var compressionCallCount = 0
    var getVideoInfoCallCount = 0
    var cancelCallCount = 0
    var cancelCurrentOperationCalled = false
    private var compressionAttempts = 0
    private var fileCompressionCounts: [URL: Int] = [:]
    
    func getVideoInfo(url: URL) async throws -> VideoInfo {
        getVideoInfoCallCount += 1
        
        if let result = videoInfoResult {
            switch result {
            case .success(let info):
                return info
            case .failure(let error):
                throw error
            }
        }
        
        if let error = mockError ?? compressionError {
            throw error
        }
        
        return mockVideoInfo
    }
    
    func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        compressionCallCount += 1
        compressionAttempts += 1
        fileCompressionCounts[input, default: 0] += 1
        
        if let result = compressionResult {
            switch result {
            case .success:
                for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                    progressHandler(progress)
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try "mock compressed video".write(to: output, atomically: true, encoding: .utf8)
                return
            case .failure(let error):
                throw error
            }
        }
        
        if shouldFailCompression {
            if failOnlyFirstFile && compressionAttempts > 1 {
                // Succeed on second and subsequent files
            } else if failOnlyFirstAttempt && fileCompressionCounts[input, default: 0] > 1 {
                // Succeed on retry attempts
            } else {
                throw compressionError ?? VideoCompressionError.compressionFailed("Mock compression failure")
            }
        }
        
        if let failFile = shouldFailOnFile, failFile == input {
            throw compressionError ?? VideoCompressionError.compressionFailed("Mock file-specific failure")
        }
        
        if let error = mockError ?? compressionError {
            throw error
        }
        
        if !shouldSucceed {
            throw compressionError ?? VideoCompressionError.compressionFailed("Mock compression failure")
        }
        
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            progressHandler(progress)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        try "mock compressed video".write(to: output, atomically: true, encoding: .utf8)
    }
    
    func cancelCurrentOperation() {
        cancelCallCount += 1
        cancelCurrentOperationCalled = true
    }
    
    func getQuickVideoInfo(url: URL) async throws -> VideoInfo {
        return try await getVideoInfo(url: url)
    }
    
    func clearMetadataCache() {
        // Mock implementation - no-op
    }
    
    func reset() {
        shouldSucceed = true
        mockError = nil
        compressionError = nil
        shouldFailOnFile = nil
        videoInfoResult = nil
        compressionResult = nil
        shouldFailCompression = false
        failOnlyFirstFile = false
        failOnlyFirstAttempt = false
        compressionCallCount = 0
        getVideoInfoCallCount = 0
        cancelCallCount = 0
        cancelCurrentOperationCalled = false
        compressionAttempts = 0
        fileCompressionCounts.removeAll()
    }
}

class MockFileManagerService: FileManagerServiceProtocol {
    var generateOutputURLResult: URL = URL(fileURLWithPath: "/test/output.mp4")
    var fileSizeResult: Result<Int64, Error> = .success(1024 * 1024)
    var fileSizeResults: [URL: Result<Int64, Error>] = [:]
    var deleteFileResult: Result<Void, Error> = .success(())
    var fileExistsResult = true
    var fileExistsResults: [String: Bool] = [:]
    var openInFinderCallCount = 0
    var deletedFiles: [URL] = []
    var openedInFinderURLs: [URL] = []
    
    func generateOutputURL(for inputURL: URL) -> URL {
        return generateOutputURLResult
    }
    
    func getFileSize(url: URL) throws -> Int64 {
        if let specificResult = fileSizeResults[url] {
            switch specificResult {
            case .success(let size):
                return size
            case .failure(let error):
                throw error
            }
        }
        
        switch fileSizeResult {
        case .success(let size):
            return size
        case .failure(let error):
            throw error
        }
    }
    
    func deleteFile(at url: URL) throws {
        switch deleteFileResult {
        case .success:
            deletedFiles.append(url)
        case .failure(let error):
            throw error
        }
    }
    
    func openInFinder(url: URL) {
        openInFinderCallCount += 1
        openedInFinderURLs.append(url)
    }
    
    func fileExists(at url: URL) -> Bool {
        if let result = fileExistsResults[url.path] {
            return result
        }
        return fileExistsResult
    }
}

class MockSettingsService: SettingsServiceProtocol, ObservableObject {
    @Published var settings = CompressionSettings()
    
    var resetCallCount = 0
    var saveWindowFrameCallCount = 0
    var loadWindowFrameCallCount = 0
    var savedWindowFrame: CGRect?
    var savedLogsWindowFrame: CGRect?
    var loadSettingsCallCount = 0
    var saveSettingsCallCount = 0
    var clearAllDataCallCount = 0
    
    func loadSettings() {
        loadSettingsCallCount += 1
    }
    
    func saveSettings() {
        saveSettingsCallCount += 1
    }
    
    func resetToDefaults() {
        resetCallCount += 1
        settings = CompressionSettings()
    }
    
    func saveWindowFrame(_ frame: CGRect) {
        saveWindowFrameCallCount += 1
        savedWindowFrame = frame
    }
    
    func loadWindowFrame() -> CGRect? {
        loadWindowFrameCallCount += 1
        return savedWindowFrame
    }
    
    func saveLogsWindowFrame(_ frame: CGRect) {
        savedLogsWindowFrame = frame
    }
    
    func loadLogsWindowFrame() -> CGRect? {
        return savedLogsWindowFrame
    }
    
    func clearAllData() {
        clearAllDataCallCount += 1
        settings = CompressionSettings()
        savedWindowFrame = nil
        savedLogsWindowFrame = nil
    }
}

@MainActor
final class VideoSzhimakaTests: XCTestCase {
    
    // MARK: - VideoFile Tests
    
    func testVideoFileInitialization() {
        let url = URL(fileURLWithPath: "/path/to/video.mp4")
        let videoFile = VideoFile(
            url: url,
            name: "video.mp4",
            duration: 120.5,
            originalSize: 1024000
        )
        
        XCTAssertEqual(videoFile.url, url)
        XCTAssertEqual(videoFile.name, "video.mp4")
        XCTAssertEqual(videoFile.duration, 120.5)
        XCTAssertEqual(videoFile.originalSize, 1024000)
        XCTAssertNil(videoFile.compressedSize)
        XCTAssertEqual(videoFile.compressionProgress, 0.0)
        XCTAssertEqual(videoFile.status, .pending)
    }
    
    func testVideoFileFormattedDuration() {
        let videoFile = VideoFile(
            url: URL(fileURLWithPath: "/test.mp4"),
            name: "test.mp4",
            duration: 125.0, // 2 minutes 5 seconds
            originalSize: 1000
        )
        
        XCTAssertEqual(videoFile.formattedDuration, "2:05")
    }
    
    func testVideoFileFormattedSizes() {
        let videoFile = VideoFile(
            url: URL(fileURLWithPath: "/test.mp4"),
            name: "test.mp4",
            duration: 60.0,
            originalSize: 1024000 // ~1MB
        )
        
        XCTAssertEqual(videoFile.formattedOriginalSize, "1 MB")
        XCTAssertEqual(videoFile.formattedCompressedSize, "—")
    }
    
    func testVideoFileCompressionRatio() {
        var videoFile = VideoFile(
            url: URL(fileURLWithPath: "/test.mp4"),
            name: "test.mp4",
            duration: 60.0,
            originalSize: 1000000
        )
        
        XCTAssertNil(videoFile.compressionRatio)
        
        videoFile.compressedSize = 500000
        XCTAssertEqual(videoFile.compressionRatio, 50.0)
        XCTAssertEqual(videoFile.formattedCompressionRatio, "50.0%")
    }
    
    func testVideoFileCodable() throws {
        let originalVideoFile = VideoFile(
            url: URL(fileURLWithPath: "/test.mp4"),
            name: "test.mp4",
            duration: 60.0,
            originalSize: 1000000
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalVideoFile)
        
        let decoder = JSONDecoder()
        let decodedVideoFile = try decoder.decode(VideoFile.self, from: data)
        
        XCTAssertEqual(decodedVideoFile.url, originalVideoFile.url)
        XCTAssertEqual(decodedVideoFile.name, originalVideoFile.name)
        XCTAssertEqual(decodedVideoFile.duration, originalVideoFile.duration)
        XCTAssertEqual(decodedVideoFile.originalSize, originalVideoFile.originalSize)
        XCTAssertEqual(decodedVideoFile.status, originalVideoFile.status)
    }
    
    // MARK: - CompressionStatus Tests
    
    func testCompressionStatusEquality() {
        XCTAssertEqual(CompressionStatus.pending, CompressionStatus.pending)
        XCTAssertEqual(CompressionStatus.compressing, CompressionStatus.compressing)
        XCTAssertEqual(CompressionStatus.completed, CompressionStatus.completed)
        XCTAssertEqual(CompressionStatus.failed(.unknownError("error")), CompressionStatus.failed(.unknownError("error")))
        
        XCTAssertNotEqual(CompressionStatus.pending, CompressionStatus.compressing)
        XCTAssertNotEqual(CompressionStatus.failed(.unknownError("error1")), CompressionStatus.failed(.unknownError("error2")))
    }
    
    func testCompressionStatusDisplayText() {
        XCTAssertEqual(CompressionStatus.pending.displayText, "Ожидает")
        XCTAssertEqual(CompressionStatus.compressing.displayText, "Сжимается")
        XCTAssertEqual(CompressionStatus.completed.displayText, "Завершено")
        XCTAssertEqual(CompressionStatus.failed(.unknownError("Test error")).displayText, "Ошибка: Неизвестная ошибка: Test error")
    }
    
    func testCompressionStatusProperties() {
        XCTAssertFalse(CompressionStatus.pending.isActive)
        XCTAssertTrue(CompressionStatus.compressing.isActive)
        XCTAssertFalse(CompressionStatus.completed.isActive)
        XCTAssertFalse(CompressionStatus.failed(.unknownError("error")).isActive)
        
        XCTAssertFalse(CompressionStatus.pending.isFinished)
        XCTAssertFalse(CompressionStatus.compressing.isFinished)
        XCTAssertTrue(CompressionStatus.completed.isFinished)
        XCTAssertTrue(CompressionStatus.failed(.unknownError("error")).isFinished)
        
        XCTAssertFalse(CompressionStatus.pending.isSuccessful)
        XCTAssertFalse(CompressionStatus.compressing.isSuccessful)
        XCTAssertTrue(CompressionStatus.completed.isSuccessful)
        XCTAssertFalse(CompressionStatus.failed(.unknownError("error")).isSuccessful)
    }
    
    func testCompressionStatusCodable() throws {
        let statuses: [CompressionStatus] = [
            .pending,
            .compressing,
            .completed,
            .failed(.unknownError("Test error message"))
        ]
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for status in statuses {
            let data = try encoder.encode(status)
            let decodedStatus = try decoder.decode(CompressionStatus.self, from: data)
            XCTAssertEqual(status, decodedStatus)
        }
    }
    
    // MARK: - VideoCodec Tests
    
    func testVideoCodecProperties() {
        XCTAssertEqual(VideoCodec.h264.displayName, "H.264 (рекомендуется)")
        XCTAssertEqual(VideoCodec.h265.displayName, "H.265 (эффективнее)")
        
        XCTAssertEqual(VideoCodec.h264.shortName, "H.264")
        XCTAssertEqual(VideoCodec.h265.shortName, "H.265")
        
        XCTAssertEqual(VideoCodec.h264.ffmpegValue, "libx264")
        XCTAssertEqual(VideoCodec.h265.ffmpegValue, "libx265")
        
        XCTAssertTrue(VideoCodec.h264.supportsHardwareAcceleration)
        XCTAssertTrue(VideoCodec.h265.supportsHardwareAcceleration)
        
        XCTAssertEqual(VideoCodec.h264.hardwareEncoder, "h264_videotoolbox")
        XCTAssertEqual(VideoCodec.h265.hardwareEncoder, "hevc_videotoolbox")
        
        XCTAssertEqual(VideoCodec.h264.defaultCRF, 23)
        XCTAssertEqual(VideoCodec.h265.defaultCRF, 25)
    }
    
    func testVideoCodecCRFRanges() {
        XCTAssertEqual(VideoCodec.h264.recommendedCRFRange, 18...28)
        XCTAssertEqual(VideoCodec.h265.recommendedCRFRange, 20...30)
        
        XCTAssertTrue(VideoCodec.h264.recommendedCRFRange.contains(23))
        XCTAssertTrue(VideoCodec.h265.recommendedCRFRange.contains(25))
    }
    
    func testVideoCodecCaseIterable() {
        let allCases = VideoCodec.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.h264))
        XCTAssertTrue(allCases.contains(.h265))
    }
    
    func testVideoCodecCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for codec in VideoCodec.allCases {
            let data = try encoder.encode(codec)
            let decodedCodec = try decoder.decode(VideoCodec.self, from: data)
            XCTAssertEqual(codec, decodedCodec)
        }
    }
    
    // MARK: - CompressionSettings Tests
    
    func testCompressionSettingsDefaults() {
        let settings = CompressionSettings()
        
        XCTAssertEqual(settings.crf, 23)
        XCTAssertEqual(settings.codec, .h264)
        XCTAssertFalse(settings.deleteOriginals)
        XCTAssertTrue(settings.copyAudio)
        XCTAssertFalse(settings.autoCloseApp)
        XCTAssertTrue(settings.showInDock)
        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertTrue(settings.useHardwareAcceleration)
    }
    
    func testCompressionSettingsCustomInitialization() {
        let settings = CompressionSettings(
            crf: 25,
            codec: .h265,
            deleteOriginals: true,
            copyAudio: false,
            autoCloseApp: true,
            showInDock: false,
            showInMenuBar: true,
            useHardwareAcceleration: false
        )
        
        XCTAssertEqual(settings.crf, 25)
        XCTAssertEqual(settings.codec, .h265)
        XCTAssertTrue(settings.deleteOriginals)
        XCTAssertFalse(settings.copyAudio)
        XCTAssertTrue(settings.autoCloseApp)
        XCTAssertFalse(settings.showInDock)
        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertFalse(settings.useHardwareAcceleration)
    }
    
    func testCompressionSettingsCRFClamping() {
        // Test H.264 CRF clamping (18-28)
        var settings = CompressionSettings(crf: 10, codec: .h264)
        XCTAssertEqual(settings.crf, 18) // Clamped to minimum
        
        settings = CompressionSettings(crf: 35, codec: .h264)
        XCTAssertEqual(settings.crf, 28) // Clamped to maximum
        
        // Test H.265 CRF clamping (20-30)
        settings = CompressionSettings(crf: 15, codec: .h265)
        XCTAssertEqual(settings.crf, 20) // Clamped to minimum
        
        settings = CompressionSettings(crf: 40, codec: .h265)
        XCTAssertEqual(settings.crf, 30) // Clamped to maximum
    }
    
    func testCompressionSettingsSetCRF() {
        var settings = CompressionSettings()
        
        settings.setCRF(20)
        XCTAssertEqual(settings.crf, 20)
        
        settings.setCRF(10) // Below minimum for H.264
        XCTAssertEqual(settings.crf, 18)
        
        settings.setCRF(35) // Above maximum for H.264
        XCTAssertEqual(settings.crf, 28)
    }
    
    func testCompressionSettingsSetCodec() {
        var settings = CompressionSettings(crf: 25)
        
        settings.setCodec(.h265)
        XCTAssertEqual(settings.codec, .h265)
        XCTAssertEqual(settings.crf, 25) // Should remain valid for H.265
        
        settings.setCodec(.h264)
        settings.setCRF(19) // Valid for H.265 but need to test codec change
        settings.setCodec(.h265)
        XCTAssertEqual(settings.crf, 20) // Should be clamped to H.265 minimum
    }
    
    func testCompressionSettingsValidation() {
        var settings = CompressionSettings()
        XCTAssertTrue(settings.isValid)
        XCTAssertTrue(settings.validationErrors.isEmpty)
        
        // Test invalid display settings
        settings.showInDock = false
        settings.showInMenuBar = false
        XCTAssertFalse(settings.isValid)
        XCTAssertFalse(settings.validationErrors.isEmpty)
        XCTAssertTrue(settings.validationErrors.contains { $0.contains("Dock") && $0.contains("меню-баре") })
    }
    
    func testCompressionSettingsResetToDefaults() {
        var settings = CompressionSettings(
            crf: 25,
            codec: .h265,
            deleteOriginals: true,
            copyAudio: false
        )
        
        settings.resetToDefaults()
        
        XCTAssertEqual(settings.crf, 23)
        XCTAssertEqual(settings.codec, .h264)
        XCTAssertFalse(settings.deleteOriginals)
        XCTAssertTrue(settings.copyAudio)
    }
    
    func testCompressionSettingsAudioCodecParameters() {
        var settings = CompressionSettings()
        
        settings.copyAudio = true
        XCTAssertEqual(settings.audioCodecParameters, ["-c:a", "copy"])
        
        settings.copyAudio = false
        XCTAssertEqual(settings.audioCodecParameters, ["-c:a", "aac", "-b:a", "128k"])
    }
    
    func testCompressionSettingsVideoCodecParameters() {
        var settings = CompressionSettings()
        
        // Test software encoding
        settings.useHardwareAcceleration = false
        settings.codec = .h264
        let softwareParams = settings.videoCodecParameters
        XCTAssertTrue(softwareParams.contains("libx264"))
        XCTAssertTrue(softwareParams.contains("23"))
        
        // Test hardware encoding
        settings.useHardwareAcceleration = true
        let hardwareParams = settings.videoCodecParameters
        XCTAssertTrue(hardwareParams.contains("h264_videotoolbox"))
        XCTAssertTrue(hardwareParams.contains("23"))
    }
    
    func testCompressionSettingsFFmpegParameters() {
        let settings = CompressionSettings()
        let params = settings.ffmpegParameters
        
        // Should contain video codec parameters
        XCTAssertTrue(params.contains("-c:v"))
        XCTAssertTrue(params.contains("-crf"))
        
        // Should contain audio codec parameters
        XCTAssertTrue(params.contains("-c:a"))
        
        // Should contain preset
        XCTAssertTrue(params.contains("-preset"))
        XCTAssertTrue(params.contains("medium"))
    }
    
    func testCompressionSettingsCodable() throws {
        let originalSettings = CompressionSettings(
            crf: 25,
            codec: .h265,
            deleteOriginals: true,
            copyAudio: false,
            autoCloseApp: true,
            showInDock: false,
            showInMenuBar: true,
            useHardwareAcceleration: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalSettings)
        
        let decoder = JSONDecoder()
        let decodedSettings = try decoder.decode(CompressionSettings.self, from: data)
        
        XCTAssertEqual(decodedSettings.crf, originalSettings.crf)
        XCTAssertEqual(decodedSettings.codec, originalSettings.codec)
        XCTAssertEqual(decodedSettings.deleteOriginals, originalSettings.deleteOriginals)
        XCTAssertEqual(decodedSettings.copyAudio, originalSettings.copyAudio)
        XCTAssertEqual(decodedSettings.autoCloseApp, originalSettings.autoCloseApp)
        XCTAssertEqual(decodedSettings.showInDock, originalSettings.showInDock)
        XCTAssertEqual(decodedSettings.showInMenuBar, originalSettings.showInMenuBar)
        XCTAssertEqual(decodedSettings.useHardwareAcceleration, originalSettings.useHardwareAcceleration)
    }
    
    func testCompressionSettingsEquality() {
        let settings1 = CompressionSettings()
        let settings2 = CompressionSettings()
        
        XCTAssertEqual(settings1, settings2)
        
        var settings3 = CompressionSettings()
        settings3.crf = 25
        
        XCTAssertNotEqual(settings1, settings3)
    }
}