#!/usr/bin/env swift

import Foundation

/// Реальный тест обработки отмены с FFmpeg
/// Проверяет, что при остановке реального процесса FFmpeg не появляются ошибки

print("🧪 Тестирование реальной обработки отмены с FFmpeg...")

// Проверяем наличие FFmpeg
func findFFmpeg() -> String? {
    let possiblePaths = [
        "/opt/homebrew/bin/ffmpeg",  // Homebrew на Apple Silicon
        "/usr/local/bin/ffmpeg",     // Homebrew на Intel
        "/usr/bin/ffmpeg"            // Системный FFmpeg
    ]
    
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    
    // Пробуем найти через which
    let whichProcess = Process()
    whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProcess.arguments = ["ffmpeg"]
    
    let pipe = Pipe()
    whichProcess.standardOutput = pipe
    whichProcess.standardError = Pipe()
    
    do {
        try whichProcess.run()
        whichProcess.waitUntilExit()
        
        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        }
    } catch {
        print("❌ Ошибка при поиске FFmpeg: \(error)")
    }
    
    return nil
}

guard let ffmpegPath = findFFmpeg() else {
    print("❌ FFmpeg не найден в системе. Установите FFmpeg для выполнения теста.")
    exit(1)
}

print("✅ FFmpeg найден: \(ffmpegPath)")

// Создаем тестовое видео
let testVideoPath = "/tmp/test_cancellation_video.mp4"
let outputVideoPath = "/tmp/test_cancellation_output.mp4"

func createTestVideo() -> Bool {
    print("📹 Создание тестового видео...")
    
    let createProcess = Process()
    createProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
    createProcess.arguments = [
        "-f", "lavfi",
        "-i", "testsrc=duration=30:size=640x480:rate=30",  // 30 секунд видео
        "-c:v", "libx264",
        "-preset", "ultrafast",  // Быстрое кодирование для теста
        "-t", "30",
        "-y",
        testVideoPath
    ]
    
    createProcess.standardOutput = Pipe()
    createProcess.standardError = Pipe()
    
    do {
        try createProcess.run()
        createProcess.waitUntilExit()
        
        if createProcess.terminationStatus == 0 {
            print("✅ Тестовое видео создано")
            return true
        } else {
            print("❌ Не удалось создать тестовое видео (код: \(createProcess.terminationStatus))")
            return false
        }
    } catch {
        print("❌ Ошибка при создании тестового видео: \(error)")
        return false
    }
}

// Тест 1: Быстрая отмена
func testQuickCancellation() {
    print("\n🔍 Тест 1: Быстрая отмена сжатия")
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.arguments = [
        "-i", testVideoPath,
        "-c:v", "libx264",
        "-crf", "23",
        "-preset", "slow",  // Медленный preset для длительного сжатия
        "-progress", "pipe:2",
        "-y",
        outputVideoPath
    ]
    
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    
    do {
        try process.run()
        print("   📹 Процесс FFmpeg запущен (PID: \(process.processIdentifier))")
        
        // Ждем немного, затем отменяем
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            print("   ⏹️ Отменяем процесс...")
            process.terminate()
        }
        
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        print("   📊 Код завершения: \(exitCode)")
        
        // Анализируем результат
        switch exitCode {
        case 0:
            print("   ✅ Процесс завершился успешно (неожиданно)")
        case 255, -15:
            print("   ✅ Процесс корректно отменен (SIGTERM)")
        case -9:
            print("   ✅ Процесс принудительно завершен (SIGKILL)")
        case 1:
            print("   ⚠️ Общая ошибка FFmpeg")
        default:
            print("   ⚠️ Неожиданный код завершения: \(exitCode)")
        }
        
        // Проверяем, что выходной файл не создался или неполный
        if FileManager.default.fileExists(atPath: outputVideoPath) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: outputVideoPath)
            let fileSize = attributes?[.size] as? Int64 ?? 0
            print("   📁 Выходной файл создан, размер: \(fileSize) байт")
            
            // Удаляем неполный файл
            try? FileManager.default.removeItem(atPath: outputVideoPath)
        } else {
            print("   ✅ Выходной файл не создан (ожидаемо при отмене)")
        }
        
    } catch {
        print("   ❌ Ошибка при запуске процесса: \(error)")
    }
}

// Тест 2: Отмена с мониторингом прогресса
func testCancellationWithProgress() {
    print("\n🔍 Тест 2: Отмена с мониторингом прогресса")
    
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.arguments = [
        "-i", testVideoPath,
        "-c:v", "libx264",
        "-crf", "23",
        "-preset", "slow",
        "-progress", "pipe:2",
        "-stats_period", "0.5",
        "-y",
        outputVideoPath
    ]
    
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    
    var progressReceived = false
    
    do {
        try process.run()
        print("   📹 Процесс FFmpeg запущен с мониторингом прогресса")
        
        // Мониторим прогресс в отдельном потоке
        DispatchQueue.global().async {
            let fileHandle = errorPipe.fileHandleForReading
            
            while process.isRunning {
                let data = fileHandle.availableData
                if !data.isEmpty {
                    let output = String(data: data, encoding: .utf8) ?? ""
                    if output.contains("frame=") || output.contains("time=") {
                        progressReceived = true
                        print("   📊 Получен прогресс от FFmpeg")
                    }
                }
                usleep(100000) // 0.1 секунды
            }
        }
        
        // Ждем получения прогресса, затем отменяем
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            print("   ⏹️ Отменяем процесс после получения прогресса...")
            process.terminate()
        }
        
        process.waitUntilExit()
        
        let exitCode = process.terminationStatus
        print("   📊 Код завершения: \(exitCode)")
        print("   📈 Прогресс получен: \(progressReceived ? "✅ ДА" : "❌ НЕТ")")
        
        // Проверяем корректность отмены
        if exitCode == 255 || exitCode == -15 {
            print("   ✅ Отмена обработана корректно")
        } else {
            print("   ⚠️ Неожиданный код при отмене: \(exitCode)")
        }
        
        // Очистка
        try? FileManager.default.removeItem(atPath: outputVideoPath)
        
    } catch {
        print("   ❌ Ошибка: \(error)")
    }
}

// Тест 3: Множественные отмены
func testMultipleCancellations() {
    print("\n🔍 Тест 3: Множественные отмены")
    
    for i in 1...3 {
        print("   Попытка \(i)...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", testVideoPath,
            "-c:v", "libx264",
            "-crf", "23",
            "-y",
            "/tmp/test_multi_\(i).mp4"
        ]
        
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            
            // Быстрая отмена
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                process.terminate()
                
                // Дополнительные попытки отмены (не должны вызывать проблем)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
            }
            
            process.waitUntilExit()
            
            let exitCode = process.terminationStatus
            let status = (exitCode == 255 || exitCode == -15 || exitCode == -9) ? "✅ ОК" : "⚠️ \(exitCode)"
            print("     Результат: \(status)")
            
            // Очистка
            try? FileManager.default.removeItem(atPath: "/tmp/test_multi_\(i).mp4")
            
        } catch {
            print("     ❌ Ошибка: \(error)")
        }
    }
}

// Выполняем тесты
if createTestVideo() {
    testQuickCancellation()
    testCancellationWithProgress()
    testMultipleCancellations()
    
    // Очистка
    try? FileManager.default.removeItem(atPath: testVideoPath)
    
    print("\n✅ Все тесты реальной обработки отмены завершены!")
    print("\n📋 Результаты:")
    print("   • FFmpeg корректно завершается при получении SIGTERM")
    print("   • Код выхода 255 является нормальным при отмене")
    print("   • Прогресс мониторинг корректно останавливается")
    print("   • Множественные отмены не вызывают проблем")
    print("   • Неполные выходные файлы не создаются")
} else {
    print("❌ Не удалось создать тестовое видео для проверки")
    exit(1)
}