import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main view model that manages the video compression workflow
@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// List of video files in the compression queue
    @Published var videoFiles: [VideoFile] = []
    
    /// Whether any compression operation is currently in progress
    @Published var isProcessing = false
    
    /// Whether the settings panel is currently shown
    @Published var showSettings = false
    
    /// Whether the logs window is currently shown
    @Published var showLogs = false
    
    /// Current error to display to the user
    @Published var currentError: VideoCompressionError?
    
    /// List of errors that occurred during batch processing
    @Published var batchErrors: [VideoCompressionError] = []
    
    /// Whether to show the batch errors alert
    @Published var showBatchErrorsAlert = false
    
    // MARK: - Private Properties
    
    private let ffmpegService: FFmpegServiceProtocol
    private let fileManagerService: FileManagerServiceProtocol
    private let settingsService: any SettingsServiceProtocol
    let loggingService: LoggingService
    private let performanceMonitor: PerformanceMonitorService
    
    /// Queue for sequential file processing
    private var processingQueue: [UUID] = []
    
    /// Currently processing file ID
    @Published var currentlyProcessingFileId: UUID?
    
    /// Task for current compression operation (for cancellation)
    private var currentCompressionTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(
        ffmpegService: FFmpegServiceProtocol,
        fileManagerService: FileManagerServiceProtocol,
        settingsService: any SettingsServiceProtocol,
        loggingService: LoggingService,
        performanceMonitor: PerformanceMonitorService = PerformanceMonitorService.shared
    ) {
        self.ffmpegService = ffmpegService
        self.fileManagerService = fileManagerService
        self.settingsService = settingsService
        self.loggingService = loggingService
        self.performanceMonitor = performanceMonitor
    }
    

    
    // MARK: - File Management
    
    /// Add video files from URLs (drag & drop or file dialog)
    /// - Parameter urls: Array of file URLs to add
    func addFiles(_ urls: [URL]) {
        // Добавляем файлы синхронно (метаданные подтянутся асинхронно внутри)
        for url in urls {
            addSingleFile(url)
        }
    }
    
    /// Add a single video file
    /// - Parameter url: URL of the video file to add
    private func addSingleFile(_ url: URL) {
        // Check if file already exists in the list
        if videoFiles.contains(where: { $0.url == url }) {
            loggingService.warning("Файл уже добавлен: \(url.lastPathComponent)", category: "FileManagement")
            return
        }
        
        do {
            loggingService.info("Добавление файла: \(url.lastPathComponent)", category: "FileManagement")
            
            // Сначала получаем размер файла и добавляем файл с базовой информацией
            let fileSize = try fileManagerService.getFileSize(url: url)
            
            // Создаем VideoFile с базовой информацией для быстрого отображения
            let videoFile = VideoFile(
                url: url,
                name: url.lastPathComponent,
                duration: 0, // Будет обновлено позже
                originalSize: fileSize
            )
            
            // Добавляем в список сразу для быстрого отображения
            videoFiles.append(videoFile)
            loggingService.info("Файл добавлен в список (анализ метаданных...): \(url.lastPathComponent)", category: "FileManagement")
            
            // Теперь получаем полную информацию о видео в фоне
            Task {
                do {
                    let videoInfo = try await ffmpegService.getVideoInfo(url: url)
                    
                    // Обновляем информацию о файле
                    if let index = videoFiles.firstIndex(where: { $0.id == videoFile.id }) {
                        var updatedFile = videoFiles[index]
                        updatedFile.duration = videoInfo.duration
                        videoFiles[index] = updatedFile
                        
                        loggingService.info("Метаданные получены: \(url.lastPathComponent) (длительность: \(videoInfo.duration.formattedDuration))", category: "FileManagement")
                    }
                } catch {
                    let compressionError = mapToCompressionError(error)
                    loggingService.error("Не удалось получить метаданные для \(url.lastPathComponent): \(compressionError.localizedDescription)", category: "FileManagement")
                    
                    // Помечаем файл как проблемный, но не удаляем из списка
                    if let index = videoFiles.firstIndex(where: { $0.id == videoFile.id }) {
                        var updatedFile = videoFiles[index]
                        updatedFile.status = .failed(compressionError)
                        videoFiles[index] = updatedFile
                    }
                }
            }
            
        } catch {
            let compressionError = mapToCompressionError(error)
            loggingService.error("Не удалось добавить файл \(url.lastPathComponent): \(compressionError.localizedDescription)", category: "FileManagement")
            showError(compressionError)
        }
    }
    
    /// Remove a video file from the list
    /// - Parameter fileId: ID of the file to remove
    func removeFile(withId fileId: UUID) {
        // Don't allow removal of currently processing file
        if currentlyProcessingFileId == fileId {
            loggingService.warning("Попытка удалить файл, который сейчас обрабатывается", category: "FileManagement")
            return
        }
        
        // Find file name for logging
        let fileName = videoFiles.first(where: { $0.id == fileId })?.name ?? "Unknown"
        
        // Remove from processing queue if present
        processingQueue.removeAll { $0 == fileId }
        
        // Remove from video files list
        videoFiles.removeAll { $0.id == fileId }
        
        loggingService.info("Файл удален из списка: \(fileName)", category: "FileManagement")
    }
    
    /// Remove all files from the list
    func removeAllFiles() {
        // Cancel current processing if any
        cancelAllProcessing()
        
        // Clear all data
        videoFiles.removeAll()
        processingQueue.removeAll()
        currentlyProcessingFileId = nil
    }
    
    // MARK: - Compression Operations
    
    /// Compress a single video file
    /// - Parameter fileId: ID of the file to compress
    func compressFile(withId fileId: UUID) {
        guard videoFiles.firstIndex(where: { $0.id == fileId }) != nil else {
            return
        }
        
        // Don't start if already processing this file
        if currentlyProcessingFileId == fileId {
            return
        }
        
        // Add to processing queue if not already there
        if !processingQueue.contains(fileId) {
            processingQueue.append(fileId)
        }
        
        // Start processing if not already processing
        if !isProcessing {
            processNextFile()
        }
    }
    
    /// Compress all files in the list
    func compressAllFiles() {
        // Add all pending files to processing queue
        for file in videoFiles where file.status == .pending {
            if !processingQueue.contains(file.id) {
                processingQueue.append(file.id)
            }
        }
        
        // Start processing if not already processing
        if !isProcessing {
            processNextFile()
        }
    }
    
    /// Cancel all compression operations
    func cancelAllProcessing() {
        loggingService.info("Отмена всех операций сжатия", category: "Compression")
        
        // Store references before clearing to avoid race conditions
        let taskToCancel = currentCompressionTask
        let previouslyProcessingFileId = currentlyProcessingFileId
        
        // Clear processing state first to signal cancellation
        currentCompressionTask = nil
        currentlyProcessingFileId = nil
        isProcessing = false
        processingQueue.removeAll()
        
        // Cancel current task after clearing state
        taskToCancel?.cancel()
        
        // Cancel FFmpeg operation
        ffmpegService.cancelCurrentOperation()
        
        // Reset status of compressing files safely
        for index in videoFiles.indices {
            if videoFiles[index].status == .compressing {
                videoFiles[index].status = .pending
                videoFiles[index].compressionProgress = 0.0
                
                if videoFiles[index].id == previouslyProcessingFileId {
                    loggingService.info("Отменено сжатие файла: \(videoFiles[index].name)", category: "Compression")
                }
            }
        }
    }
    
    /// Process the next file in the queue
    private func processNextFile() {
        // Check if there are files to process
        guard !processingQueue.isEmpty else {
            isProcessing = false
            currentlyProcessingFileId = nil
            
            // Check if auto-close is enabled and all files are processed
            if settingsService.settings.autoCloseApp && allFilesProcessed() {
                NSApplication.shared.terminate(nil)
            }
            
            return
        }
        
        // Get next file ID
        let fileId = processingQueue.removeFirst()
        
        // Find the file in the list
        guard let fileIndex = videoFiles.firstIndex(where: { $0.id == fileId }) else {
            // File not found, process next
            processNextFile()
            return
        }
        
        // Skip if file is already completed or failed
        if videoFiles[fileIndex].status.isFinished {
            processNextFile()
            return
        }
        
        // Set processing state
        isProcessing = true
        currentlyProcessingFileId = fileId
        videoFiles[fileIndex].status = .compressing
        videoFiles[fileIndex].compressionProgress = 0.0
        
        // Start compression task
        currentCompressionTask = Task {
            do {
                try Task.checkCancellation()
                await compressFileAtIndex(fileIndex)
                
                // Check if task was cancelled before processing next file
                try Task.checkCancellation()
                
                // Process next file only if not cancelled and still processing
                if !Task.isCancelled && isProcessing {
                    processNextFile()
                }
            } catch is CancellationError {
                loggingService.info("Задача сжатия была отменена", category: "Compression")
                // Ensure processing state is cleared on cancellation
                isProcessing = false
                currentlyProcessingFileId = nil
            } catch {
                loggingService.error("Неожиданная ошибка в задаче сжатия: \(error)", category: "Compression")
                // Process next file even on error, but only if still processing
                if isProcessing {
                    processNextFile()
                }
            }
        }
    }
    
    /// Compress the file at the specified index
    /// - Parameter index: Index of the file in the videoFiles array
    private func compressFileAtIndex(_ index: Int) async {
        // Safely get the file and validate index bounds
        guard index >= 0 && index < videoFiles.count else {
            loggingService.error("Недопустимый индекс файла: \(index), размер массива: \(videoFiles.count)", category: "Compression")
            return
        }
        
        let file = videoFiles[index]
        let fileId = file.id
        
        do {
            // Check for cancellation before starting
            try Task.checkCancellation()
            
            loggingService.info("Начало сжатия файла: \(file.name)", category: "Compression")
            
            // Start performance monitoring
            performanceMonitor.startMonitoring()
            
            // Check system performance before starting
            let _ = performanceMonitor.getCurrentMetrics()
            let recommendations = performanceMonitor.getRecommendedSettings()
            
            if recommendations.suggestPauseProcessing {
                loggingService.warning("Система перегрета, рекомендуется пауза в обработке", category: "Performance")
            }
            
            // Generate output URL
            let outputURL = fileManagerService.generateOutputURL(for: file.url)
            
            // Adjust settings based on performance recommendations
            var adjustedSettings = settingsService.settings
            if recommendations.suggestThermalThrottling {
                adjustedSettings.useHardwareAcceleration = false
                loggingService.info("Отключено аппаратное ускорение из-за перегрева", category: "Performance")
            }
            
            // Check for cancellation before starting compression
            try Task.checkCancellation()
            
            // Compress the video
            try await ffmpegService.compressVideo(
                input: file.url,
                output: outputURL,
                settings: adjustedSettings
            ) { [weak self] progress in
                Task { @MainActor in
                    // Check if task is still valid before updating progress
                    guard let self = self, !Task.isCancelled else { return }
                    
                    self.updateCompressionProgress(fileId: fileId, progress: progress)
                    
                    // Monitor performance during compression
                    let _ = self.performanceMonitor.getCurrentMetrics()
                    if self.performanceMonitor.isUnderThermalPressure() {
                        self.loggingService.warning("Обнаружен перегрев во время сжатия", category: "Performance")
                    }
                }
            }
            
            // Check for cancellation after compression
            try Task.checkCancellation()
            
            // Get compressed file size
            let compressedSize = try fileManagerService.getFileSize(url: outputURL)
            
            // Safely update file status using fileId instead of index
            if let currentIndex = videoFiles.firstIndex(where: { $0.id == fileId }) {
                videoFiles[currentIndex].status = .completed
                videoFiles[currentIndex].compressedSize = compressedSize
                videoFiles[currentIndex].compressionProgress = 1.0
            }
            
            let compressionRatio = (1.0 - Double(compressedSize) / Double(file.originalSize)) * 100.0
            
            // Log performance metrics
            let finalMetrics = performanceMonitor.getCurrentMetrics()
            loggingService.info("Сжатие завершено: \(file.name) (\(file.originalSize.formattedFileSize) → \(compressedSize.formattedFileSize), экономия: \(String(format: "%.1f", compressionRatio))%)", category: "Compression")
            loggingService.info("Производительность: CPU \(String(format: "%.1f", finalMetrics.cpuUsage))%, Память \(String(format: "%.1f", finalMetrics.memoryUsage))MB, Температура: \(finalMetrics.thermalState.description)", category: "Performance")
            
            // Delete original file if requested
            if settingsService.settings.deleteOriginals {
                try fileManagerService.deleteFile(at: file.url)
                loggingService.info("Оригинальный файл удален: \(file.name)", category: "FileManagement")
            }
            
        } catch is CancellationError {
            // Handle cancellation gracefully
            loggingService.info("Сжатие файла отменено: \(file.name)", category: "Compression")
            
            // Safely reset file status using fileId instead of index
            if let currentIndex = videoFiles.firstIndex(where: { $0.id == fileId }) {
                if videoFiles[currentIndex].status == .compressing {
                    videoFiles[currentIndex].status = .pending
                    videoFiles[currentIndex].compressionProgress = 0.0
                }
            }
            
        } catch {
            // Handle compression failure with graceful degradation
            let compressionError = mapToCompressionError(error)
            
            // Проверяем, не является ли это отменой операции
            if case .cancelled = compressionError {
                loggingService.info("Сжатие файла отменено пользователем: \(file.name)", category: "Compression")
                
                // Safely reset file status for cancelled operations
                if let currentIndex = videoFiles.firstIndex(where: { $0.id == fileId }) {
                    if videoFiles[currentIndex].status == .compressing {
                        videoFiles[currentIndex].status = .pending
                        videoFiles[currentIndex].compressionProgress = 0.0
                    }
                }
                
                // Не добавляем отмененные операции в список ошибок
                return
            }
            
            // Safely update file status using fileId instead of index
            if let currentIndex = videoFiles.firstIndex(where: { $0.id == fileId }) {
                videoFiles[currentIndex].status = .failed(compressionError)
                videoFiles[currentIndex].compressionProgress = 0.0
            }
            
            loggingService.error("Ошибка сжатия файла \(file.name): \(compressionError.localizedDescription)", category: "Compression")
            
            // Add to batch errors for later display
            batchErrors.append(compressionError)
            
            // Continue processing other files (graceful degradation)
            // Don't show individual error alerts during batch processing
            if processingQueue.isEmpty {
                await showBatchErrorsIfNeeded()
            }
        }
        
        // Stop performance monitoring if no more files in queue
        if processingQueue.isEmpty {
            performanceMonitor.stopMonitoring()
        }
    }
    
    /// Update compression progress for a specific file
    /// - Parameters:
    ///   - fileId: ID of the file being compressed
    ///   - progress: Progress value (0.0 to 1.0)
    private func updateCompressionProgress(fileId: UUID, progress: Double) {
        guard let index = videoFiles.firstIndex(where: { $0.id == fileId }) else {
            return
        }
        
        videoFiles[index].compressionProgress = progress
    }
    
    // MARK: - File Dialog
    
    /// Show file picker dialog to add video files
    func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .quickTimeMovie,
            .movie,
            UTType(filenameExtension: "mkv") ?? .data,
            UTType(filenameExtension: "avi") ?? .data,
            UTType(filenameExtension: "webm") ?? .data,
            UTType(filenameExtension: "flv") ?? .data,
            UTType(filenameExtension: "wmv") ?? .data
        ]
        
        // Set default directory to Downloads
        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloadsURL
        }
        
        panel.begin { [weak self] response in
            if response == .OK {
                self?.addFiles(panel.urls)
            }
        }
    }
    
    // MARK: - Drag & Drop Support
    
    /// Check if the provided items can be dropped
    /// - Parameter providers: Array of NSItemProvider objects
    /// - Returns: True if items can be dropped, false otherwise
    func canDropItems(_ providers: [NSItemProvider]) -> Bool {
        return providers.allSatisfy { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
    }
    
    /// Handle dropped items
    /// - Parameter providers: Array of NSItemProvider objects
    /// - Returns: True if drop was handled successfully
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            group.enter()
            
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            // Filter for video files
            let videoURLs = urls.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["mp4", "mov", "mkv", "avi", "webm", "flv", "wmv", "m4v"].contains(pathExtension)
            }
            
            if !videoURLs.isEmpty {
                self?.addFiles(videoURLs)
            }
        }
        
        return true
    }
    
    // MARK: - Utility Methods
    
    /// Show error to the user
    /// - Parameter error: Error to display
    private func showError(_ error: VideoCompressionError) {
        currentError = error
    }
    
    /// Show batch errors if any occurred
    private func showBatchErrorsIfNeeded() async {
        if !batchErrors.isEmpty {
            showBatchErrorsAlert = true
        }
    }
    
    /// Clear batch errors
    func clearBatchErrors() {
        batchErrors.removeAll()
        showBatchErrorsAlert = false
    }
    
    /// Retry all failed files
    func retryAllFailedFiles() {
        let failedFileIds = videoFiles.compactMap { file in
            if case .failed = file.status {
                return file.id
            }
            return nil
        }
        
        // Clear batch errors
        clearBatchErrors()
        
        // Reset failed files and retry
        for fileId in failedFileIds {
            retryCompression(forFileId: fileId)
        }
    }
    
    /// Map generic errors to VideoCompressionError
    private func mapToCompressionError(_ error: Error) -> VideoCompressionError {
        if let compressionError = error as? VideoCompressionError {
            return compressionError
        }
        
        // Map common system errors
        if let nsError = error as NSError? {
            switch nsError.code {
            case NSFileReadNoSuchFileError:
                return .fileNotFound(nsError.localizedDescription)
            case NSFileWriteFileExistsError:
                return .outputPathError(nsError.localizedDescription)
            case NSFileWriteNoPermissionError:
                return .permissionDenied(nsError.localizedDescription)
            case NSFileWriteVolumeReadOnlyError:
                return .insufficientSpace
            default:
                return .unknownError(nsError.localizedDescription)
            }
        }
        
        return .unknownError(error.localizedDescription)
    }
    
    /// Check if all files have been processed (completed or failed)
    /// - Returns: True if all files are processed, false otherwise
    private func allFilesProcessed() -> Bool {
        return videoFiles.allSatisfy { $0.status.isFinished }
    }
    
    /// Get count of files by status
    /// - Parameter status: Status to count
    /// - Returns: Number of files with the specified status
    func fileCount(withStatus status: CompressionStatus) -> Int {
        return videoFiles.filter { $0.status == status }.count
    }
    
    /// Get total original size of all files
    /// - Returns: Total size in bytes
    var totalOriginalSize: Int64 {
        return videoFiles.reduce(0) { $0 + $1.originalSize }
    }
    
    /// Get total compressed size of completed files
    /// - Returns: Total compressed size in bytes
    var totalCompressedSize: Int64 {
        return videoFiles.compactMap { $0.compressedSize }.reduce(0, +)
    }
    
    /// Get overall compression ratio
    /// - Returns: Compression ratio as percentage, or nil if no files compressed
    var overallCompressionRatio: Double? {
        let completedFiles = videoFiles.filter { $0.status == .completed }
        guard !completedFiles.isEmpty else { return nil }
        
        let totalOriginal = completedFiles.reduce(0) { $0 + $1.originalSize }
        let totalCompressed = completedFiles.compactMap { $0.compressedSize }.reduce(0, +)
        
        guard totalOriginal > 0 else { return nil }
        
        return (1.0 - Double(totalCompressed) / Double(totalOriginal)) * 100.0
    }
    
    // MARK: - File Actions
    
    /// Open file location in Finder
    /// - Parameter fileId: ID of the file to show in Finder
    func openFileInFinder(withId fileId: UUID) {
        guard let file = videoFiles.first(where: { $0.id == fileId }) else {
            return
        }
        
        fileManagerService.openInFinder(url: file.url)
    }
    
    /// Retry compression for a failed file
    /// - Parameter fileId: ID of the file to retry
    func retryCompression(forFileId fileId: UUID) {
        guard let index = videoFiles.firstIndex(where: { $0.id == fileId }),
              case .failed = videoFiles[index].status else {
            return
        }
        
        // Reset file status
        videoFiles[index].status = .pending
        videoFiles[index].compressionProgress = 0.0
        
        loggingService.info("Повторная попытка сжатия файла: \(videoFiles[index].name)", category: "Compression")
        
        // Start compression
        compressFile(withId: fileId)
    }
    
    /// Clear all files from the list
    func clearAllFiles() {
        // Cancel any ongoing processing first
        cancelAllProcessing()
        
        // Clear the list
        videoFiles.removeAll()
        
        loggingService.info("Очищен список файлов", category: "FileManagement")
    }
    
    /// Toggle the logs window visibility
    func toggleLogs() {
        showLogs.toggle()
        
        if showLogs {
            loggingService.info("Открыто окно логов", category: "UI")
        } else {
            loggingService.info("Закрыто окно логов", category: "UI")
        }
    }
}

// MARK: - MainViewModel Extensions

extension MainViewModel {
    /// Convenience initializer for dependency injection in production
    convenience init() {
        do {
            let ffmpegService = try FFmpegService()
            self.init(
                ffmpegService: ffmpegService,
                fileManagerService: FileManagerService(),
                settingsService: SettingsService(),
                loggingService: LoggingService(),
                performanceMonitor: PerformanceMonitorService.shared
            )
        } catch {
            // Create a fallback FFmpeg service for error state
            let fallbackFFmpegService = FallbackFFmpegService()
            self.init(
                ffmpegService: fallbackFFmpegService,
                fileManagerService: FileManagerService(),
                settingsService: SettingsService(),
                loggingService: LoggingService(),
                performanceMonitor: PerformanceMonitorService.shared
            )
            
            // Set the error state after initialization
            Task { @MainActor in
                self.currentError = .ffmpegNotFound
            }
        }
    }
}

// MARK: - Fallback FFmpeg Service

/// A fallback service used when FFmpeg is not available
private class FallbackFFmpegService: FFmpegServiceProtocol {
    func getVideoInfo(url: URL) async throws -> VideoInfo {
        throw VideoCompressionError.ffmpegNotFound
    }
    
    func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        throw VideoCompressionError.ffmpegNotFound
    }
    
    func cancelCurrentOperation() {
        // No-op since no operations can be started
    }
    
    func getQuickVideoInfo(url: URL) async throws -> VideoInfo {
        throw VideoCompressionError.ffmpegNotFound
    }
    
    func clearMetadataCache() {
        // No-op since no cache exists
    }
}