#!/usr/bin/env swift

import Foundation

// Простой тест для проверки логики определения увеличения размера файла

struct VideoFile {
    let originalSize: Int64
    var compressedSize: Int64?
    
    var isCompressedLarger: Bool {
        guard let compressedSize = compressedSize else { return false }
        return compressedSize > originalSize
    }
    
    var compressionRatio: Double? {
        guard let compressedSize = compressedSize, originalSize > 0 else { return nil }
        return (1.0 - Double(compressedSize) / Double(originalSize)) * 100.0
    }
}

// Тестовые случаи
print("🧪 Тестирование индикатора увеличения размера файла")
print(String(repeating: "=", count: 50))

// Случай 1: Файл уменьшился (обычное сжатие)
var file1 = VideoFile(originalSize: 100_000_000) // 100MB
file1.compressedSize = 50_000_000 // 50MB
print("Тест 1 - Обычное сжатие:")
print("  Оригинал: \(file1.originalSize) байт")
print("  Сжатый: \(file1.compressedSize!) байт")
print("  Стал больше: \(file1.isCompressedLarger)")
print("  Коэффициент сжатия: \(String(format: "%.1f", file1.compressionRatio!))%")
print()

// Случай 2: Файл увеличился
var file2 = VideoFile(originalSize: 50_000_000) // 50MB
file2.compressedSize = 75_000_000 // 75MB
print("Тест 2 - Файл увеличился:")
print("  Оригинал: \(file2.originalSize) байт")
print("  Сжатый: \(file2.compressedSize!) байт")
print("  Стал больше: \(file2.isCompressedLarger)")
print("  Коэффициент сжатия: \(String(format: "%.1f", abs(file2.compressionRatio!)))%")
print()

// Случай 3: Файл остался того же размера
var file3 = VideoFile(originalSize: 100_000_000) // 100MB
file3.compressedSize = 100_000_000 // 100MB
print("Тест 3 - Размер не изменился:")
print("  Оригинал: \(file3.originalSize) байт")
print("  Сжатый: \(file3.compressedSize!) байт")
print("  Стал больше: \(file3.isCompressedLarger)")
print("  Коэффициент сжатия: \(String(format: "%.1f", file3.compressionRatio!))%")
print()

// Случай 4: Файл еще не сжат
let file4 = VideoFile(originalSize: 100_000_000) // 100MB
print("Тест 4 - Файл не сжат:")
print("  Оригинал: \(file4.originalSize) байт")
print("  Сжатый: не определен")
print("  Стал больше: \(file4.isCompressedLarger)")
print("  Коэффициент сжатия: \(file4.compressionRatio?.description ?? "не определен")")
print()

print("✅ Все тесты завершены!")