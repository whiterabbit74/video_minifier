import XCTest
@testable import VideoSzhimaka

/// Regression tests for crash scenarios, specifically the SIGABRT crash during cancellation
@MainActor
final class CrashRegressionTests: XCTestCase {
    
    var viewModel: MainViewModel!
    var mockFFmpegService: MockFFmpegService!
    var mockFileManagerService: MockFileManagerService!
    var mockSettingsService: MockSettingsService!
    
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
    
    /// Test for the specific SIGABRT crash scenario from the crash report
    func testSIGABRTCrashRegression() async {
        // Given - simulate the exact scenario from the crash report
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        
        // Configure mock to simulate the crash scenario
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.simulateProgressUpdates = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - start compression and cancel rapidly multiple times
        for _ in 0..<5 {
            viewModel.compressFile(withId: fileId)
            
            // Wait a very short time to let compression start
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            
            // Cancel immediately
            viewModel.cancelAllProcessing()
            
            // Wait a bit before next iteration
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        // Then - should not crash and should be in consistent state
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.currentlyProcessingFileId)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    /// Test rapid cancellation during progress updates (Thread 7 crash scenario)
    func testRapidCancellationDuringProgress() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        
        // Configure for progress updates
        mockFFmpegService.simulateProgressUpdates = true
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - start compression
        viewModel.compressFile(withId: fileId)
        
        // Wait for progress to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Rapidly cancel multiple times while progress is updating
        for _ in 0..<10 {
            viewModel.cancelAllProcessing()
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms between cancellations
        }
        
        // Then - should not crash
        XCTAssertFalse(viewModel.isProcessing)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    /// Test cancellation with concurrent file operations
    func testConcurrentCancellationStressTest() async {
        // Given - multiple files
        let urls = (1...5).map { URL(fileURLWithPath: "/test/video\($0).mp4") }
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - start processing all files
        viewModel.compressAllFiles()
        
        // Concurrently cancel from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    for _ in 0..<5 {
                        await self.viewModel.cancelAllProcessing()
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }
            }
        }
        
        // Then - should not crash and be in consistent state
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.currentlyProcessingFileId)
        
        for file in viewModel.videoFiles {
            XCTAssertEqual(file.status, .pending)
            XCTAssertEqual(file.compressionProgress, 0.0)
        }
    }
    
    /// Test memory management during cancellation
    func testMemoryManagementDuringCancellation() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.simulateLongRunningCompression = true
        mockFFmpegService.compressionResult = .success(())
        
        // When - create and cancel many operations to test memory management
        for _ in 0..<20 {
            viewModel.compressFile(withId: fileId)
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            viewModel.cancelAllProcessing()
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Then - should not crash or leak memory
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.currentlyProcessingFileId)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
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