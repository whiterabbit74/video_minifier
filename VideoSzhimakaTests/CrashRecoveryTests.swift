import XCTest
import Combine
@testable import VideoSzhimaka

/// Tests for crash recovery and error resilience
@MainActor
class CrashRecoveryTests: XCTestCase {
    
    var mainViewModel: MainViewModel!
    var mockFFmpegService: MockFFmpegService!
    var mockFileManagerService: MockFileManagerService!
    var mockSettingsService: MockSettingsService!
    var loggingService: LoggingService!
    var testVideoURLs: [URL] = []
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize mock services
        mockFFmpegService = MockFFmpegService()
        mockFileManagerService = MockFileManagerService()
        mockSettingsService = MockSettingsService()
        loggingService = LoggingService()
        
        // Initialize main view model
        mainViewModel = MainViewModel(
            ffmpegService: mockFFmpegService,
            fileManagerService: mockFileManagerService,
            settingsService: mockSettingsService,
            loggingService: loggingService
        )
        
        // Create test video files
        try createTestVideoFiles()
    }
    
    override func tearDownWithError() throws {
        // Clean up test files
        for url in testVideoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        testVideoURLs.removeAll()
        
        try super.tearDownWithError()
    }
    
    private func createTestVideoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        for i in 1...3 {
            let testVideoURL = tempDir.appendingPathComponent("crash_test_video_\(i).mp4")
            let mockVideoData = "Mock video file content for crash testing \(i)".data(using: .utf8)!
            try mockVideoData.write(to: testVideoURL)
            testVideoURLs.append(testVideoURL)
        }
    }
    
    // MARK: - Service Failure Recovery Tests
    
    /// Test recovery from FFmpeg service crashes
    @MainActor func testFFmpegServiceCrashRecovery() async throws {
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        // Configure mock to simulate FFmpeg crash
        mockFFmpegService.compressionError = .ffmpegNotFound
        
        let fileId = await mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to fail
        let expectation = XCTestExpectation(description: "FFmpeg crash recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFailure {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify error was handled gracefully
        let failedFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        let isProcessingAfterFFmpegFailure = await mainViewModel.isProcessing
        XCTAssertTrue(failedFile.status.isFailure)
        XCTAssertFalse(isProcessingAfterFFmpegFailure)
    }
    
    /// Test recovery from file system errors
    @MainActor func testFileSystemErrorRecovery() async throws {
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        // Configure mock to simulate file system error
        mockFFmpegService.compressionError = .insufficientSpace
        
        let fileId = await mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to fail
        let expectation = XCTestExpectation(description: "File system error recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFailure {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify error was handled gracefully
        let failedFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        let isProcessingAfterFileSystemError = await mainViewModel.isProcessing
        XCTAssertTrue(failedFile.status.isFailure)
        XCTAssertFalse(isProcessingAfterFileSystemError)
    }
    
    // MARK: - Memory Management Tests
    
    /// Test recovery from memory pressure
    @MainActor func testMemoryPressureRecovery() async throws {
        // Add multiple large files to simulate memory pressure
        await mainViewModel.addFiles(testVideoURLs)
        
        // Configure mock to simulate memory-related failure
        mockFFmpegService.compressionError = .compressionFailed("Out of memory")
        
        // Start batch processing
        await mainViewModel.compressAllFiles()
        
        // Wait for all files to fail
        let expectation = XCTestExpectation(description: "Memory pressure recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                let allFailed = files.allSatisfy { $0.status.isFailure }
                if allFailed && !files.isEmpty {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify system recovered gracefully
        let allFailed = await mainViewModel.videoFiles.allSatisfy { $0.status.isFailure }
        let isProcessingAfterMemoryPressure = await mainViewModel.isProcessing
        XCTAssertTrue(allFailed)
        XCTAssertFalse(isProcessingAfterMemoryPressure)
        
        // Test recovery by clearing error and retrying
        mockFFmpegService.compressionError = nil
        
        let expectation2 = XCTestExpectation(description: "Recovery after memory pressure")
        
        var observer2: AnyCancellable?
        observer2 = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isSuccessful }) {
                    expectation2.fulfill()
                    observer2?.cancel()
                }
            }
        
        await mainViewModel.retryAllFailedFiles()
        await fulfillment(of: [expectation2], timeout: 10.0)
        
        let allSuccessfulAfterRetry = await mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertTrue(allSuccessfulAfterRetry)
    }
    
    // MARK: - Corruption Recovery Tests
    
    /// Test recovery from corrupted video files
    @MainActor func testCorruptedFileRecovery() async throws {
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        // Configure mock to simulate corrupted file
        mockFFmpegService.compressionError = .compressionFailed("Invalid data found")
        
        let fileId = await mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to fail
        let expectation = XCTestExpectation(description: "Corrupted file recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFailure {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify error was handled gracefully
        let failedFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        XCTAssertTrue(failedFile.status.isFailure)
    }
    
    // MARK: - Partial Failure Recovery Tests
    
    /// Test recovery from partial batch failures
    @MainActor func testPartialBatchFailureRecovery() async throws {
        await mainViewModel.addFiles(testVideoURLs)
        
        // Configure mock to fail on some files
        mockFFmpegService.compressionError = .compressionFailed("Partial failure")
        mockFFmpegService.shouldFailOnFile = testVideoURLs[1] // Fail on middle file
        
        await mainViewModel.compressAllFiles()
        
        // Wait for processing to complete
        let expectation = XCTestExpectation(description: "Partial batch failure recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify partial failure was handled correctly
        let failedFiles = await mainViewModel.videoFiles.filter { $0.status.isFailure }
        XCTAssertEqual(failedFiles.count, 1)
        
        // Verify successful files completed
        let successfulFiles = await mainViewModel.videoFiles.filter { $0.status.isSuccessful }
        XCTAssertEqual(successfulFiles.count, 2)
    }
    
    // MARK: - Concurrent Operation Recovery Tests
    
    /// Test recovery from concurrent operation conflicts
    @MainActor func testConcurrentOperationRecovery() async throws {
        await mainViewModel.addFiles(testVideoURLs)
        
        // Configure mock to simulate concurrent operation failure
        mockFFmpegService.compressionError = .compressionFailed("Multiple failure test")
        
        // Start multiple operations concurrently
        await mainViewModel.compressAllFiles()
        
        // Wait for all operations to fail
        let expectation = XCTestExpectation(description: "Concurrent operation recovery")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                let allFailed = files.allSatisfy { $0.status.isFailure }
                if allFailed && !files.isEmpty {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Verify system recovered from concurrent failures
        let allFailedConcurrent = await mainViewModel.videoFiles.allSatisfy { $0.status.isFailure }
        let isProcessingAfterConcurrentFailure = await mainViewModel.isProcessing
        XCTAssertTrue(allFailedConcurrent)
        XCTAssertFalse(isProcessingAfterConcurrentFailure)
    }
    
    // MARK: - State Consistency Tests
    
    /// Test state consistency after service replacement
    @MainActor func testServiceReplacementConsistency() async throws {
        await mainViewModel.addFiles([testVideoURLs[0]])
        
        // Start compression
        let fileId = await mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Simulate service replacement (like in crash recovery)
        let newMockSettingsService = MockSettingsService()
        
        // Verify state remains consistent
        let videoFilesCount = await mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount, 1)
        
        // Cancel and verify cleanup
        await mainViewModel.cancelAllProcessing()
        let isProcessingAfterCancel = await mainViewModel.isProcessing
        XCTAssertFalse(isProcessingAfterCancel)
    }
    
    // MARK: - Helper Methods
    
    private func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {
        await withCheckedContinuation { continuation in
            let waiter = XCTWaiter()
            let result = waiter.wait(for: expectations, timeout: timeout)
            
            switch result {
            case .completed:
                break
            case .timedOut:
                XCTFail("Expectations timed out after \(timeout) seconds")
            case .incorrectOrder:
                XCTFail("Expectations fulfilled in incorrect order")
            case .invertedFulfillment:
                XCTFail("Inverted expectation was fulfilled")
            case .interrupted:
                XCTFail("Expectation waiter was interrupted")
            @unknown default:
                XCTFail("Unknown expectation result")
            }
            
            continuation.resume()
        }
    }
}