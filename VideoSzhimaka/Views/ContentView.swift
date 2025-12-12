import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var settingsService: SettingsService

    var body: some View {
        MainView(settingsService: settingsService)
    }
}

struct MainView: View {
    @ObservedObject private var settingsService: SettingsService
    @StateObject private var viewModel: MainViewModel
    @AppStorage("appTheme") private var appTheme: String = "system" // "system", "light", "dark"
    
    init(settingsService: SettingsService) {
        self._settingsService = ObservedObject(initialValue: settingsService)
        self._viewModel = StateObject(wrappedValue: MainViewModel(settingsService: settingsService))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)
            
            FileListView(viewModel: viewModel)
            
            FooterView(viewModel: viewModel)
        }
        .frame(minWidth: 700, minHeight: 500)
        .contentBackground()
        .onDrop(of: [UTType.fileURL], isTargeted: .constant(false)) { providers in
            return viewModel.handleDrop(providers)
        }
        .errorAlert(error: $viewModel.currentError) {
            // Retry action for retryable errors
            if let error = viewModel.currentError, error.isRetryable {
                // Implementation depends on context - could retry last operation
            }
        }
        .alert("Ошибки при обработке", isPresented: $viewModel.showBatchErrorsAlert) {
            if viewModel.batchErrors.contains(where: { $0.isRetryable }) {
                Button("Повторить все") {
                    viewModel.retryAllFailedFiles()
                }
            }
            Button("OK") {
                viewModel.clearBatchErrors()
            }
        } message: {
            if viewModel.batchErrors.count == 1 {
                Text(viewModel.batchErrors.first?.localizedDescription ?? "")
            } else {
                Text("Обнаружено ошибок: \(viewModel.batchErrors.count). Проверьте логи для подробностей.")
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(settingsService: settingsService)
                .environmentObject(settingsService)
        }
        .sheet(isPresented: $viewModel.showLogs) {
            LogsView(loggingService: viewModel.loggingService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            viewModel.showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogs)) { _ in
            // Add small delay to allow settings to dismiss if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                viewModel.showLogs = true
            }
        }
        .preferredColorScheme(appTheme == "light" ? .light : (appTheme == "dark" ? .dark : nil))

    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: MainViewModel
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    // Theme logic
    private var currentThemeIcon: String {
        switch appTheme {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "gearshape.2.fill" // System/Auto icon
        }
    }
    
    private var currentThemeName: String {
        switch appTheme {
        case "light": return NSLocalizedString("Светлая", comment: "")
        case "dark": return NSLocalizedString("Темная", comment: "")
        default: return NSLocalizedString("Системная", comment: "")
        }
    }
    
    var body: some View {
        HStack {
            Text("Видео-Сжимака")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.showFilePicker()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Добавить файлы")
                
                // Theme menu (System -> Light -> Dark)
                Menu {
                    Button(action: { appTheme = "system" }) {
                        Label(NSLocalizedString("Системная", comment: ""), systemImage: "gearshape.2")
                    }
                    Button(action: { appTheme = "light" }) {
                        Label(NSLocalizedString("Светлая", comment: ""), systemImage: "sun.max")
                    }
                    Button(action: { appTheme = "dark" }) {
                        Label(NSLocalizedString("Темная", comment: ""), systemImage: "moon")
                    }
                } label: {
                    Image(systemName: currentThemeIcon)
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                .help("Тема: \(currentThemeName)")
                
                Button(action: {
                    viewModel.showSettings = true
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Настройки")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.adaptiveBackground)
    }
}

struct FileListView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Group {
            if viewModel.videoFiles.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.videoFiles) { file in
                            FileRowView(file: file, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Перетащите видеофайлы сюда")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("или нажмите кнопку \"Добавить файлы\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentBackground()
    }
}

struct FooterView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        HStack {
            // Statistics
            if !viewModel.videoFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Файлов: \(viewModel.videoFiles.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if viewModel.totalOriginalSize > 0 {
                        let sizeString = ByteCountFormatter.string(fromByteCount: viewModel.totalOriginalSize, countStyle: .file)
                        Text("Размер: \(sizeString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Показать логи") {
                    viewModel.showLogs = true
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Открыть окно логов")
                
                if viewModel.isProcessing {
                    Button("Отменить") {
                        viewModel.cancelAllProcessing()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Сжать всё") {
                        viewModel.compressAllFiles()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.videoFiles.isEmpty || viewModel.videoFiles.allSatisfy { $0.status.isFinished })
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.adaptiveBackground)
    }
}





#Preview {
    ContentView()
        .environmentObject(SettingsService())
}
