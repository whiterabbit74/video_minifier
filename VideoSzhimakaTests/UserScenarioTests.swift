import XCTest
import SwiftUI
import Combine
@testable import VideoSzhimaka

/// Automated tests for all user scenarios and workflows
@MainActor
class UserScenarioTests: XCTestCase {
    
    var mainViewModel: MainViewModel!
    var settingsViewModel: SettingsViewModel!
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
        
        // Initialize view models
        mainViewModel = MainViewModel(
            ffmpegService: mockFFmpegService,
            fileManagerService: mockFileManagerService,
            settingsService: mockSettingsService,
            loggingService: loggingService
        )
        
        settingsViewModel = SettingsViewModel(settingsService: mockSettingsService)
        
        // Create test video files
        try createTestVideoFiles()
    }
    
    override func tearDownWithError() throws {
        // Clean up test files
        for url in testVideoURLs {
            try? FileManager.default.removeItem(at: url)
        }
        testVideoURLs.removeAll()
        
        mainViewModel = nil
        settingsViewModel = nil
        mockFFmpegService = nil
        mockFileManagerService = nil
        mockSettingsService = nil
        loggingService = nil
        
        try super.tearDownWithError()
    }
    
    private func createTestVideoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        for i in 1...3 {
            let testVideoURL = tempDir.appendingPathComponent("test_video_\(i).mp4")
            let mockVideoData = "Mock video file content for testing \(i)".data(using: .utf8)!
            try mockVideoData.write(to: testVideoURL)
            testVideoURLs.append(testVideoURL)
        }
    }
    
    // MARK: - Basic User Workflow Tests
    
    @MainActor func testBasicCompressionWorkflow() async throws {
        // Step 1: User opens app and sees default settings
        XCTAssertEqual(mockSettingsService.settings.codec, .h264)
        XCTAssertEqual(mockSettingsService.settings.crf, 23)
        XCTAssertFalse(mockSettingsService.settings.deleteOriginals)
        
        // Step 2: User adds a video file
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let videoFilesCount = mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount, 1)
        let addedFile = mainViewModel.videoFiles[0]
        XCTAssertEqual(addedFile.name, testVideoURL.lastPathComponent)
        XCTAssertEqual(addedFile.status, .pending)
        
        // Step 3: User starts compression
        await mainViewModel.compressFile(withId: addedFile.id)
        
        // Wait for compression to complete
        let expectation = XCTestExpectation(description: "Basic compression")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == addedFile.id }),
                   file.status.isFinished {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Step 4: Verify compression completed successfully
        let finalFile = mainViewModel.videoFiles.first { $0.id == addedFile.id }!
        XCTAssertTrue(finalFile.status.isSuccessful)
        XCTAssertEqual(finalFile.compressionProgress, 1.0)
        XCTAssertEqual(mockFFmpegService.compressionCallCount, 1)
    }
    
    @MainActor func testSettingsChangeWorkflow() async throws {
        // Step 1: User changes codec to H.265
        mockSettingsService.settings.setCodec(.h265)
        XCTAssertEqual(mockSettingsService.settings.codec, .h265)
        
        // Step 2: User changes CRF value
        mockSettingsService.settings.setCRF(20)
        XCTAssertEqual(mockSettingsService.settings.crf, 20)
        
        // Step 3: User adds and compresses video with new settings
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let videoFilesCount2 = mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount2, 1)
        
        // Start compression and wait for completion
        let expectation = XCTestExpectation(description: "Compression with H.265")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first,
                   file.status.isFinished {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await mainViewModel.compressAllFiles()
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify compression used new settings
        let allSuccessful = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        let allCompleted = mainViewModel.videoFiles.allSatisfy { $0.compressionProgress == 1.0 }
        XCTAssertTrue(allSuccessful)
        XCTAssertTrue(allCompleted)
    }
    
    @MainActor func testCancellationWorkflow() async throws {
        // Step 1: User adds video and starts compression
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let fileId = mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait a moment for compression to start
        let expectation = XCTestExpectation(description: "Compression started")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status == .compressing {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Step 2: User cancels compression
        await mainViewModel.cancelAllProcessing()
        
        // Step 3: Verify cancellation worked
        let videoFilesCount3 = mainViewModel.videoFiles.count
        let videoFilesCount4 = mainViewModel.videoFiles.count
        let containsFileId = mainViewModel.videoFiles.contains { $0.id == fileId }
        XCTAssertEqual(videoFilesCount3, 1)
        XCTAssertEqual(videoFilesCount4, 1)
        XCTAssertFalse(containsFileId)
        
        // Step 4: User can retry compression
        await mainViewModel.addFiles([testVideoURL])
        
        let expectation2 = XCTestExpectation(description: "Retry compression")
        
        var observer2: AnyCancellable?
        observer2 = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first,
                   file.status.isSuccessful {
                    expectation2.fulfill()
                    observer2?.cancel()
                }
            }
        
        await mainViewModel.compressAllFiles()
        await fulfillment(of: [expectation2], timeout: 5.0)
        
        let videoFilesCount5 = mainViewModel.videoFiles.count
        let allSuccessful2 = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertEqual(videoFilesCount5, 2)
        XCTAssertTrue(allSuccessful2)
    }
    
    @MainActor func testFileManagementWorkflow() async throws {
        // Step 1: User adds multiple files
        await mainViewModel.addFiles(testVideoURLs)
        
        let videoFilesCount6 = mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount6, 3)
        
        // Step 2: User removes one file
        let middleFileId = mainViewModel.videoFiles[1].id
        await mainViewModel.removeFile(withId: middleFileId)
        
        let videoFilesCount7 = mainViewModel.videoFiles.count
        let containsMiddleFileId = mainViewModel.videoFiles.contains { $0.id == middleFileId }
        XCTAssertEqual(videoFilesCount7, 2)
        XCTAssertFalse(containsMiddleFileId)
        
        // Step 3: User compresses remaining files
        let expectation = XCTestExpectation(description: "Batch compression")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await mainViewModel.compressAllFiles()
        await fulfillment(of: [expectation], timeout: 10.0)
        
        let videoFilesCount8 = mainViewModel.videoFiles.count
        let allSuccessful3 = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertEqual(videoFilesCount8, 2)
        XCTAssertTrue(allSuccessful3)
    }
    
    @MainActor func testOpenInFinderWorkflow() async throws {
        // Step 1: User adds and compresses a file
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let fileId = mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to complete
        let expectation = XCTestExpectation(description: "Compression for Finder test")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFinished {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Step 2: User opens file in Finder
        await mainViewModel.openFileInFinder(withId: fileId)
        
        // Step 3: Verify Finder was called
        XCTAssertEqual(mockFileManagerService.openInFinderCallCount, 1)
    }
    
    // MARK: - Advanced Workflow Tests
    
    @MainActor func testBatchProcessingWorkflow() async throws {
        // Step 1: User changes settings for batch processing
        mockSettingsService.settings.setCodec(.h265)
        mockSettingsService.settings.setCRF(22)
        XCTAssertEqual(mockSettingsService.settings.codec, .h265)
        
        // Step 2: User adds multiple files
        await mainViewModel.addFiles(testVideoURLs)
        
        let videoFilesCount = mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount, testVideoURLs.count)
        
        // Step 3: User starts batch compression
        let expectation = XCTestExpectation(description: "Batch processing")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await mainViewModel.compressAllFiles()
        await fulfillment(of: [expectation], timeout: 15.0)
        
        // Step 4: Verify all files processed successfully
        let allSuccessful = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertTrue(allSuccessful)
    }
    
    @MainActor func testErrorHandlingWorkflow() async throws {
        // Step 1: Configure mock to fail compression
        mockFFmpegService.mockError = .compressionFailed("Mock compression error")
        
        // Step 2: User adds and tries to compress file
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let fileId = mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to fail
        let expectation = XCTestExpectation(description: "Compression failure")
        
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
        
        // Step 3: Verify error handling
        let failedFiles = mainViewModel.videoFiles.filter { $0.status.isFailure }
        XCTAssertEqual(failedFiles.count, 1)
        
        let failedFileId = failedFiles[0].id
        
        // Step 4: User retries failed file
        mockFFmpegService.mockError = nil // Clear error for retry
        
        await mainViewModel.retryCompression(forFileId: failedFileId)
        
        // Wait for retry to complete
        let expectation2 = XCTestExpectation(description: "Retry compression")
        
        var observer2: AnyCancellable?
        observer2 = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == failedFileId }),
                   file.status.isSuccessful {
                    expectation2.fulfill()
                    observer2?.cancel()
                }
            }
        
        await fulfillment(of: [expectation2], timeout: 5.0)
        
        // Step 5: Verify retry worked
        let allSuccessfulAfterRetry = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertTrue(allSuccessfulAfterRetry)
    }
    
    @MainActor func testLoggingWorkflow() async throws {
        // Step 1: User adds and compresses file
        let testVideoURL = testVideoURLs[0]
        await mainViewModel.addFiles([testVideoURL])
        
        let fileId = mainViewModel.videoFiles[0].id
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for compression to complete
        let expectation = XCTestExpectation(description: "Compression for logging test")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFinished {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Step 2: User opens logs
        await mainViewModel.toggleLogs()
        let showLogs = mainViewModel.showLogs
        XCTAssertTrue(showLogs)
        
        // Step 3: Verify logs contain compression information
        let logs = loggingService.logs
        XCTAssertFalse(logs.isEmpty)
        
        // Step 4: User closes logs
        await mainViewModel.toggleLogs()
        let showLogsAfterToggle = mainViewModel.showLogs
        XCTAssertFalse(showLogsAfterToggle)
    }
    
    // MARK: - Complex Scenario Tests
    
    @MainActor func testComplexMixedWorkflow() async throws {
        // Step 1: User changes settings
        mockSettingsService.settings.setCodec(.h265)
        mockSettingsService.settings.setCRF(25)
        XCTAssertEqual(mockSettingsService.settings.codec, .h265)
        
        // Step 2: User adds multiple files
        await mainViewModel.addFiles(testVideoURLs)
        
        // Step 3: User starts batch processing
        let fileCount = await mainViewModel.videoFiles.count
        XCTAssertEqual(fileCount, 3)
        
        let expectation = XCTestExpectation(description: "Complex workflow")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await mainViewModel.compressAllFiles()
        await fulfillment(of: [expectation], timeout: 15.0)
        
        // Step 4: Verify all files processed
        let allProcessedSuccessfully = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertTrue(allProcessedSuccessfully)
    }
    
    @MainActor func testFileRemovalDuringProcessing() async throws {
        // Step 1: Add multiple files
        await mainViewModel.addFiles(testVideoURLs)
        
        let initialVideoFilesCount = mainViewModel.videoFiles.count
        XCTAssertEqual(initialVideoFilesCount, 3)
        
        // Step 2: Remove middle file
        let fileIds = mainViewModel.videoFiles.map { $0.id }
        await mainViewModel.removeFile(withId: fileIds[1])
        
        let videoFilesCountAfterRemoval = mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCountAfterRemoval, 2)
        
        // Step 3: Process remaining files
        await mainViewModel.compressAllFiles()
        
        // Step 4: Add more files during processing
        await mainViewModel.addFiles([testVideoURLs[2]])
        
        let expectation = XCTestExpectation(description: "File removal during processing")
        
        var observer: AnyCancellable?
        observer = await mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                    observer?.cancel()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        let finalVideoFilesCount = mainViewModel.videoFiles.count
        let allFinalSuccessful = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertEqual(finalVideoFilesCount, 3)
        XCTAssertTrue(allFinalSuccessful)
    }
    
    @MainActor func testUndoRedoWorkflow() async throws {
        // Step 1: Add files
        await mainViewModel.addFiles(testVideoURLs)
        
        let initialCount = mainViewModel.videoFiles.count
        XCTAssertEqual(initialCount, 3)
        
        // Step 2: Clear all files
        await mainViewModel.clearAllFiles()
        
        let clearedCount = mainViewModel.videoFiles.count
        XCTAssertEqual(clearedCount, 0)
        
        // Step 3: Re-add files (simulating undo)
        await mainViewModel.addFiles(testVideoURLs)
        
        let readdedCount = mainViewModel.videoFiles.count
        let allReaddedSuccessful = mainViewModel.videoFiles.allSatisfy { $0.status.isSuccessful }
        XCTAssertEqual(readdedCount, 3)
        XCTAssertTrue(allReaddedSuccessful)
    }
}