import Foundation

/// Supported video codecs for compression
enum VideoCodec: String, CaseIterable, Codable {
    /// H.264 codec (recommended for compatibility)
    case h264 = "libx264"
    
    /// H.265 codec (more efficient compression)
    case h265 = "libx265"
    
    /// Human-readable display name for the codec
    var displayName: String {
        switch self {
        case .h264:
            return "H.264 (рекомендуется)"
        case .h265:
            return "H.265 (эффективнее)"
        }
    }
    
    /// Detailed description with compatibility information
    var detailedDescription: String {
        switch self {
        case .h264:
            return "Лучшая совместимость, быстрое кодирование. Поддерживается всеми устройствами и плеерами."
        case .h265:
            return "Лучшее сжатие, медленнее кодирование. Поддерживается не на всех устройствах - проверьте совместимость перед использованием."
        }
    }
    
    /// Short name for the codec
    var shortName: String {
        switch self {
        case .h264:
            return "H.264"
        case .h265:
            return "H.265"
        }
    }
    
    /// FFmpeg codec parameter value
    var ffmpegValue: String {
        return self.rawValue
    }
    
    /// Whether this codec supports hardware acceleration on Apple Silicon
    var supportsHardwareAcceleration: Bool {
        switch self {
        case .h264:
            return true  // VideoToolbox supports H.264
        case .h265:
            return true  // VideoToolbox supports H.265
        }
    }
    
    /// Hardware-accelerated encoder name for VideoToolbox (if available)
    var hardwareEncoder: String? {
        switch self {
        case .h264:
            return "h264_videotoolbox"
        case .h265:
            return "hevc_videotoolbox"
        }
    }
    
    /// Recommended CRF range for this codec
    var recommendedCRFRange: ClosedRange<Int> {
        switch self {
        case .h264:
            return 18...28
        case .h265:
            return 20...30  // H.265 typically needs slightly higher CRF for similar quality
        }
    }
    
    /// Default CRF value for this codec
    var defaultCRF: Int {
        switch self {
        case .h264:
            return 23
        case .h265:
            return 25
        }
    }
}