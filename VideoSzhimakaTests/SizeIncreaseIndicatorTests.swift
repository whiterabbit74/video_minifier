import XCTest
@testable import VideoSzhimaka

/// Tests for size increase indicator functionality
final class SizeIncreaseIndicatorTests: XCTestCase {
    
    func testIsCompressedLarger_WhenFileNotCompressed_ReturnsFalse() {
        // Given
        let file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 100_000_000
        )
        
        // When & Then
        XCTAssertFalse(file.isCompressedLarger, "File without compressed size should not be marked as larger")
    }
    
    func testIsCompressedLarger_WhenCompressedSizeSmaller_ReturnsFalse() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 100_000_000
        )
        file.compressedSize = 50_000_000
        
        // When & Then
        XCTAssertFalse(file.isCompressedLarger, "File with smaller compressed size should not be marked as larger")
    }
    
    func testIsCompressedLarger_WhenCompressedSizeEqual_ReturnsFalse() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 100_000_000
        )
        file.compressedSize = 100_000_000
        
        // When & Then
        XCTAssertFalse(file.isCompressedLarger, "File with equal compressed size should not be marked as larger")
    }
    
    func testIsCompressedLarger_WhenCompressedSizeLarger_ReturnsTrue() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 50_000_000
        )
        file.compressedSize = 75_000_000
        
        // When & Then
        XCTAssertTrue(file.isCompressedLarger, "File with larger compressed size should be marked as larger")
    }
    
    func testCompressionRatio_WhenFileIncreased_ReturnsNegativeRatio() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 50_000_000
        )
        file.compressedSize = 75_000_000
        
        // When
        let ratio = file.compressionRatio
        
        // Then
        XCTAssertNotNil(ratio, "Compression ratio should be calculated")
        XCTAssertEqual(ratio!, -50.0, accuracy: 0.1, "Compression ratio should be -50% when file increased by 50%")
    }
    
    func testCompressionRatio_WhenFileDecreased_ReturnsPositiveRatio() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 100_000_000
        )
        file.compressedSize = 50_000_000
        
        // When
        let ratio = file.compressionRatio
        
        // Then
        XCTAssertNotNil(ratio, "Compression ratio should be calculated")
        XCTAssertEqual(ratio!, 50.0, accuracy: 0.1, "Compression ratio should be 50% when file decreased by 50%")
    }
    
    func testCompressionRatio_WhenOriginalSizeZero_ReturnsNil() {
        // Given
        var file = VideoFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            name: "video.mp4",
            duration: 120.0,
            originalSize: 0
        )
        file.compressedSize = 50_000_000
        
        // When
        let ratio = file.compressionRatio
        
        // Then
        XCTAssertNil(ratio, "Compression ratio should be nil when original size is zero")
    }
}