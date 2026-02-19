import Foundation

/// Enum representing various errors that can occur during video compression
enum VideoCompressionError: LocalizedError, Codable, Equatable {
    case ffmpegNotFound
    case unsupportedFormat(String)
    case compressionFailed(String)
    case fileNotFound(String)
    case insufficientSpace
    case cancelled
    case invalidInput(String)
    case outputPathError(String)
    case permissionDenied(String)
    case networkError(String)
    case corruptedFile(String)
    case unknownError(String)
    
    /// Localized error descriptions in Russian
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return NSLocalizedString("FFmpeg не найден в ресурсах приложения", comment: "")
        case .unsupportedFormat(let format):
            return String(format: NSLocalizedString("Неподдерживаемый формат видео: %@", comment: ""), format)
        case .compressionFailed(let message):
            return String(format: NSLocalizedString("Ошибка сжатия: %@", comment: ""), message)
        case .fileNotFound(let path):
            return String(format: NSLocalizedString("Файл не найден: %@", comment: ""), path)
        case .insufficientSpace:
            return NSLocalizedString("Недостаточно места на диске для сохранения сжатого файла", comment: "")
        case .cancelled:
            return NSLocalizedString("Операция отменена пользователем", comment: "")
        case .invalidInput(let message):
            return String(format: NSLocalizedString("Некорректный входной файл: %@", comment: ""), message)
        case .outputPathError(let path):
            return String(format: NSLocalizedString("Ошибка создания выходного файла: %@", comment: ""), path)
        case .permissionDenied(let path):
            return String(format: NSLocalizedString("Нет прав доступа к файлу: %@", comment: ""), path)
        case .networkError(let message):
            return String(format: NSLocalizedString("Ошибка сети: %@", comment: ""), message)
        case .corruptedFile(let path):
            return String(format: NSLocalizedString("Поврежденный файл: %@", comment: ""), path)
        case .unknownError(let message):
            return String(format: NSLocalizedString("Неизвестная ошибка: %@", comment: ""), message)
        }
    }
    
    /// Recovery suggestions for users
    var recoverySuggestion: String? {
        switch self {
        case .ffmpegNotFound:
            return NSLocalizedString("Переустановите приложение или обратитесь в службу поддержки", comment: "")
        case .unsupportedFormat:
            return NSLocalizedString("Попробуйте конвертировать файл в поддерживаемый формат", comment: "")
        case .compressionFailed:
            return NSLocalizedString("Проверьте настройки сжатия и попробуйте снова", comment: "")
        case .fileNotFound:
            return NSLocalizedString("Убедитесь, что файл существует и не был перемещен", comment: "")
        case .insufficientSpace:
            return NSLocalizedString("Освободите место на диске и попробуйте снова", comment: "")
        case .cancelled:
            return nil
        case .invalidInput:
            return NSLocalizedString("Выберите корректный видеофайл", comment: "")
        case .outputPathError:
            return NSLocalizedString("Проверьте права доступа к папке назначения", comment: "")
        case .permissionDenied:
            return NSLocalizedString("Предоставьте приложению права доступа к файлу", comment: "")
        case .networkError:
            return NSLocalizedString("Проверьте подключение к интернету", comment: "")
        case .corruptedFile:
            return NSLocalizedString("Попробуйте использовать другой файл", comment: "")
        case .unknownError:
            return NSLocalizedString("Попробуйте перезапустить приложение", comment: "")
        }
    }
    
    /// Error codes for programmatic handling
    var errorCode: Int {
        switch self {
        case .ffmpegNotFound: return 1001
        case .unsupportedFormat: return 1002
        case .compressionFailed: return 1003
        case .fileNotFound: return 1004
        case .insufficientSpace: return 1005
        case .cancelled: return 1006
        case .invalidInput: return 1007
        case .outputPathError: return 1008
        case .permissionDenied: return 1009
        case .networkError: return 1010
        case .corruptedFile: return 1011
        case .unknownError: return 1999
        }
    }
    
    /// Whether this error allows retry
    var isRetryable: Bool {
        switch self {
        case .ffmpegNotFound, .unsupportedFormat, .cancelled, .invalidInput:
            return false
        case .compressionFailed, .fileNotFound, .insufficientSpace, .outputPathError, 
             .permissionDenied, .networkError, .corruptedFile, .unknownError:
            return true
        }
    }
}
