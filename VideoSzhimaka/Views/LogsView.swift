import SwiftUI
import UniformTypeIdentifiers

struct LogsView: View {
    @ObservedObject var loggingService: LoggingService
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var showingExportSheet = false
    @State private var exportedLogs = ""
    @Environment(\.dismiss) private var dismiss
    
    private var filteredLogs: [LogEntry] {
        var logs = loggingService.filteredLogs(by: selectedLevel)
        
        if !searchText.isEmpty {
            logs = logs.filter { entry in
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return logs.reversed() // Показываем новые логи сверху
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Панель инструментов
            HStack {
                // Фильтр по уровню
                Picker("Уровень", selection: $selectedLevel) {
                    Text("Все уровни").tag(LogLevel?.none)
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
                    TextField("Поиск в логах...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .frame(width: 200)
                
                Spacer()
                
                // Кнопки действий
                HStack {
                    Button("Экспорт") {
                        exportedLogs = loggingService.exportLogs()
                        showingExportSheet = true
                    }
                    .disabled(loggingService.logs.isEmpty)
                    
                    Button("Очистить") {
                        loggingService.clearLogs()
                    }
                    .disabled(loggingService.logs.isEmpty)
                    
                    // Кнопка закрытия
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .help("Закрыть окно логов")
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
                    Text(searchText.isEmpty ? "Логи отсутствуют" : "Логи не найдены")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Text("Попробуйте изменить поисковый запрос")
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
        .frame(minWidth: 800, minHeight: 500)
        .navigationTitle("Логи приложения")
        .sheet(isPresented: $showingExportSheet) {
            LogExportView(logs: exportedLogs)
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
                Text("Экспорт логов")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Закрыть") {
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
                Button("Копировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                }
                
                Button("Сохранить в файл") {
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

#Preview {
    let loggingService = LoggingService()
    loggingService.info("Тестовое информационное сообщение", category: "Test")
    loggingService.warning("Тестовое предупреждение", category: "Test")
    loggingService.error("Тестовая ошибка", category: "Test")
    
    return LogsView(loggingService: loggingService)
}