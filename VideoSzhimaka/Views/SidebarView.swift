import SwiftUI

private struct SavedVideoPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: CompressionSettings

    init(id: UUID = UUID(), name: String, settings: CompressionSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}

struct SidebarView: View {
    @ObservedObject var settingsService: SettingsService

    @State private var hoverInfo: String = ""
    @State private var showSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var presets: [SavedVideoPreset] = []
    @State private var activePresetId: UUID?

    private let presetsKey = "video.sidebar.userPresets"
    private let activePresetKey = "video.sidebar.activePresetId"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    SidebarGroup(title: NSLocalizedString("ПРЕСЕТЫ", comment: "")) {
                        VStack(spacing: 0) {
                            SidebarOptionRow(
                                title: NSLocalizedString("Качество", comment: ""),
                                hint: NSLocalizedString("Быстрый выбор профиля качества и размера.", comment: ""),
                                onHover: updateHover
                            ) {
                                Menu {
                                    ForEach(QualityPreset.allCases.filter { $0 != .custom }) { preset in
                                        Button(preset.displayName) {
                                            updateSettings { settings in
                                                settings.qualityPreset = preset
                                                settings.rateControlMode = .crf
                                                settings.crf = preset.recommendedCRF(for: settings.codec)
                                            }
                                            activePresetId = nil
                                            saveActivePresetId(nil)
                                        }
                                    }

                                    if !presets.isEmpty {
                                        Divider()
                                        ForEach(presets) { preset in
                                            Button(preset.name) {
                                                applyPreset(preset)
                                            }
                                        }
                                    }
                                } label: {
                                    Text(currentPresetTitle)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }

                            HStack {
                                Spacer()
                                Button {
                                    showSavePresetAlert = true
                                } label: {
                                    Label(NSLocalizedString("Сохранить", comment: ""), systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onHover { isHovering in
                                updateHover(
                                    isHovering
                                    ? NSLocalizedString("Сохраняет текущую комбинацию параметров как пользовательский пресет.", comment: "")
                                    : ""
                                )
                            }
                            .alert(NSLocalizedString("Сохранить пресет", comment: ""), isPresented: $showSavePresetAlert) {
                                TextField(NSLocalizedString("Мой пресет", comment: ""), text: $newPresetName)
                                Button(NSLocalizedString("Отмена", comment: ""), role: .cancel) {
                                    newPresetName = ""
                                }
                                Button(NSLocalizedString("Сохранить", comment: "")) {
                                    saveCurrentPreset()
                                }
                            } message: {
                                Text(NSLocalizedString("Введите название пресета", comment: ""))
                            }
                        }
                    }

                    SidebarGroup(title: NSLocalizedString("GENERAL", comment: "")) {
                        VStack(spacing: 0) {
                            SidebarOptionRow(
                                title: NSLocalizedString("Режим", comment: ""),
                                hint: NSLocalizedString("CRF, целевой битрейт или целевой размер.", comment: ""),
                                onHover: updateHover
                            ) {
                                Menu {
                                    ForEach(RateControlMode.allCases) { mode in
                                        Button(mode.displayName) {
                                            updateSettings { $0.rateControlMode = mode }
                                            activePresetId = nil
                                            saveActivePresetId(nil)
                                        }
                                    }
                                } label: {
                                    Text(rateControlModeLabel)
                                }
                            }

                            if settingsService.settings.rateControlMode == .crf {
                                SidebarOptionRow(
                                    title: NSLocalizedString("CRF", comment: ""),
                                    hint: NSLocalizedString("Ниже значение = выше качество и больше размер.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    HStack(spacing: 6) {
                                        Slider(value: crfBinding, in: crfRange, step: 1)
                                            .frame(width: 84)
                                        Text("\(settingsService.settings.crf)")
                                            .frame(width: 24, alignment: .trailing)
                                    }
                                }
                            }

                            if settingsService.settings.rateControlMode == .targetBitrate {
                                SidebarOptionRow(
                                    title: NSLocalizedString("Битрейт", comment: ""),
                                    hint: NSLocalizedString("Целевой битрейт видео в kbps.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    Stepper("\(settingsService.settings.targetBitrateKbps)", value: binding(\.targetBitrateKbps), in: 300...20000, step: 100)
                                        .labelsHidden()
                                        .frame(width: 120)
                                }
                            }

                            if settingsService.settings.rateControlMode == .targetSize {
                                SidebarOptionRow(
                                    title: NSLocalizedString("Размер MB", comment: ""),
                                    hint: NSLocalizedString("Ориентир размера итогового файла.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    Stepper("\(settingsService.settings.targetSizeMB)", value: binding(\.targetSizeMB), in: 5...10000, step: 5)
                                        .labelsHidden()
                                        .frame(width: 120)
                                }
                            }

                            SidebarOptionRow(
                                title: NSLocalizedString("Кодек", comment: ""),
                                hint: NSLocalizedString("H.265 обычно меньше размер при сопоставимом качестве.", comment: ""),
                                onHover: updateHover
                            ) {
                                Menu {
                                    ForEach(VideoCodec.allCases, id: \.rawValue) { codec in
                                        Button(codec.displayName) {
                                            updateSettings { settings in
                                                settings.setCodec(codec)
                                            }
                                            activePresetId = nil
                                            saveActivePresetId(nil)
                                        }
                                    }
                                } label: {
                                    Text(settingsService.settings.codec.displayName)
                                }
                            }

                            if !settingsService.settings.useHardwareAcceleration {
                                SidebarOptionRow(
                                    title: NSLocalizedString("Скорость", comment: ""),
                                    hint: NSLocalizedString("Медленнее обычно дает меньший размер.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    Menu {
                                        ForEach(EncodingSpeed.allCases) { speed in
                                            Button(speed.displayName) {
                                                updateSettings { $0.encodingSpeed = speed }
                                            }
                                        }
                                    } label: {
                                        Text(settingsService.settings.encodingSpeed.displayName)
                                    }
                                }
                            }
                        }
                    }

                    SidebarGroup(title: NSLocalizedString("RESIZE", comment: "")) {
                        VStack(spacing: 0) {
                            SidebarOptionRow(
                                title: NSLocalizedString("Resize", comment: ""),
                                hint: NSLocalizedString("Включить масштабирование перед кодированием.", comment: ""),
                                onHover: updateHover
                            ) {
                                Toggle("", isOn: binding(\.resizeEnabled))
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .scaleEffect(0.75)
                            }

                            if settingsService.settings.resizeEnabled {
                                SidebarOptionRow(
                                    title: NSLocalizedString("Target", comment: ""),
                                    hint: NSLocalizedString("Целевая сторона в пикселях.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    HStack(spacing: 4) {
                                        TextField(NSLocalizedString("Px", comment: ""), value: binding(\.resizeValue), formatter: resizeFormatter)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 56)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())

                                        Menu {
                                            Button(NSLocalizedString("4096 (4K)", comment: "")) { updateSettings { $0.resizeValue = 4096 } }
                                            Button(NSLocalizedString("1920 (HD)", comment: "")) { updateSettings { $0.resizeValue = 1920 } }
                                            Button(NSLocalizedString("1280 (Web)", comment: "")) { updateSettings { $0.resizeValue = 1280 } }
                                            Button("1080") { updateSettings { $0.resizeValue = 1080 } }
                                            Button("720") { updateSettings { $0.resizeValue = 720 } }
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.secondary)
                                                .frame(width: 16, height: 16)
                                                .background(Color.black.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 16)
                                    }
                                }

                                SidebarOptionRow(
                                    title: NSLocalizedString("Mode", comment: ""),
                                    hint: NSLocalizedString("Fit сохраняет пропорции, Width/Height задают ведущую сторону.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    Menu {
                                        ForEach(ResizeCondition.allCases) { condition in
                                            Button(condition.displayName) {
                                                updateSettings { $0.resizeCondition = condition }
                                                activePresetId = nil
                                                saveActivePresetId(nil)
                                            }
                                        }
                                    } label: {
                                        Text(settingsService.settings.resizeCondition.displayName)
                                    }
                                }
                            }
                        }
                    }

                    SidebarGroup(title: NSLocalizedString("WORKFLOW", comment: "")) {
                        VStack(spacing: 0) {
                            SidebarOptionRow(
                                title: NSLocalizedString("Auto close", comment: ""),
                                hint: NSLocalizedString("Закрыть приложение после завершения всех задач.", comment: ""),
                                onHover: updateHover
                            ) {
                                Toggle("", isOn: binding(\.autoCloseApp))
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .scaleEffect(0.75)
                            }

                            SidebarOptionRow(
                                title: NSLocalizedString("Hardware", comment: ""),
                                hint: NSLocalizedString("Использовать аппаратное ускорение, если доступно.", comment: ""),
                                onHover: updateHover
                            ) {
                                Toggle("", isOn: binding(\.useHardwareAcceleration))
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                    .scaleEffect(0.75)
                            }
                        }
                    }

                    SidebarGroup(title: NSLocalizedString("OUTPUT", comment: "")) {
                        VStack(spacing: 0) {
                            SidebarOptionRow(
                                title: NSLocalizedString("Что делать", comment: ""),
                                hint: NSLocalizedString("Суффикс, отдельная папка или замена исходника.", comment: ""),
                                onHover: updateHover
                            ) {
                                Menu {
                                    ForEach(OutputBehavior.allCases) { behavior in
                                        Button(behavior.localizedName) {
                                            updateSettings { $0.outputBehavior = behavior }
                                            activePresetId = nil
                                            saveActivePresetId(nil)
                                        }
                                    }
                                } label: {
                                    Text(outputBehaviorLabel)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }

                            SidebarOptionRow(
                                title: NSLocalizedString("Аудио", comment: ""),
                                hint: NSLocalizedString("Оригинал: копирует аудио без изменений. AAC: перекодирует аудио с выбранным битрейтом.", comment: ""),
                                onHover: updateHover
                            ) {
                                Menu {
                                    Button(NSLocalizedString("Оригинал (без перекодирования)", comment: "")) {
                                        updateSettings { $0.copyAudio = true }
                                        activePresetId = nil
                                        saveActivePresetId(nil)
                                    }
                                    Button(NSLocalizedString("AAC (перекодировать)", comment: "")) {
                                        updateSettings { $0.copyAudio = false }
                                        activePresetId = nil
                                        saveActivePresetId(nil)
                                    }
                                } label: {
                                    Text(settingsService.settings.copyAudio ? NSLocalizedString("Оригинал", comment: "") : NSLocalizedString("AAC", comment: ""))
                                }
                            }

                            if !settingsService.settings.copyAudio {
                                SidebarOptionRow(
                                    title: NSLocalizedString("Битрейт аудио", comment: ""),
                                    hint: NSLocalizedString("Используется только в режиме AAC.", comment: ""),
                                    onHover: updateHover
                                ) {
                                    Stepper("\(settingsService.settings.audioBitrateKbps)", value: binding(\.audioBitrateKbps), in: 64...320, step: 16)
                                        .labelsHidden()
                                        .frame(width: 110)
                                }
                            }

                            if settingsService.settings.outputBehavior == .replaceOriginal {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 10))
                                        .offset(y: 1)
                                    Text(NSLocalizedString("Исходные файлы будут заменены.", comment: ""))
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            }
                        }
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Divider()

                HStack(alignment: .top, spacing: 4) {
                    if !hoverInfo.isEmpty {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .offset(y: 1)
                    }

                    Text(hoverInfo.isEmpty ? NSLocalizedString("Наведите на пункт, чтобы увидеть подсказку.", comment: "") : hoverInfo)
                        .font(.system(size: 10))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                .frame(height: 75, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
            .background(.regularMaterial)
        }
        .frame(width: 200)
        .background(.regularMaterial)
        .onAppear {
            loadPresets()
            loadActivePresetId()
        }
    }

    private var crfRange: ClosedRange<Double> {
        let range = settingsService.settings.codec.recommendedCRFRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    private var crfBinding: Binding<Double> {
        Binding(
            get: { Double(settingsService.settings.crf) },
            set: { newValue in
                updateSettings { settings in
                    settings.setCRF(Int(newValue.rounded()))
                }
                activePresetId = nil
                saveActivePresetId(nil)
            }
        )
    }

    private var currentPresetTitle: String {
        if let id = activePresetId,
           let preset = presets.first(where: { $0.id == id }) {
            return preset.name
        }

        return settingsService.settings.qualityPreset.displayName
    }

    private func updateHover(_ text: String) {
        hoverInfo = text
    }

    private var rateControlModeLabel: String {
        switch settingsService.settings.rateControlMode {
        case .crf:
            return "CRF"
        case .targetBitrate:
            return NSLocalizedString("Битрейт", comment: "")
        case .targetSize:
            return NSLocalizedString("Размер", comment: "")
        }
    }

    private var outputBehaviorLabel: String {
        switch settingsService.settings.outputBehavior {
        case .appendCompressedToName:
            return "_compressed"
        case .subfolderCompressed:
            return "compressed/"
        case .replaceOriginal:
            return NSLocalizedString("Заменить", comment: "")
        }
    }

    private var resizeFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 240
        formatter.maximum = 8192
        formatter.allowsFloats = false
        return formatter
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CompressionSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsService.settings[keyPath: keyPath] },
            set: { newValue in
                updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
                activePresetId = nil
                saveActivePresetId(nil)
            }
        )
    }

    private func updateSettings(_ mutate: (inout CompressionSettings) -> Void) {
        var updated = settingsService.settings
        mutate(&updated)
        settingsService.settings = updated
    }

    private func saveCurrentPreset() {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let preset = SavedVideoPreset(name: trimmed, settings: settingsService.settings)
        presets.append(preset)
        savePresets()
        activePresetId = preset.id
        saveActivePresetId(preset.id)
        newPresetName = ""
    }

    private func applyPreset(_ preset: SavedVideoPreset) {
        settingsService.settings = preset.settings
        activePresetId = preset.id
        saveActivePresetId(preset.id)
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([SavedVideoPreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    private func loadActivePresetId() {
        let raw = UserDefaults.standard.string(forKey: activePresetKey)
        activePresetId = raw.flatMap(UUID.init(uuidString:))
    }

    private func saveActivePresetId(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString, forKey: activePresetKey)
    }
}

private struct SidebarOptionRow<Content: View>: View {
    let title: String
    let hint: String
    let onHover: (String) -> Void
    let valueContent: Content

    init(title: String, hint: String, onHover: @escaping (String) -> Void, @ViewBuilder value: () -> Content) {
        self.title = title
        self.hint = hint
        self.onHover = onHover
        self.valueContent = value()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer()
            valueContent
                .font(.system(size: 12))
                .menuStyle(.borderlessButton)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { isHovering in
            onHover(isHovering ? hint : "")
        }
    }
}

private struct SidebarGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.bottom, 2)

            content
        }
    }
}
