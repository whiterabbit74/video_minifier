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
        return ByteCountFormatterCache.fileFormatter().string(fromByteCount: self)
    }
}

private enum ByteCountFormatterCache {
    private static let formatterKey = "ByteCountFormatter.file"
    
    static func fileFormatter() -> ByteCountFormatter {
        let threadDictionary = Thread.current.threadDictionary
        if let formatter = threadDictionary[formatterKey] as? ByteCountFormatter {
            return formatter
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        threadDictionary[formatterKey] = formatter
        return formatter
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

    /// Toolbar-like background (lighter than main content area)
    static var videoToolbarBackground: Color {
        Color(
            NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                        return NSColor(calibratedWhite: 0.16, alpha: 1.0)
                    } else {
                        return NSColor(calibratedWhite: 0.95, alpha: 1.0)
                    }
                }
            )
        )
    }

    /// Main working area background (slightly darker than toolbar)
    static var videoMainBackground: Color {
        Color(
            NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                        return NSColor(calibratedWhite: 0.12, alpha: 1.0)
                    } else {
                        return NSColor(calibratedWhite: 0.89, alpha: 1.0)
                    }
                }
            )
        )
    }

    /// Selected tab background in toolbar
    static var videoTabSelectedBackground: Color {
        Color(
            NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                        return NSColor(calibratedWhite: 0.24, alpha: 1.0)
                    } else {
                        return NSColor(calibratedWhite: 0.86, alpha: 1.0)
                    }
                }
            )
        )
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
    
    @ViewBuilder
    func toolbarBackgroundIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            self.toolbarBackground(.regularMaterial, for: .windowToolbar)
        } else {
            self
        }
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
