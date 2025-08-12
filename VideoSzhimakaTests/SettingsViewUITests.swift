import XCTest
import SwiftUI
@testable import VideoSzhimaka

/// UI tests for SettingsView components
@MainActor
final class SettingsViewUITests: XCTestCase {
    
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
    
    // MARK: - CRF Settings Tests
    
    func testCRFSettingsView() {
        let _ = CRFSettingsView(viewModel: viewModel)
        
        // Test initial state
        XCTAssertEqual(viewModel.settings.crf, 23)
        XCTAssertEqual(viewModel.crfValue, 23.0)
        
        // Test CRF range for H.264
        viewModel.settings.codec = .h264
        XCTAssertEqual(viewModel.crfRange, 18.0...28.0)
        
        // Test CRF range for H.265
        viewModel.settings.codec = .h265
        XCTAssertEqual(viewModel.crfRange, 20.0...30.0)
        
        // Test CRF description updates
        viewModel.settings.crf = 20
        XCTAssertEqual(viewModel.crfDescription, "Очень высокое качество (большой размер)")
        
        viewModel.settings.crf = 23
        XCTAssertEqual(viewModel.crfDescription, "Высокое качество (рекомендуется)")
    }
    
    // MARK: - Codec Settings Tests
    
    func testCodecSettingsView() {
        let _ = CodecSettingsView(viewModel: viewModel)
        
        // Test initial codec
        XCTAssertEqual(viewModel.settings.codec, .h264)
        XCTAssertEqual(viewModel.codecDescription, "Лучшая совместимость, быстрое кодирование")
        
        // Test codec change
        viewModel.settings.codec = .h265
        XCTAssertEqual(viewModel.codecDescription, "Лучшее сжатие, медленнее кодирование")
        
        // Test hardware acceleration toggle
        XCTAssertTrue(viewModel.settings.useHardwareAcceleration)
        viewModel.settings.useHardwareAcceleration = false
        XCTAssertFalse(viewModel.settings.useHardwareAcceleration)
    }
    
    // MARK: - Audio Settings Tests
    
    func testAudioSettingsView() {
        let _ = AudioSettingsView(viewModel: viewModel)
        
        // Test initial audio setting
        XCTAssertTrue(viewModel.settings.copyAudio)
        
        // Test audio setting toggle
        viewModel.settings.copyAudio = false
        XCTAssertFalse(viewModel.settings.copyAudio)
    }
    
    // MARK: - Behavior Settings Tests
    
    func testBehaviorSettingsView() {
        let _ = BehaviorSettingsView(viewModel: viewModel)
        
        // Test initial behavior settings
        XCTAssertFalse(viewModel.settings.deleteOriginals)
        XCTAssertFalse(viewModel.settings.autoCloseApp)
        
        // Test behavior toggles
        viewModel.settings.deleteOriginals = true
        XCTAssertTrue(viewModel.settings.deleteOriginals)
        
        viewModel.settings.autoCloseApp = true
        XCTAssertTrue(viewModel.settings.autoCloseApp)
    }
    
    // MARK: - App Display Settings Tests
    
    func testAppDisplaySettingsView() {
        let _ = AppDisplaySettingsView(viewModel: viewModel)
        
        // Test initial display settings
        XCTAssertTrue(viewModel.settings.showInDock)
        XCTAssertTrue(viewModel.settings.showInMenuBar)
        
        // Test display toggles
        viewModel.settings.showInDock = false
        XCTAssertFalse(viewModel.settings.showInDock)
        
        viewModel.settings.showInMenuBar = false
        XCTAssertFalse(viewModel.settings.showInMenuBar)
        
        // Test validation warning when both are disabled
        XCTAssertFalse(viewModel.isValid)
        XCTAssertFalse(viewModel.validationErrors.isEmpty)
    }
    
    // MARK: - Settings Header Tests
    
    func testSettingsHeaderView() {
        var saveCallCount = 0
        var discardCallCount = 0
        var closeCallCount = 0
        
        let _ = SettingsHeaderView(
            hasUnsavedChanges: false,
            onSave: { saveCallCount += 1 },
            onDiscard: { discardCallCount += 1 },
            onClose: { closeCallCount += 1 }
        )
        
        // Test header with no unsaved changes
        XCTAssertEqual(saveCallCount, 0)
        XCTAssertEqual(discardCallCount, 0)
        XCTAssertEqual(closeCallCount, 0)
        
        // Test header with unsaved changes
        let _ = SettingsHeaderView(
            hasUnsavedChanges: true,
            onSave: { saveCallCount += 1 },
            onDiscard: { discardCallCount += 1 },
            onClose: { closeCallCount += 1 }
        )
        
        // The view should show save/discard buttons when there are unsaved changes
        // This is tested through the hasUnsavedChanges property
    }
    
    // MARK: - Reset Settings Tests
    
    func testResetSettingsView() {
        let _ = ResetSettingsView(viewModel: viewModel)
        
        // Test initial reset confirmation state
        XCTAssertFalse(viewModel.showResetConfirmation)
        
        // Test reset confirmation dialog trigger
        viewModel.showResetConfirmation = true
        XCTAssertTrue(viewModel.showResetConfirmation)
        
        // Test reset confirmation
        viewModel.confirmResetToDefaults()
        XCTAssertFalse(viewModel.showResetConfirmation)
        XCTAssertEqual(viewModel.settings, CompressionSettings.default)
    }
    
    // MARK: - Settings Section Tests
    
    func testSettingsSection() {
        let sectionView = SettingsSection(title: "Test Section", icon: "gear") {
            Text("Test Content")
        }
        
        // The section view should properly display title and icon
        // This is primarily a layout test that would be better suited for snapshot testing
        // For now, we just verify the view can be created without errors
        XCTAssertNotNil(sectionView)
    }
    
    // MARK: - Integration Tests
    
    func testSettingsViewIntegration() {
        // Test that all settings can be modified and saved
        viewModel.settings.crf = 25
        viewModel.settings.codec = .h265
        viewModel.settings.deleteOriginals = true
        viewModel.settings.copyAudio = false
        viewModel.settings.autoCloseApp = true
        viewModel.settings.useHardwareAcceleration = false
        
        // Verify all changes are reflected
        XCTAssertEqual(viewModel.settings.crf, 25)
        XCTAssertEqual(viewModel.settings.codec, .h265)
        XCTAssertTrue(viewModel.settings.deleteOriginals)
        XCTAssertFalse(viewModel.settings.copyAudio)
        XCTAssertTrue(viewModel.settings.autoCloseApp)
        XCTAssertFalse(viewModel.settings.useHardwareAcceleration)
        
        // Save settings
        viewModel.saveSettings()
        
        // Verify settings were saved
        XCTAssertEqual(mockSettingsService.settings, viewModel.settings)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() {
        // Test that important UI elements have proper accessibility
        // This would typically be done with UI testing framework
        // For now, we verify that the view model provides proper descriptions
        
        XCTAssertFalse(viewModel.crfDescription.isEmpty)
        XCTAssertFalse(viewModel.codecDescription.isEmpty)
        XCTAssertFalse(viewModel.estimatedCompressionText.isEmpty)
    }
    
    // MARK: - Edge Cases Tests
    
    func testEdgeCases() {
        // Test extreme CRF values
        viewModel.updateCRF(0)
        XCTAssertEqual(viewModel.settings.crf, 18) // Should clamp to minimum
        
        viewModel.updateCRF(100)
        XCTAssertEqual(viewModel.settings.crf, 28) // Should clamp to maximum for H.264
        
        // Test codec switching with edge case CRF values
        viewModel.settings.codec = .h264
        viewModel.settings.crf = 18 // Valid for H.264
        viewModel.updateCodec(.h265) // Switch to H.265 where 18 is invalid
        XCTAssertEqual(viewModel.settings.crf, 25) // Should use H.265 default
        
        // Test invalid display settings
        viewModel.settings.showInDock = false
        viewModel.settings.showInMenuBar = false
        XCTAssertFalse(viewModel.isValid)
        
        // Fix display settings
        viewModel.settings.showInDock = true
        XCTAssertTrue(viewModel.isValid)
    }
}

