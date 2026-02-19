import SwiftUI

struct FileRowView: View {
    let file: VideoFile
    @ObservedObject var viewModel: MainViewModel
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator and file icon
            HStack(spacing: 12) {
                statusIndicator
                
                VStack(alignment: .leading, spacing: 4) {
                    // File name and basic info
                    HStack(spacing: 8) {
                        Image(systemName: videoIcon)
                            .foregroundColor(iconColor)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .help(file.name)
                            
                            fileInfoRow
                        }
                    }
                    
                    // Progress and status information
                    statusContent
                }
            }
            
            Spacer()
            
            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(statusDescription)")
        .contextMenu {
            contextMenuContent
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Status Indicator
    
    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .shadow(color: statusColor.opacity(0.5), radius: file.status == .compressing ? 2 : 0)
            .help(statusDescription)
            .accessibilityLabel(statusDescription)
    }
    
    // MARK: - File Information Row
    
    @ViewBuilder
    private var fileInfoRow: some View {
        HStack(spacing: 12) {
            // Duration
            Label(file.formattedDuration, systemImage: "clock")
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
            
            // Original size
            Label(file.formattedOriginalSize, systemImage: "doc")
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
            
            // Compressed size and ratio (if available)
            if file.compressedSize != nil {
                let compressionColor = file.isCompressedLarger ? Color.red : Color(NSColor.successColor)
                let compressionIcon = file.isCompressedLarger ? "arrow.up.circle" : "arrow.down.circle"
                
                Label(file.formattedCompressedSize, systemImage: compressionIcon)
                    .font(.caption)
                    .foregroundColor(compressionColor)
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                
                if let ratio = file.compressionRatio {
                    let ratioText = file.isCompressedLarger ? 
                        "(+\(String(format: "%.1f", abs(ratio)))%)" : 
                        "(-\(String(format: "%.1f", ratio))%)"
                    
                    Text(ratioText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(compressionColor)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(compressionColor.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
    }
    
    // MARK: - Status Content
    
    @ViewBuilder
    private var statusContent: some View {
        switch file.status {
        case .compressing:
            compressionProgress
        case .failed(let error):
            errorDisplay(error)
        case .completed:
            completionDisplay
        case .pending:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var compressionProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(NSLocalizedString("Сжимается...", comment: ""))
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(file.compressionProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
            
            ProgressView(value: file.compressionProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(height: 6)
                .cornerRadius(3)
        }
    }
    
    @ViewBuilder
    private func errorDisplay(_ error: VideoCompressionError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(NSColor.errorColor))
                    .font(.caption)
                
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(Color(NSColor.errorColor))
                    .lineLimit(2)
                    .help(error.localizedDescription)
            }
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(suggestion)
            }
        }
    }
    
    @ViewBuilder
    private var completionDisplay: some View {
        let isLarger = file.isCompressedLarger
        let displayColor = isLarger ? Color.red : Color(NSColor.successColor)
        let iconName = isLarger ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let message = isLarger ? NSLocalizedString("Файл стал больше!", comment: "") : NSLocalizedString("Сжатие завершено", comment: "")
        
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(displayColor)
                .font(.caption)
            
            Text(message)
                .font(.caption)
                .foregroundColor(displayColor)
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Primary action button
            primaryActionButton
            
            // Secondary action buttons
            Button(action: {
                viewModel.openFileInFinder(withId: file.id)
            }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(NSLocalizedString("Открыть в Finder", comment: ""))
            .help(NSLocalizedString("Открыть в Finder", comment: ""))
            
            Button(action: {
                viewModel.removeFile(withId: file.id)
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(Color(NSColor.errorColor))
            .disabled(viewModel.currentlyProcessingFileId == file.id)
            .accessibilityLabel(NSLocalizedString("Удалить из списка", comment: ""))
            .help(deleteHelpText)
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        switch file.status {
        case .pending:
            Button(NSLocalizedString("Сжать", comment: "")) {
                viewModel.compressFile(withId: file.id)
            }
            .disabled(viewModel.isProcessing)
        case .failed(let error):
            if error.isRetryable {
                Button(NSLocalizedString("Повторить", comment: "")) {
                    viewModel.retryCompression(forFileId: file.id)
                }
            }
        case .compressing:
            Button(NSLocalizedString("Отменить", comment: "")) {
                viewModel.cancelAllProcessing()
            }
        case .completed:
            EmptyView()
        }
        
        Button(NSLocalizedString("Открыть в Finder", comment: "")) {
            viewModel.openFileInFinder(withId: file.id)
        }
        
        Button(NSLocalizedString("Удалить из списка", comment: "")) {
            viewModel.removeFile(withId: file.id)
        }
        .disabled(viewModel.currentlyProcessingFileId == file.id)
    }
    
    @ViewBuilder
    private var primaryActionButton: some View {
        switch file.status {
        case .pending:
            Button(NSLocalizedString("Сжать", comment: "")) {
                viewModel.compressFile(withId: file.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isProcessing)
            .help(compressHelpText)
            
        case .failed(let error):
            if error.isRetryable {
                Button(NSLocalizedString("Повторить", comment: "")) {
                    viewModel.retryCompression(forFileId: file.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(NSColor.warningColor))
            } else {
                Button(NSLocalizedString("Удалить", comment: "")) {
                    viewModel.removeFile(withId: file.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(Color(NSColor.errorColor))
            }
            
        case .compressing:
            Button(NSLocalizedString("Отменить", comment: "")) {
                viewModel.cancelAllProcessing()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(Color(NSColor.errorColor))
            
        case .completed:
            EmptyView()
        }
    }
    
    // MARK: - Visual Properties
    
    private var videoIcon: String {
        switch file.status {
        case .completed:
            return file.isCompressedLarger ? "video.badge.exclamationmark" : "video.badge.checkmark"
        case .failed:
            return "video.badge.exclamationmark"
        case .compressing:
            return "video.badge.ellipsis"
        case .pending:
            return "video"
        }
    }
    
    private var iconColor: Color {
        switch file.status {
        case .completed:
            // Красная иконка если файл стал больше после сжатия
            return file.isCompressedLarger ? Color.red : Color(NSColor.successColor)
        case .failed:
            return Color(NSColor.errorColor)
        case .compressing:
            return .blue
        case .pending:
            return .blue
        }
    }
    
    private var statusColor: Color {
        switch file.status {
        case .pending:
            return .gray
        case .compressing:
            return .blue
        case .completed:
            // Красный индикатор если файл стал больше после сжатия
            return file.isCompressedLarger ? Color.red : Color(NSColor.successColor)
        case .failed:
            return Color(NSColor.errorColor)
        }
    }

    private var statusDescription: String {
        switch file.status {
        case .pending:
            return NSLocalizedString("Ожидает", comment: "")
        case .compressing:
            return NSLocalizedString("Сжимается", comment: "")
        case .completed:
            return file.isCompressedLarger
                ? NSLocalizedString("Сжатие завершено (файл стал больше)", comment: "")
                : NSLocalizedString("Сжатие завершено", comment: "")
        case .failed:
            return NSLocalizedString("Ошибка при сжатии", comment: "")
        }
    }
    
    @ViewBuilder
    private var statusBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(borderColor, lineWidth: borderWidth)
            .animation(.easeInOut(duration: 0.3), value: file.status)
    }
    
    private var borderColor: Color {
        switch file.status {
        case .compressing:
            return .blue
        case .failed:
            return Color(NSColor.errorColor).opacity(0.5)
        case .completed:
            // Красная рамка если файл стал больше после сжатия
            return file.isCompressedLarger ? Color.red.opacity(0.6) : Color(NSColor.successColor).opacity(0.3)
        case .pending:
            return Color.adaptiveBorder.opacity(0.3)
        }
    }
    
    private var borderWidth: CGFloat {
        switch file.status {
        case .compressing:
            return 2.0
        case .failed:
            return 1.0
        case .completed:
            // Более толстая красная рамка если файл стал больше
            return file.isCompressedLarger ? 2.0 : 1.0
        case .pending:
            return 0.5
        }
    }

    private var deleteHelpText: String {
        if viewModel.currentlyProcessingFileId == file.id {
            return NSLocalizedString("Нельзя удалить файл во время сжатия", comment: "")
        }
        return NSLocalizedString("Удалить из списка", comment: "")
    }

    private var compressHelpText: String {
        if viewModel.isProcessing {
            return NSLocalizedString("Дождитесь завершения текущего сжатия", comment: "")
        }
        return NSLocalizedString("Сжать файл", comment: "")
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        // Pending file
        FileRowView(
            file: VideoFile(
                url: URL(fileURLWithPath: "/path/to/sample_video.mp4"),
                name: "sample_video.mp4",
                duration: 125.5,
                originalSize: 52428800
            ),
            viewModel: MainViewModel()
        )
        
        // Compressing file
        FileRowView(
            file: {
                var file = VideoFile(
                    url: URL(fileURLWithPath: "/path/to/compressing_video.mp4"),
                    name: "compressing_video.mp4",
                    duration: 67.2,
                    originalSize: 31457280
                )
                file.status = .compressing
                file.compressionProgress = 0.65
                return file
            }(),
            viewModel: MainViewModel()
        )
        
        // Completed file
        FileRowView(
            file: {
                var file = VideoFile(
                    url: URL(fileURLWithPath: "/path/to/completed_video.mp4"),
                    name: "completed_video.mp4",
                    duration: 89.1,
                    originalSize: 41943040
                )
                file.status = .completed
                file.compressedSize = 20971520
                return file
            }(),
            viewModel: MainViewModel()
        )
        
        // Failed file
        FileRowView(
            file: {
                var file = VideoFile(
                    url: URL(fileURLWithPath: "/path/to/failed_video.mp4"),
                    name: "failed_video_with_very_long_name_that_should_be_truncated.mp4",
                    duration: 156.8,
                    originalSize: 67108864
                )
                file.status = .failed(.unsupportedFormat("MP4"))
                return file
            }(),
            viewModel: MainViewModel()
        )
    }
    .padding()
    .frame(width: 700)
    .background(Color.adaptiveSecondaryBackground)
}
#endif
