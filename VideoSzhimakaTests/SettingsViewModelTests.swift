import XCTest
@testable import VideoSzhimaka

/// Tests for SettingsViewModel functionality
@MainActor
final class SettingsViewModelTests: XCTestCase {
    
    var mockSettingsService: MockSettingsService!
    var viewModel: SettingsViewModel!
    
    @MainActor override func setUp() {
        super.setUp()
        mockSettingsService = MockSettingsService()
        viewModel = SettingsViewModel(settingsService: mockSettingsService)
    }
    
    override func tearDown() {
        viewModel = nil
        mockSettingsService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(viewModel.settings, CompressionSettings.default)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.showResetConfirmation)
    }
    
    // MARK: - CRF Tests
    
    func testCRFValueBinding() {
        // Test getter
        viewModel.settings.crf = 25
        XCTAssertEqual(viewModel.crfValue, 25.0)
        
        // Test setter
        viewModel.crfValue = 20.0
        XCTAssertEqual(viewModel.settings.crf, 20)
    }
    
    func testUpdateCRF() {
        // Test valid CRF value
        viewModel.updateCRF(22)
        XCTAssertEqual(viewModel.settings.crf, 22)
        
        // Test CRF clamping - too low
        viewModel.updateCRF(10)
        XCTAssertEqual(viewModel.settings.crf, 18) // Should clamp to minimum
        
        // Test CRF clamping - too high
        viewModel.updateCRF(35)
        XCTAssertEqual(viewModel.settings.crf, 28) // Should clamp to maximum for H.264
    }
    
    func testCRFRange() {
        // Test H.264 range
        viewModel.settings.codec = .h264
        XCTAssertEqual(viewModel.crfRange, 18.0...28.0)
        
        // Test H.265 range
        viewModel.settings.codec = .h265
        XCTAssertEqual(viewModel.crfRange, 20.0...30.0)
    }
    
    func testCRFDescription() {
        viewModel.settings.crf = 19
        XCTAssertEqual(viewModel.crfDescription, "Очень высокое качество (большой размер)")
        
        viewModel.settings.crf = 23
        XCTAssertEqual(viewModel.crfDescription, "Высокое качество (рекомендуется)")
        
        viewModel.settings.crf = 25
        XCTAssertEqual(viewModel.crfDescription, "Среднее качество (баланс размера и качества)")
        
        viewModel.settings.crf = 28
        XCTAssertEqual(viewModel.crfDescription, "Низкое качество (маленький размер)")
    }
    
    // MARK: - Codec Tests
    
    func testUpdateCodec() {
        // Start with H.264 and CRF 23
        viewModel.settings.codec = .h264
        viewModel.settings.crf = 23
        
        // Switch to H.265 - CRF should remain valid
        viewModel.updateCodec(.h265)
        XCTAssertEqual(viewModel.settings.codec, .h265)
        XCTAssertEqual(viewModel.settings.crf, 23)
        
        // Set CRF to H.264-only value and switch to H.265
        viewModel.settings.codec = .h264
        viewModel.settings.crf = 18 // Valid for H.264 but not H.265
        viewModel.updateCodec(.h265)
        XCTAssertEqual(viewModel.settings.codec, .h265)
        XCTAssertEqual(viewModel.settings.crf, 25) // Should use H.265 default
    }
    
    func testCodecDescription() {
        viewModel.settings.codec = .h264
        XCTAssertEqual(viewModel.codecDescription, "Лучшая совместимость, быстрое кодирование")
        
        viewModel.settings.codec = .h265
        XCTAssertEqual(viewModel.codecDescription, "Лучшее сжатие, медленнее кодирование")
    }
    
    // MARK: - Settings Management Tests
    
    func testSaveSettings() {
        // Modify settings
        viewModel.settings.crf = 25
        viewModel.settings.codec = .h265
        
        // Save settings
        viewModel.saveSettings()
        
        // Verify settings were saved to service
        XCTAssertEqual(mockSettingsService.settings.crf, 25)
        XCTAssertEqual(mockSettingsService.settings.codec, VideoCodec.h265)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    func testDiscardChanges() {
        // Modify settings
        viewModel.settings.crf = 25
        
        // Discard changes
        viewModel.discardChanges()
        
        // Settings should revert to service settings
        XCTAssertEqual(viewModel.settings, mockSettingsService.settings)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    func testResetToDefaults() {
        // Modify settings
        viewModel.settings.crf = 25
        viewModel.settings.deleteOriginals = true
        
        // Reset to defaults
        viewModel.resetToDefaults()
        
        // Settings should be default
        XCTAssertEqual(viewModel.settings, CompressionSettings.default)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testConfirmResetToDefaults() {
        // Modify settings
        viewModel.settings.crf = 25
        viewModel.showResetConfirmation = true
        
        // Confirm reset
        viewModel.confirmResetToDefaults()
        
        // Settings should be default and saved
        XCTAssertEqual(viewModel.settings, CompressionSettings.default)
        XCTAssertEqual(mockSettingsService.settings, CompressionSettings.default)
        XCTAssertFalse(viewModel.showResetConfirmation)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Validation Tests
    
    func testValidation() {
        // Valid settings
        viewModel.settings = CompressionSettings.default
        XCTAssertTrue(viewModel.isValid)
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
        
        // Invalid settings - both display options disabled
        viewModel.settings.showInDock = false
        viewModel.settings.showInMenuBar = false
        XCTAssertFalse(viewModel.isValid)
        XCTAssertFalse(viewModel.validationErrors.isEmpty)
    }
    
    // MARK: - Estimated Compression Tests
    
    func testEstimatedCompressionText() {
        viewModel.settings.codec = .h264
        viewModel.settings.crf = 23
        
        let compressionText = viewModel.estimatedCompressionText
        XCTAssertTrue(compressionText.contains("%"))
        XCTAssertTrue(compressionText.contains("сжатие"))
    }
    
    // MARK: - Change Tracking Tests
    
    func testChangeTracking() async {
        // Initially no changes
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        
        // Modify settings
        viewModel.settings.crf = 25
        
        // Wait for change tracking to update
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should detect changes
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        
        // Save settings
        viewModel.saveSettings()
        
        // Should clear unsaved changes flag
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
}

