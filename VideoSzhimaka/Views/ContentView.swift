import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var settingsService: SettingsService

    var body: some View {
        MainView(settingsService: settingsService)
    }
}

enum AppTab {
    case optimizer
    case statistics
    case monitoring
    case settings
}

struct MainView: View {
    @ObservedObject private var settingsService: SettingsService
    @StateObject private var viewModel: MainViewModel
    @StateObject private var monitorViewModel = FolderMonitorViewModel()
    @AppStorage("appTheme") private var appTheme: String = "system"
    @State private var currentTab: AppTab = .optimizer

    init(settingsService: SettingsService) {
        self._settingsService = ObservedObject(initialValue: settingsService)
        self._viewModel = StateObject(wrappedValue: MainViewModel(settingsService: settingsService))
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(settingsService: settingsService)

            Divider()

            VStack(spacing: 0) {
                topBar

                Group {
                    switch currentTab {
                    case .optimizer:
                        VStack(spacing: 0) {
                            FileListView(viewModel: viewModel)
                            Divider()
                            FooterView(viewModel: viewModel)
                        }
                    case .statistics:
                        VStack(spacing: 0) {
                            StatisticsView(viewModel: viewModel)
                            Divider()
                            BottomStatusBar(text: NSLocalizedString("Статистика по текущей очереди обработки.", comment: ""))
                        }
                    case .monitoring:
                        VStack(spacing: 0) {
                            FolderMonitoringView(viewModel: monitorViewModel)
                            Divider()
                            BottomStatusBar(text: NSLocalizedString("Новые видео в выбранной папке автоматически добавляются в очередь и сжимаются.", comment: ""))
                        }
                    case .settings:
                        VStack(spacing: 0) {
                            SimpleSettingsView(settingsService: settingsService)
                            Divider()
                            BottomStatusBar(text: NSLocalizedString("Изменения настроек сохраняются автоматически.", comment: ""))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.videoMainBackground)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .onDrop(of: [UTType.fileURL], isTargeted: .constant(false)) { providers in
            viewModel.handleDrop(providers)
        }
        .errorAlert(error: $viewModel.currentError) {
            if let error = viewModel.currentError, error.isRetryable {
                _ = error
            }
        }
        .alert(NSLocalizedString("Ошибки при обработке", comment: ""), isPresented: $viewModel.showBatchErrorsAlert) {
            if viewModel.batchErrors.contains(where: { $0.isRetryable }) {
                Button(NSLocalizedString("Повторить все", comment: "")) {
                    viewModel.retryAllFailedFiles()
                }
            }
            Button(NSLocalizedString("OK", comment: "")) {
                viewModel.clearBatchErrors()
            }
        } message: {
            if viewModel.batchErrors.count == 1 {
                Text(viewModel.batchErrors.first?.localizedDescription ?? "")
            } else {
                Text(
                    String(
                        format: NSLocalizedString("Обнаружено ошибок: %d. Проверьте логи для подробностей.", comment: ""),
                        viewModel.batchErrors.count
                    )
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            currentTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogs)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AppDelegate.shared?.showLogsWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFiles)) { _ in
            let urls = AppDelegate.shared?.consumePendingOpenFiles() ?? []
            if !urls.isEmpty {
                DispatchQueue.main.async {
                    viewModel.addFiles(urls)
                }
            }
        }
        .onAppear {
            let urls = AppDelegate.shared?.consumePendingOpenFiles() ?? []
            if !urls.isEmpty {
                DispatchQueue.main.async {
                    viewModel.addFiles(urls)
                }
            }
            monitorViewModel.configure(settingsService: settingsService) { urls, presetSettings in
                viewModel.addAndCompressFiles(urls, settingsOverride: presetSettings)
            }
            AppDelegate.shared?.applyTheme(appTheme)
        }
        .onOpenURL { url in
            DispatchQueue.main.async {
                viewModel.addFiles([url])
            }
        }
        .onChange(of: appTheme) { _ in
            AppDelegate.shared?.applyTheme(appTheme)
        }
        .onChange(of: currentTab) { newTab in
            if newTab == .monitoring {
                monitorViewModel.refreshPresets()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                TabButton(title: NSLocalizedString("Оптимизация", comment: ""), icon: "bolt.fill", isSelected: currentTab == .optimizer) {
                    currentTab = .optimizer
                }
                TabButton(title: NSLocalizedString("Статистика", comment: ""), icon: "chart.bar.fill", isSelected: currentTab == .statistics) {
                    currentTab = .statistics
                }
                TabButton(title: NSLocalizedString("Мониторинг", comment: ""), icon: "eye.fill", isSelected: currentTab == .monitoring) {
                    currentTab = .monitoring
                }
                TabButton(title: NSLocalizedString("Настройки", comment: ""), icon: "gearshape.fill", isSelected: currentTab == .settings) {
                    currentTab = .settings
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if viewModel.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.85)
                }

                Button(action: { cycleTheme() }) {
                    Image(systemName: currentThemeIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(format: NSLocalizedString("Тема: %@", comment: ""), currentThemeName))

                if viewModel.isProcessing {
                    Button(NSLocalizedString("Отменить", comment: "")) {
                        viewModel.cancelAllProcessing()
                    }
                    .buttonStyle(.bordered)
                } else if viewModel.fileCount(withStatus: .pending) > 0 {
                    Button(NSLocalizedString("Старт", comment: "")) {
                        viewModel.compressAllFiles()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color.videoToolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.adaptiveBorder.opacity(0.7))
                .frame(height: 1)
        }
    }

    private var currentThemeIcon: String {
        switch appTheme {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var currentThemeName: String {
        switch appTheme {
        case "light": return NSLocalizedString("Светлая", comment: "")
        case "dark": return NSLocalizedString("Темная", comment: "")
        default: return NSLocalizedString("Системная", comment: "")
        }
    }

    private func cycleTheme() {
        switch appTheme {
        case "system":
            appTheme = "dark"
        case "dark":
            appTheme = "light"
        default:
            appTheme = "system"
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .imageScale(.medium)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.videoTabSelectedBackground : Color.clear)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FileListView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Group {
            if viewModel.videoFiles.isEmpty {
                EmptyStateView(viewModel: viewModel)
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
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(NSLocalizedString("Перетащите видеофайлы сюда", comment: ""))
                    .font(.title3)
                    .fontWeight(.medium)

                Text(NSLocalizedString("или нажмите кнопку \"Добавить файлы\"", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(NSLocalizedString("Добавить файлы", comment: "")) {
                viewModel.showFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.videoMainBackground)
    }
}

struct FooterView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        HStack {
            if !viewModel.videoFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: NSLocalizedString("Файлов: %d", comment: ""), viewModel.videoFiles.count))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if viewModel.totalOriginalSize > 0 {
                        let sizeString = ByteCountFormatter.string(fromByteCount: viewModel.totalOriginalSize, countStyle: .file)
                        Text(String(format: NSLocalizedString("Размер: %@", comment: ""), sizeString))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button(NSLocalizedString("Показать логи", comment: "")) {
                    AppDelegate.shared?.showLogsWindow()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                .help(NSLocalizedString("Открыть окно логов", comment: ""))

                Button(NSLocalizedString("Очистить завершенные", comment: "")) {
                    viewModel.removeCompletedFiles()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                .disabled(!hasCompletedFiles)
                .help(clearCompletedHelpText)

                if viewModel.isProcessing {
                    Button(NSLocalizedString("Отменить", comment: "")) {
                        viewModel.cancelAllProcessing()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(NSLocalizedString("Сжать всё", comment: "")) {
                        viewModel.compressAllFiles()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.videoFiles.isEmpty || viewModel.videoFiles.allSatisfy { $0.status.isFinished })
                    .keyboardShortcut(.space, modifiers: [])
                    .help(compressAllHelpText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var compressAllHelpText: String {
        if viewModel.videoFiles.isEmpty {
            return NSLocalizedString("Добавьте файлы, чтобы начать сжатие", comment: "")
        }
        if viewModel.videoFiles.allSatisfy({ $0.status.isFinished }) {
            return NSLocalizedString("Все файлы уже обработаны", comment: "")
        }
        return NSLocalizedString("Сжать все файлы", comment: "")
    }

    private var hasCompletedFiles: Bool {
        viewModel.videoFiles.contains { file in
            if case .completed = file.status {
                return true
            }
            return false
        }
    }

    private var clearCompletedHelpText: String {
        if hasCompletedFiles {
            return NSLocalizedString("Удалить завершенные файлы из списка", comment: "")
        }
        return NSLocalizedString("Нет завершенных файлов", comment: "")
    }
}

private struct BottomStatusBar: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(NSLocalizedString("Логи", comment: "")) {
                NotificationCenter.default.post(name: .openLogs, object: nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct StoredSidebarPreset: Codable, Identifiable {
    let id: UUID
    let name: String
    let settings: CompressionSettings
}

private final class FolderDirectoryWatcher {
    private let queue = DispatchQueue(label: "video.folder.monitor.watcher")
    private var timer: DispatchSourceTimer?
    private var knownPaths: Set<String> = []
    private var folderURL: URL?

    func start(
        folderURL: URL,
        initialKnownPaths: Set<String>,
        onKnownPathsChanged: @escaping (Set<String>) -> Void,
        onNewFiles: @escaping ([URL]) -> Void
    ) {
        stop()

        let canonicalFolderURL = folderURL.standardizedFileURL
        self.folderURL = canonicalFolderURL

        let initialFiles = scanVideoFiles(in: canonicalFolderURL)
        let initialPaths = Set(initialFiles.map { $0.path })
        let initialNewPaths = initialPaths.subtracting(initialKnownPaths)
        knownPaths = initialPaths
        onKnownPathsChanged(initialPaths)

        if !initialNewPaths.isEmpty {
            let initialNewFiles = initialFiles
                .filter { initialNewPaths.contains($0.path) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            DispatchQueue.main.async {
                onNewFiles(initialNewFiles)
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self, let folder = self.folderURL else { return }

            let currentFiles = self.scanVideoFiles(in: folder)
            let currentPaths = Set(currentFiles.map { $0.path })
            let newPaths = currentPaths.subtracting(self.knownPaths)
            self.knownPaths = currentPaths
            onKnownPathsChanged(currentPaths)

            guard !newPaths.isEmpty else { return }

            let newFiles = currentFiles
                .filter { newPaths.contains($0.path) }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            DispatchQueue.main.async {
                onNewFiles(newFiles)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        knownPaths.removeAll()
        folderURL = nil
    }

    private func scanVideoFiles(in folderURL: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let supportedExtensions: Set<String> = ["mp4", "mov", "mkv", "avi", "webm", "flv", "wmv", "m4v"]

        return items.filter { url in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile ?? false
        }
    }
}

@MainActor
private final class FolderMonitorViewModel: ObservableObject {
    private enum PresetSelection {
        case current
        case quality(QualityPreset)
        case saved(UUID)

        init(rawValue: String?) {
            guard let rawValue else {
                self = .current
                return
            }
            if rawValue == "current" {
                self = .current
                return
            }
            if rawValue.hasPrefix("quality:") {
                let qualityRaw = String(rawValue.dropFirst("quality:".count))
                self = QualityPreset(rawValue: qualityRaw).map { .quality($0) } ?? .current
                return
            }
            if rawValue.hasPrefix("saved:") {
                let idRaw = String(rawValue.dropFirst("saved:".count))
                self = UUID(uuidString: idRaw).map { .saved($0) } ?? .current
                return
            }
            self = .current
        }

        var rawValue: String {
            switch self {
            case .current:
                return "current"
            case .quality(let preset):
                return "quality:\(preset.rawValue)"
            case .saved(let id):
                return "saved:\(id.uuidString)"
            }
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
            updateWatcherState()
        }
    }
    @Published var monitoredFolderPath: String {
        didSet {
            UserDefaults.standard.set(monitoredFolderPath, forKey: Keys.folderPath)
            updateWatcherState()
        }
    }
    @Published var selectedPresetToken: String {
        didSet {
            UserDefaults.standard.set(selectedPresetToken, forKey: Keys.selectedPresetToken)
            updateWatcherState()
        }
    }
    @Published private(set) var presets: [StoredSidebarPreset] = []
    @Published private(set) var statusText: String = NSLocalizedString("Мониторинг выключен.", comment: "")

    private enum Keys {
        static let isEnabled = "video.monitor.enabled"
        static let folderPath = "video.monitor.folderPath"
        static let selectedPresetToken = "video.monitor.selectedPresetToken"
        static let legacySelectedPresetID = "video.monitor.selectedPresetId"
        static let sidebarPresets = "video.sidebar.userPresets"
        static let knownPathsFolder = "video.monitor.knownPaths.folder"
        static let knownPathsList = "video.monitor.knownPaths.list"
    }

    private weak var settingsService: SettingsService?
    private var onNewFilesHandler: (([URL], CompressionSettings?) -> Void)?
    private let watcher = FolderDirectoryWatcher()

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.isEnabled)
        self.monitoredFolderPath = UserDefaults.standard.string(forKey: Keys.folderPath) ?? ""
        let token = UserDefaults.standard.string(forKey: Keys.selectedPresetToken)
        if let token {
            self.selectedPresetToken = token
        } else if let legacyID = UserDefaults.standard.string(forKey: Keys.legacySelectedPresetID),
                  let uuid = UUID(uuidString: legacyID) {
            self.selectedPresetToken = PresetSelection.saved(uuid).rawValue
        } else {
            self.selectedPresetToken = PresetSelection.current.rawValue
        }
        refreshPresets()
        updateWatcherState()
    }

    func configure(
        settingsService: SettingsService,
        onNewFiles: @escaping ([URL], CompressionSettings?) -> Void
    ) {
        self.settingsService = settingsService
        self.onNewFilesHandler = onNewFiles
        refreshPresets()
        updateWatcherState()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Выбрать папку", comment: "")

        if panel.runModal() == .OK, let url = panel.url {
            monitoredFolderPath = url.path
        }
    }

    func refreshPresets() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.sidebarPresets),
            let decoded = try? JSONDecoder().decode([StoredSidebarPreset].self, from: data)
        else {
            presets = []
            selectedPresetToken = PresetSelection.current.rawValue
            return
        }

        presets = decoded
        if case .saved(let id) = currentSelection,
           !decoded.contains(where: { $0.id == id }) {
            selectedPresetToken = PresetSelection.current.rawValue
        }
    }

    var selectedPresetTitle: String {
        switch currentSelection {
        case .current:
            return NSLocalizedString("Текущие настройки", comment: "")
        case .quality(let preset):
            return String(format: NSLocalizedString("Стандарт: %@", comment: ""), preset.displayName)
        case .saved(let id):
            guard let preset = presets.first(where: { $0.id == id }) else {
                return NSLocalizedString("Текущие настройки", comment: "")
            }
            return preset.name
        }
    }

    private var currentSelection: PresetSelection {
        PresetSelection(rawValue: selectedPresetToken)
    }

    func useCurrentSettingsPreset() {
        selectedPresetToken = PresetSelection.current.rawValue
    }

    func useQualityPreset(_ preset: QualityPreset) {
        selectedPresetToken = PresetSelection.quality(preset).rawValue
    }

    func useSavedPreset(_ id: UUID) {
        selectedPresetToken = PresetSelection.saved(id).rawValue
    }

    private func resolvedSettingsOverride() -> CompressionSettings? {
        switch currentSelection {
        case .current:
            return nil
        case .quality(let preset):
            var settings = settingsService?.settings ?? CompressionSettings.default
            settings.qualityPreset = preset
            settings.rateControlMode = .crf
            settings.crf = preset.recommendedCRF(for: settings.codec)
            return settings
        case .saved(let id):
            return presets.first(where: { $0.id == id })?.settings
        }
    }

    private func effectiveSettings() -> CompressionSettings {
        resolvedSettingsOverride() ?? settingsService?.settings ?? CompressionSettings.default
    }

    private func shouldSkipOutputFile(_ url: URL, settings: CompressionSettings) -> Bool {
        switch settings.outputBehavior {
        case .appendCompressedToName:
            let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
            return baseName.hasSuffix("_compressed")
        case .subfolderCompressed:
            let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
            return parent == "compressed"
        case .replaceOriginal:
            return false
        }
    }

    private func persistedKnownPaths(for folderPath: String) -> Set<String> {
        let normalized = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        let savedFolder = UserDefaults.standard.string(forKey: Keys.knownPathsFolder)
        guard savedFolder == normalized else { return [] }

        let savedList = UserDefaults.standard.array(forKey: Keys.knownPathsList) as? [String] ?? []
        return Set(savedList)
    }

    private func persistKnownPaths(_ paths: Set<String>, for folderPath: String) {
        let normalized = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        UserDefaults.standard.set(normalized, forKey: Keys.knownPathsFolder)
        UserDefaults.standard.set(Array(paths), forKey: Keys.knownPathsList)
    }

    private func updateWatcherState() {
        guard isEnabled else {
            watcher.stop()
            statusText = NSLocalizedString("Мониторинг выключен.", comment: "")
            return
        }

        guard !monitoredFolderPath.isEmpty else {
            watcher.stop()
            statusText = NSLocalizedString("Выберите папку для мониторинга.", comment: "")
            return
        }

        let folderURL = URL(fileURLWithPath: monitoredFolderPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: monitoredFolderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            watcher.stop()
            statusText = NSLocalizedString("Папка недоступна. Выберите другую папку.", comment: "")
            return
        }

        let rememberedPaths = persistedKnownPaths(for: monitoredFolderPath)

        watcher.start(
            folderURL: folderURL,
            initialKnownPaths: rememberedPaths,
            onKnownPathsChanged: { [weak self] updatedPaths in
                guard let self else { return }
                self.persistKnownPaths(updatedPaths, for: self.monitoredFolderPath)
            }
        ) { [weak self] newURLs in
            guard let self else { return }
            let filterSettings = self.effectiveSettings()
            let filteredURLs = newURLs.filter { !self.shouldSkipOutputFile($0, settings: filterSettings) }
            guard !filteredURLs.isEmpty else {
                self.statusText = NSLocalizedString("Новые файлы обнаружены, но это результаты предыдущего сжатия. Пропущено.", comment: "")
                return
            }
            let presetSettings = self.resolvedSettingsOverride()
            self.statusText = String(
                format: NSLocalizedString("Найдено новых файлов: %d. Добавлено в очередь.", comment: ""),
                filteredURLs.count
            )
            self.onNewFilesHandler?(filteredURLs, presetSettings)
        }
        statusText = String(format: NSLocalizedString("Мониторинг активен: %@", comment: ""), folderURL.lastPathComponent)
    }
}

private struct FolderMonitoringView: View {
    @ObservedObject var viewModel: FolderMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Мониторинг", comment: ""))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(NSLocalizedString("Автоматическое добавление и сжатие новых видео в выбранной папке.", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    monitorSectionHeader(NSLocalizedString("МОНИТОРИНГ", comment: ""))

                    monitorRow(title: NSLocalizedString("Включить мониторинг", comment: ""), icon: "eye.fill") {
                        Toggle("", isOn: $viewModel.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        monitorRow(title: NSLocalizedString("Папка", comment: ""), icon: "folder.fill") {
                            Button(NSLocalizedString("Выбрать папку", comment: "")) {
                                viewModel.chooseFolder()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(viewModel.monitoredFolderPath.isEmpty ? NSLocalizedString("Папка не выбрана", comment: "") : viewModel.monitoredFolderPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .padding(.leading, 38)
                    }

                    monitorRow(title: NSLocalizedString("Пресет", comment: ""), icon: "slider.horizontal.3") {
                        Menu {
                            Button(NSLocalizedString("Текущие настройки", comment: "")) {
                                viewModel.useCurrentSettingsPreset()
                            }

                            Divider()
                            ForEach(QualityPreset.allCases.filter { $0 != .custom }) { preset in
                                Button(String(format: NSLocalizedString("Стандарт: %@", comment: ""), preset.displayName)) {
                                    viewModel.useQualityPreset(preset)
                                }
                            }

                            if !viewModel.presets.isEmpty {
                                Divider()
                                ForEach(viewModel.presets) { preset in
                                    Button(String(format: NSLocalizedString("Сохраненный: %@", comment: ""), preset.name)) {
                                        viewModel.useSavedPreset(preset.id)
                                    }
                                }
                            }
                        } label: {
                            monitorValueLabel(viewModel.selectedPresetTitle)
                        }
                        .menuStyle(.borderlessButton)
                    }

                    monitorSectionHeader(NSLocalizedString("СТАТУС", comment: ""))

                    Text(viewModel.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
        .onAppear {
            viewModel.refreshPresets()
        }
    }

    private func monitorSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monitorRow<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer(minLength: 16)
            content()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }

    private func monitorValueLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: 170, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environmentObject(SettingsService())
}
#endif
