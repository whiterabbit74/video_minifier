#!/usr/bin/env swift

import Foundation

// Простой тест для проверки извлечения метаданных
func testMetadataExtraction() {
    print("Тестирование извлечения метаданных...")
    
    // Создаем простое тестовое видео с помощью ffmpeg
    let testVideoPath = "/tmp/test_video.mp4"
    
    // Проверяем, есть ли ffmpeg в системе
    let ffmpegPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    
    var ffmpegPath: String?
    for path in ffmpegPaths {
        if FileManager.default.fileExists(atPath: path) {
            ffmpegPath = path
            break
        }
    }
    
    guard let validFFmpegPath = ffmpegPath else {
        print("❌ FFmpeg не найден в системе")
        return
    }
    
    print("✅ Найден FFmpeg: \(validFFmpegPath)")
    
    // Создаем тестовое видео
    let createProcess = Process()
    createProcess.executableURL = URL(fileURLWithPath: validFFmpegPath)
    createProcess.arguments = [
        "-f", "lavfi",
        "-i", "testsrc=duration=2:size=320x240:rate=30",
        "-f", "lavfi", 
        "-i", "sine=frequency=1000:duration=2",
        "-c:v", "libx264",
        "-c:a", "aac",
        "-shortest",
        "-y",
        testVideoPath
    ]
    
    do {
        try createProcess.run()
        createProcess.waitUntilExit()
        
        if createProcess.terminationStatus == 0 {
            print("✅ Тестовое видео создано: \(testVideoPath)")
        } else {
            print("❌ Не удалось создать тестовое видео")
            return
        }
    } catch {
        print("❌ Ошибка при создании тестового видео: \(error)")
        return
    }
    
    // Теперь тестируем извлечение метаданных
    testMetadataExtractionWithFFprobe(videoPath: testVideoPath, ffmpegPath: validFFmpegPath)
    
    // Удаляем тестовый файл
    try? FileManager.default.removeItem(atPath: testVideoPath)
}

func testMetadataExtractionWithFFprobe(videoPath: String, ffmpegPath: String) {
    print("\nТестирование извлечения метаданных с ffprobe...")
    
    // Пробуем найти ffprobe
    let ffprobePath = ffmpegPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
    
    let process = Process()
    if FileManager.default.fileExists(atPath: ffprobePath) {
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        print("✅ Используем ffprobe: \(ffprobePath)")
    } else {
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        print("⚠️ ffprobe не найден, используем ffmpeg: \(ffmpegPath)")
    }
    
    process.arguments = [
        "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        videoPath
    ]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    do {
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            if let jsonString = String(data: data, encoding: .utf8) {
                print("✅ Метаданные успешно извлечены")
                print("📊 Размер JSON: \(data.count) байт")
                
                // Пробуем парсить JSON
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let format = json["format"] as? [String: Any],
                           let duration = format["duration"] as? String {
                            print("⏱️ Длительность: \(duration) секунд")
                        }
                        
                        if let streams = json["streams"] as? [[String: Any]] {
                            print("🎬 Найдено потоков: \(streams.count)")
                            
                            for (index, stream) in streams.enumerated() {
                                if let codecType = stream["codec_type"] as? String {
                                    print("   Поток \(index): \(codecType)")
                                    
                                    if codecType == "video" {
                                        let width = stream["width"] as? Int ?? 0
                                        let height = stream["height"] as? Int ?? 0
                                        print("     Разрешение: \(width)x\(height)")
                                    }
                                }
                            }
                        }
                        
                        print("✅ JSON успешно распарсен")
                    } else {
                        print("❌ Не удалось распарсить JSON как словарь")
                    }
                } catch {
                    print("❌ Ошибка парсинга JSON: \(error)")
                    print("📄 Первые 200 символов JSON:")
                    print(String(jsonString.prefix(200)))
                }
            } else {
                print("❌ Не удалось преобразовать данные в строку")
            }
        } else {
            print("❌ Процесс завершился с кодом: \(process.terminationStatus)")
            
            if let errorPipe = process.standardError as? Pipe {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("Ошибка: \(errorString)")
                }
            }
        }
    } catch {
        print("❌ Ошибка запуска процесса: \(error)")
    }
}

// Запускаем тест
testMetadataExtraction()