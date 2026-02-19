import Foundation

/// Represents the current status of video compression
enum CompressionStatus: Codable, Equatable {
    /// File is waiting to be processed
    case pending
    
    /// File is currently being compressed
    case compressing
    
    /// File has been successfully compressed
    case completed
    
    /// Compression failed with an error
    case failed(VideoCompressionError)
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type, error, errorMessage
    }
    
    private enum StatusType: String, Codable {
        case pending, compressing, completed, failed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StatusType.self, forKey: .type)
        
        switch type {
        case .pending:
            self = .pending
        case .compressing:
            self = .compressing
        case .completed:
            self = .completed
        case .failed:
            if let decodedError = try container.decodeIfPresent(VideoCompressionError.self, forKey: .error) {
                self = .failed(decodedError)
            } else {
                // Backward compatibility for older payloads.
                let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "Unknown error"
                self = .failed(.unknownError(errorMessage))
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .pending:
            try container.encode(StatusType.pending, forKey: .type)
        case .compressing:
            try container.encode(StatusType.compressing, forKey: .type)
        case .completed:
            try container.encode(StatusType.completed, forKey: .type)
        case .failed(let error):
            try container.encode(StatusType.failed, forKey: .type)
            try container.encode(error, forKey: .error)
            // Keep the legacy field for compatibility with older app versions.
            try container.encode(error.localizedDescription, forKey: .errorMessage)
        }
    }
    
    // MARK: - Equatable Implementation
    
    static func == (lhs: CompressionStatus, rhs: CompressionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.compressing, .compressing),
             (.completed, .completed):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - CompressionStatus Extensions

extension CompressionStatus {
    /// Human-readable description of the status
    var displayText: String {
        switch self {
        case .pending:
            return NSLocalizedString("Ожидает", comment: "")
        case .compressing:
            return NSLocalizedString("Сжимается", comment: "")
        case .completed:
            return NSLocalizedString("Завершено", comment: "")
        case .failed(let error):
            return String(format: NSLocalizedString("Ошибка: %@", comment: ""), error.localizedDescription)
        }
    }
    
    /// Whether the status indicates an active operation
    var isActive: Bool {
        switch self {
        case .compressing:
            return true
        default:
            return false
        }
    }
    
    /// Whether the status indicates completion (success or failure)
    var isFinished: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
    
    /// Whether the status indicates success
    var isSuccessful: Bool {
        switch self {
        case .completed:
            return true
        default:
            return false
        }
    }
    
    /// Whether the status indicates failure
    var isFailure: Bool {
        switch self {
        case .failed:
            return true
        default:
            return false
        }
    }
}
