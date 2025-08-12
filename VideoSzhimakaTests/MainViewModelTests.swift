import XCTest
@testable import VideoSzhimaka

/// Unit tests for MainViewModel
@MainActor
final class MainViewModelTests: XCTestCase {
    
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
        viewModel = nil
        mockFFmpegService = nil
        mockFileManagerService = nil
        mockSettingsService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertTrue(viewModel.videoFiles.isEmpty)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(viewModel.showSettings)
        XCTAssertFalse(viewModel.showLogs)
        XCTAssertNil(viewModel.currentError)
        XCTAssertTrue(viewModel.batchErrors.isEmpty)
        XCTAssertFalse(viewModel.showBatchErrorsAlert)
    }
    
    // MARK: - File Management Tests
    
    func testAddSingleFile() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        let expectedVideoInfo = VideoInfo(
            duration: 120.0,
            width: 1920,
            height: 1080,
            frameRate: 30.0,
            bitrate: 5000000,
            hasAudio: true,
            audioCodec: "aac",
            videoCodec: "h264"
        )
        
        mockFFmpegService.videoInfoResult = .success(expectedVideoInfo)
        mockFileManagerService.fileSizeResult = .success(Int64(1024 * 1024 * 100)) // 100MB
        
        // When
        viewModel.addFiles([testURL])
        
        // Wait for async operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then
        XCTAssertEqual(viewModel.videoFiles.count, 1)
        
        let addedFile = viewModel.videoFiles.first!
        XCTAssertEqual(addedFile.url, testURL)
        XCTAssertEqual(addedFile.name, "video.mp4")
        XCTAssertEqual(addedFile.duration, 120.0)
        XCTAssertEqual(addedFile.originalSize, Int64(1024 * 1024 * 100))
        XCTAssertEqual(addedFile.status, .pending)
        XCTAssertEqual(addedFile.compressionProgress, 0.0)
        XCTAssertNil(addedFile.compressedSize)
    }
    
    func testAddDuplicateFile() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
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
        mockFileManagerService.fileSizeResult = .success(Int64(1024 * 1024 * 100))
        
        // When
        viewModel.addFiles([testURL])
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        viewModel.addFiles([testURL]) // Add same file again
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertEqual(viewModel.videoFiles.count, 1) // Should not add duplicate
    }
    
    func testAddFileWithError() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/invalid.mp4")
        mockFFmpegService.videoInfoResult = .failure(VideoCompressionError.invalidInput("Failed to extract metadata"))
        
        // When
        viewModel.addFiles([testURL])
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertTrue(viewModel.videoFiles.isEmpty)
        XCTAssertNotNil(viewModel.currentError)
    }
    
    func testRemoveFile() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        
        // When
        viewModel.removeFile(withId: fileId)
        
        // Then
        XCTAssertTrue(viewModel.videoFiles.isEmpty)
    }
    
    func testRemoveAllFiles() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4")
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        XCTAssertEqual(viewModel.videoFiles.count, 2)
        
        // When
        viewModel.removeAllFiles()
        
        // Then
        XCTAssertTrue(viewModel.videoFiles.isEmpty)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    // MARK: - Compression Tests
    
    func testCompressSingleFile() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        let outputURL = URL(fileURLWithPath: "/test/video_compressed.mp4")
        
        mockFileManagerService.generateOutputURLResult = outputURL
        mockFFmpegService.compressionResult = .success(())
        mockFileManagerService.fileSizeResults = [
            outputURL: .success(Int64(1024 * 1024 * 50)) // 50MB compressed
        ]
        
        // When
        viewModel.compressFile(withId: fileId)
        
        // Wait for compression to complete
        var attempts = 0
        while viewModel.isProcessing && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        
        let compressedFile = viewModel.videoFiles.first!
        XCTAssertEqual(compressedFile.status, .completed)
        XCTAssertEqual(compressedFile.compressionProgress, 1.0)
        XCTAssertEqual(compressedFile.compressedSize, Int64(1024 * 1024 * 50))
    }
    
    func testCompressAllFiles() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4")
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.compressionResult = .success(())
        mockFileManagerService.fileSizeResults = [
            URL(fileURLWithPath: "/test/output.mp4"): .success(Int64(1024 * 1024 * 50))
        ]
        
        // When
        viewModel.compressAllFiles()
        
        // Wait for all compressions to complete
        var attempts = 0
        while viewModel.isProcessing && attempts < 100 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.fileCount(withStatus: .completed), 2)
    }
    
    func testCompressionFailure() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.compressionResult = .failure(VideoCompressionError.compressionFailed("Test error"))
        
        // When
        viewModel.compressFile(withId: fileId)
        
        // Wait for compression to complete
        var attempts = 0
        while viewModel.isProcessing && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        
        let failedFile = viewModel.videoFiles.first!
        if case .failed(let error) = failedFile.status {
            XCTAssertTrue(error.localizedDescription.contains("Test error"))
        } else {
            XCTFail("Expected failed status")
        }
        
        XCTAssertEqual(failedFile.compressionProgress, 0.0)
        XCTAssertFalse(viewModel.batchErrors.isEmpty)
    }
    
    func testCancelAllProcessing() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        let fileId = viewModel.videoFiles.first!.id
        mockFileManagerService.generateOutputURLResult = URL(fileURLWithPath: "/test/output.mp4")
        mockFFmpegService.compressionResult = .success(()) // Will be cancelled
        
        // Start compression
        viewModel.compressFile(withId: fileId)
        try? await Task.sleep(nanoseconds: 50_000_000) // Let it start
        
        // When
        viewModel.cancelAllProcessing()
        
        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(mockFFmpegService.cancelCurrentOperationCalled)
        
        let file = viewModel.videoFiles.first!
        XCTAssertEqual(file.status, .pending)
        XCTAssertEqual(file.compressionProgress, 0.0)
    }
    
    // MARK: - Drag & Drop Tests
    
    func testCanDropItems() {
        // Given
        let mockProvider = MockNSItemProvider()
        mockProvider.hasItemResult = true
        
        // When
        let canDrop = viewModel.canDropItems([mockProvider])
        
        // Then
        XCTAssertTrue(canDrop)
    }
    
    func testCannotDropInvalidItems() {
        // Given
        let mockProvider = MockNSItemProvider()
        mockProvider.hasItemResult = false
        
        // When
        let canDrop = viewModel.canDropItems([mockProvider])
        
        // Then
        XCTAssertFalse(canDrop)
    }
    
    // MARK: - Statistics Tests
    
    func testTotalOriginalSize() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4")
        ]
        
        mockFileManagerService.fileSizeResults = [
            urls[0]: .success(Int64(1024 * 1024 * 100)), // 100MB
            urls[1]: .success(Int64(1024 * 1024 * 200))  // 200MB
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        // When
        let totalSize = viewModel.totalOriginalSize
        
        // Then
        XCTAssertEqual(totalSize, Int64(1024 * 1024 * 300)) // 300MB total
    }
    
    func testOverallCompressionRatio() async {
        // Given
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        await addTestFile(url: testURL)
        
        // Simulate successful compression
        var file = viewModel.videoFiles[0]
        file.status = .completed
        file.compressedSize = Int64(1024 * 1024 * 50) // 50MB compressed from 100MB original
        viewModel.videoFiles[0] = file
        
        // When
        let ratio = viewModel.overallCompressionRatio
        
        // Then
        XCTAssertNotNil(ratio)
        XCTAssertEqual(ratio!, 50.0, accuracy: 0.1) // 50% compression
    }
    
    func testFileCountWithStatus() async {
        // Given
        let urls = [
            URL(fileURLWithPath: "/test/video1.mp4"),
            URL(fileURLWithPath: "/test/video2.mp4"),
            URL(fileURLWithPath: "/test/video3.mp4")
        ]
        
        for url in urls {
            await addTestFile(url: url)
        }
        
        // Simulate different statuses
        viewModel.videoFiles[0].status = .completed
        viewModel.videoFiles[1].status = .failed(.unknownError("Error"))
        viewModel.videoFiles[2].status = .pending
        
        // When & Then
        XCTAssertEqual(viewModel.fileCount(withStatus: .completed), 1)
        XCTAssertEqual(viewModel.fileCount(withStatus: .failed(.unknownError("Error"))), 1)
        XCTAssertEqual(viewModel.fileCount(withStatus: .pending), 1)
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
        
        if let fileSize = mockFileManagerService.fileSizeResults[url] {
            mockFileManagerService.fileSizeResult = fileSize
        } else {
            mockFileManagerService.fileSizeResult = .success(Int64(1024 * 1024 * 100)) // 100MB default
        }
        
        viewModel.addFiles([url])
        try? await Task.sleep(nanoseconds: 100_000_000) // Wait for async operation
    }
}

// MARK: - Additional Mock Classes

class MockNSItemProvider: NSItemProvider {
    var hasItemResult = false
    
    override func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        return hasItemResult
    }
}