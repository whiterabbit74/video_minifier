import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @ObservedObject var loggingService: LoggingService
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var exportedLogs = ""
    @State private var filteredLogs: [LogEntry] = []
    @Environment(\.dismiss) private var dismiss
    private let filterQueue = DispatchQueue(label: "logs.filter.queue", qos: .userInitiated)
    
    var body: some View {
        VStack(spacing: 0) {
            // Панель инструментов
            HStack {
                // Фильтр по уровню
                Picker(NSLocalizedString("Уровень", comment: ""), selection: $selectedLevel) {
                    Text(NSLocalizedString("Все уровни", comment: "")).tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
                
                Spacer()
                
                // Поиск
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(NSLocalizedString("Поиск в логах...", comment: ""), text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .accessibilityLabel(NSLocalizedString("Поиск в логах", comment: ""))
                }
                .frame(width: 200)
                
                Spacer()
                
                // Кнопки действий
                HStack {
                    Button(NSLocalizedString("Экспорт", comment: "")) {
                        exportedLogs = loggingService.exportLogs()
                        showingExportSheet = true
                    }
                    .disabled(loggingService.logs.isEmpty)
                    
                    Button(NSLocalizedString("Очистить", comment: "")) {
                        loggingService.clearLogs()
                    }
                    .disabled(loggingService.logs.isEmpty)
                    
                    // Кнопка закрытия
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .accessibilityLabel(NSLocalizedString("Закрыть окно логов", comment: ""))
                    .help(NSLocalizedString("Закрыть окно логов", comment: ""))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Список логов
            if filteredLogs.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? NSLocalizedString("Логи отсутствуют", comment: "") : NSLocalizedString("Логи не найдены", comment: ""))
                        .font(.title2)
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Text(NSLocalizedString("Попробуйте изменить поисковый запрос", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                List(filteredLogs) { entry in
                    LogEntryRow(entry: entry)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(PlainListStyle())
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingExportSheet) {
            LogExportView(logs: exportedLogs)
        }
        .onAppear(perform: refreshFilteredLogs)
        .onReceive(loggingService.$logs) { _ in
            refreshFilteredLogs()
        }
        .onChange(of: selectedLevel) { _ in
            refreshFilteredLogs()
        }
        .onChange(of: searchText) { _ in
            refreshFilteredLogs()
        }
    }
    
    private func refreshFilteredLogs() {
        let level = selectedLevel
        let query = searchText
        let logsSnapshot = loggingService.logs
        let queryLowercased = query.lowercased()
        
        filterQueue.async {
            var logs = level == nil ? logsSnapshot : logsSnapshot.filter { $0.level == level }
            
            if !queryLowercased.isEmpty {
                logs = logs.filter { entry in
                    entry.message.lowercased().contains(queryLowercased) ||
                    entry.category.lowercased().contains(queryLowercased)
                }
            }
            
            let result = Array(logs.reversed())
            DispatchQueue.main.async {
                self.filteredLogs = result
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    
    private var levelColor: Color {
        switch entry.level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
    
    private var levelIcon: String {
        switch entry.level {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Иконка уровня
            Image(systemName: levelIcon)
                .foregroundColor(levelColor)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                // Время и категория
                HStack {
                    Text(entry.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(entry.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(entry.level.displayName)
                        .font(.caption)
                        .foregroundColor(levelColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(levelColor.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // Сообщение
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct LogExportView: View {
    let logs: String
    @Environment(\.presentationMode) var presentationMode
    @State private var showingSavePanel = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("Экспорт логов", comment: ""))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(NSLocalizedString("Закрыть", comment: "")) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()
            
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            HStack {
                Button(NSLocalizedString("Копировать", comment: "")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                }
                
                Button(NSLocalizedString("Сохранить в файл", comment: "")) {
                    showingSavePanel = true
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .fileExporter(
            isPresented: $showingSavePanel,
            document: LogDocument(content: logs),
            contentType: .plainText,
            defaultFilename: "VideoSzhimaka-logs-\(Date().timeIntervalSince1970).txt"
        ) { result in
            // Обработка результата сохранения
        }
    }
}

struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        content = ""
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

#if DEBUG
#Preview {
    let loggingService = LoggingService()
    loggingService.info(NSLocalizedString("Тестовое информационное сообщение", comment: ""), category: "Test")
    loggingService.warning(NSLocalizedString("Тестовое предупреждение", comment: ""), category: "Test")
    loggingService.error(NSLocalizedString("Тестовая ошибка", comment: ""), category: "Test")
    
    return LogsView(loggingService: loggingService)
}
#endif
