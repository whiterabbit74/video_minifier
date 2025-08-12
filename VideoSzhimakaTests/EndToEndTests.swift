import XCTest
import SwiftUI
import Combine
@testable import VideoSzhimaka

/// End-to-end tests for complete video compression workflow
@MainActor
class EndToEndTests: XCTestCase {
    
    var mainViewModel: MainViewModel!
    var mockFFmpegService: MockFFmpegService!
    var mockFileManagerService: MockFileManagerService!
    var mockSettingsService: MockSettingsService!
    var loggingService: LoggingService!
    var performanceMonitor: PerformanceMonitorService!
    var testVideoURLs: [URL] = []
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Initialize mock services
        mockFFmpegService = MockFFmpegService()
        mockFileManagerService = MockFileManagerService()
        mockSettingsService = MockSettingsService()
        loggingService = LoggingService()
        performanceMonitor = PerformanceMonitorService.shared
        
        // Initialize main view model with mock services
        mainViewModel = MainViewModel(
            ffmpegService: mockFFmpegService,
            fileManagerService: mockFileManagerService,
            settingsService: mockSettingsService,
            loggingService: loggingService,
            performanceMonitor: performanceMonitor
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
        
        mainViewModel = nil
        mockFFmpegService = nil
        mockFileManagerService = nil
        mockSettingsService = nil
        loggingService = nil
        performanceMonitor = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Complete Workflow Tests
    
    /// Test complete single file compression workflow
    func testCompleteVideoCompressionWorkflow() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // Step 1: Add file to the list
        await mainViewModel.addFiles([testVideoURL])
        
        let videoFilesCount = await mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount, 1)
        let addedFile = await mainViewModel.videoFiles[0]
        XCTAssertEqual(addedFile.url, testVideoURL)
        XCTAssertEqual(addedFile.status, .pending)
        
        // Step 2: Start compression
        await mainViewModel.compressFile(withId: addedFile.id)
        
        // Wait for compression to complete
        let expectation = XCTestExpectation(description: "Compression completion")
        
        // Monitor status changes
        let statusObserver = mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == addedFile.id }),
                   file.status.isFinished {
                    expectation.fulfill()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        statusObserver.cancel()
        
        // Step 3: Verify final state
        let finalFile = await mainViewModel.videoFiles.first { $0.id == addedFile.id }!
        XCTAssertTrue(finalFile.status.isSuccessful)
        XCTAssertEqual(finalFile.compressionProgress, 1.0)
        XCTAssertNotNil(finalFile.compressedSize)
        let isProcessing = await mainViewModel.isProcessing
        XCTAssertFalse(isProcessing)
    }
    
    /// Test complete batch processing workflow
    func testCompleteBatchProcessingWorkflow() async throws {
        let testVideoURLs = Array(self.testVideoURLs.prefix(3))
        
        // Step 1: Add multiple files
        await mainViewModel.addFiles(testVideoURLs)
        
        let videoFilesCount = await mainViewModel.videoFiles.count
        XCTAssertEqual(videoFilesCount, 3)
        let videoFiles = await mainViewModel.videoFiles
        XCTAssertTrue(videoFiles.allSatisfy { $0.status == .pending })
        
        // Step 2: Start batch compression
        await mainViewModel.compressAllFiles()
        
        // Wait for all compressions to complete
        let expectation = XCTestExpectation(description: "Batch compression completion")
        
        let statusObserver = mainViewModel.$videoFiles
            .sink { files in
                if files.allSatisfy({ $0.status.isFinished }) {
                    expectation.fulfill()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        statusObserver.cancel()
        
        // Step 3: Verify all files processed successfully
        let finalVideoFiles = await mainViewModel.videoFiles
        XCTAssertTrue(finalVideoFiles.allSatisfy { $0.status.isSuccessful })
        XCTAssertTrue(finalVideoFiles.allSatisfy { $0.compressionProgress == 1.0 })
        XCTAssertTrue(finalVideoFiles.allSatisfy { $0.compressedSize != nil })
        let finalIsProcessing = await mainViewModel.isProcessing
        XCTAssertFalse(finalIsProcessing)
    }
    
    /// Test workflow with file removal during processing
    func testFileRemovalDuringProcessing() async throws {
        let testVideoURLs = Array(self.testVideoURLs.prefix(2))
        
        // Add files
        await mainViewModel.addFiles(testVideoURLs)
        let initialVideoFilesCount = await mainViewModel.videoFiles.count
        XCTAssertEqual(initialVideoFilesCount, 2)
        
        let firstFileId = await mainViewModel.videoFiles[0].id
        let secondFileId = await mainViewModel.videoFiles[1].id
        
        // Start batch processing
        let batchTask = Task {
            await mainViewModel.compressAllFiles()
        }
        
        // Wait a moment for processing to start
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        // Remove the second file while processing
        await mainViewModel.removeFile(withId: secondFileId)
        
        // Wait for batch processing to complete
        await batchTask.value
        
        // Verify only first file remains and is processed
        let remainingVideoFiles = await mainViewModel.videoFiles
        XCTAssertEqual(remainingVideoFiles.count, 1)
        XCTAssertEqual(remainingVideoFiles[0].id, firstFileId)
        XCTAssertTrue(remainingVideoFiles[0].status.isSuccessful)
    }
    
    /// Test workflow with settings changes during processing
    func testSettingsChangesDuringProcessing() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // Add file with initial settings
        await mainViewModel.addFiles([testVideoURL])
        let fileId = await mainViewModel.videoFiles[0].id
        
        // Change settings
        mockSettingsService.settings.crf = 25
        mockSettingsService.settings.codec = .h265
        
        // Start compression (should use new settings)
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for completion
        let expectation = XCTestExpectation(description: "Compression with new settings")
        
        let statusObserver = mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFinished {
                    expectation.fulfill()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        statusObserver.cancel()
        
        // Verify compression completed successfully with new settings
        let finalFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        XCTAssertTrue(finalFile.status.isSuccessful)
    }
    
    /// Test workflow with error recovery
    func testErrorRecoveryWorkflow() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // Add file
        await mainViewModel.addFiles([testVideoURL])
        let fileId = await mainViewModel.videoFiles[0].id
        
        // Configure mock to fail first attempt
        mockFFmpegService.shouldSucceed = false
        mockFFmpegService.mockError = .compressionFailed("Mock failure")
        
        // First compression attempt (should fail)
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for failure
        let failureExpectation = XCTestExpectation(description: "Compression failure")
        
        let failureObserver = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   case .failed = file.status {
                    failureExpectation.fulfill()
                }
            }
        
        await fulfillment(of: [failureExpectation], timeout: 10.0)
        failureObserver.cancel()
        
        // Verify failure state
        let failedFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        XCTAssertTrue(failedFile.status.isFinished && !failedFile.status.isSuccessful)
        
        // Configure mock to succeed on retry
        mockFFmpegService.shouldSucceed = true
        mockFFmpegService.mockError = nil
        
        // Retry compression
        await mainViewModel.retryCompression(forFileId: fileId)
        
        // Wait for success
        let successExpectation = XCTestExpectation(description: "Compression success")
        
        let successObserver = await mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isSuccessful {
                    successExpectation.fulfill()
                }
            }
        
        await fulfillment(of: [successExpectation], timeout: 10.0)
        successObserver.cancel()
        
        // Verify success state
        let successFile = await mainViewModel.videoFiles.first { $0.id == fileId }!
        XCTAssertTrue(successFile.status.isSuccessful)
        XCTAssertEqual(successFile.compressionProgress, 1.0)
    }
    
    /// Test complete workflow with file deletion after compression
    func testWorkflowWithFileDeletion() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // Configure settings to delete originals
        mockSettingsService.settings.deleteOriginals = true
        
        // Add and compress file
        await mainViewModel.addFiles([testVideoURL])
        let fileId = await mainViewModel.videoFiles[0].id
        
        await mainViewModel.compressFile(withId: fileId)
        
        // Wait for completion
        let expectation = XCTestExpectation(description: "Compression with deletion")
        
        let statusObserver = mainViewModel.$videoFiles
            .sink { files in
                if let file = files.first(where: { $0.id == fileId }),
                   file.status.isFinished {
                    expectation.fulfill()
                }
            }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        statusObserver.cancel()
        
        // Verify file was marked for deletion
        XCTAssertTrue(mockFileManagerService.deletedFiles.contains(testVideoURL))
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        for i in 0..<5 {
            let videoURL = tempDir.appendingPathComponent("test_video_\(i).mp4")
            
            // Create empty test files (mock service will handle the "compression")
            try Data().write(to: videoURL)
            testVideoURLs.append(videoURL)
        }
    }
}

// MARK: - Supporting Extensions

import Combine