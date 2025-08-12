import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        MainView()
    }
}

struct MainView: View {
    @EnvironmentObject private var settingsService: SettingsService
    @StateObject private var viewModel: MainViewModel
    @AppStorage("appTheme") private var appTheme: String = "dark" // "light" or "dark"
    
    init() {
        // Create viewModel with default services - will be updated in onAppear
        self._viewModel = StateObject(wrappedValue: MainViewModel())
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
            SettingsView()
                .environmentObject(settingsService)
        }
        .sheet(isPresented: $viewModel.showLogs) {
            LogsView(loggingService: viewModel.loggingService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            viewModel.showSettings = true
        }
        .preferredColorScheme(appTheme == "light" ? .light : .dark)

    }
}

struct HeaderView: View {
    @ObservedObject var viewModel: MainViewModel
    @AppStorage("appTheme") private var appTheme: String = "dark"
    
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
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Добавить файлы")
                    }
                }
                .buttonStyle(.bordered)
                
                // Theme toggle button (left of settings)
                Button(action: {
                    appTheme = (appTheme == "light") ? "dark" : "light"
                }) {
                    Image(systemName: appTheme == "light" ? "sun.max.fill" : "moon.fill")
                }
                .buttonStyle(.bordered)
                .help("Переключить тему")
                
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
                        Text("Размер: \(ByteCountFormatter.string(fromByteCount: viewModel.totalOriginalSize, countStyle: .file))")
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
}