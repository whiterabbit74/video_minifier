import Foundation

/// Protocol defining the interface for file management operations
protocol FileManagerServiceProtocol {
    /// Generate a unique output URL for a compressed video file
    /// - Parameter inputURL: The original video file URL
    /// - Returns: A unique URL for the compressed output file
    func generateOutputURL(for inputURL: URL, behavior: OutputBehavior) -> URL
    
    /// Delete a file at the specified URL
    /// - Parameter url: The URL of the file to delete
    /// - Throws: FileManagerError if deletion fails
    func deleteFile(at url: URL) throws

    /// Move or replace a file at destination
    /// - Parameters:
    ///   - sourceURL: The file to move
    ///   - destinationURL: The destination URL
    func moveFile(from sourceURL: URL, to destinationURL: URL) throws
    
    /// Open a file or folder in Finder
    /// - Parameter url: The URL to open in Finder
    func openInFinder(url: URL)
    
    /// Get the size of a file in bytes
    /// - Parameter url: The URL of the file
    /// - Returns: The file size in bytes
    /// - Throws: FileManagerError if unable to get file size
    func getFileSize(url: URL) throws -> Int64
    
    /// Check if a file exists at the specified URL
    /// - Parameter url: The URL to check
    /// - Returns: True if file exists, false otherwise
    func fileExists(at url: URL) -> Bool
}

/// Errors that can occur during file management operations
enum FileManagerError: LocalizedError {
    case fileNotFound(URL)
    case deletionFailed(URL, Error)
    case sizeCalculationFailed(URL, Error)
    case invalidURL(URL)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return String(format: NSLocalizedString("Файл не найден: %@", comment: ""), url.lastPathComponent)
        case .deletionFailed(let url, let error):
            return String(format: NSLocalizedString("Не удалось удалить файл %@: %@", comment: ""), url.lastPathComponent, error.localizedDescription)
        case .sizeCalculationFailed(let url, let error):
            return String(format: NSLocalizedString("Не удалось получить размер файла %@: %@", comment: ""), url.lastPathComponent, error.localizedDescription)
        case .invalidURL(let url):
            return String(format: NSLocalizedString("Некорректный URL: %@", comment: ""), url.absoluteString)
        }
    }
}
