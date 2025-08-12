import Foundation
import CoreGraphics
import Combine

/// Service for managing application settings and persistence
final class SettingsService: SettingsServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published var settings = CompressionSettings.default
    
    // MARK: - Private Properties
    
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let compressionSettings = "compression_settings"
        static let windowFrame = "window_frame"
        static let logsWindowFrame = "logs_window_frame"
        static let hasLaunchedBefore = "has_launched_before"
    }
    
    // MARK: - Initialization
    
    /// Initialize with custom UserDefaults (useful for testing)
    /// - Parameter userDefaults: UserDefaults instance to use
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        
        // Load settings on initialization
        loadSettings()
        
        // Set up automatic saving when settings change
        setupAutoSave()
        
        // Mark first launch if needed
        markFirstLaunchIfNeeded()
    }
    
    // MARK: - Settings Management
    
    func loadSettings() {
        if let data = userDefaults.data(forKey: Keys.compressionSettings) {
            do {
                let loadedSettings = try JSONDecoder().decode(CompressionSettings.self, from: data)
                
                // Validate loaded settings
                if loadedSettings.isValid {
                    self.settings = loadedSettings
                } else {
                    // If settings are invalid, reset to defaults and save
                    print("⚠️ Loaded settings are invalid, resetting to defaults")
                    self.settings = CompressionSettings.default
                    saveSettings()
                }
            } catch {
                print("❌ Failed to decode settings: \(error)")
                // If decoding fails, use defaults
                self.settings = CompressionSettings.default
                saveSettings()
            }
        } else {
            // No saved settings, use defaults
            self.settings = CompressionSettings.default
            saveSettings()
        }
    }
    
    func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: Keys.compressionSettings)
            
            // Force synchronization to ensure data is written
            userDefaults.synchronize()
        } catch {
            print("❌ Failed to encode settings: \(error)")
        }
    }
    
    func resetToDefaults() {
        settings = CompressionSettings.default
        saveSettings()
    }
    
    // MARK: - Window Frame Management
    
    func saveWindowFrame(_ frame: CGRect) {
        let frameDict: [String: Double] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height)
        ]
        
        userDefaults.set(frameDict, forKey: Keys.windowFrame)
        userDefaults.synchronize()
    }
    
    func loadWindowFrame() -> CGRect? {
        guard let frameDict = userDefaults.dictionary(forKey: Keys.windowFrame) as? [String: Double],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return nil
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    func saveLogsWindowFrame(_ frame: CGRect) {
        let frameDict: [String: Double] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height)
        ]
        
        userDefaults.set(frameDict, forKey: Keys.logsWindowFrame)
        userDefaults.synchronize()
    }
    
    func loadLogsWindowFrame() -> CGRect? {
        guard let frameDict = userDefaults.dictionary(forKey: Keys.logsWindowFrame) as? [String: Double],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return nil
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Data Management
    
    func clearAllData() {
        userDefaults.removeObject(forKey: Keys.compressionSettings)
        userDefaults.removeObject(forKey: Keys.windowFrame)
        userDefaults.removeObject(forKey: Keys.logsWindowFrame)
        userDefaults.removeObject(forKey: Keys.hasLaunchedBefore)
        userDefaults.synchronize()
        
        // Reset to defaults
        settings = CompressionSettings.default
    }
    
    // MARK: - Private Methods
    
    private func setupAutoSave() {
        // Automatically save settings when they change
        $settings
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveSettings()
            }
            .store(in: &cancellables)
    }
    
    private func markFirstLaunchIfNeeded() {
        if !userDefaults.bool(forKey: Keys.hasLaunchedBefore) {
            userDefaults.set(true, forKey: Keys.hasLaunchedBefore)
            userDefaults.synchronize()
        }
    }
}

// MARK: - SettingsService Extensions

extension SettingsService {
    
    /// Whether this is the first launch of the application
    var isFirstLaunch: Bool {
        return !userDefaults.bool(forKey: Keys.hasLaunchedBefore)
    }
    
    /// Get default window frame for main window
    static var defaultWindowFrame: CGRect {
        return CGRect(x: 100, y: 100, width: 800, height: 600)
    }
    
    /// Get default window frame for logs window
    static var defaultLogsWindowFrame: CGRect {
        return CGRect(x: 150, y: 150, width: 700, height: 500)
    }
}