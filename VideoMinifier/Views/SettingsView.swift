import SwiftUI

/// Settings panel view for configuring compression parameters
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showUnsavedChangesConfirmation = false

    init(settingsService: SettingsService) {
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(settingsService: settingsService))
    }

    init(viewModel: SettingsViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SettingsHeaderView(
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                onSave: {
                    viewModel.saveSettings()
                    dismiss()
                },
                onDiscard: {
                    viewModel.discardChanges()
                    dismiss()
                },
                onClose: {
                    handleCloseRequest()
                }
            )
            
            Divider()
            
            // Settings Content
            ScrollView {
                VStack(spacing: 24) {
                    // General Section (Language)
                    SettingsSection(title: NSLocalizedString("Общие", comment: ""), icon: "gearshape") {
                        GeneralSettingsView(viewModel: viewModel)
                    }
                    
                    // Video Quality Section
                    SettingsSection(title: NSLocalizedString("Качество видео", comment: ""), icon: "video") {
                        CRFSettingsView(viewModel: viewModel)
                    }
                    
                    // Resolution Section
                    SettingsSection(title: NSLocalizedString("Разрешение", comment: ""), icon: "arrow.up.left.and.arrow.down.right") {
                        ResolutionSettingsView(viewModel: viewModel)
                    }
                    
                    // Codec Section
                    SettingsSection(title: NSLocalizedString("Кодек", comment: ""), icon: "gear") {
                        CodecSettingsView(viewModel: viewModel)
                    }
                    
                    // Audio Section
                    SettingsSection(title: NSLocalizedString("Аудио", comment: ""), icon: "speaker.wave.2") {
                        AudioSettingsView(viewModel: viewModel)
                    }
                    
                    // Behavior Section
                    SettingsSection(title: NSLocalizedString("Поведение", comment: ""), icon: "slider.horizontal.3") {
                        BehaviorSettingsView(viewModel: viewModel)
                    }
                    
                    // App Display Section
                    SettingsSection(title: NSLocalizedString("Отображение приложения", comment: ""), icon: "macwindow") {
                        AppDisplaySettingsView(viewModel: viewModel)
                    }
                    
                    // Reset Section
                    ResetSettingsView(viewModel: viewModel)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .background(Color.adaptiveBackground)
        .confirmationDialog(
            NSLocalizedString("Сброс настроек", comment: ""),
            isPresented: $viewModel.showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Сбросить", comment: ""), role: .destructive) {
                viewModel.confirmResetToDefaults()
            }
            Button(NSLocalizedString("Отмена", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Все настройки будут сброшены к значениям по умолчанию. Это действие нельзя отменить.", comment: ""))
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .confirmationDialog(
            NSLocalizedString("Сохранить изменения?", comment: ""),
            isPresented: $showUnsavedChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Сохранить", comment: "")) {
                viewModel.saveSettings()
                dismiss()
            }
            Button(NSLocalizedString("Не сохранять", comment: ""), role: .destructive) {
                viewModel.discardChanges()
                dismiss()
            }
            Button(NSLocalizedString("Отмена", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Есть несохранённые изменения. Сохранить их перед закрытием?", comment: ""))
        }

        .alert(NSLocalizedString("Требуется перезапуск", comment: ""), isPresented: $viewModel.restartRequired) {
            Button(NSLocalizedString("Перезапустить сейчас", comment: "")) {
                viewModel.restartApp()
            }
            Button(NSLocalizedString("Позже", comment: "")) {
                // Just dismiss the alert, user can restart manually later
                viewModel.restartRequired = false
            }
        } message: {
            Text(NSLocalizedString("Чтобы изменить язык, необходимо перезапустить приложение", comment: ""))
        }
    }

    private func handleCloseRequest() {
        if viewModel.hasUnsavedChanges {
            showUnsavedChangesConfirmation = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Header View

struct SettingsHeaderView: View {
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            Text(NSLocalizedString("Настройки", comment: ""))
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            if hasUnsavedChanges {
                HStack(spacing: 8) {
                    Button(NSLocalizedString("Отменить", comment: ""), action: onDiscard)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    
                    Button(NSLocalizedString("Сохранить", comment: ""), action: onSave)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button(NSLocalizedString("Готово", comment: ""), action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.leading, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Язык", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            // We bind simply to the settings language. The ViewModel handles the side effects.
            // The key fix is ensuring that the restart alert is presented at the top level
            // and persists even if the view refreshes.
            Picker("", selection: $viewModel.settings.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.localizedName).tag(lang)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: viewModel.settings.language) { _ in
                 // Trigger save immediately to check for language change
                 // This is where 'restartRequired' gets set in the ViewModel
                 viewModel.saveSettings()
            }
        }
    }
}

// MARK: - CRF Settings

struct CRFSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Режим контроля", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.rateControlMode) {
                ForEach(RateControlMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: viewModel.settings.rateControlMode) { newMode in
                viewModel.updateRateControlMode(newMode)
            }
            
            Text(viewModel.rateControlDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if viewModel.settings.rateControlMode == .targetBitrate {
                HStack {
                    Text(NSLocalizedString("Целевой битрейт", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(viewModel.settings.targetBitrateKbps) kbps")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.targetBitrateKbps) },
                        set: { viewModel.settings.targetBitrateKbps = Int($0.rounded()) }
                    ),
                    in: 300...15000,
                    step: 50
                )
            }
            
            if viewModel.settings.rateControlMode == .targetSize {
                HStack {
                    Text(NSLocalizedString("Целевой размер", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(viewModel.settings.targetSizeMB) MB")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.targetSizeMB) },
                        set: { viewModel.settings.targetSizeMB = Int($0.rounded()) }
                    ),
                    in: 5...2000,
                    step: 5
                )
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Text(NSLocalizedString("Баланс размер/качество", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.qualityPreset) {
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .onChange(of: viewModel.settings.qualityPreset) { newPreset in
                viewModel.updateQualityPreset(newPreset)
            }
            .disabled(!viewModel.isCRFMode)
            
            Text(viewModel.qualityPresetDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Text(NSLocalizedString("CRF (Constant Rate Factor)", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(viewModel.settings.crf)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            Slider(
                value: $viewModel.crfValue,
                in: viewModel.crfRange,
                step: 1
            ) {
                Text(NSLocalizedString("CRF", comment: ""))
            } minimumValueLabel: {
                Text("\(Int(viewModel.crfRange.lowerBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("\(Int(viewModel.crfRange.upperBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(!viewModel.isCRFMode)
            
            Text(viewModel.crfDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(viewModel.estimatedCompressionText)
                .font(.caption)
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Codec Settings

struct CodecSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Кодек", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.codec) {
                ForEach(VideoCodec.allCases, id: \.self) { codec in
                    Text(codec.displayName)
                        .tag(codec)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: viewModel.settings.codec) { newCodec in
                viewModel.updateCodec(newCodec)
            }
            
            Text(viewModel.codecDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Предупреждение для H.265
            if viewModel.settings.codec == .h265 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                    Text(NSLocalizedString("H.265 поддерживается не на всех устройствах", comment: ""))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
            
            Toggle(NSLocalizedString("Использовать аппаратное ускорение", comment: ""), isOn: $viewModel.settings.useHardwareAcceleration)
                .font(.subheadline)
            
            Divider()
            
            Text(NSLocalizedString("Скорость кодирования", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.encodingSpeed) {
                ForEach(EncodingSpeed.allCases) { speed in
                    Text(speed.displayName).tag(speed)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(viewModel.settings.useHardwareAcceleration)
            
            if viewModel.settings.useHardwareAcceleration {
                Text(NSLocalizedString("Скорость задаётся аппаратным кодировщиком", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Audio Settings

struct AudioSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(NSLocalizedString("Не перекодировать аудио", comment: ""), isOn: $viewModel.settings.copyAudio)
                .font(.subheadline)
            
            Text(viewModel.settings.copyAudio ? 
                 NSLocalizedString("Аудиодорожка будет скопирована без изменений", comment: "") : 
                 NSLocalizedString("Аудио будет перекодировано в AAC 128kbps", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !viewModel.settings.copyAudio {
                HStack {
                    Text(NSLocalizedString("Битрейт аудио", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(viewModel.settings.audioBitrateKbps) kbps")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(viewModel.settings.audioBitrateKbps) },
                        set: { viewModel.settings.audioBitrateKbps = Int($0.rounded()) }
                    ),
                    in: 64...320,
                    step: 16
                )
                
                Text(NSLocalizedString("Каналы", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: $viewModel.settings.audioChannels) {
                    Text(NSLocalizedString("1 (Mono)", comment: "")).tag(1)
                    Text(NSLocalizedString("2 (Stereo)", comment: "")).tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss // Add this
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Поведение выхода файла", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.outputBehavior) {
                ForEach(OutputBehavior.allCases) { behavior in
                    Text(behavior.localizedName).tag(behavior)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            
            Toggle(NSLocalizedString("Автоматически закрыть приложение после завершения", comment: ""), isOn: $viewModel.settings.autoCloseApp)
                .font(.subheadline)
            
            Divider()
            
            Button(action: {
                NotificationCenter.default.post(name: .openLogs, object: nil)
                // Dismiss settings will be handled by the parent view/notification observer logic if needed, 
                // but usually we want to keep settings open or close it explicitly. 
                // User asked to "show logs", usually implies bringing logs window to front.
                // We'll close settings to show the logs clearly.
                // Using NotificationCenter to trigger this actions allows decoupling.
                // We should dismiss this view too.
                // Note: The parent view will receive the notification and show the logs.
                // We dismiss this view to make sure the logs are visible if they are presented as a sheet on the main view.
                dismiss() // This will now work
            }) {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text(NSLocalizedString("Показать логи", comment: ""))
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - App Display Settings

struct AppDisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Режим отображения", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.displayMode) {
                ForEach(AppDisplayMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            
            if !viewModel.settings.showInDock && !viewModel.settings.showInMenuBar {
                 HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text(NSLocalizedString("Приложение должно отображаться либо в Dock, либо в меню-баре", comment: ""))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Resolution Settings

struct ResolutionSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Выходное разрешение", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("", selection: $viewModel.settings.resolutionPreset) {
                ForEach(ResolutionPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            
            Text(NSLocalizedString("Масштабирование выполняется только при превышении выбранного размера", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Reset Settings

struct ResetSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Сброс настроек", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(NSLocalizedString("Вернуть все настройки к значениям по умолчанию", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(NSLocalizedString("Сбросить", comment: "")) {
                    viewModel.showResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }
}



// MARK: - Previews

#if DEBUG
#Preview {
    SettingsView(viewModel: .preview)
}
#endif
