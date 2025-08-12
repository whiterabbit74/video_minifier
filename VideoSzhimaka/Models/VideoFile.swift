import Foundation

/// Represents a video file in the compression queue
struct VideoFile: Identifiable, Codable {
    /// Unique identifier for the video file
    let id = UUID()
    
    /// URL path to the video file
    let url: URL
    
    /// Display name of the file
    let name: String
    
    /// Duration of the video in seconds
    var duration: TimeInterval
    
    /// Original file size in bytes
    let originalSize: Int64
    
    /// Compressed file size in bytes (nil if not yet compressed)
    var compressedSize: Int64?
    
    /// Current compression progress (0.0 to 1.0)
    var compressionProgress: Double = 0.0
    
    /// Current status of the compression process
    var status: CompressionStatus = .pending
    
    /// Custom coding keys to handle UUID serialization
    private enum CodingKeys: String, CodingKey {
        case url, name, duration, originalSize, compressedSize, compressionProgress, status
    }
    
    /// Initialize a new VideoFile
    init(url: URL, name: String, duration: TimeInterval, originalSize: Int64) {
        self.url = url
        self.name = name
        self.duration = duration
        self.originalSize = originalSize
    }
}

// MARK: - VideoFile Extensions

extension VideoFile {
    /// Formatted duration string (e.g., "1:23" or "12:34")
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Formatted original file size string
    var formattedOriginalSize: String {
        return ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
    }
    
    /// Formatted compressed file size string
    var formattedCompressedSize: String {
        guard let compressedSize = compressedSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: compressedSize, countStyle: .file)
    }
    
    /// Compression ratio as percentage (nil if not yet compressed)
    var compressionRatio: Double? {
        guard let compressedSize = compressedSize, originalSize > 0 else { return nil }
        return (1.0 - Double(compressedSize) / Double(originalSize)) * 100.0
    }
    
    /// Formatted compression ratio string
    var formattedCompressionRatio: String {
        guard let ratio = compressionRatio else { return "—" }
        return String(format: "%.1f%%", ratio)
    }
    
    /// Whether the compressed file is larger than the original
    var isCompressedLarger: Bool {
        guard let compressedSize = compressedSize else { return false }
        return compressedSize > originalSize
    }
}