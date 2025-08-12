import Foundation
import os.log

/// Service for monitoring performance and resource usage during video compression
class PerformanceMonitorService: ObservableObject {
    static let shared = PerformanceMonitorService()
    
    @Published var currentCPUUsage: Double = 0.0
    @Published var currentMemoryUsage: Double = 0.0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    
    private let logger = Logger(subsystem: "com.videoszhimaka.VideoSzhimaka", category: "Performance")
    private var monitoringTimer: Timer?
    private var isMonitoring = false
    
    private init() {
        setupThermalStateMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start performance monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
        
        logger.info("Performance monitoring started")
    }
    
    /// Stop performance monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        
        logger.info("Performance monitoring stopped")
    }
    
    /// Get current system performance metrics
    func getCurrentMetrics() -> PerformanceMetrics {
        return PerformanceMetrics(
            cpuUsage: getCPUUsage(),
            memoryUsage: getMemoryUsage(),
            thermalState: ProcessInfo.processInfo.thermalState,
            timestamp: Date()
        )
    }
    
    /// Check if system is under thermal pressure
    func isUnderThermalPressure() -> Bool {
        return thermalState == .serious || thermalState == .critical
    }
    
    /// Get recommended compression settings based on current performance
    func getRecommendedSettings() -> PerformanceRecommendations {
        let metrics = getCurrentMetrics()
        
        var recommendations = PerformanceRecommendations()
        
        // Adjust based on CPU usage
        if metrics.cpuUsage > 80 {
            recommendations.suggestLowerCRF = true
            recommendations.suggestSequentialProcessing = true
        }
        
        // Adjust based on memory usage
        if metrics.memoryUsage > 80 {
            recommendations.suggestMemoryOptimization = true
        }
        
        // Adjust based on thermal state
        switch metrics.thermalState {
        case .serious, .critical:
            recommendations.suggestThermalThrottling = true
            recommendations.suggestPauseProcessing = true
        case .fair:
            recommendations.suggestSlowerProcessing = true
        case .nominal:
            break
        @unknown default:
            break
        }
        
        return recommendations
    }
    
    // MARK: - Private Methods
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
            self?.logger.info("Thermal state changed to: \(ProcessInfo.processInfo.thermalState.rawValue)")
        }
    }
    
    private func updatePerformanceMetrics() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cpuUsage = self?.getCPUUsage() ?? 0.0
            let memoryUsage = self?.getMemoryUsage() ?? 0.0
            
            DispatchQueue.main.async {
                self?.currentCPUUsage = cpuUsage
                self?.currentMemoryUsage = memoryUsage
            }
        }
    }
    
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100.0
        }
        
        return 0.0
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / (1024 * 1024) // MB
        }
        
        return 0.0
    }
}

// MARK: - Supporting Types

struct PerformanceMetrics {
    let cpuUsage: Double
    let memoryUsage: Double
    let thermalState: ProcessInfo.ThermalState
    let timestamp: Date
}

struct PerformanceRecommendations {
    var suggestLowerCRF = false
    var suggestSequentialProcessing = false
    var suggestMemoryOptimization = false
    var suggestThermalThrottling = false
    var suggestPauseProcessing = false
    var suggestSlowerProcessing = false
}

// MARK: - Extensions

extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal:
            return "Нормальная"
        case .fair:
            return "Умеренная"
        case .serious:
            return "Высокая"
        case .critical:
            return "Критическая"
        @unknown default:
            return "Неизвестная"
        }
    }
}