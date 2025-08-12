import XCTest
@testable import VideoSzhimaka

/// Unit tests for VideoCompressionError
@MainActor
final class VideoCompressionErrorTests: XCTestCase {
    
    // MARK: - Error Description Tests
    
    func testFFmpegNotFoundErrorDescription() {
        let error = VideoCompressionError.ffmpegNotFound
        XCTAssertEqual(error.localizedDescription, "FFmpeg не найден в ресурсах приложения")
        XCTAssertEqual(error.errorCode, 1001)
        XCTAssertFalse(error.isRetryable)
    }
    
    func testUnsupportedFormatErrorDescription() {
        let format = "AVI"
        let error = VideoCompressionError.unsupportedFormat(format)
        XCTAssertEqual(error.localizedDescription, "Неподдерживаемый формат видео: \(format)")
        XCTAssertEqual(error.errorCode, 1002)
        XCTAssertFalse(error.isRetryable)
    }
    
    func testCompressionFailedErrorDescription() {
        let message = "Недостаточно памяти"
        let error = VideoCompressionError.compressionFailed(message)
        XCTAssertEqual(error.localizedDescription, "Ошибка сжатия: \(message)")
        XCTAssertEqual(error.errorCode, 1003)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testFileNotFoundErrorDescription() {
        let path = "/path/to/missing/file.mp4"
        let error = VideoCompressionError.fileNotFound(path)
        XCTAssertEqual(error.localizedDescription, "Файл не найден: \(path)")
        XCTAssertEqual(error.errorCode, 1004)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testInsufficientSpaceErrorDescription() {
        let error = VideoCompressionError.insufficientSpace
        XCTAssertEqual(error.localizedDescription, "Недостаточно места на диске для сохранения сжатого файла")
        XCTAssertEqual(error.errorCode, 1005)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testCancelledErrorDescription() {
        let error = VideoCompressionError.cancelled
        XCTAssertEqual(error.localizedDescription, "Операция отменена пользователем")
        XCTAssertEqual(error.errorCode, 1006)
        XCTAssertFalse(error.isRetryable)
    }
    
    func testInvalidInputErrorDescription() {
        let message = "Поврежденный файл"
        let error = VideoCompressionError.invalidInput(message)
        XCTAssertEqual(error.localizedDescription, "Некорректный входной файл: \(message)")
        XCTAssertEqual(error.errorCode, 1007)
        XCTAssertFalse(error.isRetryable)
    }
    
    func testOutputPathErrorDescription() {
        let path = "/readonly/path"
        let error = VideoCompressionError.outputPathError(path)
        XCTAssertEqual(error.localizedDescription, "Ошибка создания выходного файла: \(path)")
        XCTAssertEqual(error.errorCode, 1008)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testPermissionDeniedErrorDescription() {
        let path = "/protected/file.mp4"
        let error = VideoCompressionError.permissionDenied(path)
        XCTAssertEqual(error.localizedDescription, "Нет прав доступа к файлу: \(path)")
        XCTAssertEqual(error.errorCode, 1009)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testNetworkErrorDescription() {
        let message = "Connection timeout"
        let error = VideoCompressionError.networkError(message)
        XCTAssertEqual(error.localizedDescription, "Ошибка сети: \(message)")
        XCTAssertEqual(error.errorCode, 1010)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testCorruptedFileErrorDescription() {
        let path = "/path/to/corrupted.mp4"
        let error = VideoCompressionError.corruptedFile(path)
        XCTAssertEqual(error.localizedDescription, "Поврежденный файл: \(path)")
        XCTAssertEqual(error.errorCode, 1011)
        XCTAssertTrue(error.isRetryable)
    }
    
    func testUnknownErrorDescription() {
        let message = "Unexpected error occurred"
        let error = VideoCompressionError.unknownError(message)
        XCTAssertEqual(error.localizedDescription, "Неизвестная ошибка: \(message)")
        XCTAssertEqual(error.errorCode, 1999)
        XCTAssertTrue(error.isRetryable)
    }
    
    // MARK: - Recovery Suggestion Tests
    
    func testFFmpegNotFoundRecoverySuggestion() {
        let error = VideoCompressionError.ffmpegNotFound
        XCTAssertEqual(error.recoverySuggestion, "Переустановите приложение или обратитесь в службу поддержки")
    }
    
    func testUnsupportedFormatRecoverySuggestion() {
        let error = VideoCompressionError.unsupportedFormat("AVI")
        XCTAssertEqual(error.recoverySuggestion, "Попробуйте конвертировать файл в поддерживаемый формат")
    }
    
    func testCompressionFailedRecoverySuggestion() {
        let error = VideoCompressionError.compressionFailed("Memory error")
        XCTAssertEqual(error.recoverySuggestion, "Проверьте настройки сжатия и попробуйте снова")
    }
    
    func testFileNotFoundRecoverySuggestion() {
        let error = VideoCompressionError.fileNotFound("/missing/file.mp4")
        XCTAssertEqual(error.recoverySuggestion, "Убедитесь, что файл существует и не был перемещен")
    }
    
    func testInsufficientSpaceRecoverySuggestion() {
        let error = VideoCompressionError.insufficientSpace
        XCTAssertEqual(error.recoverySuggestion, "Освободите место на диске и попробуйте снова")
    }
    
    func testCancelledRecoverySuggestion() {
        let error = VideoCompressionError.cancelled
        XCTAssertNil(error.recoverySuggestion)
    }
    
    func testInvalidInputRecoverySuggestion() {
        let error = VideoCompressionError.invalidInput("Corrupted")
        XCTAssertEqual(error.recoverySuggestion, "Выберите корректный видеофайл")
    }
    
    func testOutputPathErrorRecoverySuggestion() {
        let error = VideoCompressionError.outputPathError("/readonly")
        XCTAssertEqual(error.recoverySuggestion, "Проверьте права доступа к папке назначения")
    }
    
    func testPermissionDeniedRecoverySuggestion() {
        let error = VideoCompressionError.permissionDenied("/protected/file")
        XCTAssertEqual(error.recoverySuggestion, "Предоставьте приложению права доступа к файлу")
    }
    
    func testNetworkErrorRecoverySuggestion() {
        let error = VideoCompressionError.networkError("Timeout")
        XCTAssertEqual(error.recoverySuggestion, "Проверьте подключение к интернету")
    }
    
    func testCorruptedFileRecoverySuggestion() {
        let error = VideoCompressionError.corruptedFile("/corrupted.mp4")
        XCTAssertEqual(error.recoverySuggestion, "Попробуйте использовать другой файл")
    }
    
    func testUnknownErrorRecoverySuggestion() {
        let error = VideoCompressionError.unknownError("Unknown")
        XCTAssertEqual(error.recoverySuggestion, "Попробуйте перезапустить приложение")
    }
    
    // MARK: - Retry Capability Tests
    
    func testRetryableErrors() {
        let retryableErrors: [VideoCompressionError] = [
            .compressionFailed("Error"),
            .fileNotFound("/path"),
            .insufficientSpace,
            .outputPathError("/path"),
            .permissionDenied("/path"),
            .networkError("Error"),
            .corruptedFile("/path"),
            .unknownError("Error")
        ]
        
        for error in retryableErrors {
            XCTAssertTrue(error.isRetryable, "Error \(error) should be retryable")
        }
    }
    
    func testNonRetryableErrors() {
        let nonRetryableErrors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat("AVI"),
            .cancelled,
            .invalidInput("Error")
        ]
        
        for error in nonRetryableErrors {
            XCTAssertFalse(error.isRetryable, "Error \(error) should not be retryable")
        }
    }
    
    // MARK: - Error Code Tests
    
    func testUniqueErrorCodes() {
        let errors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat(""),
            .compressionFailed(""),
            .fileNotFound(""),
            .insufficientSpace,
            .cancelled,
            .invalidInput(""),
            .outputPathError(""),
            .permissionDenied(""),
            .networkError(""),
            .corruptedFile(""),
            .unknownError("")
        ]
        
        let errorCodes = errors.map { $0.errorCode }
        let uniqueErrorCodes = Set(errorCodes)
        
        XCTAssertEqual(errorCodes.count, uniqueErrorCodes.count, "All error codes should be unique")
    }
    
    func testErrorCodeRanges() {
        let errors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat(""),
            .compressionFailed(""),
            .fileNotFound(""),
            .insufficientSpace,
            .cancelled,
            .invalidInput(""),
            .outputPathError(""),
            .permissionDenied(""),
            .networkError(""),
            .corruptedFile("")
        ]
        
        for error in errors {
            XCTAssertTrue(error.errorCode >= 1001 && error.errorCode <= 1011, 
                         "Error code \(error.errorCode) should be in range 1001-1011")
        }
        
        let unknownError = VideoCompressionError.unknownError("")
        XCTAssertEqual(unknownError.errorCode, 1999, "Unknown error should have code 1999")
    }
}

// MARK: - CompressionStatus Error Integration Tests

@MainActor
final class CompressionStatusErrorTests: XCTestCase {
    
    func testCompressionStatusWithVideoCompressionError() {
        let error = VideoCompressionError.compressionFailed("Test error")
        let status = CompressionStatus.failed(error)
        
        XCTAssertEqual(status.displayText, "Ошибка: Ошибка сжатия: Test error")
        XCTAssertTrue(status.isFinished)
        XCTAssertFalse(status.isSuccessful)
        XCTAssertFalse(status.isActive)
    }
    
    func testCompressionStatusEquality() {
        let error1 = VideoCompressionError.compressionFailed("Same error")
        let error2 = VideoCompressionError.compressionFailed("Same error")
        let error3 = VideoCompressionError.compressionFailed("Different error")
        
        let status1 = CompressionStatus.failed(error1)
        let status2 = CompressionStatus.failed(error2)
        let status3 = CompressionStatus.failed(error3)
        
        XCTAssertEqual(status1, status2)
        XCTAssertNotEqual(status1, status3)
    }
    
    func testCompressionStatusCodable() throws {
        let error = VideoCompressionError.fileNotFound("/test/path")
        let originalStatus = CompressionStatus.failed(error)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalStatus)
        
        let decoder = JSONDecoder()
        let decodedStatus = try decoder.decode(CompressionStatus.self, from: data)
        
        // Note: After decoding, the specific error type is lost and becomes unknownError
        if case .failed(let decodedError) = decodedStatus {
            XCTAssertTrue(decodedError.localizedDescription.contains("Файл не найден: /test/path"))
        } else {
            XCTFail("Decoded status should be failed")
        }
    }
}

// MARK: - Error Mapping Tests

@MainActor
final class ErrorMappingTests: XCTestCase {
    
    @MainActor
    func testNSErrorMapping() {
        let _ = MainViewModel()
        
        // Test file not found error
        let _ = NSError(domain: NSCocoaErrorDomain, 
                                       code: NSFileReadNoSuchFileError, 
                                       userInfo: [NSLocalizedDescriptionKey: "File not found"])
        
        // We can't directly test the private mapToCompressionError method,
        // but we can test the behavior through public methods
        // This would be tested through integration tests
    }
    
    func testGenericErrorMapping() {
        // Test that generic errors are properly mapped to VideoCompressionError
        struct TestError: Error {
            let message: String
        }
        
        let _ = TestError(message: "Generic test error")
        
        // This would be tested through the MainViewModel's error handling
        // in integration tests
    }
}

// MARK: - Graceful Degradation Tests

@MainActor
final class GracefulDegradationTests: XCTestCase {
    
    @MainActor
    func testErrorHandlingIntegration() async {
        // Test that the error handling system is properly integrated
        let error = VideoCompressionError.compressionFailed("Test error")
        
        // Test error properties
        XCTAssertTrue(error.isRetryable)
        XCTAssertEqual(error.errorCode, 1003)
        XCTAssertEqual(error.localizedDescription, "Ошибка сжатия: Test error")
        XCTAssertEqual(error.recoverySuggestion, "Проверьте настройки сжатия и попробуйте снова")
    }
    
    @MainActor
    func testCompressionStatusWithError() {
        // Test that CompressionStatus properly handles errors
        let error = VideoCompressionError.fileNotFound("/test/path")
        let status = CompressionStatus.failed(error)
        
        XCTAssertTrue(status.isFinished)
        XCTAssertFalse(status.isSuccessful)
        XCTAssertFalse(status.isActive)
        XCTAssertEqual(status.displayText, "Ошибка: Файл не найден: /test/path")
    }
    
    @MainActor
    func testRetryableVsNonRetryableErrors() {
        // Test retryable errors
        let retryableErrors: [VideoCompressionError] = [
            .compressionFailed("Error"),
            .fileNotFound("/path"),
            .insufficientSpace,
            .outputPathError("/path"),
            .permissionDenied("/path"),
            .networkError("Error"),
            .corruptedFile("/path"),
            .unknownError("Error")
        ]
        
        for error in retryableErrors {
            XCTAssertTrue(error.isRetryable, "Error \(error) should be retryable")
        }
        
        // Test non-retryable errors
        let nonRetryableErrors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat("AVI"),
            .cancelled,
            .invalidInput("Error")
        ]
        
        for error in nonRetryableErrors {
            XCTAssertFalse(error.isRetryable, "Error \(error) should not be retryable")
        }
    }
    
    @MainActor
    func testErrorLocalization() {
        // Test that all errors have proper Russian localization
        let errors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat("AVI"),
            .compressionFailed("Memory error"),
            .fileNotFound("/missing/file.mp4"),
            .insufficientSpace,
            .cancelled,
            .invalidInput("Corrupted"),
            .outputPathError("/readonly"),
            .permissionDenied("/protected/file"),
            .networkError("Timeout"),
            .corruptedFile("/corrupted.mp4"),
            .unknownError("Unknown")
        ]
        
        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.isEmpty, "Error description should not be empty")
            // All error descriptions should be in Russian (contain Cyrillic characters)
            let containsCyrillic = description.range(of: "[а-яё]", options: [.regularExpression, .caseInsensitive]) != nil
            XCTAssertTrue(containsCyrillic, "Error description should be in Russian: \(description)")
        }
    }
    
    @MainActor
    func testErrorRecoverySuggestions() {
        // Test that appropriate errors have recovery suggestions
        let errorsWithSuggestions: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat("AVI"),
            .compressionFailed("Error"),
            .fileNotFound("/path"),
            .insufficientSpace,
            .invalidInput("Error"),
            .outputPathError("/path"),
            .permissionDenied("/path"),
            .networkError("Error"),
            .corruptedFile("/path"),
            .unknownError("Error")
        ]
        
        for error in errorsWithSuggestions {
            XCTAssertNotNil(error.recoverySuggestion, "Error \(error) should have recovery suggestion")
            XCTAssertFalse(error.recoverySuggestion!.isEmpty, "Recovery suggestion should not be empty")
        }
        
        // Test that cancelled error has no recovery suggestion
        let cancelledError = VideoCompressionError.cancelled
        XCTAssertNil(cancelledError.recoverySuggestion, "Cancelled error should not have recovery suggestion")
    }
    
    @MainActor
    func testErrorCodes() {
        // Test that all errors have unique error codes
        let errors: [VideoCompressionError] = [
            .ffmpegNotFound,
            .unsupportedFormat(""),
            .compressionFailed(""),
            .fileNotFound(""),
            .insufficientSpace,
            .cancelled,
            .invalidInput(""),
            .outputPathError(""),
            .permissionDenied(""),
            .networkError(""),
            .corruptedFile(""),
            .unknownError("")
        ]
        
        let errorCodes = errors.map { $0.errorCode }
        let uniqueErrorCodes = Set(errorCodes)
        
        XCTAssertEqual(errorCodes.count, uniqueErrorCodes.count, "All error codes should be unique")
        
        // Test specific error code ranges
        for error in errors {
            if error.errorCode == 1999 {
                // Unknown error has special code
                continue
            }
            XCTAssertTrue(error.errorCode >= 1001 && error.errorCode <= 1011, 
                         "Error code \(error.errorCode) should be in range 1001-1011")
        }
    }
}