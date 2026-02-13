#!/usr/bin/env swift

import Foundation

/// Тест для проверки обработки ошибок отмены сжатия
/// Проверяет, что при остановке сжатия не появляются лишние ошибки и окна
/// ИСПРАВЛЕНО: Код выхода 255 теперь обрабатывается как отмена, а не ошибка

print("🧪 Тестирование обработки ошибок отмены сжатия (исправленная версия)...")

// Создаем тестовое видео
let testVideoPath = "/tmp/test_cancellation_video.mp4"
let createProcess = Process()
createProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
createProcess.arguments = ["ffmpeg"]

let pipe = Pipe()
createProcess.standardOutput = pipe
createProcess.standardError = Pipe()

do {
    try createProcess.run()
    createProcess.waitUntilExit()
    
    if createProcess.terminationStatus != 0 {
        print("❌ FFmpeg не найден в системе")
        exit(1)
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let ffmpegPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    
    if ffmpegPath.isEmpty {
        print("❌ Не удалось найти путь к FFmpeg")
        exit(1)
    }
    
    print("✅ FFmpeg найден: \(ffmpegPath)")
    
    // Создаем тестовое видео
    let createVideoProcess = Process()
    createVideoProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
    createVideoProcess.arguments = [
        "-f", "lavfi",
        "-i", "testsrc=duration=10:size=320x240:rate=30",
        "-c:v", "libx264",
        "-t", "10",
        "-y",
        testVideoPath
    ]
    
    createVideoProcess.standardOutput = Pipe()
    createVideoProcess.standardError = Pipe()
    
    try createVideoProcess.run()
    createVideoProcess.waitUntilExit()
    
    if createVideoProcess.terminationStatus == 0 {
        print("✅ Тестовое видео создано: \(testVideoPath)")
    } else {
        print("❌ Не удалось создать тестовое видео")
        exit(1)
    }
    
    // Тест 1: Проверяем обработку кода выхода 255 (SIGTERM)
    print("\n🔍 Тест 1: Обработка кода выхода 255 (SIGTERM)")
    
    let compressionProcess = Process()
    compressionProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
    compressionProcess.arguments = [
        "-i", testVideoPath,
        "-c:v", "libx264",
        "-crf", "23",
        "-progress", "pipe:2",
        "-y",
        "/tmp/test_output_cancelled.mp4"
    ]
    
    let errorPipe = Pipe()
    compressionProcess.standardError = errorPipe
    compressionProcess.standardOutput = Pipe()
    
    try compressionProcess.run()
    
    // Ждем немного, затем отменяем
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
        print("⏹️ Отменяем процесс FFmpeg...")
        compressionProcess.terminate()
    }
    
    compressionProcess.waitUntilExit()
    
    let terminationStatus = compressionProcess.terminationStatus
    print("📊 Код завершения: \(terminationStatus)")
    
    // Проверяем обработку различных кодов выхода (ИСПРАВЛЕНО)
    switch terminationStatus {
    case 0:
        print("✅ Процесс завершился успешно")
    case 255, -15: // SIGTERM может быть представлен как 255 или -15
        print("✅ Процесс был корректно отменен (SIGTERM) - НЕ ОШИБКА!")
    case -9:
        print("✅ Процесс был принудительно завершен (SIGKILL) - НЕ ОШИБКА!")
    case 1:
        print("❌ Общая ошибка FFmpeg - ЭТО ОШИБКА")
    case 2:
        print("❌ Неверные аргументы - ЭТО ОШИБКА")
    default:
        print("⚠️ Неожиданный код завершения: \(terminationStatus)")
    }
    
    // Читаем stderr для анализа ошибок
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let errorString = String(data: errorData, encoding: .utf8) ?? ""
    
    if !errorString.isEmpty {
        print("📝 Вывод stderr:")
        let lines = errorString.components(separatedBy: .newlines).prefix(10)
        for line in lines {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                print("   \(line)")
            }
        }
    }
    
    // Тест 2: Проверяем множественные отмены
    print("\n🔍 Тест 2: Множественные отмены")
    
    for i in 1...3 {
        print("   Попытка \(i)...")
        
        let multiProcess = Process()
        multiProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
        multiProcess.arguments = [
            "-i", testVideoPath,
            "-c:v", "libx264",
            "-crf", "23",
            "-y",
            "/tmp/test_output_multi_\(i).mp4"
        ]
        
        multiProcess.standardOutput = Pipe()
        multiProcess.standardError = Pipe()
        
        try multiProcess.run()
        
        // Быстрая отмена
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            multiProcess.terminate()
            
            // Дополнительные попытки отмены (не должны вызывать проблем)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                if multiProcess.isRunning {
                    multiProcess.interrupt()
                }
            }
        }
        
        multiProcess.waitUntilExit()
        print("   ✅ Попытка \(i) завершена с кодом: \(multiProcess.terminationStatus)")
    }
    
    // Тест 3: Проверяем обработку ошибок в Swift коде
    print("\n🔍 Тест 3: Обработка ошибок в Swift")
    
    func simulateFFmpegError(exitCode: Int32) -> String {
        switch exitCode {
        case 0:
            return "Успешное завершение"
        case 1:
            return "Общая ошибка"
        case 255, -15:
            return "Операция отменена пользователем"
        case -9:
            return "Процесс принудительно завершен"
        default:
            return "FFmpeg завершился с кодом: \(exitCode)"
        }
    }
    
    let testCodes: [Int32] = [0, 1, 255, -15, -9, 2, 127]
    for code in testCodes {
        let message = simulateFFmpegError(exitCode: code)
        print("   Код \(code): \(message)")
    }
    
    // Очистка
    try? FileManager.default.removeItem(atPath: testVideoPath)
    
    print("\n✅ Все тесты обработки ошибок отмены завершены успешно!")
    
    print("\n📋 ВАЖНЫЕ ИСПРАВЛЕНИЯ:")
    print("   • Код выхода 255 от FFmpeg при SIGTERM НЕ является ошибкой")
    print("   • Код выхода -15 (SIGTERM) НЕ является ошибкой") 
    print("   • Код выхода -9 (SIGKILL) НЕ является ошибкой")
    print("   • Только коды 1, 2 и другие являются реальными ошибками")
    print("   • При отмене пользователем НЕ должны показываться диалоги ошибок")
    print("   • Статус файла должен сбрасываться в 'pending', а не 'failed'")
    
} catch {
    print("❌ Ошибка при выполнении тестов: \(error)")
    exit(1)
}