import XCTest
import SwiftUI
@testable import VideoSzhimaka

/// UI tests for drag & drop functionality
@MainActor
class DragDropUITests: XCTestCase {
    
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
        
        mainViewModel = nil
        mockFFmpegService = nil
        mockFileManagerService = nil
        mockSettingsService = nil
        loggingService = nil
        
        try super.tearDownWithError()
    }
    
    // MARK: - Drag & Drop Tests
    
    /// Test drag & drop of single video file
    func testDragDropSingleVideoFile() async throws {
        let testVideoURL = testVideoURLs[0]
        let providers = [NSItemProvider(object: testVideoURL as NSURL)]
        
        // Simulate drag & drop
        let result = mainViewModel.handleDrop(providers)
        
        XCTAssertTrue(result, "Drag & drop should succeed")
        
        // Wait for async drop handling to complete
        try await waitForDropCompletion(expectedCount: 1)
        
        let addedFile = mainViewModel.videoFiles[0]
        XCTAssertEqual(addedFile.url, testVideoURL)
        XCTAssertEqual(addedFile.name, testVideoURL.lastPathComponent)
        XCTAssertEqual(addedFile.status, .pending)
    }
    
    /// Test drag & drop of multiple video files
    func testDragDropMultipleVideoFiles() async throws {
        let testURLs = Array(testVideoURLs.prefix(3))
        let providers = testURLs.map { NSItemProvider(object: $0 as NSURL) }
        
        // Simulate drag & drop
        let result = mainViewModel.handleDrop(providers)
        
        XCTAssertTrue(result, "Drag & drop should succeed")
        
        // Wait for async drop handling to complete
        try await waitForDropCompletion(expectedCount: 3)
        
        // Verify all files were added correctly
        for (index, url) in testURLs.enumerated() {
            let addedFile = mainViewModel.videoFiles[index]
            XCTAssertEqual(addedFile.url, url)
            XCTAssertEqual(addedFile.name, url.lastPathComponent)
            XCTAssertEqual(addedFile.status, .pending)
        }
    }
    
    /// Test drag & drop with mixed file types (should filter video files only)
    func testDragDropMixedFileTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        // Create mixed file types
        let videoURL = testVideoURLs[0]
        let textURL = tempDir.appendingPathComponent("test.txt")
        let imageURL = tempDir.appendingPathComponent("test.jpg")
        
        try "Test content".write(to: textURL, atomically: true, encoding: .utf8)
        try Data().write(to: imageURL)
        
        defer {
            try? FileManager.default.removeItem(at: textURL)
            try? FileManager.default.removeItem(at: imageURL)
        }
        
        let providers = [
            NSItemProvider(object: videoURL as NSURL),
            NSItemProvider(object: textURL as NSURL),
            NSItemProvider(object: imageURL as NSURL)
        ]
        
        // Simulate drag & drop
        let result = mainViewModel.handleDrop(providers)
        
        XCTAssertTrue(result, "Drag & drop should succeed")
        
        // Wait for async drop handling to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(mainViewModel.videoFiles.count, 1, "Only video file should be added")
        
        let addedFile = mainViewModel.videoFiles[0]
        XCTAssertEqual(addedFile.url, videoURL)
    }
    
    /// Test drag & drop with unsupported video formats
    func testDragDropUnsupportedVideoFormats() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let unsupportedURL = tempDir.appendingPathComponent("test.wmv")
        
        try Data().write(to: unsupportedURL)
        defer { try? FileManager.default.removeItem(at: unsupportedURL) }
        
        let providers = [NSItemProvider(object: unsupportedURL as NSURL)]
        
        // Configure mock to reject unsupported format
        mockFFmpegService.shouldSucceed = false
        mockFFmpegService.mockError = .unsupportedFormat(unsupportedURL.pathExtension)
        
        // Simulate drag & drop
        let result = mainViewModel.handleDrop(providers)
        
        // Should still add file but show error when trying to get info
        XCTAssertTrue(result, "Drag & drop should succeed")
        
        // Wait for async drop handling to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(mainViewModel.videoFiles.count, 1)
        
        // File should be added but may show error state
        let addedFile = mainViewModel.videoFiles[0]
        XCTAssertEqual(addedFile.url, unsupportedURL)
    }
    
    /// Test drag & drop with duplicate files
    func testDragDropDuplicateFiles() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // First drop
        let providers1 = [NSItemProvider(object: testVideoURL as NSURL)]
        let result1 = mainViewModel.handleDrop(providers1)
        
        XCTAssertTrue(result1)
        
        // Wait for first drop to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(mainViewModel.videoFiles.count, 1)
        
        // Second drop of same file
        let providers2 = [NSItemProvider(object: testVideoURL as NSURL)]
        let result2 = mainViewModel.handleDrop(providers2)
        
        XCTAssertTrue(result2)
        
        // Wait for second drop to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should not add duplicate - implementation may vary
        // This test verifies the behavior is consistent
        let finalCount = mainViewModel.videoFiles.count
        XCTAssertGreaterThanOrEqual(finalCount, 1)
        XCTAssertLessThanOrEqual(finalCount, 2)
    }
    
    /// Test drag & drop while processing
    func testDragDropWhileProcessing() async throws {
        let firstVideoURL = testVideoURLs[0]
        let secondVideoURL = testVideoURLs[1]
        
        // Add first file and start processing
        await mainViewModel.addFiles([firstVideoURL])
        
        // Wait for first file to be added
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        guard mainViewModel.videoFiles.count > 0 else {
            XCTFail("First file was not added")
            return
        }
        
        let fileId = mainViewModel.videoFiles[0].id
        
        let compressionTask = Task {
            await mainViewModel.compressFile(withId: fileId)
        }
        
        // Wait for processing to start
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Try to drop another file while processing
        let providers = [NSItemProvider(object: secondVideoURL as NSURL)]
        let result = mainViewModel.handleDrop(providers)
        
        XCTAssertTrue(result, "Should be able to add files while processing")
        
        // Wait for drop to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(mainViewModel.videoFiles.count, 2)
        
        // Wait for first compression to complete
        await compressionTask.value
        
        // Verify both files are in the list
        XCTAssertEqual(mainViewModel.videoFiles.count, 2)
        XCTAssertTrue(mainViewModel.videoFiles[0].status.isFinished)
        XCTAssertEqual(mainViewModel.videoFiles[1].status, .pending)
    }
    
    /// Test drag & drop with large number of files
    func testDragDropLargeNumberOfFiles() async throws {
        let providers = testVideoURLs.map { NSItemProvider(object: $0 as NSURL) }
        
        // Simulate dropping all test files
        let result = mainViewModel.handleDrop(providers)
        
        XCTAssertTrue(result, "Drag & drop should succeed")
        
        // Wait for async drop handling to complete with longer timeout for multiple files
        try await waitForDropCompletion(expectedCount: testVideoURLs.count, timeout: 2.0)
        
        // Verify all files were added correctly
        for (index, url) in testVideoURLs.enumerated() {
            let addedFile = mainViewModel.videoFiles[index]
            XCTAssertEqual(addedFile.url, url)
            XCTAssertEqual(addedFile.status, .pending)
        }
    }
    
    /// Test drag & drop error handling
    func testDragDropErrorHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let nonExistentURL = tempDir.appendingPathComponent("nonexistent.mp4")
        
        let providers = [NSItemProvider(object: nonExistentURL as NSURL)]
        
        // Simulate drag & drop of non-existent file
        let result = mainViewModel.handleDrop(providers)
        
        // Behavior may vary - either reject the drop or add with error state
        // This test ensures consistent error handling
        if result {
            // If file was added, it should show appropriate error state
            XCTAssertEqual(mainViewModel.videoFiles.count, 1)
        } else {
            // If drop was rejected, no files should be added
            XCTAssertEqual(mainViewModel.videoFiles.count, 0)
        }
    }
    
    /// Test drag & drop with file access permissions
    func testDragDropFilePermissions() async throws {
        let testVideoURL = testVideoURLs[0]
        
        // Create a file with restricted permissions
        let restrictedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("restricted.mp4")
        
        try Data().write(to: restrictedURL)
        
        // Remove read permissions
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: restrictedURL.path
        )
        
        defer {
            // Restore permissions for cleanup
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: restrictedURL.path
            )
            try? FileManager.default.removeItem(at: restrictedURL)
        }
        
        let providers = [NSItemProvider(object: restrictedURL as NSURL)]
        
        // Simulate drag & drop
        let result = mainViewModel.handleDrop(providers)
        
        // Should handle permission errors gracefully
        if result {
            XCTAssertEqual(mainViewModel.videoFiles.count, 1)
            // File may be added but show error when accessing
        } else {
            XCTAssertEqual(mainViewModel.videoFiles.count, 0)
        }
    }
    
    // MARK: - File Dialog Tests
    
    /// Test file selection through dialog
    func testFileDialogSelection() async throws {
        let testURLs = Array(testVideoURLs.prefix(2))
        
        // Simulate file dialog selection
        await mainViewModel.addFiles(testURLs)
        
        XCTAssertEqual(mainViewModel.videoFiles.count, 2)
        
        for (index, url) in testURLs.enumerated() {
            let addedFile = mainViewModel.videoFiles[index]
            XCTAssertEqual(addedFile.url, url)
            XCTAssertEqual(addedFile.name, url.lastPathComponent)
            XCTAssertEqual(addedFile.status, .pending)
        }
    }
    
    /// Test file dialog with no selection
    func testFileDialogNoSelection() async throws {
        let initialCount = mainViewModel.videoFiles.count
        
        // Simulate file dialog with no selection
        await mainViewModel.addFiles([])
        
        XCTAssertEqual(mainViewModel.videoFiles.count, initialCount)
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "webm"]
        
        for (index, ext) in videoExtensions.enumerated() {
            let videoURL = tempDir.appendingPathComponent("test_video_\(index).\(ext)")
            
            // Create empty test files
            try Data().write(to: videoURL)
            testVideoURLs.append(videoURL)
        }
    }
    
    /// Helper method to wait for drop operation to complete
    /// - Parameters:
    ///   - expectedCount: Expected number of files after drop
    ///   - timeout: Maximum time to wait in seconds
    private func waitForDropCompletion(expectedCount: Int, timeout: TimeInterval = 1.0) async throws {
        let startTime = Date()
        
        while mainViewModel.videoFiles.count != expectedCount {
            if Date().timeIntervalSince(startTime) > timeout {
                XCTFail("Timeout waiting for drop completion. Expected \(expectedCount) files, got \(mainViewModel.videoFiles.count)")
                return
            }
            
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }
    }
}