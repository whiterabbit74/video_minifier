import Foundation

/// Application display mode
enum AppDisplayMode: String, CaseIterable, Identifiable, Codable {
    case dockAndMenuBar
    case dockOnly
    case menuBarOnly
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .dockAndMenuBar: return NSLocalizedString("Dock и меню-бар", comment: "")
        case .dockOnly: return NSLocalizedString("Только Dock", comment: "")
        case .menuBarOnly: return NSLocalizedString("Только меню-бар", comment: "")
        }
    }
}

/// Application language
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english
    case russian
    case chineseSimplified // zh-Hans
    case spanish           // es
    case french            // fr
    case german            // de
    case japanese          // ja
    case portuguese        // pt-BR
    case italian           // it
    case korean            // ko
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .system: return NSLocalizedString("Системный", comment: "")
        case .english: return "English"
        case .russian: return "Русский"
        case .chineseSimplified: return "简体中文"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        case .portuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .korean: return "한국어"
        }
    }
    
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .russian: return "ru"
        case .chineseSimplified: return "zh-Hans"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        case .japanese: return "ja"
        case .portuguese: return "pt-BR"
        case .italian: return "it"
        case .korean: return "ko"
        }
    }
}

enum OutputBehavior: String, CaseIterable, Identifiable, Codable {
    case appendCompressedToName
    case subfolderCompressed
    case replaceOriginal
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .appendCompressedToName:
            return NSLocalizedString("Добавить _compressed к имени", comment: "")
        case .subfolderCompressed:
            return NSLocalizedString("Папка compressed", comment: "")
        case .replaceOriginal:
            return NSLocalizedString("Заменить исходный файл", comment: "")
        }
    }
}

/// Configuration settings for video compression
struct CompressionSettings: Codable, Equatable {
    /// Constant Rate Factor (CRF) value for quality control (18-28)
    var crf: Int = 23

    /// High-level quality preset for size/quality balance
    var qualityPreset: QualityPreset = .medium

    /// Rate control mode for video encoding
    var rateControlMode: RateControlMode = .crf

    /// Target video bitrate in kbps (used when rateControlMode == .targetBitrate)
    var targetBitrateKbps: Int = 2000

    /// Target output size in MB (used when rateControlMode == .targetSize)
    var targetSizeMB: Int = 50
    
    /// Video codec to use for compression
    var codec: VideoCodec = .h264
    
    /// Whether to delete original files after successful compression
    var deleteOriginals: Bool = false

    /// Output behavior after compression
    var outputBehavior: OutputBehavior = .appendCompressedToName
    
    /// Whether to copy audio without re-encoding (true) or encode to AAC 128kbps (false)
    var copyAudio: Bool = true

    /// Audio bitrate in kbps when re-encoding audio
    var audioBitrateKbps: Int = 128

    /// Audio channel count when re-encoding audio
    var audioChannels: Int = 2
    
    /// Whether to automatically close the application after all tasks complete
    var autoCloseApp: Bool = false
    
    /// Whether to show the application in the Dock
    var showInDock: Bool = true
    
    /// Whether to show the application in the menu bar
    var showInMenuBar: Bool = true
    
    /// Whether to use hardware acceleration when available
    var useHardwareAcceleration: Bool = true

    /// Encoding speed preset for software encoding
    var encodingSpeed: EncodingSpeed = .medium

    /// Output resolution preset
    var resolutionPreset: ResolutionPreset = .original

    /// Enable custom resize before compression
    var resizeEnabled: Bool = false

    /// Target value for resize in pixels
    var resizeValue: Int = 1920

    /// Resize mode: fit/width/height
    var resizeCondition: ResizeCondition = .fit
    
    /// Application language preference
    var language: AppLanguage = .system
    
    /// Computed display mode helper
    var displayMode: AppDisplayMode {
        get {
            if showInDock && showInMenuBar { return .dockAndMenuBar }
            if showInDock { return .dockOnly }
            if showInMenuBar { return .menuBarOnly }
            return .dockAndMenuBar // Default fallback
        }
        set {
            switch newValue {
            case .dockAndMenuBar:
                showInDock = true
                showInMenuBar = true
            case .dockOnly:
                showInDock = true
                showInMenuBar = false
            case .menuBarOnly:
                showInDock = false
                showInMenuBar = true
            }
        }
    }
    
    /// Initialize with default settings
    init() {}
    
    /// Initialize with custom settings
    init(
        crf: Int = 23,
        qualityPreset: QualityPreset = .medium,
        rateControlMode: RateControlMode = .crf,
        targetBitrateKbps: Int = 2000,
        targetSizeMB: Int = 50,
        codec: VideoCodec = .h264,
        deleteOriginals: Bool = false,
        outputBehavior: OutputBehavior = .appendCompressedToName,
        copyAudio: Bool = true,
        audioBitrateKbps: Int = 128,
        audioChannels: Int = 2,
        autoCloseApp: Bool = false,
        showInDock: Bool = true,
        showInMenuBar: Bool = true,
        useHardwareAcceleration: Bool = true,
        encodingSpeed: EncodingSpeed = .medium,
        resolutionPreset: ResolutionPreset = .original,
        resizeEnabled: Bool = false,
        resizeValue: Int = 1920,
        resizeCondition: ResizeCondition = .fit,
        language: AppLanguage = .system
    ) {
        self.qualityPreset = qualityPreset
        self.rateControlMode = rateControlMode
        self.targetBitrateKbps = max(300, targetBitrateKbps)
        self.targetSizeMB = max(1, targetSizeMB)
        if qualityPreset == .custom {
            self.crf = Self.clampCRF(crf, for: codec)
        } else {
            self.crf = qualityPreset.recommendedCRF(for: codec)
        }
        self.codec = codec
        self.deleteOriginals = deleteOriginals
        self.outputBehavior = outputBehavior
        self.copyAudio = copyAudio
        self.audioBitrateKbps = max(32, audioBitrateKbps)
        self.audioChannels = audioChannels == 1 ? 1 : 2
        self.autoCloseApp = autoCloseApp
        self.showInDock = showInDock
        self.showInMenuBar = showInMenuBar
        self.useHardwareAcceleration = useHardwareAcceleration
        self.encodingSpeed = encodingSpeed
        self.resolutionPreset = resolutionPreset
        self.resizeEnabled = resizeEnabled
        self.resizeValue = max(16, resizeValue)
        self.resizeCondition = resizeCondition
        self.language = language
    }
    
    /// Clamp CRF value to valid range for the given codec
    private static func clampCRF(_ crf: Int, for codec: VideoCodec) -> Int {
        let range = codec.recommendedCRFRange
        return max(range.lowerBound, min(range.upperBound, crf))
    }
    
    /// Update CRF value with validation
    mutating func setCRF(_ newCRF: Int) {
        self.qualityPreset = .custom
        self.rateControlMode = .crf
        self.crf = Self.clampCRF(newCRF, for: codec)
    }
    
    /// Update codec and adjust CRF if necessary
    mutating func setCodec(_ newCodec: VideoCodec) {
        self.codec = newCodec
        if qualityPreset == .custom {
            self.crf = Self.clampCRF(self.crf, for: newCodec)
        } else {
            self.crf = qualityPreset.recommendedCRF(for: newCodec)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case crf
        case qualityPreset
        case rateControlMode
        case targetBitrateKbps
        case targetSizeMB
        case codec
        case deleteOriginals
        case outputBehavior
        case copyAudio
        case audioBitrateKbps
        case audioChannels
        case autoCloseApp
        case showInDock
        case showInMenuBar
        case useHardwareAcceleration
        case encodingSpeed
        case resolutionPreset
        case resizeEnabled
        case resizeValue
        case resizeCondition
        case language
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let decodedCRF = try container.decodeIfPresent(Int.self, forKey: .crf) ?? 23
        let decodedCodec = try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264
        let decodedPreset = try container.decodeIfPresent(QualityPreset.self, forKey: .qualityPreset)
        let decodedRateControl = try container.decodeIfPresent(RateControlMode.self, forKey: .rateControlMode) ?? .crf
        
        self.codec = decodedCodec
        self.qualityPreset = decodedPreset ?? .custom
        self.rateControlMode = decodedRateControl
        if self.qualityPreset == .custom {
            self.crf = Self.clampCRF(decodedCRF, for: decodedCodec)
        } else {
            self.crf = self.qualityPreset.recommendedCRF(for: decodedCodec)
        }
        
        let decodedDeleteOriginals = try container.decodeIfPresent(Bool.self, forKey: .deleteOriginals) ?? false
        let decodedOutputBehavior = try container.decodeIfPresent(OutputBehavior.self, forKey: .outputBehavior)
        self.deleteOriginals = decodedDeleteOriginals
        self.outputBehavior = decodedOutputBehavior ?? (decodedDeleteOriginals ? .replaceOriginal : .appendCompressedToName)
        self.copyAudio = try container.decodeIfPresent(Bool.self, forKey: .copyAudio) ?? true
        self.audioBitrateKbps = try container.decodeIfPresent(Int.self, forKey: .audioBitrateKbps) ?? 128
        self.audioChannels = try container.decodeIfPresent(Int.self, forKey: .audioChannels) ?? 2
        self.autoCloseApp = try container.decodeIfPresent(Bool.self, forKey: .autoCloseApp) ?? false
        self.showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? true
        self.showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        self.useHardwareAcceleration = try container.decodeIfPresent(Bool.self, forKey: .useHardwareAcceleration) ?? true
        self.encodingSpeed = try container.decodeIfPresent(EncodingSpeed.self, forKey: .encodingSpeed) ?? .medium
        self.resolutionPreset = try container.decodeIfPresent(ResolutionPreset.self, forKey: .resolutionPreset) ?? .original
        self.resizeEnabled = try container.decodeIfPresent(Bool.self, forKey: .resizeEnabled) ?? false
        self.resizeValue = max(16, try container.decodeIfPresent(Int.self, forKey: .resizeValue) ?? 1920)
        self.resizeCondition = try container.decodeIfPresent(ResizeCondition.self, forKey: .resizeCondition) ?? .fit
        self.targetBitrateKbps = try container.decodeIfPresent(Int.self, forKey: .targetBitrateKbps) ?? 2000
        self.targetSizeMB = try container.decodeIfPresent(Int.self, forKey: .targetSizeMB) ?? 50
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
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
            let format = NSLocalizedString("CRF значение %d вне рекомендуемого диапазона %@ для кодека %@", comment: "")
            let message = String(format: format, crf, crfRange.description, codec.shortName)
            errors.append(message)
        }
        
        if !showInDock && !showInMenuBar {
            errors.append(NSLocalizedString("Приложение должно отображаться либо в Dock, либо в меню-баре", comment: ""))
        }

        if rateControlMode == .targetBitrate {
            if targetBitrateKbps < 300 {
                errors.append(NSLocalizedString("Целевой битрейт слишком низкий", comment: ""))
            }
        }

        if rateControlMode == .targetSize {
            if targetSizeMB < 1 {
                errors.append(NSLocalizedString("Целевой размер слишком мал", comment: ""))
            }
        }

        if resizeEnabled && resizeValue < 16 {
            errors.append(NSLocalizedString("Значение resize слишком мало", comment: ""))
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
            return ["-c:a", "aac", "-b:a", "\(audioBitrateKbps)k", "-ac", "\(audioChannels)"]
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

    /// VideoToolbox quality value (0-100) for hardware encoding
    var videoToolboxQualityValue: Int {
        if qualityPreset != .custom {
            return qualityPreset.videoToolboxQuality
        }
        
        let range = codec.recommendedCRFRange
        let normalized = Double(crf - range.lowerBound) / Double(range.upperBound - range.lowerBound)
        let quality = 80.0 - (normalized * 50.0) // 80 (best) -> 30 (worst)
        return max(10, min(90, Int(quality.rounded())))
    }

    /// Estimated audio bitrate for size targeting when audio is copied
    var estimatedAudioBitrateKbps: Int {
        return max(64, min(256, audioBitrateKbps))
    }

    /// Compute target video bitrate in kbps for size/bitrate modes
    func targetVideoBitrateKbps(duration: TimeInterval, hasAudio: Bool) -> Int? {
        guard duration > 0 else { return nil }
        
        switch rateControlMode {
        case .crf:
            return nil
        case .targetBitrate:
            return max(300, targetBitrateKbps)
        case .targetSize:
            let totalKbps = (Double(targetSizeMB) * 8192.0) / duration
            let audioKbps = hasAudio ? (copyAudio ? Double(estimatedAudioBitrateKbps) : Double(audioBitrateKbps)) : 0.0
            let videoKbps = max(300.0, totalKbps - audioKbps)
            return Int(videoKbps.rounded())
        }
    }

    /// Optional scale filter for output resolution
    var scaleFilter: String? {
        if resizeEnabled {
            let value = max(16, resizeValue)
            switch resizeCondition {
            case .fit:
                return "scale='min(iw,\(value))':'min(ih,\(value))':force_original_aspect_ratio=decrease"
            case .width:
                return "scale='min(iw,\(value))':-2:force_original_aspect_ratio=decrease"
            case .height:
                return "scale=-2:'min(ih,\(value))':force_original_aspect_ratio=decrease"
            }
        }

        switch resolutionPreset {
        case .original:
            return nil
        case .p2160:
            return "scale=-2:'min(ih,2160)'"
        case .p1440:
            return "scale=-2:'min(ih,1440)'"
        case .p1080:
            return "scale=-2:'min(ih,1080)'"
        case .p720:
            return "scale=-2:'min(ih,720)'"
        case .p480:
            return "scale=-2:'min(ih,480)'"
        }
    }
}

// MARK: - Quality Presets

enum QualityPreset: String, CaseIterable, Identifiable, Codable {
    case veryHigh
    case high
    case medium
    case low
    case veryLow
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .veryHigh: return NSLocalizedString("Очень высокое", comment: "")
        case .high: return NSLocalizedString("Высокое", comment: "")
        case .medium: return NSLocalizedString("Среднее", comment: "")
        case .low: return NSLocalizedString("Низкое", comment: "")
        case .veryLow: return NSLocalizedString("Очень низкое", comment: "")
        case .custom: return NSLocalizedString("Свое", comment: "")
        }
    }
    
    var description: String {
        switch self {
        case .veryHigh: return NSLocalizedString("Максимальное качество, большой размер", comment: "")
        case .high: return NSLocalizedString("Высокое качество, умеренный размер", comment: "")
        case .medium: return NSLocalizedString("Сбалансированно по качеству и размеру", comment: "")
        case .low: return NSLocalizedString("Ниже качество, меньший размер", comment: "")
        case .veryLow: return NSLocalizedString("Минимальный размер, заметная потеря качества", comment: "")
        case .custom: return NSLocalizedString("Точная настройка CRF", comment: "")
        }
    }
    
    func recommendedCRF(for codec: VideoCodec) -> Int {
        switch codec {
        case .h264:
            switch self {
            case .veryHigh: return 18
            case .high: return 20
            case .medium: return 23
            case .low: return 26
            case .veryLow: return 28
            case .custom: return codec.defaultCRF
            }
        case .h265:
            switch self {
            case .veryHigh: return 20
            case .high: return 22
            case .medium: return 25
            case .low: return 28
            case .veryLow: return 30
            case .custom: return codec.defaultCRF
            }
        }
    }
    
    var videoToolboxQuality: Int {
        switch self {
        case .veryHigh: return 80
        case .high: return 70
        case .medium: return 60
        case .low: return 45
        case .veryLow: return 30
        case .custom: return 60
        }
    }
}

// MARK: - Rate Control

enum RateControlMode: String, CaseIterable, Identifiable, Codable {
    case crf
    case targetBitrate
    case targetSize
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .crf: return NSLocalizedString("CRF (качество)", comment: "")
        case .targetBitrate: return NSLocalizedString("Целевой битрейт", comment: "")
        case .targetSize: return NSLocalizedString("Целевой размер", comment: "")
        }
    }
    
    var description: String {
        switch self {
        case .crf: return NSLocalizedString("Лучшее качество при заданном CRF", comment: "")
        case .targetBitrate: return NSLocalizedString("Стабильный битрейт, предсказуемый размер", comment: "")
        case .targetSize: return NSLocalizedString("Ориентир на размер файла", comment: "")
        }
    }
}

// MARK: - Encoding Speed

enum EncodingSpeed: String, CaseIterable, Identifiable, Codable {
    case ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .ultrafast: return "Ultrafast"
        case .superfast: return "Superfast"
        case .veryfast: return "Veryfast"
        case .faster: return "Faster"
        case .fast: return "Fast"
        case .medium: return "Medium"
        case .slow: return "Slow"
        case .slower: return "Slower"
        case .veryslow: return "Veryslow"
        }
    }
    
    var ffmpegValue: String { rawValue }
}

enum ResizeCondition: String, CaseIterable, Identifiable, Codable {
    case fit
    case width
    case height

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit:
            return NSLocalizedString("Fit", comment: "")
        case .width:
            return NSLocalizedString("Width", comment: "")
        case .height:
            return NSLocalizedString("Height", comment: "")
        }
    }
}

// MARK: - Resolution Presets

enum ResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case original
    case p2160
    case p1440
    case p1080
    case p720
    case p480
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .original: return NSLocalizedString("Оригинал", comment: "")
        case .p2160: return "2160p"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }
}
