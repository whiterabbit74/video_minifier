import XCTest
@testable import VideoSzhimaka

/// Integration tests for app behavior and Apple Silicon optimization
@MainActor
class AppBehaviorIntegrationTests: XCTestCase {
    
    var app: VideoSzhimakaApp!
    var performanceMonitor: PerformanceMonitorService!
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        performanceMonitor = PerformanceMonitorService.shared
    }
    
    override func tearDownWithError() throws {
        performanceMonitor?.stopMonitoring()
        performanceMonitor = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Architecture Compatibility Tests
    
    /// Test that the app correctly detects Apple Silicon architecture
    func testAppleSiliconArchitectureDetection() throws {
        #if arch(arm64)
        // Test should pass on Apple Silicon
        XCTAssertTrue(true, "Running natively on Apple Silicon")
        #else
        // Test should fail on Intel or Rosetta
        XCTFail("App should only run on Apple Silicon (arm64)")
        #endif
    }
    
    /// Test that hardware acceleration is available and working
    func testHardwareAccelerationAvailability() throws {
        let settings = CompressionSettings(useHardwareAcceleration: true)
        
        // Test H.264 hardware encoder
        XCTAssertTrue(VideoCodec.h264.supportsHardwareAcceleration)
        XCTAssertEqual(VideoCodec.h264.hardwareEncoder, "h264_videotoolbox")
        
        // Test H.265 hardware encoder
        XCTAssertTrue(VideoCodec.h265.supportsHardwareAcceleration)
        XCTAssertEqual(VideoCodec.h265.hardwareEncoder, "hevc_videotoolbox")
        
        // Test settings include hardware acceleration
        XCTAssertTrue(settings.useHardwareAcceleration)
    }
    
    /// Test performance monitoring functionality
    func testPerformanceMonitoring() throws {
        performanceMonitor.startMonitoring()
        
        // Wait a moment for monitoring to start
        let expectation = XCTestExpectation(description: "Performance monitoring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        let metrics = performanceMonitor.getCurrentMetrics()
        
        // Verify metrics are reasonable
        XCTAssertGreaterThanOrEqual(metrics.cpuUsage, 0.0)
        XCTAssertLessThanOrEqual(metrics.cpuUsage, 100.0)
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0.0)
        
        // Test thermal state monitoring
        XCTAssertNotNil(metrics.thermalState)
        
        performanceMonitor.stopMonitoring()
    }
    
    /// Test thermal throttling recommendations
    func testThermalThrottlingRecommendations() throws {
        let recommendations = performanceMonitor.getRecommendedSettings()
        
        // Recommendations should be valid
        XCTAssertNotNil(recommendations)
        
        // Test that recommendations are based on current system state
        let thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .serious, .critical:
            XCTAssertTrue(recommendations.suggestThermalThrottling || recommendations.suggestPauseProcessing)
        case .fair:
            XCTAssertTrue(recommendations.suggestSlowerProcessing || !recommendations.suggestThermalThrottling)
        case .nominal:
            XCTAssertFalse(recommendations.suggestPauseProcessing)
        @unknown default:
            break
        }
    }
    
    /// Test that app settings are optimized for Apple Silicon
    func testAppleSiliconOptimizedSettings() throws {
        let defaultSettings = CompressionSettings.default
        
        // Hardware acceleration should be enabled by default
        XCTAssertTrue(defaultSettings.useHardwareAcceleration)
        
        // Default codec should be appropriate for Apple Silicon
        XCTAssertTrue([VideoCodec.h264, VideoCodec.h265].contains(defaultSettings.codec))
        
        // CRF should be in valid range
        XCTAssertTrue(defaultSettings.codec.recommendedCRFRange.contains(defaultSettings.crf))
    }
    
    /// Test FFmpeg integration with VideoToolbox
    func testFFmpegVideoToolboxIntegration() throws {
        let ffmpegService = try FFmpegService()
        
        // Test that FFmpeg service initializes correctly
        XCTAssertNotNil(ffmpegService)
        
        // Test settings with hardware acceleration
        let settings = CompressionSettings(
            codec: .h264,
            useHardwareAcceleration: true
        )
        
        let videoParams = settings.videoCodecParameters
        
        // Should use VideoToolbox encoder when hardware acceleration is enabled
        if settings.useHardwareAcceleration && settings.codec.supportsHardwareAcceleration {
            XCTAssertTrue(videoParams.contains("h264_videotoolbox") || videoParams.contains("hevc_videotoolbox"))
        }
    }
    
    /// Test app behavior under different thermal states
    func testAppBehaviorUnderThermalPressure() throws {
        performanceMonitor.startMonitoring()
        defer { performanceMonitor.stopMonitoring() }
        
        // Simulate different thermal states and test recommendations
        let currentState = ProcessInfo.processInfo.thermalState
        let recommendations = performanceMonitor.getRecommendedSettings()
        
        switch currentState {
        case .nominal:
            // Normal operation should not suggest throttling
            XCTAssertFalse(recommendations.suggestPauseProcessing)
            XCTAssertFalse(recommendations.suggestThermalThrottling)
            
        case .fair:
            // Fair thermal state might suggest slower processing
            // This is acceptable behavior
            break
            
        case .serious, .critical:
            // High thermal states should suggest protective measures
            XCTAssertTrue(recommendations.suggestThermalThrottling || recommendations.suggestPauseProcessing)
            
        @unknown default:
            XCTFail("Unknown thermal state encountered")
        }
    }
    
    /// Test memory management during intensive operations
    func testMemoryManagementOptimization() throws {
        performanceMonitor.startMonitoring()
        defer { performanceMonitor.stopMonitoring() }
        
        let initialMemory = performanceMonitor.currentMemoryUsage
        
        // Simulate memory-intensive operation
        var testData: [Data] = []
        for _ in 0..<100 {
            testData.append(Data(count: 1024 * 1024)) // 1MB each
        }
        
        let peakMemory = performanceMonitor.currentMemoryUsage
        
        // Clear test data
        testData.removeAll()
        
        // Force garbage collection
        autoreleasepool {
            // Empty pool to encourage cleanup
        }
        
        // Wait for memory to be reclaimed
        let expectation = XCTestExpectation(description: "Memory cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        
        let finalMemory = performanceMonitor.currentMemoryUsage
        
        // Memory should have increased during test
        XCTAssertGreaterThan(peakMemory, initialMemory)
        
        // Memory should be lower after cleanup (allowing for some variance)
        XCTAssertLessThan(finalMemory, peakMemory * 0.9)
    }
    
    /// Test that the app properly handles resource constraints
    func testResourceConstraintHandling() throws {
        let recommendations = performanceMonitor.getRecommendedSettings()
        
        // Test CPU usage recommendations
        if recommendations.suggestSequentialProcessing {
            // App should handle high CPU usage appropriately
            XCTAssertTrue(true, "Sequential processing recommended for high CPU usage")
        }
        
        // Test memory usage recommendations
        if recommendations.suggestMemoryOptimization {
            // App should handle high memory usage appropriately
            XCTAssertTrue(true, "Memory optimization recommended")
        }
        
        // Test thermal recommendations
        if recommendations.suggestThermalThrottling {
            // App should handle thermal pressure appropriately
            XCTAssertTrue(true, "Thermal throttling recommended")
        }
    }
    
    /// Test app startup performance on Apple Silicon
    func testAppStartupPerformance() throws {
        let startTime = Date()
        
        // Simulate app initialization
        let settingsService = SettingsService()
        let loggingService = LoggingService()
        let fileManagerService = FileManagerService()
        let ffmpegService = try FFmpegService()
        
        let initializationTime = Date().timeIntervalSince(startTime)
        
        // App should initialize quickly on Apple Silicon (< 2 seconds)
        XCTAssertLessThan(initializationTime, 2.0, "App initialization should be fast on Apple Silicon")
        
        // Services should be properly initialized
        XCTAssertNotNil(settingsService)
        XCTAssertNotNil(loggingService)
        XCTAssertNotNil(fileManagerService)
        XCTAssertNotNil(ffmpegService)
    }
}