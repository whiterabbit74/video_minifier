import Foundation

/// Информация о видеофайле, полученная от FFmpeg
struct VideoInfo {
    let duration: TimeInterval
    let width: Int
    let height: Int
    let frameRate: Double
    let bitrate: Int64
    let hasAudio: Bool
    let audioCodec: String?
    let videoCodec: String?
}

// FFmpegError is now replaced by VideoCompressionError
// This enum is kept for backward compatibility during migration
typealias FFmpegError = VideoCompressionError

/// Протокол для сервиса работы с FFmpeg
protocol FFmpegServiceProtocol {
    /// Получить информацию о видеофайле
    /// - Parameter url: URL видеофайла
    /// - Returns: Информация о видео
    /// - Throws: VideoCompressionError при ошибке получения информации
    func getVideoInfo(url: URL) async throws -> VideoInfo
    
    /// Сжать видеофайл
    /// - Parameters:
    ///   - input: URL входного файла
    ///   - output: URL выходного файла
    ///   - settings: Настройки сжатия
    ///   - progressHandler: Callback для отслеживания прогресса (0.0 - 1.0)
    /// - Throws: VideoCompressionError при ошибке сжатия
    func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws
    
    /// Отменить текущую операцию сжатия
    func cancelCurrentOperation()
    
    /// Быстрое получение базовой информации о видео
    /// - Parameter url: URL видеофайла
    /// - Returns: Базовая информация о видео
    /// - Throws: VideoCompressionError при ошибке
    func getQuickVideoInfo(url: URL) async throws -> VideoInfo
    
    /// Очистить кэш метаданных
    func clearMetadataCache()
}