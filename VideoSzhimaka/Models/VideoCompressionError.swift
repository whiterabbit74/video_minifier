import Foundation

/// Enum representing various errors that can occur during video compression
enum VideoCompressionError: LocalizedError {
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
            return "FFmpeg не найден в ресурсах приложения"
        case .unsupportedFormat(let format):
            return "Неподдерживаемый формат видео: \(format)"
        case .compressionFailed(let message):
            return "Ошибка сжатия: \(message)"
        case .fileNotFound(let path):
            return "Файл не найден: \(path)"
        case .insufficientSpace:
            return "Недостаточно места на диске для сохранения сжатого файла"
        case .cancelled:
            return "Операция отменена пользователем"
        case .invalidInput(let message):
            return "Некорректный входной файл: \(message)"
        case .outputPathError(let path):
            return "Ошибка создания выходного файла: \(path)"
        case .permissionDenied(let path):
            return "Нет прав доступа к файлу: \(path)"
        case .networkError(let message):
            return "Ошибка сети: \(message)"
        case .corruptedFile(let path):
            return "Поврежденный файл: \(path)"
        case .unknownError(let message):
            return "Неизвестная ошибка: \(message)"
        }
    }
    
    /// Recovery suggestions for users
    var recoverySuggestion: String? {
        switch self {
        case .ffmpegNotFound:
            return "Переустановите приложение или обратитесь в службу поддержки"
        case .unsupportedFormat:
            return "Попробуйте конвертировать файл в поддерживаемый формат"
        case .compressionFailed:
            return "Проверьте настройки сжатия и попробуйте снова"
        case .fileNotFound:
            return "Убедитесь, что файл существует и не был перемещен"
        case .insufficientSpace:
            return "Освободите место на диске и попробуйте снова"
        case .cancelled:
            return nil
        case .invalidInput:
            return "Выберите корректный видеофайл"
        case .outputPathError:
            return "Проверьте права доступа к папке назначения"
        case .permissionDenied:
            return "Предоставьте приложению права доступа к файлу"
        case .networkError:
            return "Проверьте подключение к интернету"
        case .corruptedFile:
            return "Попробуйте использовать другой файл"
        case .unknownError:
            return "Попробуйте перезапустить приложение"
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