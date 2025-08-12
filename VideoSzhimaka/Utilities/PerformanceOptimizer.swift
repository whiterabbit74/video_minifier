import Foundation
import SwiftUI

/// Utility class for performance optimizations
class PerformanceOptimizer {
    static let shared = PerformanceOptimizer()
    
    private init() {}
    
    /// Optimize memory usage by clearing caches
    func optimizeMemoryUsage() {
        // Clear URL caches
        URLCache.shared.removeAllCachedResponses()
        
        // Force garbage collection
        autoreleasepool {
            // This block helps with memory cleanup
        }
    }
    
    /// Get recommended batch size based on available memory
    func getRecommendedBatchSize() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let availableMemory = physicalMemory / 1024 / 1024 // Convert to MB
        
        // Recommend batch size based on available memory
        switch availableMemory {
        case 0..<8000: // Less than 8GB
            return 1
        case 8000..<16000: // 8-16GB
            return 2
        case 16000..<32000: // 16-32GB
            return 3
        default: // 32GB+
            return 5
        }
    }
    
    /// Check if system is under memory pressure
    func isUnderMemoryPressure() -> Bool {
        let memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return false }
        
        // Consider under pressure if using more than 80% of available memory
        let usedMemory = memoryInfo.resident_size
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        return Double(usedMemory) / Double(totalMemory) > 0.8
    }
    
    /// Optimize UI performance by reducing animations during heavy operations
    func optimizeUIPerformance(isProcessing: Bool) {
        DispatchQueue.main.async {
            if isProcessing {
                // Reduce animation duration during processing
                NSAnimationContext.current.duration = 0.1
            } else {
                // Restore normal animation duration
                NSAnimationContext.current.duration = 0.25
            }
        }
    }
}

/// View modifier for performance optimization
struct PerformanceOptimizedModifier: ViewModifier {
    let isProcessing: Bool
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                PerformanceOptimizer.shared.optimizeUIPerformance(isProcessing: isProcessing)
            }
            .onChange(of: isProcessing) { newValue in
                PerformanceOptimizer.shared.optimizeUIPerformance(isProcessing: newValue)
            }
    }
}

extension View {
    /// Apply performance optimizations based on processing state
    func performanceOptimized(isProcessing: Bool) -> some View {
        modifier(PerformanceOptimizedModifier(isProcessing: isProcessing))
    }
}