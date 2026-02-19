import Foundation
import CoreGraphics

/// Protocol defining the interface for settings management
protocol SettingsServiceProtocol: ObservableObject {
    /// Current compression settings
    var settings: CompressionSettings { get set }
    
    /// Load settings from persistent storage
    func loadSettings()
    
    /// Save current settings to persistent storage
    func saveSettings()
    
    /// Reset all settings to default values
    func resetToDefaults()
    
    /// Save window frame to persistent storage
    /// - Parameter frame: The window frame to save
    func saveWindowFrame(_ frame: CGRect)
    
    /// Load window frame from persistent storage
    /// - Returns: The saved window frame, or nil if none exists
    func loadWindowFrame() -> CGRect?
    
    /// Save logs window frame to persistent storage
    /// - Parameter frame: The logs window frame to save
    func saveLogsWindowFrame(_ frame: CGRect)
    
    /// Load logs window frame from persistent storage
    /// - Returns: The saved logs window frame, or nil if none exists
    func loadLogsWindowFrame() -> CGRect?
    
    /// Clear all saved data
    func clearAllData()
}