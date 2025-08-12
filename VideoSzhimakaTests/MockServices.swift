import Foundation
import SwiftUI
import XCTest
@testable import VideoSzhimaka

// MARK: - Mock FFmpeg Service

class MockFFmpegService: FFmpegServiceProtocol {
    var shouldSucceed = true
    var mockError: VideoCompressionError?
    var compressionError: VideoCompressionError?
    var shouldFailOnFile: URL?
    var videoInfoResult: Result<VideoInfo, Error>?
    var compressionResult: Result<Void, Error>?
    var shouldFailCompression = false
    var failOnlyFirstFile = false
    var failOnlyFirstAttempt = false
    var mockVideoInfo = VideoInfo(
        duration: 120.0,
        width: 1920,
        height: 1080,
        frameRate: 30.0,
        bitrate: 5000000,
        hasAudio: true,
        audioCodec: "aac",
        videoCodec: "h264"
    )
    
    var compressionCallCount = 0
    var getVideoInfoCallCount = 0
    var cancelCallCount = 0
    var cancelCurrentOperationCalled = false
    private var compressionAttempts = 0
    private var fileCompressionCounts: [URL: Int] = [:]
    
    func getVideoInfo(url: URL) async throws -> VideoInfo {
        getVideoInfoCallCount += 1
        
        // Use videoInfoResult if set
        if let result = videoInfoResult {
            switch result {
            case .success(let info):
                return info
            case .failure(let error):
                throw error
            }
        }
        
        if let error = mockError ?? compressionError {
            throw error
        }
        
        return mockVideoInfo
    }
    
    func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        compressionCallCount += 1
        compressionAttempts += 1
        fileCompressionCounts[input, default: 0] += 1
        
        // Use compressionResult if set
        if let result = compressionResult {
            switch result {
            case .success:
                // Simulate progress updates
                for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                    progressHandler(progress)
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }
                // Create mock output file
                try "mock compressed video".write(to: output, atomically: true, encoding: .utf8)
                return
            case .failure(let error):
                throw error
            }
        }
        
        // Handle different failure scenarios
        if shouldFailCompression {
            if failOnlyFirstFile && compressionAttempts > 1 {
                // Succeed on second and subsequent files
            } else if failOnlyFirstAttempt && fileCompressionCounts[input, default: 0] > 1 {
                // Succeed on retry attempts
            } else {
                // Fail with the configured error
                throw compressionError ?? VideoCompressionError.compressionFailed("Mock compression failure")
            }
        }
        
        // Check if this specific file should fail
        if let failFile = shouldFailOnFile, failFile == input {
            throw compressionError ?? VideoCompressionError.compressionFailed("Mock file-specific failure")
        }
        
        if let error = mockError ?? compressionError {
            throw error
        }
        
        if !shouldSucceed {
            throw compressionError ?? VideoCompressionError.compressionFailed("Mock compression failure")
        }
        
        // Simulate progress updates
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            progressHandler(progress)
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Create mock output file
        try "mock compressed video".write(to: output, atomically: true, encoding: .utf8)
    }
    
    func cancelCurrentOperation() {
        cancelCallCount += 1
        cancelCurrentOperationCalled = true
    }
    
    func getQuickVideoInfo(url: URL) async throws -> VideoInfo {
        // For mock purposes, return the same as getVideoInfo
        return try await getVideoInfo(url: url)
    }
    
    func clearMetadataCache() {
        // Mock implementation - no-op
    }
    
    func reset() {
        shouldSucceed = true
        mockError = nil
        compressionError = nil
        shouldFailOnFile = nil
        videoInfoResult = nil
        compressionResult = nil
        shouldFailCompression = false
        failOnlyFirstFile = false
        failOnlyFirstAttempt = false
        compressionCallCount = 0
        getVideoInfoCallCount = 0
        cancelCallCount = 0
        cancelCurrentOperationCalled = false
        compressionAttempts = 0
        fileCompressionCounts.removeAll()
    }
}

// MARK: - Mock File Manager Service

class MockFileManagerService: FileManagerServiceProtocol {
    var generateOutputURLResult: URL = URL(fileURLWithPath: "/test/output.mp4")
    var fileSizeResult: Result<Int64, Error> = .success(1024 * 1024) // 1MB
    var fileSizeResults: [URL: Result<Int64, Error>] = [:]
    var deleteFileResult: Result<Void, Error> = .success(())
    var fileExistsResult = true
    var fileExistsResults: [String: Bool] = [:]
    var openInFinderCallCount = 0
    var deletedFiles: [URL] = []
    var openedInFinderURLs: [URL] = []
    
    func generateOutputURL(for inputURL: URL) -> URL {
        return generateOutputURLResult
    }
    
    func getFileSize(url: URL) throws -> Int64 {
        // Use specific result for URL if available
        if let specificResult = fileSizeResults[url] {
            switch specificResult {
            case .success(let size):
                return size
            case .failure(let error):
                throw error
            }
        }
        
        // Fall back to general result
        switch fileSizeResult {
        case .success(let size):
            return size
        case .failure(let error):
            throw error
        }
    }
    
    func deleteFile(at url: URL) throws {
        switch deleteFileResult {
        case .success:
            deletedFiles.append(url)
        case .failure(let error):
            throw error
        }
    }
    
    func openInFinder(url: URL) {
        openInFinderCallCount += 1
        openedInFinderURLs.append(url)
    }
    
    func fileExists(at url: URL) -> Bool {
        if let result = fileExistsResults[url.path] {
            return result
        }
        return fileExistsResult
    }
}

// MARK: - Mock Settings Service

class MockSettingsService: SettingsServiceProtocol, ObservableObject {
    @Published var settings = CompressionSettings()
    
    var resetCallCount = 0
    var saveWindowFrameCallCount = 0
    var loadWindowFrameCallCount = 0
    var savedWindowFrame: CGRect?
    
    func resetToDefaults() {
        resetCallCount += 1
        settings = CompressionSettings()
    }
    
    func saveWindowFrame(_ frame: CGRect) {
        saveWindowFrameCallCount += 1
        savedWindowFrame = frame
    }
    
    func loadWindowFrame() -> CGRect? {
        loadWindowFrameCallCount += 1
        return savedWindowFrame
    }
}

// MARK: - Test Utilities

extension XCTestCase {
    /// Helper function to wait for expectations with proper async handling
    func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {
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
    
    /// Create a temporary test video file
    func createTestVideoFile(name: String = "test_video.mp4") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testVideoURL = tempDir.appendingPathComponent(name)
        
        // Create a mock video file with some content
        let mockVideoData = "Mock video file content for testing".data(using: .utf8)!
        try mockVideoData.write(to: testVideoURL)
        
        return testVideoURL
    }
    
    /// Helper function for async assertions with MainActor
    @MainActor
    func asyncAssertEqual<T: Equatable>(_ expression1: @autoclosure () async throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let value1 = try await expression1()
            let value2 = try expression2()
            XCTAssertEqual(value1, value2, message(), file: file, line: line)
        } catch {
            XCTFail("Async assertion failed with error: \(error)", file: file, line: line)
        }
    }
    
    /// Helper function for async boolean assertions with MainActor
    @MainActor
    func asyncAssertTrue(_ expression: @autoclosure () async throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let value = try await expression()
            XCTAssertTrue(value, message(), file: file, line: line)
        } catch {
            XCTFail("Async assertion failed with error: \(error)", file: file, line: line)
        }
    }
    
    /// Helper function for async boolean assertions with MainActor
    @MainActor
    func asyncAssertFalse(_ expression: @autoclosure () async throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let value = try await expression()
            XCTAssertFalse(value, message(), file: file, line: line)
        } catch {
            XCTFail("Async assertion failed with error: \(error)", file: file, line: line)
        }
    }
}