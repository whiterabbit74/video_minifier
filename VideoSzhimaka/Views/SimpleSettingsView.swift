import SwiftUI
import AppKit

struct SimpleSettingsView: View {
    @ObservedObject var settingsService: SettingsService
    @AppStorage("appTheme") private var appTheme: String = "system"
    @State private var ffmpegPath: String?
    @State private var ffprobePath: String?
    @State private var showRestartLanguageAlert = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Настройки", comment: ""))
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(NSLocalizedString("Конфигурация поведения приложения", comment: ""))
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
                    sectionHeader(NSLocalizedString("WORKFLOW", comment: ""))

                    settingsRow(title: NSLocalizedString("Выход файла", comment: ""), icon: "tray.and.arrow.down.fill") {
                        Menu {
                            ForEach(OutputBehavior.allCases) { behavior in
                                Button(behavior.localizedName) {
                                    settingsService.settings.outputBehavior = behavior
                                }
                            }
                        } label: {
                            menuValueLabel(outputBehaviorTitle)
                        }
                        .menuStyle(.borderlessButton)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        settingsRow(title: NSLocalizedString("Автовыключение после сжатия", comment: ""), icon: "power.circle") {
                            Toggle("", isOn: binding(\.autoCloseApp))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Text(NSLocalizedString("Если включено, приложение завершится после окончания сжатия всех файлов в текущей очереди.", comment: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 38)
                    }

                    sectionHeader(NSLocalizedString("INTERFACE", comment: ""))

                    settingsRow(title: NSLocalizedString("Тема", comment: ""), icon: "paintpalette.fill") {
                        Picker("", selection: $appTheme) {
                            Text(NSLocalizedString("Авто", comment: "")).tag("system")
                            Text(NSLocalizedString("Темная", comment: "")).tag("dark")
                            Text(NSLocalizedString("Светлая", comment: "")).tag("light")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    settingsRow(title: NSLocalizedString("Видимость", comment: ""), icon: "macwindow") {
                        Menu {
                            ForEach(AppDisplayMode.allCases) { mode in
                                Button(mode.localizedName) {
                                    settingsService.settings.displayMode = mode
                                }
                            }
                        } label: {
                            menuValueLabel(settingsService.settings.displayMode.localizedName)
                        }
                        .menuStyle(.borderlessButton)
                    }

                    settingsRow(title: NSLocalizedString("Язык", comment: ""), icon: "globe") {
                        Menu {
                            ForEach(AppLanguage.allCases) { lang in
                                Button(languageMenuTitle(for: lang)) {
                                    setAppLanguage(lang)
                                }
                            }
                        } label: {
                            menuValueLabel(languageMenuTitle(for: settingsService.settings.language))
                        }
                        .menuStyle(.borderlessButton)
                    }

                    sectionHeader(NSLocalizedString("SYSTEM", comment: ""))

                    HStack(spacing: 10) {
                        Image(systemName: libraryStatusIsHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(libraryStatusIsHealthy ? Color.green : Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Связь с библиотеками", comment: ""))
                                .font(.system(size: 12, weight: .semibold))
                            Text(libraryStatusText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            HStack {
                Text("VideoSzhimaka")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(NSLocalizedString("Показать логи", comment: "")) {
                    NotificationCenter.default.post(name: .openLogs, object: nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                Button(NSLocalizedString("Сбросить по умолчанию", comment: "")) {
                    settingsService.resetToDefaults()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red.opacity(0.8))
                .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshLibraryStatus()
        }
        .alert(NSLocalizedString("Перезапустить приложение?", comment: ""), isPresented: $showRestartLanguageAlert) {
            Button(NSLocalizedString("Позже", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Перезапустить", comment: "")) {
                restartApp()
            }
        } message: {
            Text(NSLocalizedString("Язык интерфейса изменен. Для полного применения нужен перезапуск.", comment: ""))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private func settingsRow<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsLabel(title: title, icon: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            content()
                .frame(maxWidth: 170, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var outputBehaviorTitle: String {
        settingsService.settings.outputBehavior.localizedName
    }

    private func menuValueLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: 170, alignment: .trailing)
    }

    private var libraryStatusIsHealthy: Bool {
        ffmpegPath != nil
    }

    private var libraryStatusText: String {
        guard let ffmpegPath else {
            return NSLocalizedString("FFmpeg не найден.", comment: "")
        }
        guard ffprobePath != nil else {
            return String(format: NSLocalizedString("FFmpeg подключен (%@). FFprobe недоступен.", comment: ""), (ffmpegPath as NSString).lastPathComponent)
        }
        return String(format: NSLocalizedString("FFmpeg/FFprobe подключены (%@).", comment: ""), (ffmpegPath as NSString).lastPathComponent)
    }

    private func refreshLibraryStatus() {
        let fileManager = FileManager.default

        let bundledFFmpeg = [
            (Bundle.main.resourcePath ?? "") + "/ffmpeg",
            (Bundle.main.resourcePath ?? "") + "/bin/ffmpeg",
            (Bundle.main.resourcePath ?? "") + "/Resources/bin/ffmpeg"
        ]
        let bundledFFprobe = bundledFFmpeg.map { $0.replacingOccurrences(of: "ffmpeg", with: "ffprobe") }

        let ffmpegCandidates = bundledFFmpeg
        let ffprobeCandidates = bundledFFprobe

        ffmpegPath = ffmpegCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        ffprobePath = ffprobeCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    private func languageMenuTitle(for language: AppLanguage) -> String {
        if language == .system {
            return "\(NSLocalizedString("Системный", comment: "")) (\(resolvedSystemLanguageName))"
        }
        return language.localizedName
    }

    private var resolvedSystemLanguageName: String {
        let rawCode = Locale.preferredLanguages.first ?? "en"
        let normalized = rawCode.replacingOccurrences(of: "_", with: "-").lowercased()

        let mapped: AppLanguage
        if normalized.hasPrefix("ru") {
            mapped = .russian
        } else if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-cn") || normalized.hasPrefix("zh-sg") {
            mapped = .chineseSimplified
        } else if normalized.hasPrefix("es") {
            mapped = .spanish
        } else if normalized.hasPrefix("fr") {
            mapped = .french
        } else if normalized.hasPrefix("de") {
            mapped = .german
        } else if normalized.hasPrefix("ja") {
            mapped = .japanese
        } else if normalized.hasPrefix("pt-br") {
            mapped = .portuguese
        } else if normalized.hasPrefix("it") {
            mapped = .italian
        } else if normalized.hasPrefix("ko") {
            mapped = .korean
        } else {
            mapped = .english
        }

        return mapped.localizedName
    }

    private func setAppLanguage(_ language: AppLanguage) {
        let old = settingsService.settings.language
        settingsService.settings.language = language
        settingsService.saveSettings()

        if old != language {
            showRestartLanguageAlert = true
        }
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CompressionSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsService.settings[keyPath: keyPath] },
            set: { newValue in
                settingsService.settings[keyPath: keyPath] = newValue
            }
        )
    }
}

private struct SettingsLabel: View {
    let title: String
    let icon: String

    var body: some View {
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
    }
}
