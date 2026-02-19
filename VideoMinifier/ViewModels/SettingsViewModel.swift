import Foundation
import SwiftUI
import Combine

/// ViewModel for managing settings panel state and interactions
@MainActor
class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current compression settings (bound to UI controls)
    @Published var settings: CompressionSettings
    
    /// Whether settings have been modified from their saved state
    @Published var hasUnsavedChanges = false
    
    /// Whether to show the reset confirmation dialog
    @Published var showResetConfirmation = false
    
    /// Whether a restart is required to apply changes (e.g. language)
    @Published var restartRequired = false
    
    // MARK: - Private Properties
    
    // MARK: - Private Properties
    
    private let settingsService: any SettingsServiceProtocol
    private var originalSettings: CompressionSettings
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(settingsService: any SettingsServiceProtocol) {
        self.settingsService = settingsService
        self.settings = settingsService.settings
        self.originalSettings = settingsService.settings
        
        // Monitor settings changes
        setupChangeTracking()
    }
    
    // MARK: - Settings Management
    
    /// Save current settings to persistent storage
    func saveSettings() {
        // Check if language changed
        if settings.language != originalSettings.language {
            // Flag restart required
            restartRequired = true
        }
        
        settingsService.settings = settings
        settingsService.saveSettings()
        
        // We do NOT update originalSettings here if language changed, because we want to track that "change" state 
        // until the app restarts, or at least keep the restart flag active.
        // However, for the purpose of "Unsaved Changes" UI, we can consider it saved.
        // The restart alert is independent of "hasUnsavedChanges".
        originalSettings = settings
        hasUnsavedChanges = false
    }
    
    /// Discard changes and revert to saved settings
    func discardChanges() {
        settings = originalSettings
        hasUnsavedChanges = false
    }
    
    /// Reset settings to default values
    func resetToDefaults() {
        settings = CompressionSettings.default
        hasUnsavedChanges = (settings != originalSettings)
    }
    
    /// Confirm reset to defaults (called after user confirmation)
    func confirmResetToDefaults() {
        resetToDefaults()
        saveSettings()
        showResetConfirmation = false
    }
    
    // MARK: - CRF Management
    
    /// Update CRF value and adjust for codec compatibility
    /// - Parameter newCRF: New CRF value
    func updateCRF(_ newCRF: Int) {
        let clampedCRF = max(settings.codec.recommendedCRFRange.lowerBound, 
                            min(settings.codec.recommendedCRFRange.upperBound, newCRF))
        settings.qualityPreset = .custom
        settings.rateControlMode = .crf
        settings.crf = clampedCRF
    }
    
    /// Get CRF value as Double for Slider binding
    var crfValue: Double {
        get { Double(settings.crf) }
        set { updateCRF(Int(newValue.rounded())) }
    }
    
    // MARK: - Codec Management
    
    /// Update video codec and adjust CRF if necessary
    /// - Parameter newCodec: New video codec
    func updateCodec(_ newCodec: VideoCodec) {
        settings.codec = newCodec
        
        if settings.qualityPreset == .custom {
            let newRange = newCodec.recommendedCRFRange
            if !newRange.contains(settings.crf) {
                settings.crf = newCodec.defaultCRF
            }
        } else {
            settings.crf = settings.qualityPreset.recommendedCRF(for: newCodec)
        }
    }
    
    /// Update quality preset and sync CRF
    func updateQualityPreset(_ newPreset: QualityPreset) {
        settings.qualityPreset = newPreset
        settings.rateControlMode = .crf
        if newPreset != .custom {
            settings.crf = newPreset.recommendedCRF(for: settings.codec)
        }
    }
    
    /// Update rate control mode
    func updateRateControlMode(_ newMode: RateControlMode) {
        settings.rateControlMode = newMode
        if newMode != .crf {
            settings.qualityPreset = .custom
        }
    }
    
    // MARK: - Validation
    
    /// Get current validation errors
    var validationErrors: [String] {
        return settings.validationErrors
    }
    
    /// Whether current settings are valid
    var isValid: Bool {
        return settings.isValid
    }
    
    // MARK: - UI Helpers
    
    /// Get CRF range for current codec
    var crfRange: ClosedRange<Double> {
        let range = settings.codec.recommendedCRFRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }
    
    /// Get CRF description text
    var crfDescription: String {
        switch settings.crf {
        case 18...20:
            return NSLocalizedString("Отличное качество, большой размер", comment: "")
        case 21...23:
            return NSLocalizedString("Хорошее качество, средний размер", comment: "")
        case 24...26:
            return NSLocalizedString("Среднее качество, малый размер", comment: "")
        case 27...28:
            return NSLocalizedString("Низкое качество, очень малый размер", comment: "")
        default:
            return NSLocalizedString("Пользовательское качество", comment: "")
        }
    }
    
    var qualityPresetDescription: String {
        return settings.qualityPreset.description
    }
    
    var rateControlDescription: String {
        return settings.rateControlMode.description
    }
    
    var isCRFMode: Bool {
        return settings.rateControlMode == .crf
    }
    
    /// Get codec description text
    var codecDescription: String {
        return settings.codec.detailedDescription
    }
    
    /// Get estimated compression ratio text
    var estimatedCompressionText: String {
        switch settings.rateControlMode {
        case .crf:
            let ratio = estimatedCompressionRatio
            let format = NSLocalizedString("Ориентировочное сжатие: ~%d%%", comment: "")
            return String(format: format, Int(ratio * 100))
        case .targetBitrate:
            let format = NSLocalizedString("Целевой битрейт: %d kbps", comment: "")
            return String(format: format, settings.targetBitrateKbps)
        case .targetSize:
            let format = NSLocalizedString("Целевой размер: %d MB", comment: "")
            return String(format: format, settings.targetSizeMB)
        }
    }
    
    /// Calculate estimated compression ratio based on current settings
    private var estimatedCompressionRatio: Double {
        // Rough estimation based on CRF and codec
        let baseRatio: Double
        
        switch settings.codec {
        case .h264:
            baseRatio = 0.3 // H.264 typically achieves ~30% of original size
        case .h265:
            baseRatio = 0.2 // H.265 typically achieves ~20% of original size
        }
        
        // Adjust based on CRF (lower CRF = higher quality = larger size)
        let crfFactor = Double(settings.crf - 18) / 10.0 // Normalize to 0-1 range
        let adjustedRatio = baseRatio * (0.5 + crfFactor * 0.5) // Scale between 50%-100% of base ratio
        
        return min(0.8, max(0.1, 1.0 - adjustedRatio)) // Clamp between 10%-80% compression
    }
    
    // MARK: - Private Methods
    
    /// Set up change tracking for unsaved changes detection
    private func setupChangeTracking() {
        // Monitor all settings changes
        $settings
            .dropFirst() // Skip initial value
            .sink { [weak self] newSettings in
                guard let self = self else { return }
                self.hasUnsavedChanges = (newSettings != self.originalSettings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Restart Logic
    
    /// Relaunches the application
    func restartApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - SettingsViewModel Extensions

extension SettingsViewModel {
    
    /// Convenience initializer for dependency injection in production
    convenience init() {
        self.init(settingsService: SettingsService())
    }
    
    /// Create a preview instance for SwiftUI previews
    static var preview: SettingsViewModel {
        let mockService = MockSettingsService()
        return SettingsViewModel(settingsService: mockService)
    }
}

// MARK: - Mock Service for Previews

private class MockSettingsService: SettingsServiceProtocol {
    @Published var settings = CompressionSettings.default
    
    func loadSettings() {}
    func saveSettings() {}
    func resetToDefaults() {
        settings = CompressionSettings.default
    }
    func saveWindowFrame(_ frame: CGRect) {}
    func loadWindowFrame() -> CGRect? { return nil }
    func saveLogsWindowFrame(_ frame: CGRect) {}
    func loadLogsWindowFrame() -> CGRect? { return nil }
    func clearAllData() {}
}
