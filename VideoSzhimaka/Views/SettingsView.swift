import SwiftUI

/// Settings panel view for configuring compression parameters
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
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
                    if viewModel.hasUnsavedChanges {
                        // Show unsaved changes dialog
                        // For now, just discard changes
                        viewModel.discardChanges()
                    }
                    dismiss()
                }
            )
            
            Divider()
            
            // Settings Content
            ScrollView {
                VStack(spacing: 24) {
                    // Video Quality Section
                    SettingsSection(title: "Качество видео", icon: "video") {
                        CRFSettingsView(viewModel: viewModel)
                    }
                    
                    // Codec Section
                    SettingsSection(title: "Кодек", icon: "gear") {
                        CodecSettingsView(viewModel: viewModel)
                    }
                    
                    // Audio Section
                    SettingsSection(title: "Аудио", icon: "speaker.wave.2") {
                        AudioSettingsView(viewModel: viewModel)
                    }
                    
                    // Behavior Section
                    SettingsSection(title: "Поведение", icon: "slider.horizontal.3") {
                        BehaviorSettingsView(viewModel: viewModel)
                    }
                    
                    // App Display Section
                    SettingsSection(title: "Отображение приложения", icon: "macwindow") {
                        AppDisplaySettingsView(viewModel: viewModel)
                    }
                    
                    // Reset Section
                    ResetSettingsView(viewModel: viewModel)
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color.adaptiveBackground)
        .confirmationDialog(
            "Сбросить настройки",
            isPresented: $viewModel.showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить", role: .destructive) {
                viewModel.confirmResetToDefaults()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все настройки будут сброшены к значениям по умолчанию. Это действие нельзя отменить.")
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
            Text("Настройки")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            if hasUnsavedChanges {
                HStack(spacing: 8) {
                    Button("Отменить", action: onDiscard)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    
                    Button("Сохранить", action: onSave)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Готово", action: onClose)
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

// MARK: - CRF Settings

struct CRFSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CRF (Constant Rate Factor)")
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
                Text("CRF")
            } minimumValueLabel: {
                Text("\(Int(viewModel.crfRange.lowerBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("\(Int(viewModel.crfRange.upperBound))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
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
            Text("Видеокодек")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Picker("Кодек", selection: $viewModel.settings.codec) {
                ForEach(VideoCodec.allCases, id: \.self) { codec in
                    Text(codec.displayName)
                        .tag(codec)
                }
            }
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
                    
                    Text("H.265 поддерживается не на всех устройствах")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
            
            Toggle("Использовать аппаратное ускорение", isOn: $viewModel.settings.useHardwareAcceleration)
                .font(.subheadline)
        }
    }
}

// MARK: - Audio Settings

struct AudioSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Не перекодировать аудио", isOn: $viewModel.settings.copyAudio)
                .font(.subheadline)
            
            Text(viewModel.settings.copyAudio ? 
                 "Аудиодорожка будет скопирована без изменений" : 
                 "Аудио будет перекодировано в AAC 128kbps")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Удалять оригинальные файлы после сжатия", isOn: $viewModel.settings.deleteOriginals)
                .font(.subheadline)
            
            Toggle("Автоматически закрыть приложение после завершения", isOn: $viewModel.settings.autoCloseApp)
                .font(.subheadline)
        }
    }
}

// MARK: - App Display Settings

struct AppDisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Показывать в Dock", isOn: $viewModel.settings.showInDock)
                .font(.subheadline)
            
            Toggle("Показывать в меню-баре", isOn: $viewModel.settings.showInMenuBar)
                .font(.subheadline)
            
            if !viewModel.settings.showInDock && !viewModel.settings.showInMenuBar {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text("Приложение должно отображаться либо в Dock, либо в меню-баре")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
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
                    Text("Сброс настроек")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Вернуть все настройки к значениям по умолчанию")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Сбросить") {
                    viewModel.showResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }
}



// MARK: - Previews

#Preview {
    SettingsView()
}