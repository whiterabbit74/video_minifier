import XCTest
import Foundation
@testable import VideoSzhimaka

@MainActor
final class FileManagerServiceTests: XCTestCase {
    
    var fileManagerService: FileManagerService!
    var tempDirectory: URL!
    var mockFileManager: MockFileManager!
    var mockWorkspace: MockWorkspace!
    
    @MainActor override func setUp() {
        super.setUp()
        
        // Create temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoSzhimakaTests")
            .appendingPathComponent(UUID().uuidString)
        
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create mock objects
        mockFileManager = MockFileManager()
        mockWorkspace = MockWorkspace()
        
        // Initialize service with mocks
        fileManagerService = FileManagerService(fileManager: mockFileManager, workspace: mockWorkspace)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        fileManagerService = nil
        tempDirectory = nil
        mockFileManager = nil
        mockWorkspace = nil
        
        super.tearDown()
    }
    
    // MARK: - generateOutputURL Tests
    
    func testGenerateOutputURL_WithNonExistingFile_ReturnsBaseURL() {
        // Given
        let inputURL = tempDirectory.appendingPathComponent("video.mp4")
        let expectedURL = tempDirectory.appendingPathComponent("video_compressed.mp4")
        
        mockFileManager.fileExistsResult = false
        
        // When
        let result = fileManagerService.generateOutputURL(for: inputURL)
        
        // Then
        XCTAssertEqual(result, expectedURL)
    }
    
    func testGenerateOutputURL_WithExistingFile_ReturnsUniqueURL() {
        // Given
        let inputURL = tempDirectory.appendingPathComponent("video.mp4")
        let baseURL = tempDirectory.appendingPathComponent("video_compressed.mp4")
        let expectedURL = tempDirectory.appendingPathComponent("video_compressed (1).mp4")
        
        mockFileManager.fileExistsResults = [
            baseURL.path: true,  // Base file exists
            expectedURL.path: false  // First alternative doesn't exist
        ]
        
        // When
        let result = fileManagerService.generateOutputURL(for: inputURL)
        
        // Then
        XCTAssertEqual(result, expectedURL)
    }
    
    func testGenerateOutputURL_WithMultipleExistingFiles_ReturnsCorrectSuffix() {
        // Given
        let inputURL = tempDirectory.appendingPathComponent("video.mp4")
        let baseURL = tempDirectory.appendingPathComponent("video_compressed.mp4")
        let firstAlternative = tempDirectory.appendingPathComponent("video_compressed (1).mp4")
        let secondAlternative = tempDirectory.appendingPathComponent("video_compressed (2).mp4")
        let expectedURL = tempDirectory.appendingPathComponent("video_compressed (3).mp4")
        
        mockFileManager.fileExistsResults = [
            baseURL.path: true,
            firstAlternative.path: true,
            secondAlternative.path: true,
            expectedURL.path: false
        ]
        
        // When
        let result = fileManagerService.generateOutputURL(for: inputURL)
        
        // Then
        XCTAssertEqual(result, expectedURL)
    }
    
    func testGenerateOutputURL_WithDifferentExtensions_PreservesMP4Extension() {
        // Given
        let inputURL = tempDirectory.appendingPathComponent("video.mov")
        let expectedURL = tempDirectory.appendingPathComponent("video_compressed.mp4")
        
        mockFileManager.fileExistsResult = false
        
        // When
        let result = fileManagerService.generateOutputURL(for: inputURL)
        
        // Then
        XCTAssertEqual(result, expectedURL)
        XCTAssertEqual(result.pathExtension, "mp4")
    }
    
    // MARK: - deleteFile Tests
    
    func testDeleteFile_WithExistingFile_DeletesSuccessfully() throws {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        mockFileManager.fileExistsResult = true
        mockFileManager.removeItemShouldSucceed = true
        
        // When & Then
        XCTAssertNoThrow(try fileManagerService.deleteFile(at: fileURL))
        XCTAssertTrue(mockFileManager.removeItemCalled)
        XCTAssertEqual(mockFileManager.removeItemURL, fileURL)
    }
    
    func testDeleteFile_WithNonExistingFile_ThrowsFileNotFoundError() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        mockFileManager.fileExistsResult = false
        
        // When & Then
        XCTAssertThrowsError(try fileManagerService.deleteFile(at: fileURL)) { error in
            guard case FileManagerError.fileNotFound(let url) = error else {
                XCTFail("Expected FileManagerError.fileNotFound, got \(error)")
                return
            }
            XCTAssertEqual(url, fileURL)
        }
    }
    
    func testDeleteFile_WithDeletionFailure_ThrowsDeletionFailedError() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: nil)
        
        mockFileManager.fileExistsResult = true
        mockFileManager.removeItemShouldSucceed = false
        mockFileManager.removeItemError = underlyingError
        
        // When & Then
        XCTAssertThrowsError(try fileManagerService.deleteFile(at: fileURL)) { error in
            guard case FileManagerError.deletionFailed(let url, let innerError) = error else {
                XCTFail("Expected FileManagerError.deletionFailed, got \(error)")
                return
            }
            XCTAssertEqual(url, fileURL)
            XCTAssertEqual(innerError as NSError, underlyingError)
        }
    }
    
    // MARK: - openInFinder Tests
    
    func testOpenInFinder_WithExistingFile_SelectsFileInFinder() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        mockFileManager.fileExistsResult = true
        
        // When
        fileManagerService.openInFinder(url: fileURL)
        
        // Then
        XCTAssertTrue(mockWorkspace.selectFileCalled)
        XCTAssertEqual(mockWorkspace.selectFilePath, fileURL.path)
        XCTAssertEqual(mockWorkspace.selectFileRootPath, tempDirectory.path)
    }
    
    func testOpenInFinder_WithNonExistingFile_OpensParentDirectory() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        mockFileManager.fileExistsResults = [
            fileURL.path: false,  // File doesn't exist
            tempDirectory.path: true  // Parent directory exists
        ]
        
        // Reset workspace mock state
        mockWorkspace.openCalled = false
        mockWorkspace.openURL = nil
        mockWorkspace.selectFileCalled = false
        
        // When
        fileManagerService.openInFinder(url: fileURL)
        
        // Then
        XCTAssertTrue(mockWorkspace.openCalled, "Expected workspace.open to be called")
        XCTAssertEqual(mockWorkspace.openURL, tempDirectory)
        XCTAssertFalse(mockWorkspace.selectFileCalled, "Expected selectFile NOT to be called")
    }
    
    // MARK: - getFileSize Tests
    
    func testGetFileSize_WithExistingFile_ReturnsCorrectSize() throws {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        let expectedSize: Int64 = 1024
        
        mockFileManager.fileExistsResult = true
        mockFileManager.fileAttributes = [.size: expectedSize]
        
        // When
        let result = try fileManagerService.getFileSize(url: fileURL)
        
        // Then
        XCTAssertEqual(result, expectedSize)
    }
    
    func testGetFileSize_WithNonExistingFile_ThrowsFileNotFoundError() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        mockFileManager.fileExistsResult = false
        
        // When & Then
        XCTAssertThrowsError(try fileManagerService.getFileSize(url: fileURL)) { error in
            guard case FileManagerError.fileNotFound(let url) = error else {
                XCTFail("Expected FileManagerError.fileNotFound, got \(error)")
                return
            }
            XCTAssertEqual(url, fileURL)
        }
    }
    
    func testGetFileSize_WithAttributesError_ThrowsSizeCalculationFailedError() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: nil)
        
        mockFileManager.fileExistsResult = true
        mockFileManager.attributesError = underlyingError
        
        // When & Then
        XCTAssertThrowsError(try fileManagerService.getFileSize(url: fileURL)) { error in
            guard case FileManagerError.sizeCalculationFailed(let url, let innerError) = error else {
                XCTFail("Expected FileManagerError.sizeCalculationFailed, got \(error)")
                return
            }
            XCTAssertEqual(url, fileURL)
            XCTAssertEqual(innerError as NSError, underlyingError)
        }
    }
    
    // MARK: - fileExists Tests
    
    func testFileExists_WithExistingFile_ReturnsTrue() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        mockFileManager.fileExistsResult = true
        
        // When
        let result = fileManagerService.fileExists(at: fileURL)
        
        // Then
        XCTAssertTrue(result)
    }
    
    func testFileExists_WithNonExistingFile_ReturnsFalse() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        mockFileManager.fileExistsResult = false
        
        // When
        let result = fileManagerService.fileExists(at: fileURL)
        
        // Then
        XCTAssertFalse(result)
    }
    
    // MARK: - Extension Tests
    
    func testGetFormattedFileSize_WithValidFile_ReturnsFormattedString() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("test.mp4")
        mockFileManager.fileExistsResult = true
        mockFileManager.fileAttributes = [.size: Int64(1024)]
        
        // When
        let result = fileManagerService.getFormattedFileSize(url: fileURL)
        
        // Then
        XCTAssertNotEqual(result, "—")
        XCTAssertTrue(result.contains("KB") || result.contains("bytes"))
    }
    
    func testGetFormattedFileSize_WithInvalidFile_ReturnsPlaceholder() {
        // Given
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        mockFileManager.fileExistsResult = false
        
        // When
        let result = fileManagerService.getFormattedFileSize(url: fileURL)
        
        // Then
        XCTAssertEqual(result, "—")
    }
    
    func testIsVideoFile_WithVideoExtensions_ReturnsTrue() {
        // Given
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp"]
        
        for ext in videoExtensions {
            // When
            let url = tempDirectory.appendingPathComponent("video.\(ext)")
            let result = fileManagerService.isVideoFile(url: url)
            
            // Then
            XCTAssertTrue(result, "Extension \(ext) should be recognized as video")
        }
    }
    
    func testIsVideoFile_WithNonVideoExtensions_ReturnsFalse() {
        // Given
        let nonVideoExtensions = ["txt", "pdf", "jpg", "png", "doc", "zip"]
        
        for ext in nonVideoExtensions {
            // When
            let url = tempDirectory.appendingPathComponent("file.\(ext)")
            let result = fileManagerService.isVideoFile(url: url)
            
            // Then
            XCTAssertFalse(result, "Extension \(ext) should not be recognized as video")
        }
    }
    
    func testGetDownloadsDirectory_ReturnsValidURL() {
        // When
        let result = fileManagerService.getDownloadsDirectory()
        
        // Then
        XCTAssertTrue(result.path.contains("Downloads"))
    }
}

// MARK: - Mock Classes

class MockFileManager: FileManager {
    var fileExistsResult = false
    var fileExistsResults: [String: Bool] = [:]
    var removeItemCalled = false
    var removeItemURL: URL?
    var removeItemShouldSucceed = true
    var removeItemError: Error?
    var fileAttributes: [FileAttributeKey: Any] = [:]
    var attributesError: Error?
    
    override func fileExists(atPath path: String) -> Bool {
        if let result = fileExistsResults[path] {
            return result
        }
        return fileExistsResult
    }
    
    override func removeItem(at URL: URL) throws {
        removeItemCalled = true
        removeItemURL = URL
        
        if !removeItemShouldSucceed {
            throw removeItemError ?? NSError(domain: "MockError", code: 1, userInfo: nil)
        }
    }
    
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        if let error = attributesError {
            throw error
        }
        return fileAttributes
    }
}

class MockWorkspace: NSWorkspace {
    var selectFileCalled = false
    var selectFilePath: String?
    var selectFileRootPath: String?
    var openCalled = false
    var openURL: URL?
    
    override func selectFile(_ fullPath: String?, inFileViewerRootedAtPath rootFullPath: String) -> Bool {
        selectFileCalled = true
        selectFilePath = fullPath
        selectFileRootPath = rootFullPath
        return true
    }
    
    override func open(_ url: URL) -> Bool {
        openCalled = true
        openURL = url
        return true
    }
}