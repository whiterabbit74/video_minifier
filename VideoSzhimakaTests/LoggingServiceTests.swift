import XCTest
@testable import VideoSzhimaka

@MainActor
final class LoggingServiceTests: XCTestCase {
    var loggingService: LoggingService!
    
    // Хелпер: дождаться выполнения задач в главной очереди (для асинхронного добавления логов)
    func flushMainQueue() {
        let exp = expectation(description: "flush main queue")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }
    
    @MainActor override func setUp() {
        super.setUp()
        loggingService = LoggingService()
        // Don't clear logs here as it will add another log entry
        // Дожидаемся, пока init залогирует "Приложение запущено"
        flushMainQueue()
    }
    
    override func tearDown() {
        loggingService = nil
        super.tearDown()
    }
    
    func testLogEntry() {
        // Given
        let message = "Test message"
        let category = "Test"
        let initialCount = loggingService.logs.count
        
        // When
        loggingService.info(message, category: category)
        flushMainQueue()
        
        // Then
        XCTAssertEqual(loggingService.logs.count, initialCount + 1)
        let lastLog = loggingService.logs.last!
        XCTAssertEqual(lastLog.message, message)
        XCTAssertEqual(lastLog.category, category)
        XCTAssertEqual(lastLog.level, .info)
    }
    
    func testLogLevels() {
        // Given
        let message = "Test message"
        let category = "Test"
        let initialCount = loggingService.logs.count
        
        // When
        loggingService.info(message, category: category)
        loggingService.warning(message, category: category)
        loggingService.error(message, category: category)
        flushMainQueue()
        
        // Then
        XCTAssertEqual(loggingService.logs.count, initialCount + 3)
        let logs = loggingService.logs.suffix(3) // Get last 3 logs
        XCTAssertEqual(logs.count, 3)
        XCTAssertEqual(Array(logs)[0].level, .info)
        XCTAssertEqual(Array(logs)[1].level, .warning)
        XCTAssertEqual(Array(logs)[2].level, .error)
    }
    
    func testFilteredLogs() {
        // Given
        loggingService.info("Info message", category: "Test")
        loggingService.warning("Warning message", category: "Test")
        loggingService.error("Error message", category: "Test")
        flushMainQueue()
        
        // When
        let infoLogs = loggingService.filteredLogs(by: .info)
        let warningLogs = loggingService.filteredLogs(by: .warning)
        let errorLogs = loggingService.filteredLogs(by: .error)
        let allLogs = loggingService.filteredLogs(by: nil)
        
        // Then
        XCTAssertTrue(infoLogs.contains { $0.message == "Info message" })
        XCTAssertTrue(warningLogs.contains { $0.message == "Warning message" })
        XCTAssertTrue(errorLogs.contains { $0.message == "Error message" })
        XCTAssertGreaterThanOrEqual(allLogs.count, 3) // At least the 3 test logs
    }
    
    func testClearLogs() {
        // Given
        loggingService.info("Test message", category: "Test")
        flushMainQueue()
        XCTAssertGreaterThan(loggingService.logs.count, 0)
        
        // When
        loggingService.clearLogs()
        flushMainQueue()
        
        // Then
        XCTAssertEqual(loggingService.logs.count, 1) // Only the "Логи очищены" message
        XCTAssertEqual(loggingService.logs.last?.message, "Логи очищены")
    }
    
    func testExportLogs() {
        // Given
        loggingService.info("Test message 1", category: "Test")
        loggingService.warning("Test message 2", category: "Test")
        flushMainQueue()
        
        // When
        let exportedLogs = loggingService.exportLogs()
        
        // Then
        XCTAssertTrue(exportedLogs.contains("Test message 1"))
        XCTAssertTrue(exportedLogs.contains("Test message 2"))
        XCTAssertTrue(exportedLogs.contains("[INFO]"))
        XCTAssertTrue(exportedLogs.contains("[WARNING]"))
    }
    
    func testLogEntryFormatting() {
        // Given
        let entry = LogEntry(
            timestamp: Date(),
            level: .info,
            message: "Test message",
            category: "Test"
        )
        
        // When
        let formattedMessage = entry.formattedMessage
        let formattedTimestamp = entry.formattedTimestamp
        
        // Then
        XCTAssertTrue(formattedMessage.contains("Test message"))
        XCTAssertTrue(formattedMessage.contains("[INFO]"))
        XCTAssertTrue(formattedMessage.contains("[Test]"))
        XCTAssertFalse(formattedTimestamp.isEmpty)
    }
    
    func testLogLevelDisplayNames() {
        // Then
        XCTAssertEqual(LogLevel.info.displayName, "Информация")
        XCTAssertEqual(LogLevel.warning.displayName, "Предупреждение")
        XCTAssertEqual(LogLevel.error.displayName, "Ошибка")
    }
    
    func testMaxLogEntries() {
        // Given
        let maxEntries = 1000
        
        // When - Add more than max entries
        for i in 0..<(maxEntries + 100) {
            loggingService.info("Message \(i)", category: "Test")
        }
        flushMainQueue()
        
        // Then
        XCTAssertLessThanOrEqual(loggingService.logs.count, maxEntries)
    }
    
    func testConcurrentLogging() {
        // Given
        let expectation = XCTestExpectation(description: "Concurrent logging")
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()
        
        // When - Log from multiple threads
        for i in 0..<100 {
            group.enter()
            queue.async {
                self.loggingService.info("Concurrent message \(i)", category: "Concurrent")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        flushMainQueue()
        
        // Then
        let concurrentLogs = loggingService.logs.filter { $0.category == "Concurrent" }
        XCTAssertEqual(concurrentLogs.count, 100)
    }
}