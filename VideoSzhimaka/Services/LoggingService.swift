import Foundation
import OSLog

enum LogLevel: String, CaseIterable, Codable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var displayName: String {
        switch self {
        case .info: return "Информация"
        case .warning: return "Предупреждение"
        case .error: return "Ошибка"
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
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
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
    @Published var logs: [LogEntry] = []
    
    private let logger = Logger(subsystem: "com.videoszhimaka.VideoSzhimaka", category: "LoggingService")
    private let maxLogEntries = 1000
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "logging.queue", qos: .utility)
    
    init() {
        // Создаем URL для файла логов в папке Application Support
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                   in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDirectory = appSupportURL.appendingPathComponent("VideoSzhimaka")
        
        // Создаем папку если её нет
        try? FileManager.default.createDirectory(at: appDirectory, 
                                               withIntermediateDirectories: true)
        
        logFileURL = appDirectory.appendingPathComponent("app.log")
        
        // Очищаем старые логи при запуске
        cleanupOldLogs()
        
        // Логируем запуск приложения
        info("Приложение запущено", category: "App")
    }
    
    func log(_ message: String, level: LogLevel, category: String = "General") {
        let entry = LogEntry(timestamp: Date(), level: level, message: message, category: category)
        
        DispatchQueue.main.async {
            self.logs.append(entry)
            
            // Ограничиваем количество логов в памяти
            if self.logs.count > self.maxLogEntries {
                self.logs.removeFirst(self.logs.count - self.maxLogEntries)
            }
        }
        
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
        }
        
        queue.async {
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
        
        info("Логи очищены", category: "Logging")
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
        
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logLine.data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            }
        } else {
            try? logLine.write(to: logFileURL, atomically: true, encoding: .utf8)
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
}