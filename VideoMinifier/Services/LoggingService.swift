import Foundation
import OSLog

enum LogLevel: String, CaseIterable, Codable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var displayName: String {
        switch self {
        case .info: return NSLocalizedString("Информация", comment: "")
        case .warning: return NSLocalizedString("Предупреждение", comment: "")
        case .error: return NSLocalizedString("Ошибка", comment: "")
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

struct LogEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    let category: String
    
    private static let timestampFormatterKey = "LogEntry.timestampFormatter"
    
    private static func timestampFormatter() -> DateFormatter {
        let threadDictionary = Thread.current.threadDictionary
        if let formatter = threadDictionary[timestampFormatterKey] as? DateFormatter {
            return formatter
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        threadDictionary[timestampFormatterKey] = formatter
        return formatter
    }
    
    var formattedTimestamp: String {
        return Self.timestampFormatter().string(from: timestamp)
    }
    
    var formattedMessage: String {
        "[\(formattedTimestamp)] [\(level.rawValue)] [\(category)] \(message)"
    }
}

protocol LoggingServiceProtocol: ObservableObject {
    var logs: [LogEntry] { get }
    
    func log(_ message: String, level: LogLevel, category: String)
    func info(_ message: String, category: String)
    func warning(_ message: String, category: String)
    func error(_ message: String, category: String)
    func clearLogs()
    func exportLogs() -> String
    func filteredLogs(by level: LogLevel?) -> [LogEntry]
}

class LoggingService: LoggingServiceProtocol {
    static let shared = LoggingService()
    @Published var logs: [LogEntry] = []
    
    private let logger = Logger(subsystem: "com.videominifier.VideoMinifier", category: "LoggingService")
    private let maxLogEntries = 1000
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "logging.queue", qos: .utility)
    private var pendingEntries: [LogEntry] = []
    private var flushScheduled = false
    private var flushTimer: Timer?
    
    init() {
        // Создаем URL для файла логов в папке Application Support
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDirectory = appSupportURL.appendingPathComponent("VideoMinifier")
        
        // Создаем папку если её нет
        try? FileManager.default.createDirectory(at: appDirectory, 
                                               withIntermediateDirectories: true)
        
        logFileURL = appDirectory.appendingPathComponent("app.log")
        
        // Очищаем старые логи при запуске
        cleanupOldLogs()
        
        // Логируем запуск приложения
        info(NSLocalizedString("Приложение запущено", comment: ""), category: "App")
    }
    
    func log(_ message: String, level: LogLevel, category: String = "General") {
        let entry = LogEntry(timestamp: Date(), level: level, message: message, category: category)
        enqueueLogEntry(entry)
        
        // Логируем в системный лог
        logger.log(level: level.osLogType, "[\(category)] \(message)")
        
        // Сохраняем в файл асинхронно
        queue.async {
            self.writeToFile(entry)
        }
    }
    
    func info(_ message: String, category: String = "General") {
        log(message, level: .info, category: category)
    }
    
    func warning(_ message: String, category: String = "General") {
        log(message, level: .warning, category: category)
    }
    
    func error(_ message: String, category: String = "General") {
        log(message, level: .error, category: category)
    }
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.pendingEntries.removeAll()
            self.flushScheduled = false
            self.flushTimer?.invalidate()
            self.flushTimer = nil
        }
        
        queue.async {
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
        
        info(NSLocalizedString("Логи очищены", comment: ""), category: "Logging")
    }
    
    func exportLogs() -> String {
        return logs.map { $0.formattedMessage }.joined(separator: "\n")
    }
    
    func filteredLogs(by level: LogLevel?) -> [LogEntry] {
        guard let level = level else { return logs }
        return logs.filter { $0.level == level }
    }
    
    private func writeToFile(_ entry: LogEntry) {
        let logLine = entry.formattedMessage + "\n"
        guard let data = logLine.data(using: .utf8) else { return }
        
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            _ = FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        do {
            let fileHandle = try FileHandle(forWritingTo: logFileURL)
            defer {
                try? fileHandle.close()
            }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } catch {
            // Не падаем из-за ошибок записи логов
        }
    }
    
    private func cleanupOldLogs() {
        queue.async {
            guard FileManager.default.fileExists(atPath: self.logFileURL.path) else { return }
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: self.logFileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let daysSinceModification = Calendar.current.dateComponents([.day], 
                                                                              from: modificationDate, 
                                                                              to: Date()).day ?? 0
                    
                    // Удаляем логи старше 7 дней
                    if daysSinceModification > 7 {
                        try FileManager.default.removeItem(at: self.logFileURL)
                    }
                }
            } catch {
                // Игнорируем ошибки очистки
            }
        }
    }

    private func enqueueLogEntry(_ entry: LogEntry) {
        DispatchQueue.main.async {
            self.pendingEntries.append(entry)
            if !self.flushScheduled {
                self.flushScheduled = true
                self.scheduleFlush()
            }
        }
    }
    
    private func scheduleFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.flushPendingEntries()
        }
    }
    
    private func flushPendingEntries() {
        flushTimer?.invalidate()
        flushTimer = nil
        guard !pendingEntries.isEmpty else {
            flushScheduled = false
            return
        }
        
        logs.append(contentsOf: pendingEntries)
        pendingEntries.removeAll()
        flushScheduled = false
        
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
    }
}
