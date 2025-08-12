#!/usr/bin/env swift

import Foundation

/// Тест для проверки чистой обработки отмены сжатия без ошибок и окон
/// Проверяет, что код выхода 255 от FFmpeg обрабатывается как отмена, а не как ошибка

print("🧪 Тестирование чистой обработки отмены сжатия...")

// Симуляция обработки различных кодов выхода FFmpeg
func handleFFmpegExitCode(_ exitCode: Int32, wasCancelled: Bool) -> (isError: Bool, message: String) {
    // Проверяем, была ли операция отменена пользователем
    if wasCancelled {
        return (false, "Операция отменена пользователем")
    }
    
    // Обрабатываем различные коды завершения
    switch exitCode {
    case 0:
        return (false, "Успешное завершение")
    case 255, -15:
        // Код 255 или -15 обычно означает SIGTERM (отмена пользователем)
        return (false, "FFmpeg завершен с SIGTERM (отмена пользователем)")
    case -9:
        // SIGKILL - принудительное завершение
        return (false, "FFmpeg завершен с SIGKILL")
    case 1:
        // Общая ошибка FFmpeg
        return (true, "Общая ошибка FFmpeg (код 1)")
    case 2:
        // Неверные аргументы
        return (true, "Неверные аргументы FFmpeg (код 2)")
    default:
        // Другие ошибки
        return (true, "FFmpeg завершился с кодом: \(exitCode)")
    }
}

// Тест 1: Проверяем обработку кода 255 без отмены
print("\n🔍 Тест 1: Код выхода 255 без явной отмены")
let result1 = handleFFmpegExitCode(255, wasCancelled: false)
print("   Результат: \(result1.message)")
print("   Это ошибка: \(result1.isError ? "❌ ДА" : "✅ НЕТ")")

// Тест 2: Проверяем обработку кода 255 с отменой
print("\n🔍 Тест 2: Код выхода 255 с явной отменой")
let result2 = handleFFmpegExitCode(255, wasCancelled: true)
print("   Результат: \(result2.message)")
print("   Это ошибка: \(result2.isError ? "❌ ДА" : "✅ НЕТ")")

// Тест 3: Проверяем обработку других кодов
print("\n🔍 Тест 3: Различные коды выхода")
let testCodes: [(Int32, Bool)] = [
    (0, false),     // Успех
    (1, false),     // Ошибка
    (2, false),     // Неверные аргументы
    (-9, false),    // SIGKILL
    (-15, false),   // SIGTERM
    (255, true),    // Отмена пользователем
]

for (code, cancelled) in testCodes {
    let result = handleFFmpegExitCode(code, wasCancelled: cancelled)
    let status = result.isError ? "❌ ОШИБКА" : "✅ ОК"
    print("   Код \(code) (отмена: \(cancelled)): \(status) - \(result.message)")
}

// Тест 4: Симуляция реального сценария отмены
print("\n🔍 Тест 4: Симуляция реального сценария отмены")

class MockFFmpegProcess {
    var isRunning = false
    var terminationStatus: Int32 = 0
    var wasCancelledByUser = false
    
    func start() {
        isRunning = true
        print("   📹 FFmpeg процесс запущен")
    }
    
    func terminate() {
        if isRunning {
            wasCancelledByUser = true
            terminationStatus = 255  // SIGTERM обычно дает код 255
            isRunning = false
            print("   ⏹️ FFmpeg процесс завершен пользователем (SIGTERM)")
        }
    }
    
    func handleTermination() -> (shouldShowError: Bool, message: String) {
        let result = handleFFmpegExitCode(terminationStatus, wasCancelled: wasCancelledByUser)
        
        if result.isError {
            return (true, "Ошибка сжатия: \(result.message)")
        } else {
            return (false, result.message)
        }
    }
}

// Симулируем нормальное завершение
print("\n   Сценарий 1: Нормальное завершение")
let process1 = MockFFmpegProcess()
process1.start()
process1.terminationStatus = 0
process1.isRunning = false
let result4a = process1.handleTermination()
print("   Показать ошибку: \(result4a.shouldShowError ? "❌ ДА" : "✅ НЕТ")")
print("   Сообщение: \(result4a.message)")

// Симулируем отмену пользователем
print("\n   Сценарий 2: Отмена пользователем")
let process2 = MockFFmpegProcess()
process2.start()
process2.terminate()  // Пользователь нажал отмену
let result4b = process2.handleTermination()
print("   Показать ошибку: \(result4b.shouldShowError ? "❌ ДА" : "✅ НЕТ")")
print("   Сообщение: \(result4b.message)")

// Симулируем реальную ошибку
print("\n   Сценарий 3: Реальная ошибка FFmpeg")
let process3 = MockFFmpegProcess()
process3.start()
process3.terminationStatus = 1  // Реальная ошибка
process3.isRunning = false
let result4c = process3.handleTermination()
print("   Показать ошибку: \(result4c.shouldShowError ? "❌ ДА" : "✅ НЕТ")")
print("   Сообщение: \(result4c.message)")

// Тест 5: Проверяем логику UI обновлений
print("\n🔍 Тест 5: Логика обновления UI при отмене")

enum CompressionStatus {
    case pending
    case compressing
    case completed
    case failed(String)
    case cancelled
}

func handleCompressionResult(exitCode: Int32, wasCancelled: Bool) -> CompressionStatus {
    let result = handleFFmpegExitCode(exitCode, wasCancelled: wasCancelled)
    
    if wasCancelled || (!result.isError && (exitCode == 255 || exitCode == -15 || exitCode == -9)) {
        return .cancelled
    } else if result.isError {
        return .failed(result.message)
    } else if exitCode == 0 {
        return .completed
    } else {
        return .pending
    }
}

let testScenarios: [(String, Int32, Bool)] = [
    ("Успешное завершение", 0, false),
    ("Отмена пользователем", 255, true),
    ("SIGTERM без отмены", 255, false),
    ("SIGKILL", -9, false),
    ("Ошибка FFmpeg", 1, false),
    ("Неверные аргументы", 2, false)
]

for (scenario, code, cancelled) in testScenarios {
    let status = handleCompressionResult(exitCode: code, wasCancelled: cancelled)
    print("   \(scenario): \(status)")
}

print("\n✅ Все тесты чистой обработки отмены завершены!")
print("\n📋 Выводы:")
print("   • Код выхода 255 от FFmpeg при отмене НЕ должен показываться как ошибка")
print("   • Отмененные операции должны сбрасывать статус файла в 'pending'")
print("   • Никаких диалогов ошибок при отмене пользователем")
print("   • Только реальные ошибки FFmpeg (коды 1, 2 и др.) показываются как ошибки")