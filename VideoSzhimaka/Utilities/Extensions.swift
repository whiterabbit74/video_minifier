import SwiftUI
import Foundation

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Formatted duration string (e.g., "1:23" or "12:34")
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    /// Formatted file size string (e.g., "1.2 MB", "345 KB")
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

// MARK: - Color Extensions

extension Color {
    /// Background color that adapts to light/dark mode
    static var adaptiveBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    /// Secondary background color that adapts to light/dark mode
    static var adaptiveSecondaryBackground: Color {
        Color(NSColor.windowBackgroundColor)
    }
    
    /// Border color that adapts to light/dark mode
    static var adaptiveBorder: Color {
        Color(NSColor.separatorColor)
    }
    
    /// Tertiary color for less important text
    static var adaptiveTertiary: Color {
        Color(NSColor.tertiaryLabelColor)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply theme-aware styling for cards/panels
    func cardStyle() -> some View {
        self
            .background(Color.adaptiveBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.adaptiveBorder.opacity(0.3), lineWidth: 0.5)
            )
    }
    
    /// Apply theme-aware styling for the main content area
    func contentBackground() -> some View {
        self
            .background(Color.adaptiveSecondaryBackground)
    }
}

// MARK: - NSColor Extensions

extension NSColor {
    /// Success color that works in both light and dark mode
    static var successColor: NSColor {
        if #available(macOS 10.15, *) {
            return NSColor.systemGreen
        } else {
            return NSColor.green
        }
    }
    
    /// Error color that works in both light and dark mode
    static var errorColor: NSColor {
        if #available(macOS 10.15, *) {
            return NSColor.systemRed
        } else {
            return NSColor.red
        }
    }
    
    /// Warning color that works in both light and dark mode
    static var warningColor: NSColor {
        if #available(macOS 10.15, *) {
            return NSColor.systemOrange
        } else {
            return NSColor.orange
        }
    }
}