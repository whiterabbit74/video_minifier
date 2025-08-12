#!/usr/bin/env swift

import Foundation

// Тестовые JSON данные, которые должен возвращать ffprobe
let testJSON = """
{
  "streams": [
    {
      "index": 0,
      "codec_name": "h264",
      "codec_type": "video",
      "width": 320,
      "height": 240,
      "r_frame_rate": "30/1",
      "avg_frame_rate": "30/1"
    },
    {
      "index": 1,
      "codec_name": "aac",
      "codec_type": "audio"
    }
  ],
  "format": {
    "duration": "2.000000",
    "bit_rate": "128000"
  }
}
"""

func testJSONParsing() {
    print("Тестирование парсинга JSON метаданных...")
    
    guard let data = testJSON.data(using: .utf8) else {
        print("❌ Не удалось создать данные из JSON строки")
        return
    }
    
    do {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Не удалось распарсить JSON как словарь")
            return
        }
        
        guard let format = json["format"] as? [String: Any] else {
            print("❌ Не найден раздел format")
            return
        }
        
        guard let streams = json["streams"] as? [[String: Any]] else {
            print("❌ Не найден раздел streams")
            return
        }
        
        if streams.isEmpty {
            print("❌ Нет потоков в видеофайле")
            return
        }
        
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
            print("❌ Не найден видео поток")
            return
        }
        
        // Извлекаем параметры видео
        let width = video["width"] as? Int ?? 0
        let height = video["height"] as? Int ?? 0
        let videoCodec = video["codec_name"] as? String
        
        // Проверяем, что видео имеет валидные размеры
        if width <= 0 || height <= 0 {
            print("⚠️ Видео имеет невалидные размеры: \(width)x\(height)")
        }
        
        // Вычисляем FPS
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
        
        print("✅ Парсинг метаданных успешен!")
        print("📊 Результаты:")
        print("   Длительность: \(duration) секунд")
        print("   Разрешение: \(width)x\(height)")
        print("   FPS: \(frameRate)")
        print("   Битрейт: \(bitrate)")
        print("   Видео кодек: \(videoCodec ?? "неизвестно")")
        print("   Есть аудио: \(hasAudio)")
        print("   Аудио кодек: \(audioCodec ?? "нет")")
        
        // Создаем структуру VideoInfo (имитируем)
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
        
        let videoInfo = VideoInfo(
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            bitrate: bitrate,
            hasAudio: hasAudio,
            audioCodec: audioCodec,
            videoCodec: videoCodec
        )
        
        print("✅ VideoInfo структура создана успешно")
        
    } catch {
        print("❌ Ошибка парсинга JSON: \(error)")
    }
}

// Запускаем тест
testJSONParsing()