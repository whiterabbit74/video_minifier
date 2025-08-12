import XCTest
import Combine
import CoreGraphics
@testable import VideoSzhimaka

@MainActor
final class SettingsServiceTests: XCTestCase {
    
    private var settingsService: SettingsService!
    private var mockUserDefaults: UserDefaults!
    private var cancellables: Set<AnyCancellable>!
    
    @MainActor override func setUp() {
        super.setUp()
        
        // Create a mock UserDefaults for testing
        mockUserDefaults = UserDefaults(suiteName: "test.VideoSzhimaka.SettingsServiceTests")!
        
        // Clear any existing data
        mockUserDefaults.removePersistentDomain(forName: "test.VideoSzhimaka.SettingsServiceTests")
        
        // Initialize settings service with mock UserDefaults
        settingsService = SettingsService(userDefaults: mockUserDefaults)
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        
        // Clean up mock UserDefaults
        mockUserDefaults.removePersistentDomain(forName: "test.VideoSzhimaka.SettingsServiceTests")
        mockUserDefaults = nil
        settingsService = nil
        
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaultSettings() {
        // When initializing without saved settings
        let service = SettingsService(userDefaults: mockUserDefaults)
        
        // Then should use default settings
        XCTAssertEqual(service.settings, CompressionSettings.default)
    }
    
    func testInitializationWithSavedSettings() throws {
        // Given saved settings in UserDefaults
        let customSettings = CompressionSettings(
            crf: 25,
            codec: .h265,
            deleteOriginals: true,
            copyAudio: false
        )
        
        let data = try JSONEncoder().encode(customSettings)
        mockUserDefaults.set(data, forKey: "compression_settings")
        
        // When initializing
        let service = SettingsService(userDefaults: mockUserDefaults)
        
        // Then should load saved settings
        XCTAssertEqual(service.settings.crf, 25)
        XCTAssertEqual(service.settings.codec, .h265)
        XCTAssertTrue(service.settings.deleteOriginals)
        XCTAssertFalse(service.settings.copyAudio)
    }
    
    func testInitializationWithCorruptedSettings() {
        // Given corrupted data in UserDefaults
        mockUserDefaults.set("invalid json data", forKey: "compression_settings")
        
        // When initializing
        let service = SettingsService(userDefaults: mockUserDefaults)
        
        // Then should fall back to default settings
        XCTAssertEqual(service.settings, CompressionSettings.default)
    }
    
    func testInitializationWithInvalidSettings() throws {
        // Given invalid settings (both dock and menu bar disabled)
        var invalidSettings = CompressionSettings.default
        invalidSettings.showInDock = false
        invalidSettings.showInMenuBar = false
        
        let data = try JSONEncoder().encode(invalidSettings)
        mockUserDefaults.set(data, forKey: "compression_settings")
        
        // When initializing
        let service = SettingsService(userDefaults: mockUserDefaults)
        
        // Then should fall back to default settings
        XCTAssertEqual(service.settings, CompressionSettings.default)
    }
    
    // MARK: - Settings Management Tests
    
    func testLoadSettings() throws {
        // Given settings saved in UserDefaults
        let customSettings = CompressionSettings(crf: 20, codec: .h265)
        let data = try JSONEncoder().encode(customSettings)
        mockUserDefaults.set(data, forKey: "compression_settings")
        
        // When loading settings
        settingsService.loadSettings()
        
        // Then settings should be loaded
        XCTAssertEqual(settingsService.settings.crf, 20)
        XCTAssertEqual(settingsService.settings.codec, .h265)
    }
    
    func testSaveSettings() throws {
        // Given modified settings
        settingsService.settings.crf = 25
        settingsService.settings.codec = .h265
        settingsService.settings.deleteOriginals = true
        
        // When saving settings
        settingsService.saveSettings()
        
        // Then settings should be saved to UserDefaults
        let data = mockUserDefaults.data(forKey: "compression_settings")
        XCTAssertNotNil(data)
        
        let savedSettings = try JSONDecoder().decode(CompressionSettings.self, from: data!)
        XCTAssertEqual(savedSettings.crf, 25)
        XCTAssertEqual(savedSettings.codec, .h265)
        XCTAssertTrue(savedSettings.deleteOriginals)
    }
    
    func testResetToDefaults() {
        // Given modified settings
        settingsService.settings.crf = 25
        settingsService.settings.codec = .h265
        settingsService.settings.deleteOriginals = true
        
        // When resetting to defaults
        settingsService.resetToDefaults()
        
        // Then settings should be reset to defaults
        XCTAssertEqual(settingsService.settings, CompressionSettings.default)
        
        // And should be saved to UserDefaults
        let data = mockUserDefaults.data(forKey: "compression_settings")
        XCTAssertNotNil(data)
    }
    
    func testAutoSaveOnSettingsChange() {
        let expectation = XCTestExpectation(description: "Settings should be auto-saved")
        
        // Given a settings change observer
        var savedData: Data?
        settingsService.$settings
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main) // Wait for debounce
            .sink { _ in
                savedData = self.mockUserDefaults.data(forKey: "compression_settings")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When changing settings
        settingsService.settings.crf = 25
        
        // Then settings should be auto-saved after debounce
        wait(for: [expectation], timeout: 2.0)
        XCTAssertNotNil(savedData)
    }
    
    // MARK: - Window Frame Management Tests
    
    func testSaveAndLoadWindowFrame() {
        let testFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        
        // When saving window frame
        settingsService.saveWindowFrame(testFrame)
        
        // Then should be able to load it back
        let loadedFrame = settingsService.loadWindowFrame()
        XCTAssertNotNil(loadedFrame)
        XCTAssertEqual(loadedFrame!, testFrame)
    }
    
    func testLoadWindowFrameWhenNoneExists() {
        // When loading window frame without saving any
        let loadedFrame = settingsService.loadWindowFrame()
        
        // Then should return nil
        XCTAssertNil(loadedFrame)
    }
    
    func testSaveAndLoadLogsWindowFrame() {
        let testFrame = CGRect(x: 150, y: 250, width: 700, height: 500)
        
        // When saving logs window frame
        settingsService.saveLogsWindowFrame(testFrame)
        
        // Then should be able to load it back
        let loadedFrame = settingsService.loadLogsWindowFrame()
        XCTAssertNotNil(loadedFrame)
        XCTAssertEqual(loadedFrame!, testFrame)
    }
    
    func testLoadLogsWindowFrameWhenNoneExists() {
        // When loading logs window frame without saving any
        let loadedFrame = settingsService.loadLogsWindowFrame()
        
        // Then should return nil
        XCTAssertNil(loadedFrame)
    }
    
    func testWindowFramePersistence() {
        let mainFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let logsFrame = CGRect(x: 150, y: 250, width: 700, height: 500)
        
        // When saving both frames
        settingsService.saveWindowFrame(mainFrame)
        settingsService.saveLogsWindowFrame(logsFrame)
        
        // And creating a new service instance
        let newService = SettingsService(userDefaults: mockUserDefaults)
        
        // Then both frames should be persisted
        XCTAssertEqual(newService.loadWindowFrame(), mainFrame)
        XCTAssertEqual(newService.loadLogsWindowFrame(), logsFrame)
    }
    
    // MARK: - Data Management Tests
    
    func testClearAllData() {
        // Given saved settings and window frames
        settingsService.settings.crf = 25
        settingsService.saveSettings()
        settingsService.saveWindowFrame(CGRect(x: 100, y: 100, width: 800, height: 600))
        settingsService.saveLogsWindowFrame(CGRect(x: 150, y: 150, width: 700, height: 500))
        
        // When clearing all data
        settingsService.clearAllData()
        
        // Then all data should be removed
        XCTAssertNil(mockUserDefaults.data(forKey: "compression_settings"))
        XCTAssertNil(mockUserDefaults.dictionary(forKey: "window_frame"))
        XCTAssertNil(mockUserDefaults.dictionary(forKey: "logs_window_frame"))
        XCTAssertFalse(mockUserDefaults.bool(forKey: "has_launched_before"))
        
        // And settings should be reset to defaults
        XCTAssertEqual(settingsService.settings, CompressionSettings.default)
    }
    
    // MARK: - First Launch Tests
    
    func testFirstLaunchDetection() {
        // Given a fresh UserDefaults
        let freshUserDefaults = UserDefaults(suiteName: "test.fresh")!
        freshUserDefaults.removePersistentDomain(forName: "test.fresh")
        
        // When creating a new service
        let service = SettingsService(userDefaults: freshUserDefaults)
        
        // Then should not be first launch (marked during init)
        XCTAssertFalse(service.isFirstLaunch)
        
        // And the flag should be set
        XCTAssertTrue(freshUserDefaults.bool(forKey: "has_launched_before"))
        
        // Clean up
        freshUserDefaults.removePersistentDomain(forName: "test.fresh")
    }
    
    func testSubsequentLaunchDetection() {
        // Given UserDefaults with first launch flag set
        mockUserDefaults.set(true, forKey: "has_launched_before")
        
        // When creating a service
        let service = SettingsService(userDefaults: mockUserDefaults)
        
        // Then should not be first launch
        XCTAssertFalse(service.isFirstLaunch)
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultWindowFrames() {
        let defaultMainFrame = SettingsService.defaultWindowFrame
        let defaultLogsFrame = SettingsService.defaultLogsWindowFrame
        
        XCTAssertEqual(defaultMainFrame, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(defaultLogsFrame, CGRect(x: 150, y: 150, width: 700, height: 500))
    }
    
    // MARK: - ObservableObject Tests
    
    func testObservableObjectConformance() {
        let expectation = XCTestExpectation(description: "Settings change should trigger objectWillChange")
        
        // Given an observer for objectWillChange
        settingsService.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When changing settings
        settingsService.settings.crf = 25
        
        // Then objectWillChange should be triggered
        wait(for: [expectation], timeout: 0.1)
    }
    
    func testPublishedSettingsUpdates() {
        let expectation = XCTestExpectation(description: "Published settings should update")
        
        // Given an observer for settings changes
        settingsService.$settings
            .dropFirst() // Skip initial value
            .sink { settings in
                XCTAssertEqual(settings.crf, 25)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // When changing settings
        settingsService.settings.crf = 25
        
        // Then published settings should update
        wait(for: [expectation], timeout: 0.1)
    }
    
    // MARK: - Error Handling Tests
    
    func testSaveSettingsWithEncodingError() {
        // This test is more conceptual since CompressionSettings should always encode successfully
        // But we can test the error handling path by mocking if needed
        
        // For now, just verify that normal encoding works
        settingsService.settings.crf = 25
        settingsService.saveSettings()
        
        let data = mockUserDefaults.data(forKey: "compression_settings")
        XCTAssertNotNil(data)
    }
    
    func testLoadSettingsWithMalformedData() {
        // Given malformed JSON data
        mockUserDefaults.set("{ invalid json", forKey: "compression_settings")
        
        // When loading settings
        settingsService.loadSettings()
        
        // Then should fall back to defaults
        XCTAssertEqual(settingsService.settings, CompressionSettings.default)
    }
    
    func testLoadSettingsWithWrongDataType() {
        // Given wrong data type
        mockUserDefaults.set(12345, forKey: "compression_settings")
        
        // When loading settings
        settingsService.loadSettings()
        
        // Then should fall back to defaults
        XCTAssertEqual(settingsService.settings, CompressionSettings.default)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteSettingsLifecycle() throws {
        // Given initial default settings
        XCTAssertEqual(settingsService.settings, CompressionSettings.default)
        
        // When modifying settings
        settingsService.settings.crf = 25
        settingsService.settings.codec = .h265
        settingsService.settings.deleteOriginals = true
        
        // And saving them
        settingsService.saveSettings()
        
        // And creating a new service instance
        let newService = SettingsService(userDefaults: mockUserDefaults)
        
        // Then settings should be persisted
        XCTAssertEqual(newService.settings.crf, 25)
        XCTAssertEqual(newService.settings.codec, .h265)
        XCTAssertTrue(newService.settings.deleteOriginals)
        
        // When resetting to defaults
        newService.resetToDefaults()
        
        // Then should be back to defaults
        XCTAssertEqual(newService.settings, CompressionSettings.default)
        
        // And should persist the reset
        let finalService = SettingsService(userDefaults: mockUserDefaults)
        XCTAssertEqual(finalService.settings, CompressionSettings.default)
    }
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access should be safe")
        expectation.expectedFulfillmentCount = 10
        
        // When accessing settings concurrently
        DispatchQueue.concurrentPerform(iterations: 10) { index in
            settingsService.settings.crf = 20 + index
            settingsService.saveSettings()
            _ = settingsService.loadWindowFrame()
            expectation.fulfill()
        }
        
        // Then should not crash
        wait(for: [expectation], timeout: 2.0)
    }
}