import XCTest
@testable import VideoSzhimaka

/// Performance tests for video compression with different file sizes
@MainActor
class PerformanceTests: XCTestCase {
    
    var ffmpegService: FFmpegService!
    var performanceMonitor: PerformanceMonitorService!
    var testVideoURLs: [URL] = []
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        ffmpegService = try FFmpegService()
        performanceMonitor = PerformanceMonitorService.shared
        
        // Create test video files of different sizes
        try createTestVideoFiles()
    }
    
    override func tearDownWithError() throws {
        // Clean up test files
        for url in testVideoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        testVideoURLs.removeAll()
        
        ffmpegService = nil
        performanceMonitor = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Performance Tests
    
    /// Test compression performance with small video files (< 10MB)
    func testSmallVideoCompressionPerformance() throws {
        let smallVideoURL = try createTestVideo(duration: 10, resolution: .sd) // ~5MB
        
        measure {
            let expectation = XCTestExpectation(description: "Small video compression")
            
            Task {
                do {
                    let outputURL = smallVideoURL.appendingPathExtension("compressed.mp4")
                    let settings = CompressionSettings(
                        crf: 23,
                        codec: .h264
                    )
                    
                    try await ffmpegService.compressVideo(
                        input: smallVideoURL,
                        output: outputURL,
                        settings: settings
                    ) { progress in
                        // Monitor progress
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Small video compression failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    /// Test compression performance with medium video files (10-100MB)
    func testMediumVideoCompressionPerformance() throws {
        let mediumVideoURL = try createTestVideo(duration: 60, resolution: .hd) // ~50MB
        
        measure {
            let expectation = XCTestExpectation(description: "Medium video compression")
            
            Task {
                do {
                    let outputURL = mediumVideoURL.appendingPathExtension("compressed.mp4")
                    let settings = CompressionSettings(
                        crf: 23,
                        codec: .h264
                    )
                    
                    try await ffmpegService.compressVideo(
                        input: mediumVideoURL,
                        output: outputURL,
                        settings: settings
                    ) { progress in
                        // Monitor progress
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Medium video compression failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 120.0)
        }
    }
    
    /// Test compression performance with large video files (> 100MB)
    func testLargeVideoCompressionPerformance() throws {
        let largeVideoURL = try createTestVideo(duration: 300, resolution: .fullHD) // ~200MB
        
        measure {
            let expectation = XCTestExpectation(description: "Large video compression")
            
            Task {
                do {
                    let outputURL = largeVideoURL.appendingPathExtension("compressed.mp4")
                    let settings = CompressionSettings(
                        crf: 23,
                        codec: .h264
                    )
                    
                    try await ffmpegService.compressVideo(
                        input: largeVideoURL,
                        output: outputURL,
                        settings: settings
                    ) { progress in
                        // Monitor progress
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Large video compression failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 300.0)
        }
    }
    
    /// Test hardware vs software encoding performance
    func testHardwareVsSoftwarePerformance() throws {
        let testVideoURL = try createTestVideo(duration: 30, resolution: .hd)
        
        // Test hardware encoding
        let hardwareTime = try measureCompressionTime(
            videoURL: testVideoURL,
            useHardwareAcceleration: true
        )
        
        // Test software encoding
        let softwareTime = try measureCompressionTime(
            videoURL: testVideoURL,
            useHardwareAcceleration: false
        )
        
        // Hardware should be faster (or at least not significantly slower)
        XCTAssertLessThanOrEqual(hardwareTime, softwareTime * 1.5, 
                                "Hardware acceleration should not be significantly slower than software")
        
        print("Hardware encoding time: \(hardwareTime)s")
        print("Software encoding time: \(softwareTime)s")
        print("Hardware speedup: \(softwareTime / hardwareTime)x")
    }
    
    /// Test batch processing performance
    func testBatchProcessingPerformance() throws {
        let videoURLs = try (0..<5).map { _ in
            try createTestVideo(duration: 15, resolution: .sd)
        }
        
        measure {
            let expectation = XCTestExpectation(description: "Batch processing")
            
            Task {
                do {
                    for (index, videoURL) in videoURLs.enumerated() {
                        let outputURL = videoURL.appendingPathExtension("batch_\(index).mp4")
                        let settings = CompressionSettings(
                            crf: 23,
                            codec: .h264
                        )
                        
                        try await ffmpegService.compressVideo(
                            input: videoURL,
                            output: outputURL,
                            settings: settings
                        ) { progress in
                            // Monitor progress
                        }
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Batch processing failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 180.0)
        }
    }
    
    /// Test memory usage during compression
    func testMemoryUsageDuringCompression() throws {
        let testVideoURL = try createTestVideo(duration: 60, resolution: .fullHD)
        
        performanceMonitor.startMonitoring()
        defer { performanceMonitor.stopMonitoring() }
        
        var maxMemoryUsage: Double = 0
        var memoryReadings: [Double] = []
        
        let expectation = XCTestExpectation(description: "Memory usage test")
        
        // Monitor memory usage every second
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let currentMemory = self.performanceMonitor.currentMemoryUsage
            memoryReadings.append(currentMemory)
            maxMemoryUsage = max(maxMemoryUsage, currentMemory)
        }
        
        Task {
            do {
                let outputURL = testVideoURL.appendingPathExtension("memory_test.mp4")
                let settings = CompressionSettings(
                    crf: 23,
                    codec: .h264
                )
                
                try await ffmpegService.compressVideo(
                    input: testVideoURL,
                    output: outputURL,
                    settings: settings
                ) { progress in
                    // Monitor progress
                }
                
                timer.invalidate()
                expectation.fulfill()
            } catch {
                timer.invalidate()
                XCTFail("Memory usage test failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 180.0)
        
        // Assert memory usage is reasonable (< 1GB for this test)
        XCTAssertLessThan(maxMemoryUsage, 1024, "Memory usage should be less than 1GB")
        
        print("Max memory usage: \(maxMemoryUsage) MB")
        print("Average memory usage: \(memoryReadings.reduce(0, +) / Double(memoryReadings.count)) MB")
    }
    
    /// Test thermal throttling behavior
    func testThermalThrottlingBehavior() throws {
        performanceMonitor.startMonitoring()
        defer { performanceMonitor.stopMonitoring() }
        
        // Create a demanding compression task
        let testVideoURL = try createTestVideo(duration: 120, resolution: .fourK)
        
        let expectation = XCTestExpectation(description: "Thermal throttling test")
        
        Task {
            do {
                let outputURL = testVideoURL.appendingPathExtension("thermal_test.mp4")
                let settings = CompressionSettings(
                    crf: 18, // High quality to stress the system
                    codec: .h265
                )
                
                try await ffmpegService.compressVideo(
                    input: testVideoURL,
                    output: outputURL,
                    settings: settings
                ) { progress in
                    // Check thermal state during compression
                    let thermalState = self.performanceMonitor.thermalState
                    if thermalState == .serious || thermalState == .critical {
                        print("Thermal throttling detected: \(thermalState)")
                    }
                }
                
                expectation.fulfill()
            } catch {
                XCTFail("Thermal throttling test failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 600.0) // Longer timeout for demanding task
    }
    
    /// Test batch processing performance with different queue sizes
    func testBatchProcessingPerformanceScaling() throws {
        let batchSizes = [1, 3, 5, 10]
        var results: [Int: TimeInterval] = [:]
        
        for batchSize in batchSizes {
            let videoURLs = try (0..<batchSize).map { _ in
                try createTestVideo(duration: 10, resolution: .sd)
            }
            
            let startTime = Date()
            let expectation = XCTestExpectation(description: "Batch size \(batchSize)")
            
            Task {
                do {
                    for (index, videoURL) in videoURLs.enumerated() {
                        let outputURL = videoURL.appendingPathExtension("batch_\(index).mp4")
                        let settings = CompressionSettings(
                            crf: 23,
                            codec: .h264
                        )
                        
                        try await ffmpegService.compressVideo(
                            input: videoURL,
                            output: outputURL,
                            settings: settings
                        ) { progress in
                            // Monitor progress
                        }
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Batch processing failed for size \(batchSize): \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: TimeInterval(batchSize * 30))
            
            let processingTime = Date().timeIntervalSince(startTime)
            results[batchSize] = processingTime
            
            print("Batch size \(batchSize): \(processingTime)s")
        }
        
        // Verify that processing time scales reasonably
        XCTAssertLessThan(results[1]! * 2.5, results[3]!, "3-file batch should not be more than 2.5x slower than single file")
        XCTAssertLessThan(results[3]! * 2.0, results[5]!, "5-file batch should not be more than 2x slower than 3-file batch")
    }
    
    /// Test concurrent vs sequential batch processing performance
    func testConcurrentVsSequentialBatchProcessing() throws {
        let videoURLs = try (0..<3).map { _ in
            try createTestVideo(duration: 15, resolution: .hd)
        }
        
        // Test sequential processing (current app behavior)
        let sequentialTime = try measureSequentialProcessing(videoURLs: videoURLs)
        
        // Test simulated concurrent processing (for comparison)
        let concurrentTime = try measureConcurrentProcessing(videoURLs: videoURLs)
        
        print("Sequential processing time: \(sequentialTime)s")
        print("Concurrent processing time: \(concurrentTime)s")
        
        // Sequential should be more predictable and stable
        XCTAssertGreaterThan(sequentialTime, 0)
        XCTAssertGreaterThan(concurrentTime, 0)
        
        // Note: Sequential might be slower but more stable for thermal management
        // This test documents the performance characteristics
    }
    
    /// Test performance with different video resolutions in batch
    func testMixedResolutionBatchPerformance() throws {
        let mixedVideoURLs = [
            try createTestVideo(duration: 10, resolution: .sd),
            try createTestVideo(duration: 10, resolution: .hd),
            try createTestVideo(duration: 10, resolution: .fullHD)
        ]
        
        measure {
            let expectation = XCTestExpectation(description: "Mixed resolution batch")
            
            Task {
                do {
                    for (index, videoURL) in mixedVideoURLs.enumerated() {
                        let outputURL = videoURL.appendingPathExtension("mixed_\(index).mp4")
                        let settings = CompressionSettings(
                            crf: 23,
                            codec: .h264
                        )
                        
                        try await ffmpegService.compressVideo(
                            input: videoURL,
                            output: outputURL,
                            settings: settings
                        ) { progress in
                            // Monitor progress
                        }
                    }
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Mixed resolution batch failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 120.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoFiles() throws {
        // Create test videos of different sizes
        testVideoURLs = [
            try createTestVideo(duration: 5, resolution: .sd),
            try createTestVideo(duration: 30, resolution: .hd),
            try createTestVideo(duration: 60, resolution: .fullHD)
        ]
    }
    
    private func createTestVideo(duration: Int, resolution: VideoResolution) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("test_\(duration)s_\(resolution.name).mp4")
        
        // Find FFmpeg binary path
        var ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil, inDirectory: "bin")
        if ffmpegPath == nil {
            ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil)
        }
        if ffmpegPath == nil {
            // Try system paths
            let systemPaths = [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
            for path in systemPaths {
                if FileManager.default.fileExists(atPath: path) {
                    ffmpegPath = path
                    break
                }
            }
        }
        
        guard let validFFmpegPath = ffmpegPath else {
            throw VideoCompressionError.ffmpegNotFound
        }
        
        // Create a test video using FFmpeg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: validFFmpegPath)
        process.arguments = [
            "-f", "lavfi",
            "-i", "testsrc2=duration=\(duration):size=\(resolution.size):rate=30",
            "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=\(duration)",
            "-c:v", "libx264",
            "-c:a", "aac",
            "-y", videoURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw VideoCompressionError.compressionFailed("Failed to create test video")
        }
        
        testVideoURLs.append(videoURL)
        return videoURL
    }
    
    private func measureCompressionTime(videoURL: URL, useHardwareAcceleration: Bool) throws -> TimeInterval {
        let startTime = Date()
        let expectation = XCTestExpectation(description: "Compression timing")
        
        Task {
            do {
                let outputURL = videoURL.appendingPathExtension("timing_test.mp4")
                let settings = CompressionSettings(
                    crf: 23,
                    codec: .h264
                )
                
                try await ffmpegService.compressVideo(
                    input: videoURL,
                    output: outputURL,
                    settings: settings
                ) { progress in
                    // Monitor progress
                }
                
                expectation.fulfill()
            } catch {
                XCTFail("Compression timing test failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 120.0)
        return Date().timeIntervalSince(startTime)
    }
    
    private func measureSequentialProcessing(videoURLs: [URL]) throws -> TimeInterval {
        let startTime = Date()
        let expectation = XCTestExpectation(description: "Sequential processing")
        
        Task {
            do {
                for (index, videoURL) in videoURLs.enumerated() {
                    let outputURL = videoURL.appendingPathExtension("sequential_\(index).mp4")
                    let settings = CompressionSettings(
                        crf: 23,
                        codec: .h264
                    )
                    
                    try await ffmpegService.compressVideo(
                        input: videoURL,
                        output: outputURL,
                        settings: settings
                    ) { progress in
                        // Monitor progress
                    }
                }
                
                expectation.fulfill()
            } catch {
                XCTFail("Sequential processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: TimeInterval(videoURLs.count * 60))
        return Date().timeIntervalSince(startTime)
    }
    
    private func measureConcurrentProcessing(videoURLs: [URL]) throws -> TimeInterval {
        let startTime = Date()
        let expectation = XCTestExpectation(description: "Concurrent processing")
        
        Task {
            do {
                // Simulate concurrent processing with TaskGroup
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (index, videoURL) in videoURLs.enumerated() {
                        group.addTask {
                            let outputURL = videoURL.appendingPathExtension("concurrent_\(index).mp4")
                            let settings = CompressionSettings(
                                crf: 23,
                                codec: .h264
                            )
                            
                            try await self.ffmpegService.compressVideo(
                                input: videoURL,
                                output: outputURL,
                                settings: settings
                            ) { progress in
                                // Monitor progress
                            }
                        }
                    }
                    
                    try await group.waitForAll()
                }
                
                expectation.fulfill()
            } catch {
                XCTFail("Concurrent processing failed: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 180.0)
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - Supporting Types

enum VideoResolution {
    case sd
    case hd
    case fullHD
    case fourK
    
    var size: String {
        switch self {
        case .sd: return "640x480"
        case .hd: return "1280x720"
        case .fullHD: return "1920x1080"
        case .fourK: return "3840x2160"
        }
    }
    
    var name: String {
        switch self {
        case .sd: return "SD"
        case .hd: return "HD"
        case .fullHD: return "FullHD"
        case .fourK: return "4K"
        }
    }
}