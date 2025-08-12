import XCTest
@testable import VideoSzhimaka

/// Comprehensive tests for cancellation functionality to prevent crashes
@MainActor
final class CancellationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    var viewModel: MainViewModel!
    var mockFFmpegService: MockFFmpegService!
    var mockFileManagerService: MockFileManagerService!
    var mockSettingsService: MockSettingsService!
    
    // MARK: - Setup and Teardown
    
    @MainActor override func setUp() {
        super.setUp()
        
        mockFFmpegService = MockFFmpegService()
        mockFileManagerService = MockFileManagerService()
        mockSettingsService = MockSettingsService()
        
        viewModel = MainViewModel(
            ffmpegService: mockFFmpegService,
            fileManagerService: mockFileManagerService,
            settingsService: mockSettingsService,
            loggingService: LoggingService()
        )
    }
    
    override func tearDown() {
        viewModel?.cancelAllProcessing()
        viewModel = nil
        mockFFmpegService = nil
        mockFileManagerService = nil
        mockSettingsService = nil
        super.tearDown()
    }
    
    // MARK: - Cancellation Tests
    
    func testCancelSingleFileCompression() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        
        // Configure mock to simulate long-running compression
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When
        viewModel.compressFile(withId: fileId)
        
        // Wait for compression to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertEqual(viewModel.videoFiles.first!.status, .compressing)
        
        // Cancel the operation
        viewModel.cancelAllProcessing()
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(mockFFmpegService.cancelCurrentOperationCalled)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    func testCancelMultipleFileCompression() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4"),
            URL(fileURLWithPath: "/test/video3.mp4")
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When
        viewModel.compressAllFiles()
        
        // Wait for compression to start
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isProcessing)
        
        // Cancel all operations
        viewModel.cancelAllProcessing()
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(mockFFmpegService.cancelCurrentOperationCalled)
        
        // All files should be reset to pending
        for file in viewModel.videoFiles {
            XCTAssertEqual(file.status, .pending)
            XCTAssertEqual(file.compressionProgress, 0.0)
        }
    }
    
    func testCancelBeforeCompressionStarts() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.compressionResult = .success(())
        
        // When - cancel immediately after starting compression
        viewModel.compressFile(withId: fileId)
        viewModel.cancelAllProcessing()
        
        // Wait a bit to ensure no processing occurs
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    func testCancelDuringProgressUpdates() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        
        // Configure mock to send progress updates
        mockFFmpegService.simulateProgressUpdates = true
        mockFFmpegService.compressionResult = .success(())
        
        // When
        viewModel.compressFile(withId: fileId)
        
        // Wait for some progress updates
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        // Verify progress is being updated
        let progressBeforeCancel = viewModel.videoFiles.first!.compressionProgress
        XCTAssertGreaterThan(progressBeforeCancel, 0.0)
        
        // Cancel during progress updates
        viewModel.cancelAllProcessing()
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    func testMultipleCancellationCalls() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When
        viewModel.compressFile(withId: fileId)
        try? await Task.sleep(nanoseconds: 50_000_000)
        
        // Call cancel multiple times rapidly
        viewModel.cancelAllProcessing()
        viewModel.cancelAllProcessing()
        viewModel.cancelAllProcessing()
        
        // Then - should not crash and should be in consistent state
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.currentlyProcessingFileId)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    func testCancelAndRestartCompression() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - start, cancel, then restart
        viewModel.compressFile(withId: fileId)
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        viewModel.cancelAllProcessing()
        XCTAssertFalse(viewModel.isProcessing)
        
        // Reset mock for second attempt
        mockFFmpegService.reset()
        mockFFmpegService.compressionResult = .success(())
        mockFileManagerService.fileSizeResults = [
            URL(fileURLWithPath: "/test/output.mp4"): .success(Int64(1024 * 1024 * 50))
        ]
        
        // Restart compression
        viewModel.compressFile(withId: fileId)
        
        // Wait for completion
        var attempts = 0
        while viewModel.isProcessing && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .completed)
        XCTAssertEqual(file.compressionProgress, 1.0)
    }
    
    func testCancelWithQueuedFiles() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4"),
            URL(fileURLWithPath: "/test/video3.mp4")
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - start processing all files
        viewModel.compressAllFiles()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify processing started
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNotNil(viewModel.currentlyProcessingFileId)
        
        // Cancel all
        viewModel.cancelAllProcessing()
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.currentlyProcessingFileId)
        
        // All files should be reset
        for file in viewModel.videoFiles {
            XCTAssertEqual(file.status, .pending)
            XCTAssertEqual(file.compressionProgress, 0.0)
        }
    }
    
    func testCancelAfterCompletion() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.compressionResult = .success(())
        mockFileManagerService.fileSizeResults = [
            URL(fileURLWithPath: "/test/output.mp4"): .success(Int64(1024 * 1024 * 50))
        ]
        
        // When - complete compression first
        viewModel.compressFile(withId: fileId)
        
        var attempts = 0
        while viewModel.isProcessing && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        
        // Verify completion
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.videoFiles.first!.status, .completed)
        
        // Cancel after completion
        viewModel.cancelAllProcessing()
        
        // Then - should not affect completed files
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.videoFiles.first!.status, .completed)
        XCTAssertEqual(viewModel.videoFiles.first!.compressionProgress, 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func addTestFile(url: URL) async {
        let videoInfo = VideoInfo(
            duration: 120.0,
            width: 1920,
            height: 1080,
            frameRate: 30.0,
            bitrate: 5000000,
            hasAudio: true,
            audioCodec: "aac",
            videoCodec: "h264"
        )
        
        mockFFmpegService.videoInfoResult = .success(videoInfo)
        mockFileManagerService.fileSizeResult = .success(Int64(1024 * 1024 * 100)) // 100MB
        
        viewModel.addFiles([url])
        try? await Task.sleep(nanoseconds: 100_000_000) // Wait for async operation
    }
}

// MARK: - Enhanced Mock FFmpeg Service

extension MockFFmpegService {
    var simulateLongRunningCompression: Bool {
        get { _simulateLongRunningCompression }
        set { _simulateLongRunningCompression = newValue }
    }
    
    var simulateProgressUpdates: Bool {
        get { _simulateProgressUpdates }
        set { _simulateProgressUpdates = newValue }
    }
    
    private var _simulateLongRunningCompression: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.simulateLongRunning) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.simulateLongRunning, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    private var _simulateProgressUpdates: Bool {
        get { objc_getAssociatedObject(self, &AssociatedKeys.simulateProgress) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &AssociatedKeys.simulateProgress, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    
    private struct AssociatedKeys {
        static var simulateLongRunning = "simulateLongRunning"
        static var simulateProgress = "simulateProgress"
    }
    
    override func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        self.progressHandler = progressHandler
        
        // Track compression attempts
        compressionAttempts += 1
        fileCompressionCounts[input, default: 0] += 1
        
        if simulateProgressUpdates {
            // Simulate progress updates with cancellation checks
            for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                try Task.checkCancellation()
                progressHandler(progress)
                
                if simulateLongRunningCompression {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds per update
                } else {
                    try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds per update
                }
            }
        } else if simulateLongRunningCompression {
            // Simulate long-running compression without progress updates
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            progressHandler(1.0)
        } else {
            // Quick compression
            progressHandler(1.0)
        }
        
        // Handle different failure scenarios
        if shouldFailCompression {
            if failOnlyFirstFile && compressionAttempts > 1 {
                return
            }
            
            if failOnlyFirstAttempt && fileCompressionCounts[input, default: 0] > 1 {
                return
            }
            
            throw compressionError
        }
        
        switch compressionResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
    
    override func reset() {
        super.reset()
        simulateLongRunningCompression = false
        simulateProgressUpdates = false
    }
}