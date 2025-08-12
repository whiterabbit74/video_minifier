import SwiftUI

/// A view modifier that displays error alerts with retry functionality
struct ErrorAlertModifier: ViewModifier {
    @Binding var error: VideoCompressionError?
    let onRetry: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .alert("Ошибка", isPresented: .constant(error != nil)) {
                if let error = error {
                    if error.isRetryable && onRetry != nil {
                        Button("Повторить") {
                            onRetry?()
                            self.error = nil
                        }
                    }
                    
                    Button("OK") {
                        self.error = nil
                    }
                }
            } message: {
                if let error = error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                        
                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
    }
}

/// Extension to make error alerts easier to use
extension View {
    /// Shows an error alert with optional retry functionality
    /// - Parameters:
    ///   - error: Binding to the error to display
    ///   - onRetry: Optional closure to call when user taps retry
    func errorAlert(error: Binding<VideoCompressionError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorAlertModifier(error: error, onRetry: onRetry))
    }
}

/// A dedicated view for displaying error information
struct ErrorView: View {
    let error: VideoCompressionError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Произошла ошибка")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            HStack(spacing: 12) {
                if error.isRetryable && onRetry != nil {
                    Button("Повторить") {
                        onRetry?()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Закрыть") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

/// A view that displays multiple errors in a list format
struct ErrorListView: View {
    let errors: [VideoCompressionError]
    let onRetryAll: (() -> Void)?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text("Обнаружены ошибки (\(errors.count))")
                    .font(.headline)
                
                Spacer()
                
                Button("Закрыть") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(errors.enumerated()), id: \.offset) { index, error in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(error.localizedDescription)")
                                .font(.body)
                            
                            if let suggestion = error.recoverySuggestion {
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        if index < errors.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            
            if errors.contains(where: { $0.isRetryable }) && onRetryAll != nil {
                HStack {
                    Spacer()
                    Button("Повторить все") {
                        onRetryAll?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

#if DEBUG
struct ErrorAlertView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Single error preview
            ErrorView(
                error: .compressionFailed("Недостаточно памяти"),
                onRetry: {},
                onDismiss: {}
            )
            .previewDisplayName("Single Error")
            
            // Multiple errors preview
            ErrorListView(
                errors: [
                    .fileNotFound("video1.mp4"),
                    .insufficientSpace,
                    .compressionFailed("Неподдерживаемый кодек")
                ],
                onRetryAll: {},
                onDismiss: {}
            )
            .previewDisplayName("Multiple Errors")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
#endif