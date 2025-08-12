import Foundation

/// Configuration settings for video compression
struct CompressionSettings: Codable, Equatable {
    /// Constant Rate Factor (CRF) value for quality control (18-28)
    var crf: Int = 23
    
    /// Video codec to use for compression
    var codec: VideoCodec = .h264
    
    /// Whether to delete original files after successful compression
    var deleteOriginals: Bool = false
    
    /// Whether to copy audio without re-encoding (true) or encode to AAC 128kbps (false)
    var copyAudio: Bool = true
    
    /// Whether to automatically close the application after all tasks complete
    var autoCloseApp: Bool = false
    
    /// Whether to show the application in the Dock
    var showInDock: Bool = true
    
    /// Whether to show the application in the menu bar
    var showInMenuBar: Bool = true
    
    /// Whether to use hardware acceleration when available
    var useHardwareAcceleration: Bool = true
    
    /// Initialize with default settings
    init() {}
    
    /// Initialize with custom settings
    init(
        crf: Int = 23,
        codec: VideoCodec = .h264,
        deleteOriginals: Bool = false,
        copyAudio: Bool = true,
        autoCloseApp: Bool = false,
        showInDock: Bool = true,
        showInMenuBar: Bool = true,
        useHardwareAcceleration: Bool = true
    ) {
        self.crf = Self.clampCRF(crf, for: codec)
        self.codec = codec
        self.deleteOriginals = deleteOriginals
        self.copyAudio = copyAudio
        self.autoCloseApp = autoCloseApp
        self.showInDock = showInDock
        self.showInMenuBar = showInMenuBar
        self.useHardwareAcceleration = useHardwareAcceleration
    }
    
    /// Clamp CRF value to valid range for the given codec
    private static func clampCRF(_ crf: Int, for codec: VideoCodec) -> Int {
        let range = codec.recommendedCRFRange
        return max(range.lowerBound, min(range.upperBound, crf))
    }
    
    /// Update CRF value with validation
    mutating func setCRF(_ newCRF: Int) {
        self.crf = Self.clampCRF(newCRF, for: codec)
    }
    
    /// Update codec and adjust CRF if necessary
    mutating func setCodec(_ newCodec: VideoCodec) {
        self.codec = newCodec
        self.crf = Self.clampCRF(self.crf, for: newCodec)
    }
}

// MARK: - CompressionSettings Extensions

extension CompressionSettings {
    /// Default settings instance
    static let `default` = CompressionSettings()
    
    /// Validate all settings and return any issues
    var validationErrors: [String] {
        var errors: [String] = []
        
        let crfRange = codec.recommendedCRFRange
        if !crfRange.contains(crf) {
            errors.append("CRF значение \(crf) вне рекомендуемого диапазона \(crfRange) для кодека \(codec.shortName)")
        }
        
        if !showInDock && !showInMenuBar {
            errors.append("Приложение должно отображаться либо в Dock, либо в меню-баре")
        }
        
        return errors
    }
    
    /// Whether the current settings are valid
    var isValid: Bool {
        return validationErrors.isEmpty
    }
    
    /// Reset all settings to default values
    mutating func resetToDefaults() {
        self = CompressionSettings.default
    }
    
    /// Get FFmpeg audio codec parameters based on copyAudio setting
    var audioCodecParameters: [String] {
        if copyAudio {
            return ["-c:a", "copy"]
        } else {
            return ["-c:a", "aac", "-b:a", "128k"]
        }
    }
    
    /// Get FFmpeg video codec parameters based on current settings
    var videoCodecParameters: [String] {
        var params: [String] = []
        
        if useHardwareAcceleration, let hwEncoder = codec.hardwareEncoder {
            params.append(contentsOf: ["-c:v", hwEncoder])
        } else {
            params.append(contentsOf: ["-c:v", codec.ffmpegValue])
        }
        
        params.append(contentsOf: ["-crf", String(crf)])
        
        return params
    }
    
    /// Get complete FFmpeg parameters for compression
    var ffmpegParameters: [String] {
        var params: [String] = []
        
        // Video codec parameters
        params.append(contentsOf: videoCodecParameters)
        
        // Audio codec parameters
        params.append(contentsOf: audioCodecParameters)
        
        // Additional quality settings
        params.append(contentsOf: ["-preset", "medium"])
        
        return params
    }
}