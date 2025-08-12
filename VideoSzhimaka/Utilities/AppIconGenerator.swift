import Foundation
import AppKit
import SwiftUI

/// Utility to generate app icon programmatically
class AppIconGenerator {
    
    /// Generate app icon images for all required sizes
    static func generateAppIcons() {
        let sizes: [CGFloat] = [16, 32, 128, 256, 512]
        
        for size in sizes {
            let image = createAppIcon(size: size)
            let scaledImage = createAppIcon(size: size * 2) // 2x version
            
            // Save images (this would be used during build process)
            // For now, we'll just create the images in memory
            _ = image
            _ = scaledImage
        }
    }
    
    /// Create app icon with video compression theme
    private static func createAppIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        
        image.lockFocus()
        
        // Background gradient
        let gradient = NSGradient(colors: [
            NSColor.systemBlue.withAlphaComponent(0.8),
            NSColor.systemPurple.withAlphaComponent(0.6)
        ])
        
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
        
        gradient?.draw(in: path, angle: 45)
        
        // Video symbol
        let symbolSize = size * 0.6
        let symbolRect = NSRect(
            x: (size - symbolSize) / 2,
            y: (size - symbolSize) / 2,
            width: symbolSize,
            height: symbolSize
        )
        
        // Create video play symbol
        let videoPath = NSBezierPath()
        let centerX = symbolRect.midX
        let centerY = symbolRect.midY
        let radius = symbolSize * 0.3
        
        // Play triangle
        videoPath.move(to: NSPoint(x: centerX - radius * 0.3, y: centerY - radius * 0.5))
        videoPath.line(to: NSPoint(x: centerX - radius * 0.3, y: centerY + radius * 0.5))
        videoPath.line(to: NSPoint(x: centerX + radius * 0.5, y: centerY))
        videoPath.close()
        
        NSColor.white.setFill()
        videoPath.fill()
        
        // Compression arrows
        let arrowSize = size * 0.15
        let arrowPath = NSBezierPath()
        
        // Down arrow (compression)
        let arrowX = centerX + radius * 0.8
        let arrowY = centerY
        
        arrowPath.move(to: NSPoint(x: arrowX, y: arrowY + arrowSize))
        arrowPath.line(to: NSPoint(x: arrowX, y: arrowY - arrowSize))
        arrowPath.move(to: NSPoint(x: arrowX - arrowSize * 0.3, y: arrowY - arrowSize * 0.7))
        arrowPath.line(to: NSPoint(x: arrowX, y: arrowY - arrowSize))
        arrowPath.line(to: NSPoint(x: arrowX + arrowSize * 0.3, y: arrowY - arrowSize * 0.7))
        
        NSColor.white.withAlphaComponent(0.8).setStroke()
        arrowPath.lineWidth = size * 0.02
        arrowPath.stroke()
        
        image.unlockFocus()
        
        return image
    }
}

/// SwiftUI view for displaying the app icon
struct AppIconView: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            
            // Video play symbol
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundColor(.white)
            
            // Compression indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: size * 0.2))
                        .foregroundColor(.white.opacity(0.8))
                        .offset(x: -size * 0.1, y: -size * 0.1)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    AppIconView(size: 128)
}