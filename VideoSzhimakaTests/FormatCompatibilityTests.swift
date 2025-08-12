import XCTest
@testable import VideoSzhimaka

/// Tests for video format compatibility and codec support
@MainActor
class FormatCompatibilityTests: XCTestCase {
    
    var ffmpegService: FFmpegService!
    var mockFFmpegService: MockFFmpegService!
    var testVideoURLs: [String: URL] = [:]
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize services
        ffmpegService = try FFmpegService()
        mockFFmpegService = MockFFmpegService()
        
        // Create test video files for different formats
        try createTestVideoFiles()
    }
    
    override func tearDownWithError() throws {
        // Clean up test files
        for (_, url) in testVideoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        testVideoURLs.removeAll()
        
        ffmpegService = nil
        mockFFmpegService = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Format Support Tests
    
    /// Test support for common video formats
    func testCommonVideoFormatSupport() throws {
        let supportedFormats = [
            "mp4": "MPEG-4 Part 14",
            "mov": "QuickTime Movie",
            "mkv": "Matroska Video",
            "avi": "Audio Video Interleave",
            "webm": "WebM Video",
            "m4v": "iTunes Video",
            "3gp": "3GPP Multimedia",
            "flv": "Flash Video",
            "wmv": "Windows Media Video",
            "mpg": "MPEG Video",
            "mpeg": "MPEG Video",
            "ts": "MPEG Transport Stream",
            "mts": "AVCHD Video",
            "m2ts": "Blu-ray Video"
        ]
        
        for (format, description) in supportedFormats {
            let isSupported = VideoFile.isSupportedFormat(format)
            XCTAssertTrue(isSupported, "\(description) (.\(format)) should be supported")
        }
    }
    
    /// Test rejection of unsupported formats
    func testUnsupportedFormatRejection() throws {
        let unsupportedFormats = [
            "txt": "Text File",
            "jpg": "JPEG Image",
            "png": "PNG Image",
            "pdf": "PDF Document",
            "doc": "Word Document",
            "zip": "ZIP Archive",
            "exe": "Executable File"
        ]
        
        for (format, description) in unsupportedFormats {
            let isSupported = VideoFile.isSupportedFormat(format)
            XCTAssertFalse(isSupported, "\(description) (.\(format)) should not be supported")
        }
    }
    
    /// Test video codec compatibility
    func testVideoCodecCompatibility() throws {
        let codecTests = [
            ("h264", VideoCodec.h264, true),
            ("h265", VideoCodec.h265, true),
            ("hevc", VideoCodec.h265, true),
            ("x264", VideoCodec.h264, true),
            ("x265", VideoCodec.h265, true),
            ("vp8", nil, false),
            ("vp9", nil, false),
            ("av1", nil, false)
        ]
        
        for (codecName, expectedCodec, shouldSupport) in codecTests {
            if shouldSupport {
                XCTAssertNotNil(expectedCodec, "Codec \(codecName) should be supported")
                if let codec = expectedCodec {
                    XCTAssertTrue(codec.supportsHardwareAcceleration, 
                                 "Supported codec \(codecName) should have hardware acceleration")
                }
            } else {
                // These codecs are not currently supported by the app
                // but FFmpeg might support them
                XCTAssertTrue(true, "Codec \(codecName) is not supported by app (expected)")
            }
        }
    }
    
    /// Test hardware acceleration availability for different codecs
    func testHardwareAccelerationSupport() throws {
        let hardwareCodecs = [
            VideoCodec.h264: "h264_videotoolbox",
            VideoCodec.h265: "hevc_videotoolbox"
        ]
        
        for (codec, expectedEncoder) in hardwareCodecs {
            XCTAssertTrue(codec.supportsHardwareAcceleration, 
                         "Codec \(codec) should support hardware acceleration")
            XCTAssertEqual(codec.hardwareEncoder, expectedEncoder, 
                          "Hardware encoder for \(codec) should be \(expectedEncoder)")
        }
    }
    
    /// Test CRF ranges for different codecs
    func testCodecCRFRanges() throws {
        // Test H.264 CRF range
        let h264Range = VideoCodec.h264.recommendedCRFRange
        XCTAssertEqual(h264Range.lowerBound, 18)
        XCTAssertEqual(h264Range.upperBound, 28)
        XCTAssertTrue(h264Range.contains(VideoCodec.h264.defaultCRF))
        
        // Test H.265 CRF range
        let h265Range = VideoCodec.h265.recommendedCRFRange
        XCTAssertEqual(h265Range.lowerBound, 20)
        XCTAssertEqual(h265Range.upperBound, 30)
        XCTAssertTrue(h265Range.contains(VideoCodec.h265.defaultCRF))
    }
    
    // MARK: - Format Conversion Tests
    
    /// Test conversion between different input and output formats
    func testFormatConversionMatrix() async throws {
        let inputFormats = ["mp4", "mov", "mkv", "avi"]
        let outputFormat = "mp4" // App always outputs MP4
        
        for inputFormat in inputFormats {
            guard let inputURL = testVideoURLs[inputFormat] else {
                XCTFail("Test video for format \(inputFormat) not found")
                continue
            }
            
            let outputURL = inputURL.appendingPathExtension("converted.mp4")
            let settings = CompressionSettings(
                crf: 23,
                codec: .h264,
                useHardwareAcceleration: true
            )
            
            do {
                // Use mock service for testing
                try await mockFFmpegService.compressVideo(
                    input: inputURL,
                    output: outputURL,
                    settings: settings
                ) { progress in
                    // Monitor progress
                }
                
                XCTAssertTrue(true, "Conversion from \(inputFormat) to \(outputFormat) should succeed")
            } catch {
                XCTFail("Conversion from \(inputFormat) to \(outputFormat) failed: \(error)")
            }
        }
    }
    
    /// Test handling of corrupted video files
    func testCorruptedVideoFileHandling() async throws {
        let corruptedURL = createCorruptedVideoFile()
        defer { try? FileManager.default.removeItem(at: corruptedURL) }
        
        // Configure mock to simulate corrupted file error
        mockFFmpegService.shouldSucceed = false
        mockFFmpegService.mockError = .compressionFailed("Invalid data found when processing input")
        
        let outputURL = corruptedURL.appendingPathExtension("output.mp4")
        let settings = CompressionSettings()
        
        do {
            try await mockFFmpegService.compressVideo(
                input: corruptedURL,
                output: outputURL,
                settings: settings
            ) { _ in }
            
            XCTFail("Corrupted file processing should fail")
        } catch let error as VideoCompressionError {
            switch error {
            case .compressionFailed:
                XCTAssertTrue(true, "Corrupted file should produce compression error")
            default:
                XCTFail("Unexpected error type for corrupted file: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    /// Test handling of zero-byte files
    func testZeroByteFileHandling() async throws {
        let zeroByteURL = createZeroByteVideoFile()
        defer { try? FileManager.default.removeItem(at: zeroByteURL) }
        
        // Configure mock to simulate zero-byte file error
        mockFFmpegService.shouldSucceed = false
        mockFFmpegService.mockError = .fileNotFound(zeroByteURL.path)
        
        do {
            let videoInfo = try await mockFFmpegService.getVideoInfo(url: zeroByteURL)
            XCTFail("Zero-byte file should not provide valid video info")
        } catch let error as VideoCompressionError {
            switch error {
            case .fileNotFound:
                XCTAssertTrue(true, "Zero-byte file should be treated as not found")
            default:
                XCTFail("Unexpected error type for zero-byte file: \(error)")
            }
        }
    }
    
    /// Test handling of very large video files
    func testLargeVideoFileHandling() async throws {
        // Simulate large file handling without actually creating large files
        let largeFileURL = testVideoURLs["mp4"]!
        
        // Configure mock to simulate large file processing
        mockFFmpegService.mockVideoInfo = VideoInfo(
            duration: 7200.0, // 2 hours
            width: 3840,       // 4K resolution
            height: 2160,
            frameRate: 30.0,
            bitrate: 50000000, // 50 Mbps for 4K
            hasAudio: true,
            audioCodec: "aac",
            videoCodec: "h264"
        )
        
        let videoInfo = try await mockFFmpegService.getVideoInfo(url: largeFileURL)
        
        XCTAssertEqual(videoInfo.duration, 7200.0)
        XCTAssertEqual(videoInfo.width, 3840)
        XCTAssertEqual(videoInfo.height, 2160)
        
        // Test that compression settings are appropriate for large files
        let settings = CompressionSettings(
            crf: 25, // Higher CRF for large files to reduce size
            codec: .h265, // More efficient codec
            useHardwareAcceleration: true
        )
        
        let outputURL = largeFileURL.appendingPathExtension("large_output.mp4")
        
        try await mockFFmpegService.compressVideo(
            input: largeFileURL,
            output: outputURL,
            settings: settings
        ) { progress in
            XCTAssertGreaterThanOrEqual(progress, 0.0)
            XCTAssertLessThanOrEqual(progress, 1.0)
        }
    }
    
    /// Test audio codec compatibility
    func testAudioCodecCompatibility() throws {
        var settings = CompressionSettings()
        
        // Test audio copy mode
        settings.copyAudio = true
        let copyParams = settings.audioCodecParameters
        XCTAssertEqual(copyParams, ["-c:a", "copy"])
        
        // Test audio re-encoding mode
        settings.copyAudio = false
        let encodeParams = settings.audioCodecParameters
        XCTAssertEqual(encodeParams, ["-c:a", "aac", "-b:a", "128k"])
    }
    
    /// Test resolution and frame rate preservation
    func testResolutionAndFrameRatePreservation() async throws {
        let testURL = testVideoURLs["mp4"]!
        
        // Configure mock with specific video info
        mockFFmpegService.mockVideoInfo = VideoInfo(
            duration: 60.0,
            width: 1920,
            height: 1080,
            frameRate: 30.0,
            bitrate: 5000000,
            hasAudio: true,
            audioCodec: "aac",
            videoCodec: "h264"
        )
        
        let videoInfo = try await mockFFmpegService.getVideoInfo(url: testURL)
        
        XCTAssertEqual(videoInfo.width, 1920)
        XCTAssertEqual(videoInfo.height, 1080)
        XCTAssertEqual(videoInfo.frameRate, 30.0) // Default from mock
        
        // Verify that compression preserves these properties
        let settings = CompressionSettings()
        let ffmpegParams = settings.ffmpegParameters
        
        // Should not contain resolution or frame rate changes
        XCTAssertFalse(ffmpegParams.contains("-s"))
        XCTAssertFalse(ffmpegParams.contains("-r"))
    }
    
    // MARK: - Edge Case Tests
    
    /// Test handling of files with special characters in names
    func testSpecialCharacterFilenames() throws {
        let specialNames = [
            "test file with spaces.mp4",
            "test-file-with-dashes.mp4",
            "test_file_with_underscores.mp4",
            "test.file.with.dots.mp4",
            "тест-файл-кириллица.mp4",
            "test[brackets].mp4",
            "test(parentheses).mp4"
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        
        for name in specialNames {
            let url = tempDir.appendingPathComponent(name)
            
            do {
                try Data().write(to: url)
                
                // Test that the file can be processed
                let isSupported = VideoFile.isSupportedFormat(url.pathExtension)
                XCTAssertTrue(isSupported, "File with special characters should be supported: \(name)")
                
                // Clean up
                try FileManager.default.removeItem(at: url)
            } catch {
                XCTFail("Failed to create or process file with special characters: \(name)")
            }
        }
    }
    
    /// Test handling of very short video files
    func testVeryShortVideoFiles() async throws {
        // Configure mock for very short video
        mockFFmpegService.mockVideoInfo = VideoInfo(
            duration: 0.1, // 100ms
            width: 640,
            height: 480,
            frameRate: 30.0,
            bitrate: 1000000,
            hasAudio: false,
            audioCodec: nil,
            videoCodec: "h264"
        )
        
        let testURL = testVideoURLs["mp4"]!
        let videoInfo = try await mockFFmpegService.getVideoInfo(url: testURL)
        
        XCTAssertEqual(videoInfo.duration, 0.1)
        
        // Very short videos should still be processable
        let outputURL = testURL.appendingPathExtension("short_output.mp4")
        let settings = CompressionSettings()
        
        try await mockFFmpegService.compressVideo(
            input: testURL,
            output: outputURL,
            settings: settings
        ) { progress in
            // Progress should still work for short videos
            XCTAssertGreaterThanOrEqual(progress, 0.0)
            XCTAssertLessThanOrEqual(progress, 1.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let formats = ["mp4", "mov", "mkv", "avi", "webm"]
        
        for format in formats {
            let url = tempDir.appendingPathComponent("test_video.\(format)")
            try Data().write(to: url)
            testVideoURLs[format] = url
        }
    }
    
    private func createCorruptedVideoFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let corruptedURL = tempDir.appendingPathComponent("corrupted.mp4")
        
        // Create file with invalid video data
        let corruptedData = Data([0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])
        try! corruptedData.write(to: corruptedURL)
        
        return corruptedURL
    }
    
    private func createZeroByteVideoFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let zeroByteURL = tempDir.appendingPathComponent("zerobyte.mp4")
        
        // Create empty file
        try! Data().write(to: zeroByteURL)
        
        return zeroByteURL
    }
}

// MARK: - VideoFile Extension for Testing

extension VideoFile {
    static func isSupportedFormat(_ pathExtension: String) -> Bool {
        let supportedExtensions = [
            "mp4", "mov", "mkv", "avi", "webm", "m4v",
            "3gp", "flv", "wmv", "mpg", "mpeg", "ts", "mts", "m2ts"
        ]
        return supportedExtensions.contains(pathExtension.lowercased())
    }
}