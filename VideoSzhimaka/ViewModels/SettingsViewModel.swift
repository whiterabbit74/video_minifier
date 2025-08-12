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
    
    // MARK: - Private Properties
    
    private let settingsService: any SettingsServiceProtocol
    private var originalSettings: CompressionSettings
    
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
        settingsService.settings = settings
        settingsService.saveSettings()
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
        
        // Adjust CRF if the current value is outside the new codec's range
        let newRange = newCodec.recommendedCRFRange
        if !newRange.contains(settings.crf) {
            // Use the codec's default CRF if current value is out of range
            settings.crf = newCodec.defaultCRF
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
            return "Очень высокое качество (большой размер)"
        case 21...23:
            return "Высокое качество (рекомендуется)"
        case 24...26:
            return "Среднее качество (баланс размера и качества)"
        case 27...28:
            return "Низкое качество (маленький размер)"
        default:
            return "Пользовательское значение"
        }
    }
    
    /// Get codec description text
    var codecDescription: String {
        return settings.codec.detailedDescription
    }
    
    /// Get estimated compression ratio text
    var estimatedCompressionText: String {
        let ratio = estimatedCompressionRatio
        return String(format: "~%.0f%% сжатие", ratio * 100)
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
    
    private var cancellables = Set<AnyCancellable>()
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