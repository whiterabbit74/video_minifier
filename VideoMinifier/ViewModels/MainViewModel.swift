import Foundation
import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main view model that manages the video compression workflow
@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// List of video files in the compression queue
    @Published var videoFiles: [VideoFile] = [] {
        didSet {
            recomputeAggregates()
        }
    }
    
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

    /// Index cache for fast lookup by file ID
    private var videoFileIndexById: [UUID: Int] = [:]
    
    /// Set of input URLs to prevent duplicate additions
    private var inputURLSet: Set<URL> = []
    
    private enum StatusBucket: CaseIterable {
        case pending
        case compressing
        case completed
        case failed
    }
    
    private var statusCounts: [StatusBucket: Int] = [:]
    private var failedStatusCountsByError: [String: Int] = [:]
    private var cachedTotalOriginalSize: Int64 = 0
    private var cachedTotalCompressedSize: Int64 = 0
    private var cachedCompletedOriginalSize: Int64 = 0
    private var cachedCompletedCompressedSize: Int64 = 0
    
    private var lastPerformanceSampleTime: Date?
    
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
    @discardableResult
    func addFiles(_ urls: [URL], settingsOverride: CompressionSettings? = nil) -> [UUID] {
        var addedFileIds: [UUID] = []

        // Добавляем файлы синхронно (метаданные подтянутся асинхронно внутри)
        for url in urls {
            if let fileId = addSingleFile(url, settingsOverride: settingsOverride) {
                addedFileIds.append(fileId)
            }
        }

        return addedFileIds
    }

    /// Add files and immediately enqueue them for compression
    func addAndCompressFiles(_ urls: [URL], settingsOverride: CompressionSettings? = nil) {
        let addedFileIds = addFiles(urls, settingsOverride: settingsOverride)
        for fileId in addedFileIds {
            compressFile(withId: fileId)
        }
    }
    
    /// Add a single video file
    /// - Parameter url: URL of the video file to add
    private func addSingleFile(_ url: URL, settingsOverride: CompressionSettings?) -> UUID? {
        let canonicalURL = url.standardizedFileURL
        // Check if file already exists in the list
        if inputURLSet.contains(canonicalURL) {
            loggingService.warning(
                String(format: NSLocalizedString("Файл уже добавлен: %@", comment: ""), canonicalURL.lastPathComponent),
                category: "FileManagement"
            )
            return nil
        }
        
        do {
            loggingService.info(
                String(format: NSLocalizedString("Добавление файла: %@", comment: ""), url.lastPathComponent),
                category: "FileManagement"
            )
            
            // Сначала получаем размер файла и добавляем файл с базовой информацией
            let fileSize = try fileManagerService.getFileSize(url: url)
            
            // Создаем VideoFile с базовой информацией для быстрого отображения
            let videoFile = VideoFile(
                url: url,
                name: url.lastPathComponent,
                duration: 0, // Будет обновлено позже
                originalSize: fileSize,
                customCompressionSettings: settingsOverride
            )
            
            // Добавляем в список сразу для быстрого отображения
            videoFiles.append(videoFile)
            videoFileIndexById[videoFile.id] = videoFiles.count - 1
            inputURLSet.insert(canonicalURL)
            loggingService.info(
                String(format: NSLocalizedString("Файл добавлен в список (анализ метаданных...): %@", comment: ""), url.lastPathComponent),
                category: "FileManagement"
            )
            
            // Теперь получаем полную информацию о видео в фоне
            Task {
                do {
                    let videoInfo = try await ffmpegService.getVideoInfo(url: url)
                    
                    // Обновляем информацию о файле
                    if let index = indexForFileId(videoFile.id) {
                        var updatedFile = videoFiles[index]
                        updatedFile.duration = videoInfo.duration
                        videoFiles[index] = updatedFile
                        
                        loggingService.info(
                            String(
                                format: NSLocalizedString("Метаданные получены: %@ (длительность: %@)", comment: ""),
                                url.lastPathComponent,
                                videoInfo.duration.formattedDuration
                            ),
                            category: "FileManagement"
                        )
                    }
                } catch {
                    let compressionError = mapToCompressionError(error)
                    loggingService.error(
                        String(
                            format: NSLocalizedString("Не удалось получить метаданные для %@: %@", comment: ""),
                            url.lastPathComponent,
                            compressionError.localizedDescription
                        ),
                        category: "FileManagement"
                    )
                    
                    // Помечаем файл как проблемный, но не удаляем из списка
                    if let index = indexForFileId(videoFile.id) {
                        var updatedFile = videoFiles[index]
                        updatedFile.status = .failed(compressionError)
                        videoFiles[index] = updatedFile
                    }
                }
            }
            return videoFile.id
        } catch {
            let compressionError = mapToCompressionError(error)
            loggingService.error(
                String(
                    format: NSLocalizedString("Не удалось добавить файл %@: %@", comment: ""),
                    url.lastPathComponent,
                    compressionError.localizedDescription
                ),
                category: "FileManagement"
            )
            showError(compressionError)
            return nil
        }
    }
    
    /// Remove a video file from the list
    /// - Parameter fileId: ID of the file to remove
    func removeFile(withId fileId: UUID) {
        // Don't allow removal of currently processing file
        if currentlyProcessingFileId == fileId {
            loggingService.warning(NSLocalizedString("Попытка удалить файл, который сейчас обрабатывается", comment: ""), category: "FileManagement")
            return
        }
        
        // Find file name for logging
        let fileName = indexForFileId(fileId).map { videoFiles[$0].name } ?? "Unknown"
        
        // Remove from processing queue if present
        processingQueue.removeAll { $0 == fileId }
        
        // Remove from video files list
        if let index = indexForFileId(fileId) {
            let removedFile = videoFiles[index]
            videoFiles.remove(at: index)
            videoFileIndexById.removeValue(forKey: fileId)
            inputURLSet.remove(removedFile.originalURL.standardizedFileURL)
            rebuildIndexCache(from: index)
        }
        
        loggingService.info(
            String(format: NSLocalizedString("Файл удален из списка: %@", comment: ""), fileName),
            category: "FileManagement"
        )
    }
    
    /// Remove all files from the list
    func removeAllFiles() {
        // Cancel current processing if any
        cancelAllProcessing()
        
        // Clear all data
        videoFiles.removeAll()
        videoFileIndexById.removeAll()
        inputURLSet.removeAll()
        processingQueue.removeAll()
        currentlyProcessingFileId = nil
    }

    /// Remove completed files from the list
    func removeCompletedFiles() {
        let remainingFiles = videoFiles.filter { file in
            if case .completed = file.status {
                return false
            }
            return true
        }

        if remainingFiles.count == videoFiles.count {
            return
        }

        videoFiles = remainingFiles
        videoFileIndexById.removeAll()
        inputURLSet = Set(remainingFiles.map { $0.originalURL.standardizedFileURL })
        processingQueue.removeAll { id in
            !remainingFiles.contains(where: { $0.id == id })
        }
        for (index, file) in remainingFiles.enumerated() {
            videoFileIndexById[file.id] = index
        }
        if let currentId = currentlyProcessingFileId,
           !remainingFiles.contains(where: { $0.id == currentId }) {
            currentlyProcessingFileId = nil
        }
    }
    
    // MARK: - Compression Operations
    
    /// Compress a single video file
    /// - Parameter fileId: ID of the file to compress
    func compressFile(withId fileId: UUID) {
        guard indexForFileId(fileId) != nil else {
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
        loggingService.info(NSLocalizedString("Отмена всех операций сжатия", comment: ""), category: "Compression")
        
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
                    loggingService.info(
                        String(format: NSLocalizedString("Отменено сжатие файла: %@", comment: ""), videoFiles[index].name),
                        category: "Compression"
                    )
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
        guard let fileIndex = indexForFileId(fileId) else {
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
                await compressFile(withId: fileId)
                
                // Check if task was cancelled before processing next file
                try Task.checkCancellation()
                
                // Process next file only if not cancelled and still processing
                if !Task.isCancelled && isProcessing {
                    processNextFile()
                }
            } catch is CancellationError {
                loggingService.info(NSLocalizedString("Задача сжатия была отменена", comment: ""), category: "Compression")
                // Ensure processing state is cleared on cancellation
                isProcessing = false
                currentlyProcessingFileId = nil
            } catch {
                loggingService.error(
                    String(format: NSLocalizedString("Неожиданная ошибка в задаче сжатия: %@", comment: ""), String(describing: error)),
                    category: "Compression"
                )
                // Process next file even on error, but only if still processing
                if isProcessing {
                    processNextFile()
                }
            }
        }
    }
    
    /// Compress the file with the specified ID
    /// - Parameter fileId: ID of the file in the videoFiles array
    private func compressFile(withId fileId: UUID) async {
        guard let index = indexForFileId(fileId) else {
            loggingService.warning(
                String(format: NSLocalizedString("Файл не найден при попытке обработки: %@", comment: ""), fileId.uuidString),
                category: "Compression"
            )
            return
        }
        
        let file = videoFiles[index]
        
        do {
            // Check for cancellation before starting
            try Task.checkCancellation()
            
            loggingService.info(
                String(format: NSLocalizedString("Начало сжатия файла: %@", comment: ""), file.name),
                category: "Compression"
            )
            
            // Start performance monitoring
            performanceMonitor.startMonitoring()
            
            // Check system performance before starting
            let _ = performanceMonitor.getCurrentMetrics()
            let recommendations = performanceMonitor.getRecommendedSettings()
            
            if recommendations.suggestPauseProcessing {
                loggingService.warning(NSLocalizedString("Система перегрета, рекомендуется пауза в обработке", comment: ""), category: "Performance")
            }
            
            // Prefer per-file settings for monitored files; fallback to current global settings.
            var adjustedSettings = file.customCompressionSettings ?? settingsService.settings
            if recommendations.suggestThermalThrottling {
                adjustedSettings.useHardwareAcceleration = false
                loggingService.info(NSLocalizedString("Отключено аппаратное ускорение из-за перегрева", comment: ""), category: "Performance")
            }

            // Generate output URL
            let outputURL = fileManagerService.generateOutputURL(for: file.originalURL, behavior: adjustedSettings.outputBehavior)
            
            // Check for cancellation before starting compression
            try Task.checkCancellation()
            
            // Compress the video
            try await ffmpegService.compressVideo(
                input: file.originalURL,
                output: outputURL,
                settings: adjustedSettings
            ) { [weak self] progress in
                Task { @MainActor in
                    // Check if task is still valid before updating progress
                    guard let self = self, !Task.isCancelled else { return }
                    
                    self.updateCompressionProgress(fileId: fileId, progress: progress)
                    
                    // Monitor performance during compression (rate-limited)
                    let now = Date()
                    if self.lastPerformanceSampleTime == nil ||
                        now.timeIntervalSince(self.lastPerformanceSampleTime ?? now) >= 1.0 {
                        self.lastPerformanceSampleTime = now
                        let _ = self.performanceMonitor.getCurrentMetrics()
                        if self.performanceMonitor.isUnderThermalPressure() {
                            self.loggingService.warning(NSLocalizedString("Обнаружен перегрев во время сжатия", comment: ""), category: "Performance")
                        }
                    }
                }
            }
            
            // Check for cancellation after compression
            try Task.checkCancellation()
            
            // Get compressed file size
            let compressedSize = try fileManagerService.getFileSize(url: outputURL)
            
            let isCompressedLarger = compressedSize > file.originalSize

            // Safely update file status using fileId instead of index
            if let currentIndex = indexForFileId(fileId) {
                videoFiles[currentIndex].status = .completed
                videoFiles[currentIndex].compressedSize = compressedSize
                videoFiles[currentIndex].compressionProgress = 1.0

                if !isCompressedLarger {
                    switch adjustedSettings.outputBehavior {
                    case .replaceOriginal:
                        do {
                            try fileManagerService.moveFile(from: outputURL, to: file.originalURL)
                            videoFiles[currentIndex].url = file.originalURL
                            videoFiles[currentIndex].name = file.originalURL.lastPathComponent
                        } catch {
                            loggingService.error(
                                String(
                                    format: NSLocalizedString("Не удалось заменить исходный файл: %@: %@", comment: ""),
                                    file.name,
                                    error.localizedDescription
                                ),
                                category: "FileManagement"
                            )
                            videoFiles[currentIndex].url = outputURL
                            videoFiles[currentIndex].name = outputURL.lastPathComponent
                        }
                    case .appendCompressedToName, .subfolderCompressed:
                        videoFiles[currentIndex].url = outputURL
                        videoFiles[currentIndex].name = outputURL.lastPathComponent
                    }
                }
            }

            let compressionRatio = (1.0 - Double(compressedSize) / Double(file.originalSize)) * 100.0

            // Log performance metrics
            let finalMetrics = performanceMonitor.getCurrentMetrics()
            loggingService.info(
                String(
                    format: NSLocalizedString("Сжатие завершено: %@ (%@ → %@, экономия: %@%%)", comment: ""),
                    file.name,
                    file.originalSize.formattedFileSize,
                    compressedSize.formattedFileSize,
                    String(format: "%.1f", compressionRatio)
                ),
                category: "Compression"
            )
            loggingService.info(
                String(
                    format: NSLocalizedString("Производительность: CPU %@%%, Память %@MB, Температура: %@", comment: ""),
                    String(format: "%.1f", finalMetrics.cpuUsage),
                    String(format: "%.1f", finalMetrics.memoryUsage),
                    finalMetrics.thermalState.description
                ),
                category: "Performance"
            )

            // If compressed file is larger than original, delete the compressed file immediately
            if isCompressedLarger {
                do {
                    try fileManagerService.deleteFile(at: outputURL)
                    loggingService.warning(
                        String(
                            format: NSLocalizedString("Сжатый файл больше оригинала, удаляю сжатую версию: %@", comment: ""),
                            outputURL.lastPathComponent
                        ),
                        category: "FileManagement"
                    )
                } catch {
                    loggingService.error(
                        String(
                            format: NSLocalizedString("Не удалось удалить сжатый файл: %@: %@", comment: ""),
                            outputURL.lastPathComponent,
                            error.localizedDescription
                        ),
                        category: "FileManagement"
                    )
                }
            }
            
            if adjustedSettings.outputBehavior == .replaceOriginal && isCompressedLarger {
                loggingService.info(NSLocalizedString("Оригинал НЕ заменен, так как сжатый файл оказался больше", comment: ""), category: "FileManagement")
            }
            
        } catch is CancellationError {
            // Handle cancellation gracefully
            loggingService.info(
                String(format: NSLocalizedString("Сжатие файла отменено: %@", comment: ""), file.name),
                category: "Compression"
            )
            
            // Safely reset file status using fileId instead of index
            if let currentIndex = indexForFileId(fileId) {
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
                loggingService.info(
                    String(format: NSLocalizedString("Сжатие файла отменено пользователем: %@", comment: ""), file.name),
                    category: "Compression"
                )
                
                // Safely reset file status for cancelled operations
                if let currentIndex = indexForFileId(fileId) {
                    if videoFiles[currentIndex].status == .compressing {
                        videoFiles[currentIndex].status = .pending
                        videoFiles[currentIndex].compressionProgress = 0.0
                    }
                }
                
                // Не добавляем отмененные операции в список ошибок
                return
            }
            
            // Safely update file status using fileId instead of index
            if let currentIndex = indexForFileId(fileId) {
                videoFiles[currentIndex].status = .failed(compressionError)
                videoFiles[currentIndex].compressionProgress = 0.0
            }
            
            loggingService.error(
                String(
                    format: NSLocalizedString("Ошибка сжатия файла %@: %@", comment: ""),
                    file.name,
                    compressionError.localizedDescription
                ),
                category: "Compression"
            )
            
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
        guard let index = indexForFileId(fileId) else {
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
        let fileURLType = UTType.fileURL.identifier
        return providers.allSatisfy { provider in
            provider.hasItemConformingToTypeIdentifier(fileURLType)
        }
    }
    
    /// Handle dropped items
    /// - Parameter providers: Array of NSItemProvider objects
    /// - Returns: True if drop was handled successfully
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let urlAccessQueue = DispatchQueue(label: "com.videominifier.dropurls")
        
        for provider in providers {
            group.enter()
            
            let fileURLType = UTType.fileURL.identifier
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urlAccessQueue.sync {
                        urls.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let collectedURLs = urlAccessQueue.sync { urls }

            // Filter for video files
            let videoURLs = collectedURLs.filter { url in
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
        switch status {
        case .pending:
            return statusCounts[.pending] ?? 0
        case .compressing:
            return statusCounts[.compressing] ?? 0
        case .completed:
            return statusCounts[.completed] ?? 0
        case .failed(let error):
            return failedStatusCountsByError[error.localizedDescription] ?? 0
        }
    }
    
    /// Get total original size of all files
    /// - Returns: Total size in bytes
    var totalOriginalSize: Int64 {
        return cachedTotalOriginalSize
    }
    
    /// Get total compressed size of completed files
    /// - Returns: Total compressed size in bytes
    var totalCompressedSize: Int64 {
        return cachedTotalCompressedSize
    }
    
    /// Get overall compression ratio
    /// - Returns: Compression ratio as percentage, or nil if no files compressed
    var overallCompressionRatio: Double? {
        guard statusCounts[.completed, default: 0] > 0 else { return nil }
        guard cachedCompletedOriginalSize > 0 else { return nil }
        return (1.0 - Double(cachedCompletedCompressedSize) / Double(cachedCompletedOriginalSize)) * 100.0
    }
    
    // MARK: - File Actions
    
    /// Open file location in Finder
    /// - Parameter fileId: ID of the file to show in Finder
    func openFileInFinder(withId fileId: UUID) {
        guard let index = indexForFileId(fileId) else {
            return
        }
        
        fileManagerService.openInFinder(url: videoFiles[index].url)
    }
    
    /// Retry compression for a failed file
    /// - Parameter fileId: ID of the file to retry
    func retryCompression(forFileId fileId: UUID) {
        guard let index = indexForFileId(fileId),
              case .failed = videoFiles[index].status else {
            return
        }
        
        // Reset file status
        videoFiles[index].status = .pending
        videoFiles[index].compressionProgress = 0.0
        
        loggingService.info(
            String(format: NSLocalizedString("Повторная попытка сжатия файла: %@", comment: ""), videoFiles[index].name),
            category: "Compression"
        )
        
        // Start compression
        compressFile(withId: fileId)
    }
    
    /// Clear all files from the list
    func clearAllFiles() {
        // Cancel any ongoing processing first
        cancelAllProcessing()
        
        // Clear the list
        videoFiles.removeAll()
        videoFileIndexById.removeAll()
        inputURLSet.removeAll()
        
        loggingService.info(NSLocalizedString("Очищен список файлов", comment: ""), category: "FileManagement")
    }
    
    /// Toggle the logs window visibility
    func toggleLogs() {
        showLogs.toggle()
        
        if showLogs {
            loggingService.info(NSLocalizedString("Открыто окно логов", comment: ""), category: "UI")
        } else {
            loggingService.info(NSLocalizedString("Закрыто окно логов", comment: ""), category: "UI")
        }
    }
}

// MARK: - Index Cache

extension MainViewModel {
    private func indexForFileId(_ id: UUID) -> Int? {
        if let index = videoFileIndexById[id],
           index < videoFiles.count,
           videoFiles[index].id == id {
            return index
        }
        
        if let index = videoFiles.firstIndex(where: { $0.id == id }) {
            videoFileIndexById[id] = index
            return index
        }
        
        return nil
    }
    
    private func rebuildIndexCache(from startIndex: Int) {
        guard startIndex < videoFiles.count else { return }
        for index in startIndex..<videoFiles.count {
            videoFileIndexById[videoFiles[index].id] = index
        }
    }
    
    private func recomputeAggregates() {
        var counts: [StatusBucket: Int] = [.pending: 0, .compressing: 0, .completed: 0, .failed: 0]
        var failedCounts: [String: Int] = [:]
        var totalOriginal: Int64 = 0
        var totalCompressed: Int64 = 0
        var completedOriginal: Int64 = 0
        var completedCompressed: Int64 = 0
        
        for file in videoFiles {
            totalOriginal += file.originalSize
            if let compressedSize = file.compressedSize {
                totalCompressed += compressedSize
            }
            
            switch file.status {
            case .pending:
                counts[.pending, default: 0] += 1
            case .compressing:
                counts[.compressing, default: 0] += 1
            case .completed:
                counts[.completed, default: 0] += 1
                completedOriginal += file.originalSize
                if let compressedSize = file.compressedSize {
                    completedCompressed += compressedSize
                }
            case .failed:
                counts[.failed, default: 0] += 1
                if case .failed(let error) = file.status {
                    failedCounts[error.localizedDescription, default: 0] += 1
                }
            }
        }
        
        statusCounts = counts
        failedStatusCountsByError = failedCounts
        cachedTotalOriginalSize = totalOriginal
        cachedTotalCompressedSize = totalCompressed
        cachedCompletedOriginalSize = completedOriginal
        cachedCompletedCompressedSize = completedCompressed
    }
}

// MARK: - MainViewModel Extensions

extension MainViewModel {
    /// Convenience initializer for dependency injection in production
    convenience init(settingsService: any SettingsServiceProtocol) {
        do {
            let ffmpegService = try FFmpegService()
            self.init(
                ffmpegService: ffmpegService,
                fileManagerService: FileManagerService(),
                settingsService: settingsService,
                loggingService: LoggingService.shared,
                performanceMonitor: PerformanceMonitorService.shared
            )
        } catch {
            // Create a fallback FFmpeg service for error state
            let fallbackFFmpegService = FallbackFFmpegService()
            self.init(
                ffmpegService: fallbackFFmpegService,
                fileManagerService: FileManagerService(),
                settingsService: settingsService,
                loggingService: LoggingService.shared,
                performanceMonitor: PerformanceMonitorService.shared
            )

            // Set the error state after initialization
            Task { @MainActor in
                self.currentError = .ffmpegNotFound
            }
        }
    }

    convenience init() {
        self.init(settingsService: SettingsService())
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
