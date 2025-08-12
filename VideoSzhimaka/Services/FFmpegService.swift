import Foundation
import os.log

/// Реализация сервиса для работы с FFmpeg
class FFmpegService: FFmpegServiceProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.videoszhimaka.VideoSzhimaka", category: "FFmpegService")
    private var ffmpegPath: String
    private var currentProcess: Process?
    private var currentProgressTask: Task<Void, Never>?
    private let processQueue = DispatchQueue(label: "ffmpeg.processing", qos: .userInitiated)
    
    // Кэш для метаданных видео (ключ: путь к файлу + размер + дата модификации)
    private var metadataCache: [String: VideoInfo] = [:]
    private let cacheQueue = DispatchQueue(label: "ffmpeg.cache", attributes: .concurrent)
    
    init() throws {
        // Инициализируем ffmpegPath пустой строкой, установим правильное значение ниже
        self.ffmpegPath = ""
        
        // Получаем путь к встроенному FFmpeg бинарнику
        guard let bundlePath = Bundle.main.resourcePath else {
            throw VideoCompressionError.ffmpegNotFound
        }
        
        // Ищем FFmpeg в разных возможных местах внутри bundle
        let possiblePaths = [
            bundlePath + "/ffmpeg",           // Прямо в Resources
            bundlePath + "/bin/ffmpeg",      // В Resources/bin
            bundlePath + "/Resources/bin/ffmpeg" // Альтернативный путь
        ]
        
        var ffmpegBinaryPath: String?
        
        // Находим первый существующий путь
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ffmpegBinaryPath = path
                break
            }
        }
        
        guard let validPath = ffmpegBinaryPath else {
            logger.error("FFmpeg binary not found in bundle at any of these paths: \(possiblePaths)")
            // Fallback к системному FFmpeg
            try initializeWithSystemFFmpeg()
            return
        }
        
        // Тестируем, что найденный бинарник может быть запущен
        if try testFFmpegBinary(at: validPath) {
            self.ffmpegPath = validPath
            logger.info("FFmpeg service initialized with bundled binary: \(validPath)")
            return
        } else {
            logger.warning("Bundled FFmpeg binary failed to run, trying system FFmpeg")
            try initializeWithSystemFFmpeg()
        }
    }
    
    private func initializeWithSystemFFmpeg() throws {
        let systemPaths = [
            "/opt/homebrew/bin/ffmpeg",  // Homebrew on Apple Silicon
            "/usr/local/bin/ffmpeg",     // Homebrew on Intel
            "/usr/bin/ffmpeg"            // System FFmpeg
        ]
        
        for systemPath in systemPaths {
            if FileManager.default.fileExists(atPath: systemPath) {
                if try testFFmpegBinary(at: systemPath) {
                    self.ffmpegPath = systemPath
                    logger.info("FFmpeg service initialized with system binary: \(systemPath)")
                    return
                }
            }
        }
        
        logger.error("No working FFmpeg binary found")
        throw VideoCompressionError.ffmpegNotFound
    }
    
    private func testFFmpegBinary(at path: String) throws -> Bool {
        let testProcess = Process()
        testProcess.executableURL = URL(fileURLWithPath: path)
        testProcess.arguments = ["-version"]
        testProcess.standardOutput = Pipe()
        testProcess.standardError = Pipe()
        
        do {
            try testProcess.run()
            testProcess.waitUntilExit()
            return testProcess.terminationStatus == 0
        } catch {
            logger.warning("Failed to test FFmpeg binary at \(path): \(error)")
            return false
        }
    }
    
    /// Проверяем, доступен ли указанный видеокодировщик в установленном FFmpeg
    private func isEncoderAvailable(_ encoderName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return false }
            return output.contains(encoderName)
        } catch {
            logger.warning("Failed to query encoders: \(error)")
            return false
        }
    }
    
    func getVideoInfo(url: URL) async throws -> VideoInfo {
        logger.info("Getting video info for: \(url.path)")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoCompressionError.fileNotFound(url.path)
        }
        
        // Проверяем кэш
        let cacheKey = try generateCacheKey(for: url)
        
        return try await withCheckedThrowingContinuation { continuation in
            cacheQueue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: VideoCompressionError.unknownError("Service deallocated"))
                    return
                }
                
                // Проверяем кэш
                if let cachedInfo = self.metadataCache[cacheKey] {
                    self.logger.info("Using cached metadata for: \(url.path)")
                    continuation.resume(returning: cachedInfo)
                    return
                }
                
                // Извлекаем метаданные в фоновой очереди
                self.processQueue.async {
                    do {
                        let videoInfo = try self.extractVideoMetadata(from: url)
                        
                        // Сохраняем в кэш
                        self.cacheQueue.async(flags: .barrier) {
                            self.metadataCache[cacheKey] = videoInfo
                            
                            // Ограничиваем размер кэша (максимум 100 файлов)
                            if self.metadataCache.count > 100 {
                                let oldestKey = self.metadataCache.keys.first!
                                self.metadataCache.removeValue(forKey: oldestKey)
                            }
                        }
                        
                        continuation.resume(returning: videoInfo)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    func compressVideo(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        logger.info("Starting video compression: \(input.path) -> \(output.path)")
        
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw VideoCompressionError.fileNotFound(input.path)
        }
        
        // Проверяем, что выходная директория существует
        let outputDirectory = output.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: outputDirectory.path) {
            throw VideoCompressionError.outputPathError(outputDirectory.path)
        }
        
        return try await withTaskCancellationHandler {
            try await self.performVideoCompression(
                input: input,
                output: output,
                settings: settings,
                progressHandler: progressHandler
            )
        } onCancel: {
            self.cancelCurrentOperation()
        }
    }
    
    func cancelCurrentOperation() {
        logger.info("Cancellation requested")
        
        processQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Сохраняем ссылки перед очисткой
            let processToTerminate = self.currentProcess
            let progressTaskToCancel = self.currentProgressTask
            
            // Сразу очищаем состояние, чтобы сигнализировать об отмене
            self.currentProcess = nil
            self.currentProgressTask = nil
            
            // Отменяем задачу мониторинга прогресса
            progressTaskToCancel?.cancel()
            
            if let process = processToTerminate {
                if process.isRunning {
                    self.logger.info("Terminating FFmpeg process (PID: \(process.processIdentifier))")
                    
                    // Сначала пытаемся корректно завершить процесс
                    process.terminate()
                    
                    // Ждем немного для корректного завершения
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        if process.isRunning {
                            self.logger.warning("Process still running after SIGTERM, sending SIGKILL")
                            process.interrupt()
                            
                            // Последняя попытка через еще 0.5 секунды
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                                if process.isRunning {
                                    self.logger.error("Failed to terminate FFmpeg process with standard signals, trying kill -9")
                                    // В крайнем случае можно попробовать kill -9
                                    let killTask = Process()
                                    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                                    killTask.arguments = ["-9", String(process.processIdentifier)]
                                    do {
                                        try killTask.run()
                                        killTask.waitUntilExit()
                                        self.logger.info("Force killed FFmpeg process with kill -9")
                                    } catch {
                                        self.logger.error("Failed to execute kill -9: \(error)")
                                    }
                                }
                            }
                        } else {
                            self.logger.info("FFmpeg process terminated successfully")
                        }
                    }
                } else {
                    self.logger.info("FFmpeg process was already terminated")
                }
            } else {
                self.logger.info("No FFmpeg process to cancel")
            }
        }
    }
    
    func clearMetadataCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.metadataCache.removeAll()
        }
    }
    
    /// Быстрое получение базовой информации о видео (только размер файла и формат)
    func getQuickVideoInfo(url: URL) async throws -> VideoInfo {
        logger.info("Getting quick video info for: \(url.path)")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VideoCompressionError.fileNotFound(url.path)
        }
        
        // Получаем размер файла
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Возвращаем базовую информацию с заглушками
        return VideoInfo(
            duration: 0, // Будет определено позже
            width: 0,    // Будет определено позже
            height: 0,   // Будет определено позже
            frameRate: 0,
            bitrate: fileSize * 8, // Примерный битрейт на основе размера файла
            hasAudio: true, // Предполагаем наличие аудио
            audioCodec: nil,
            videoCodec: url.pathExtension.lowercased() // Используем расширение как предварительный кодек
        )
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()
        
        return "\(url.path)_\(fileSize)_\(modificationDate.timeIntervalSince1970)"
    }
    
    private func extractVideoMetadata(from url: URL) throws -> VideoInfo {
        let process = Process()
        
        // Определяем путь к ffprobe (обычно находится рядом с ffmpeg)
        let ffprobePath = ffmpegPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
        
        // Проверяем, существует ли ffprobe, если нет - используем ffmpeg
        if FileManager.default.fileExists(atPath: ffprobePath) {
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            // Оптимизированные параметры ffprobe для быстрого извлечения метаданных
            process.arguments = [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                "-analyzeduration", "1000000",    // Анализируем только первую секунду (1M микросекунд)
                "-probesize", "5000000",          // Читаем только первые 5MB файла
                "-fflags", "+genpts",             // Генерируем PTS для поврежденных файлов
                url.path
            ]
        } else {
            // Fallback: используем ffmpeg для получения информации о файле
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-analyzeduration", "1000000",    // Анализируем только первую секунду
                "-probesize", "5000000",          // Читаем только первые 5MB
                "-i", url.path,
                "-t", "0.1",                      // Обрабатываем только 0.1 секунды
                "-f", "null",
                "-"
            ]
        }
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            
            // Добавляем таймаут для операции извлечения метаданных (10 секунд)
            let timeoutSeconds = 10.0
            let startTime = Date()
            
            while process.isRunning {
                if Date().timeIntervalSince(startTime) > timeoutSeconds {
                    logger.warning("Metadata extraction timeout after \(timeoutSeconds) seconds, terminating process")
                    process.terminate()
                    throw VideoCompressionError.invalidInput("Metadata extraction timeout - file may be corrupted or too large")
                }
                usleep(100000) // Спим 0.1 секунды
            }
            
        } catch {
            logger.error("Failed to run metadata extraction process: \(error)")
            throw VideoCompressionError.invalidInput("Failed to run metadata extraction: \(error.localizedDescription)")
        }
        
        // Определяем, используем ли мы ffprobe или ffmpeg
        let usingFFprobe = FileManager.default.fileExists(atPath: ffmpegPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe"))
        
        if usingFFprobe {
            // Для ffprobe проверяем статус выхода
            if process.terminationStatus != 0 {
                let errorData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Metadata extraction failed with status \(process.terminationStatus): \(errorString)")
                throw VideoCompressionError.invalidInput("Failed to extract metadata: \(errorString)")
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if data.isEmpty {
                logger.error("No metadata output received from ffprobe")
                throw VideoCompressionError.invalidInput("No metadata received from video file")
            }
            
            return try parseVideoMetadata(from: data)
        } else {
            // Для ffmpeg парсим stderr для получения информации о файле
            let errorData = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            
            if errorString.isEmpty {
                throw VideoCompressionError.invalidInput("No output received from ffmpeg")
            }
            
            return try parseFFmpegOutput(errorString)
        }
    }
    
    private func parseVideoMetadata(from data: Data) throws -> VideoInfo {
        // Логируем полученные данные для отладки
        if let jsonString = String(data: data, encoding: .utf8) {
            logger.debug("Received metadata JSON: \(jsonString)")
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VideoCompressionError.invalidInput("Invalid JSON format in metadata")
            }
            
            guard let format = json["format"] as? [String: Any] else {
                throw VideoCompressionError.invalidInput("No format information found in metadata")
            }
            
            guard let streams = json["streams"] as? [[String: Any]] else {
                throw VideoCompressionError.invalidInput("No streams information found in metadata")
            }
            
            if streams.isEmpty {
                throw VideoCompressionError.invalidInput("No streams found in video file")
            }
            
            return try parseStreamsAndFormat(streams: streams, format: format)
            
        } catch let jsonError as NSError {
            logger.error("JSON parsing error: \(jsonError)")
            throw VideoCompressionError.invalidInput("Failed to parse video metadata: \(jsonError.localizedDescription)")
        }
    }
    
    private func parseFFmpegOutput(_ output: String) throws -> VideoInfo {
        logger.debug("Parsing ffmpeg output: \(output)")
        
        // Ищем информацию о видео в выводе ffmpeg
        var duration: TimeInterval = 0
        var width = 0
        var height = 0
        var frameRate: Double = 30.0
        var hasAudio = false
        var videoCodec: String?
        var audioCodec: String?
        
        // Парсим длительность: Duration: 00:01:23.45
        if let durationMatch = output.range(of: #"Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})"#, options: .regularExpression) {
            let durationString = String(output[durationMatch])
            let components = durationString.replacingOccurrences(of: "Duration: ", with: "").split(separator: ":")
            if components.count >= 3 {
                let hours = Double(components[0]) ?? 0
                let minutes = Double(components[1]) ?? 0
                let secondsAndMs = String(components[2]).split(separator: ".")
                let seconds = Double(secondsAndMs[0]) ?? 0
                let ms = secondsAndMs.count > 1 ? Double(secondsAndMs[1]) ?? 0 : 0
                duration = hours * 3600 + minutes * 60 + seconds + ms / 100
            }
        }
        
        // Ищем видео поток: Stream #0:0: Video: h264, yuv420p, 1920x1080, 25 fps
        let videoPattern = #"Stream #\d+:\d+.*?: Video: ([^,]+).*?(\d+)x(\d+).*?(\d+(?:\.\d+)?) fps"#
        if let videoMatch = output.range(of: videoPattern, options: .regularExpression) {
            let videoString = String(output[videoMatch])
            
            // Извлекаем кодек
            if let codecMatch = videoString.range(of: #"Video: ([^,]+)"#, options: .regularExpression) {
                let codecString = String(videoString[codecMatch])
                videoCodec = codecString.replacingOccurrences(of: "Video: ", with: "").components(separatedBy: ",")[0].trimmingCharacters(in: .whitespaces)
            }
            
            // Извлекаем размеры
            if let sizeMatch = videoString.range(of: #"(\d+)x(\d+)"#, options: .regularExpression) {
                let sizeString = String(videoString[sizeMatch])
                let dimensions = sizeString.split(separator: "x")
                if dimensions.count == 2 {
                    width = Int(dimensions[0]) ?? 0
                    height = Int(dimensions[1]) ?? 0
                }
            }
            
            // Извлекаем FPS
            if let fpsMatch = videoString.range(of: #"(\d+(?:\.\d+)?) fps"#, options: .regularExpression) {
                let fpsString = String(videoString[fpsMatch])
                let fpsValue = fpsString.replacingOccurrences(of: " fps", with: "")
                frameRate = Double(fpsValue) ?? 30.0
            }
        }
        
        // Ищем аудио поток: Stream #0:1: Audio: aac
        if output.contains("Audio:") {
            hasAudio = true
            if let audioMatch = output.range(of: #"Audio: ([^,\s]+)"#, options: .regularExpression) {
                let audioString = String(output[audioMatch])
                audioCodec = audioString.replacingOccurrences(of: "Audio: ", with: "")
            }
        }
        
        logger.info("Parsed video info from ffmpeg: \(width)x\(height), \(frameRate)fps, duration: \(duration)s")
        
        return VideoInfo(
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            bitrate: 0, // Битрейт сложно извлечь из ffmpeg вывода
            hasAudio: hasAudio,
            audioCodec: audioCodec,
            videoCodec: videoCodec
        )
    }
    
    private func parseStreamsAndFormat(streams: [[String: Any]], format: [String: Any]) throws -> VideoInfo {
        
        // Получаем длительность
        let durationString = format["duration"] as? String ?? "0"
        let duration = TimeInterval(durationString) ?? 0
        
        // Получаем битрейт
        let bitrateString = format["bit_rate"] as? String ?? "0"
        let bitrate = Int64(bitrateString) ?? 0
        
        // Ищем видео и аудио потоки
        var videoStream: [String: Any]?
        var audioStream: [String: Any]?
        
        for stream in streams {
            if let codecType = stream["codec_type"] as? String {
                if codecType == "video" && videoStream == nil {
                    videoStream = stream
                } else if codecType == "audio" && audioStream == nil {
                    audioStream = stream
                }
            }
        }
        
        guard let video = videoStream else {
            logger.error("No video stream found in streams: \(streams)")
            throw VideoCompressionError.invalidInput("No video stream found in file")
        }
        
        // Извлекаем параметры видео с проверками
        let width = video["width"] as? Int ?? 0
        let height = video["height"] as? Int ?? 0
        let videoCodec = video["codec_name"] as? String
        
        // Проверяем, что видео имеет валидные размеры
        if width <= 0 || height <= 0 {
            logger.warning("Video has invalid dimensions: \(width)x\(height)")
        }
        
        // Вычисляем FPS с улучшенной обработкой
        var frameRate: Double = 30.0
        if let rFrameRate = video["r_frame_rate"] as? String, !rFrameRate.isEmpty {
            let components = rFrameRate.split(separator: "/")
            if components.count == 2,
               let numerator = Double(components[0]),
               let denominator = Double(components[1]),
               denominator > 0 {
                frameRate = numerator / denominator
            }
        } else if let avgFrameRate = video["avg_frame_rate"] as? String, !avgFrameRate.isEmpty {
            let components = avgFrameRate.split(separator: "/")
            if components.count == 2,
               let numerator = Double(components[0]),
               let denominator = Double(components[1]),
               denominator > 0 {
                frameRate = numerator / denominator
            }
        }
        
        // Параметры аудио
        let hasAudio = audioStream != nil
        let audioCodec = audioStream?["codec_name"] as? String
        
        logger.info("Successfully parsed video metadata: \(width)x\(height), \(frameRate)fps, duration: \(duration)s")
        
        return VideoInfo(
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            bitrate: bitrate,
            hasAudio: hasAudio,
            audioCodec: audioCodec,
            videoCodec: videoCodec
        )
    }
    
    private func performVideoCompression(
        input: URL,
        output: URL,
        settings: CompressionSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        // Сначала получаем длительность видео для расчета прогресса
        let videoInfo = try extractVideoMetadata(from: input)
        let totalDuration = videoInfo.duration
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        // Формируем аргументы для FFmpeg с поддержкой VideoToolbox
        var arguments = ["-i", input.path]
        
        // Попытка аппаратного кодирования (если включено в настройках)
        if settings.useHardwareAcceleration, let hwEncoder = settings.codec.hardwareEncoder {
            if isEncoderAvailable(hwEncoder) {
                arguments.append(contentsOf: [
                    "-c:v", hwEncoder,
                    "-q:v", String(settings.crf)
                ])
                logger.info("Using hardware acceleration with \(hwEncoder)")
            } else {
                // Fallback к программному кодированию, если аппаратный кодировщик недоступен
                arguments.append(contentsOf: [
                    "-c:v", settings.codec.ffmpegValue,
                    "-crf", String(settings.crf),
                    "-preset", "medium"
                ])
                logger.warning("Hardware encoder \(hwEncoder) not available. Falling back to software \(settings.codec.ffmpegValue)")
            }
        } else {
            // Программное кодирование
            arguments.append(contentsOf: [
                "-c:v", settings.codec.ffmpegValue,
                "-crf", String(settings.crf),
                "-preset", "medium"
            ])
            logger.info("Using software encoding with \(settings.codec.ffmpegValue)")
        }
        
        // Настройки аудио
        arguments.append(contentsOf: settings.audioCodecParameters)
        
        // Добавляем параметры для более частого обновления прогресса и ограничиваем время на входной анализ
        arguments.append(contentsOf: [
            "-progress", "pipe:2",  // Вывод прогресса в stderr
            "-stats_period", "0.5", // Обновление статистики каждые 0.5 сек
            "-analyzeduration", "1000000", // 1s анализ
            "-probesize", "5000000"       // 5MB
        ])
        
        // Перезаписывать выходной файл без запроса
        arguments.append(contentsOf: ["-y", output.path])
        
        process.arguments = arguments
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        
        // Сохраняем ссылку на процесс для возможности отмены
        currentProcess = process

        // Ожидание завершения процесса с установкой terminationHandler ДО запуска
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var continuationResumed = false
                let continuationLock = NSLock()

                // Безопасная функция для завершения continuation
                let safeContinuation: @Sendable (Result<Void, Error>) -> Void = { result in
                    continuationLock.lock()
                    defer { continuationLock.unlock() }
                    if !continuationResumed {
                        continuationResumed = true
                        continuation.resume(with: result)
                    }
                }

                // Устанавливаем обработчик завершения процесса ДО запуска
                process.terminationHandler = { [weak self] terminatedProcess in
                    guard let self = self else { return }
                    let exitCode = terminatedProcess.terminationStatus
                    let reason = terminatedProcess.terminationReason
                    self.logger.info("FFmpeg process terminated with status: \(exitCode), reason: \(String(describing: reason))")

                    // Проверяем, была ли операция отменена
                    if self.currentProcess == nil {
                        self.logger.info("Process was cancelled by user")
                        safeContinuation(.failure(VideoCompressionError.cancelled))
                        return
                    }

                    // Если процесс завершен сигналом (SIGTERM/SIGKILL) — трактуем как отмену
                    if reason == .uncaughtSignal && (exitCode == 15 || exitCode == 9) {
                        self.logger.info("FFmpeg terminated by signal (treated as cancellation)")
                        safeContinuation(.failure(VideoCompressionError.cancelled))
                        return
                    }

                    // Обрабатываем различные коды завершения
                    switch exitCode {
                    case 0:
                        safeContinuation(.success(()))
                    case 1:
                        safeContinuation(.failure(VideoCompressionError.compressionFailed("FFmpeg general error (exit code 1)")))
                    case 2:
                        safeContinuation(.failure(VideoCompressionError.invalidInput("FFmpeg invalid arguments (exit code 2)")))
                    case 255:
                        // Часто FFmpeg возвращает 255 при SIGTERM; если это не отмена — считаем ошибкой
                        safeContinuation(.failure(VideoCompressionError.compressionFailed("FFmpeg process failed with exit code: 255")))
                    default:
                        safeContinuation(.failure(VideoCompressionError.compressionFailed("FFmpeg process failed with exit code: \(exitCode)")))
                    }
                }

                // Запускаем мониторинг отмены в отдельной задаче
                Task {
                    while process.isRunning {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if currentProcess == nil {
                            logger.info("Process cancellation detected, terminating FFmpeg")
                            if process.isRunning {
                                process.terminate()
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                if process.isRunning { process.interrupt() }
                            }
                            process.terminationHandler = nil
                            safeContinuation(.failure(VideoCompressionError.cancelled))
                            break
                        }
                    }
                }

                // Запускаем процесс
                do {
                    try process.run()

                    // Проверяем, что процесс не был отменен сразу после запуска
                    if currentProcess == nil {
                        logger.info("Process was cancelled immediately after start")
                        if process.isRunning { process.terminate() }
                        safeContinuation(.failure(VideoCompressionError.cancelled))
                        return
                    }

                    // Запускаем мониторинг прогресса после успешного старта процесса
                    let progressTask = Task {
                        await self.monitorProgress(
                            pipe: errorPipe,
                            totalDuration: totalDuration,
                            progressHandler: progressHandler,
                            processReference: process
                        )
                    }
                    currentProgressTask = progressTask

                } catch {
                    // Не удалось запустить процесс
                    logger.error("Process execution failed to start: \(error)")
                    process.terminationHandler = nil
                    safeContinuation(.failure(VideoCompressionError.compressionFailed("Process execution failed: \(error.localizedDescription)")))
                }
            }

            // Очищаем обработчик после завершения
            process.terminationHandler = nil

            // Финальная проверка отмены
            guard currentProcess != nil else {
                logger.info("Process was cancelled after completion")
                throw VideoCompressionError.cancelled
            }

        } catch let error as VideoCompressionError {
            currentProcess = nil
            currentProgressTask = nil
            throw error
        } catch {
            currentProcess = nil
            currentProgressTask = nil
            logger.error("Process execution failed: \(error)")
            throw VideoCompressionError.compressionFailed("Process execution failed: \(error.localizedDescription)")
        }
        
        currentProcess = nil
        currentProgressTask = nil
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.error("FFmpeg compression failed: \(errorString)")
            throw VideoCompressionError.compressionFailed(errorString)
        }
        
        logger.info("Video compression completed successfully")
    }
    
    private func monitorProgress(
        pipe: Pipe,
        totalDuration: TimeInterval,
        progressHandler: @escaping (Double) -> Void,
        processReference: Process
    ) async {
        let fileHandle = pipe.fileHandleForReading
        var buffer = ""
        var lastProgress: Double = 0
        var isMonitoringActive = true
        
        logger.info("Starting progress monitoring for process PID: \(processReference.processIdentifier)")
        
        // Компилируем regex один раз для лучшей производительности
        guard let timeRegex = try? NSRegularExpression(pattern: #"time=(\d{1,2}):(\d{2}):(\d{2})\.(\d{2})"#) else {
            logger.error("Failed to compile progress regex")
            return
        }
        
        // Мониторим процесс с использованием локальной ссылки
        while isMonitoringActive && processReference.isRunning {
            // Проверяем глобальное состояние отмены
            if currentProcess == nil {
                logger.info("Progress monitoring stopped - global cancellation detected")
                isMonitoringActive = false
                break
            }
            
            // Читаем доступные данные с обработкой ошибок
            let data: Data
            do {
                data = fileHandle.availableData
            } catch {
                logger.warning("Failed to read progress data: \(error)")
                break
            }
            
            if data.isEmpty {
                // Используем async sleep вместо usleep
                do {
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                } catch {
                    // Task was cancelled
                    logger.info("Progress monitoring task cancelled")
                    break
                }
                continue
            }
            
            guard let newOutput = String(data: data, encoding: .utf8) else { 
                logger.warning("Failed to decode progress output as UTF-8")
                continue 
            }
            buffer += newOutput
            
            // Обрабатываем построчно для лучшего парсинга
            let lines = buffer.components(separatedBy: .newlines)
            buffer = lines.last ?? "" // Сохраняем последнюю неполную строку
            
            for line in lines.dropLast() {
                if let progress = parseProgressFromLine(line, totalDuration: totalDuration, regex: timeRegex) {
                    // Обновляем прогресс только если изменение значительное (больше 0.5%)
                    if abs(progress - lastProgress) > 0.005 {
                        lastProgress = progress
                        
                        // Проверяем состояние отмены перед обновлением UI
                        if currentProcess != nil {
                            DispatchQueue.main.async {
                                progressHandler(progress)
                            }
                        } else {
                            logger.info("Skipping progress update due to cancellation")
                            isMonitoringActive = false
                            break
                        }
                    }
                }
            }
        }
        
        // Безопасная финальная проверка прогресса
        // Проверяем только если мониторинг завершился естественным образом
        if isMonitoringActive && currentProcess != nil && !processReference.isRunning {
            let terminationStatus = processReference.terminationStatus
            if terminationStatus == 0 && lastProgress < 1.0 {
                logger.info("Setting final progress to 100% (process completed successfully)")
                DispatchQueue.main.async {
                    progressHandler(1.0)
                }
            }
        }
        
        logger.info("Progress monitoring ended. Final progress: \(lastProgress)")
    }
    
    private func parseProgressFromLine(_ line: String, totalDuration: TimeInterval, regex: NSRegularExpression) -> Double? {
        // Сначала пробуем парсить новый формат прогресса (out_time_ms=...)
        if line.hasPrefix("out_time_ms=") {
            let timeString = line.replacingOccurrences(of: "out_time_ms=", with: "")
            if let microseconds = Int64(timeString), microseconds > 0 {
                let currentTime = TimeInterval(microseconds) / 1_000_000.0 // Конвертируем микросекунды в секунды
                guard totalDuration > 0 else { return nil }
                return min(currentTime / totalDuration, 1.0)
            }
        }
        
        // Fallback к старому формату (time=HH:MM:SS.ss)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        
        guard let match = regex.firstMatch(in: line, range: range) else {
            return nil
        }
        
        guard let hoursRange = Range(match.range(at: 1), in: line),
              let minutesRange = Range(match.range(at: 2), in: line),
              let secondsRange = Range(match.range(at: 3), in: line),
              let millisecondsRange = Range(match.range(at: 4), in: line) else {
            return nil
        }
        
        let hours = Int(line[hoursRange]) ?? 0
        let minutes = Int(line[minutesRange]) ?? 0
        let seconds = Int(line[secondsRange]) ?? 0
        let milliseconds = Int(line[millisecondsRange]) ?? 0
        
        let currentTime = TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(milliseconds) / 100.0
        
        guard totalDuration > 0 else { return nil }
        
        return min(currentTime / totalDuration, 1.0)
    }
}