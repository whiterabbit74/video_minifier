import Foundation

/// Represents a video file in the compression queue
struct VideoFile: Identifiable, Codable {
    /// Unique identifier for the video file
    let id: UUID

    /// Original URL path to the video file (used for reprocessing/deletion)
    let originalURL: URL

    /// Current URL used for interactions (may point to the compressed file)
    var url: URL

    /// Display name of the file
    var name: String
    
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
        case id, url, name, duration, originalSize, compressedSize, compressionProgress, status, originalURL
    }
    
    /// Initialize a new VideoFile
    init(url: URL, name: String, duration: TimeInterval, originalSize: Int64) {
        self.id = UUID()
        self.originalURL = url
        self.url = url
        self.name = name
        self.duration = duration
        self.originalSize = originalSize
    }
}

// MARK: - Codable

extension VideoFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode ID, or generate new one for backward compatibility
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        let decodedURL = try container.decode(URL.self, forKey: .url)

        self.url = decodedURL
        self.originalURL = try container.decodeIfPresent(URL.self, forKey: .originalURL) ?? decodedURL
        self.name = try container.decode(String.self, forKey: .name)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
        self.originalSize = try container.decode(Int64.self, forKey: .originalSize)
        self.compressedSize = try container.decodeIfPresent(Int64.self, forKey: .compressedSize)
        self.compressionProgress = try container.decodeIfPresent(Double.self, forKey: .compressionProgress) ?? 0.0
        self.status = try container.decodeIfPresent(CompressionStatus.self, forKey: .status) ?? .pending
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(originalURL, forKey: .originalURL)
        try container.encode(name, forKey: .name)
        try container.encode(duration, forKey: .duration)
        try container.encode(originalSize, forKey: .originalSize)
        try container.encodeIfPresent(compressedSize, forKey: .compressedSize)
        try container.encode(compressionProgress, forKey: .compressionProgress)
        try container.encode(status, forKey: .status)
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