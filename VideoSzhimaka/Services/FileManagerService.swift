import Foundation
import AppKit

/// Service for managing file system operations
final class FileManagerService: FileManagerServiceProtocol {
    
    // MARK: - Private Properties
    
    private let fileManager: FileManager
    private let workspace: NSWorkspace
    
    // MARK: - Initialization
    
    /// Initialize with custom FileManager and NSWorkspace (useful for testing)
    /// - Parameters:
    ///   - fileManager: FileManager instance to use
    ///   - workspace: NSWorkspace instance to use
    init(fileManager: FileManager = .default, workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
    }
    
    // MARK: - FileManagerServiceProtocol Implementation
    
    func generateOutputURL(for inputURL: URL) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let baseOutputURL = directory.appendingPathComponent("\(filename)_compressed.mp4")
        
        // If the file doesn't exist, return the base URL
        if !fileExists(at: baseOutputURL) {
            return baseOutputURL
        }
        
        // Generate unique filename with suffix
        return generateUniqueURL(baseURL: baseOutputURL)
    }
    
    func deleteFile(at url: URL) throws {
        guard fileExists(at: url) else {
            throw FileManagerError.fileNotFound(url)
        }
        
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw FileManagerError.deletionFailed(url, error)
        }
    }
    
    func openInFinder(url: URL) {
        if fileExists(at: url) {
            // If it's a file, select it in Finder
            workspace.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } else {
            // If file doesn't exist, try to open the parent directory
            let parentDirectory = url.deletingLastPathComponent()
            if fileExists(at: parentDirectory) {
                workspace.open(parentDirectory)
            }
        }
    }
    
    func getFileSize(url: URL) throws -> Int64 {
        guard fileExists(at: url) else {
            throw FileManagerError.fileNotFound(url)
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? Int64 else {
                throw FileManagerError.sizeCalculationFailed(url, NSError(domain: "FileManagerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to extract file size from attributes"]))
            }
            return fileSize
        } catch {
            throw FileManagerError.sizeCalculationFailed(url, error)
        }
    }
    
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    // MARK: - Private Methods
    
    /// Generate a unique URL by adding numeric suffixes
    /// - Parameter baseURL: The base URL to make unique
    /// - Returns: A unique URL with numeric suffix if needed
    private func generateUniqueURL(baseURL: URL) -> URL {
        let directory = baseURL.deletingLastPathComponent()
        let filename = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension
        
        var counter = 1
        var candidateURL: URL
        
        repeat {
            let uniqueFilename = "\(filename) (\(counter)).\(fileExtension)"
            candidateURL = directory.appendingPathComponent(uniqueFilename)
            counter += 1
        } while fileExists(at: candidateURL)
        
        return candidateURL
    }
}

// MARK: - FileManagerService Extensions

extension FileManagerService {
    
    /// Get formatted file size string
    /// - Parameter url: The file URL
    /// - Returns: Formatted file size string (e.g., "1.5 MB")
    func getFormattedFileSize(url: URL) -> String {
        do {
            let sizeInBytes = try getFileSize(url: url)
            return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
        } catch {
            return "—"
        }
    }
    
    /// Check if URL points to a video file based on extension
    /// - Parameter url: The URL to check
    /// - Returns: True if the file appears to be a video file
    func isVideoFile(url: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp"]
        let fileExtension = url.pathExtension.lowercased()
        return videoExtensions.contains(fileExtension)
    }
    
    /// Get the Downloads directory URL
    /// - Returns: URL to the user's Downloads directory
    func getDownloadsDirectory() -> URL {
        let urls = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)
        return urls.first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}