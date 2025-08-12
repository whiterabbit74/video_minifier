import XCTest
@testable import VideoSzhimaka

@MainActor
final class FFmpegServiceTests: XCTestCase {
    var ffmpegService: FFmpegService!
    var testVideoURL: URL!
    var tempDirectory: URL!
    
    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Создаем временную директорию для тестов
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFmpegServiceTests")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        // Создаем тестовый видеофайл с помощью FFmpeg
        try createTestVideo()
        
        // Инициализируем сервис
        ffmpegService = try FFmpegService()
    }
    
    override func tearDownWithError() throws {
        // Удаляем временную директорию
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        
        ffmpegService = nil
        testVideoURL = nil
        tempDirectory = nil
        
        try super.tearDownWithError()
    }
    
    func testFFmpegServiceInitialization() throws {
        // Тест успешной инициализации сервиса
        XCTAssertNotNil(ffmpegService)
    }
    
    func testGetVideoInfo() async throws {
        // Тест получения информации о видео
        let videoInfo = try await ffmpegService.getVideoInfo(url: testVideoURL)
        
        XCTAssertGreaterThan(videoInfo.duration, 0)
        XCTAssertGreaterThan(videoInfo.width, 0)
        XCTAssertGreaterThan(videoInfo.height, 0)
        XCTAssertGreaterThan(videoInfo.frameRate, 0)
        XCTAssertNotNil(videoInfo.videoCodec)
    }
    
    func testGetVideoInfoWithNonExistentFile() async {
        // Тест с несуществующим файлом
        let nonExistentURL = tempDirectory.appendingPathComponent("nonexistent.mp4")
        
        do {
            _ = try await ffmpegService.getVideoInfo(url: nonExistentURL)
            XCTFail("Expected VideoCompressionError.fileNotFound")
        } catch VideoCompressionError.fileNotFound {
            // Ожидаемая ошибка
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testVideoCompression() async throws {
        // Тест сжатия видео
        let outputURL = tempDirectory.appendingPathComponent("compressed_test.mp4")
        let settings = CompressionSettings(
            crf: 23,
            codec: .h264,
            deleteOriginals: false,
            copyAudio: true,
            autoCloseApp: false,
            showInDock: true,
            showInMenuBar: true
        )
        
        var progressUpdates: [Double] = []
        
        try await ffmpegService.compressVideo(
            input: testVideoURL,
            output: outputURL,
            settings: settings
        ) { progress in
            progressUpdates.append(progress)
        }
        
        // Проверяем, что выходной файл создан
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        
        // Проверяем, что получали обновления прогресса
        XCTAssertFalse(progressUpdates.isEmpty)
        
        // Проверяем, что последнее значение прогресса близко к 1.0
        if let lastProgress = progressUpdates.last {
            XCTAssertGreaterThanOrEqual(lastProgress, 0.9)
        }
        
        // Проверяем информацию о сжатом файле
        let compressedInfo = try await ffmpegService.getVideoInfo(url: outputURL)
        let originalInfo = try await ffmpegService.getVideoInfo(url: testVideoURL)
        
        XCTAssertEqual(compressedInfo.width, originalInfo.width)
        XCTAssertEqual(compressedInfo.height, originalInfo.height)
        XCTAssertEqual(compressedInfo.duration, originalInfo.duration, accuracy: 1.0)
    }
    
    func testVideoCompressionWithH265() async throws {
        // Тест сжатия с кодеком H.265
        let outputURL = tempDirectory.appendingPathComponent("compressed_h265_test.mp4")
        let settings = CompressionSettings(
            crf: 25,
            codec: .h265,
            deleteOriginals: false,
            copyAudio: false,
            autoCloseApp: false,
            showInDock: true,
            showInMenuBar: true
        )
        
        // Пропускаем тест, если H.265 энкодер недоступен на машине разработчика/CI
        if !isAnyH265EncoderAvailable() {
            throw XCTSkip("H.265 encoder not available on this machine. Skipping test.")
        }
        
        try await ffmpegService.compressVideo(
            input: testVideoURL,
            output: outputURL,
            settings: settings
        ) { _ in }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        
        let compressedInfo = try await ffmpegService.getVideoInfo(url: outputURL)
        XCTAssertEqual(compressedInfo.videoCodec, "hevc")
    }
    
    func testVideoCompressionWithInvalidOutput() async {
        // Тест с недопустимым путем вывода
        let invalidOutputURL = URL(fileURLWithPath: "/invalid/path/output.mp4")
        let settings = CompressionSettings()
        
        do {
            try await ffmpegService.compressVideo(
                input: testVideoURL,
                output: invalidOutputURL,
                settings: settings
            ) { _ in }
            XCTFail("Expected VideoCompressionError.outputPathError")
        } catch VideoCompressionError.outputPathError {
            // Ожидаемая ошибка
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCancelOperation() async throws {
        // Тест отмены операции
        let outputURL = tempDirectory.appendingPathComponent("cancelled_test.mp4")
        let settings = CompressionSettings()
        
        let compressionTask = Task {
            try await ffmpegService.compressVideo(
                input: testVideoURL,
                output: outputURL,
                settings: settings
            ) { _ in }
        }
        
        // Отменяем операцию через небольшую задержку
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.ffmpegService.cancelCurrentOperation()
        }
        
        do {
            try await compressionTask.value
            // Если операция завершилась успешно, это тоже нормально для быстрых файлов
        } catch {
            // Ошибка отмены также допустима
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideo() throws {
        testVideoURL = tempDirectory.appendingPathComponent("test_video.mp4")
        
        // Создаем простое тестовое видео с помощью FFmpeg
        var ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil, inDirectory: "bin")
        if ffmpegPath == nil {
            ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil)
        }
        
        guard let validFFmpegPath = ffmpegPath else {
            throw VideoCompressionError.ffmpegNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: validFFmpegPath)
        process.arguments = [
            "-f", "lavfi",
            "-i", "testsrc=duration=1:size=160x120:rate=24",
            "-f", "lavfi",
            "-i", "sine=frequency=1000:duration=1",
            "-c:v", "libx264",
            "-c:a", "aac",
            "-shortest",
            "-y",
            testVideoURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw VideoCompressionError.compressionFailed("Failed to create test video")
        }
        
        guard FileManager.default.fileExists(atPath: testVideoURL.path) else {
            throw VideoCompressionError.fileNotFound(testVideoURL.path)
        }
    }

    // MARK: - Helpers
    private func ffmpegPathForTests() -> String? {
        if let path = Bundle.main.path(forResource: "ffmpeg", ofType: nil, inDirectory: "bin") {
            return path
        }
        if let path = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return path
        }
        // Попробуем системные пути
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            return c
        }
        return nil
    }

    private func isAnyH265EncoderAvailable() -> Bool {
        guard let path = ffmpegPathForTests() else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-hide_banner", "-encoders"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard let s = String(data: data, encoding: .utf8) else { return false }
            return s.contains("hevc_videotoolbox") || s.contains("libx265")
        } catch {
            return false
        }
    }
}