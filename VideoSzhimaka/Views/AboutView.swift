import SwiftUI

struct AboutView: View {
    @State private var ffmpegLicenseText: String = ""
    @State private var isLicenseLoaded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(appDisplayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Версия \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Text("Сторонние компоненты")
                .font(.headline)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 8) {
                Text("FFmpeg")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Это приложение включает FFmpeg. Полный текст лицензии ниже.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                GroupBox {
                    ScrollView {
                        Text(ffmpegLicenseText.isEmpty ? placeholderLicenseNote : ffmpegLicenseText)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 180)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Закрыть") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 360)
        .onAppear(perform: loadLicense)
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Приложение")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var placeholderLicenseNote: String {
        "Не удалось загрузить текст лицензии FFmpeg из бандла. Убедитесь, что файл Resources/LICENSES/FFmpeg_LICENSE.txt включён в сборку."
    }

    private func loadLicense() {
        guard !isLicenseLoaded else { return }
        isLicenseLoaded = true

        if let url = Bundle.main.url(forResource: "FFmpeg_LICENSE", withExtension: "txt", subdirectory: "LICENSES") {
            do {
                ffmpegLicenseText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                ffmpegLicenseText = placeholderLicenseNote
            }
        } else if let url = Bundle.main.url(forResource: "FFmpeg_LICENSE", withExtension: "txt") {
            // fallback: file at root of resources
            ffmpegLicenseText = (try? String(contentsOf: url, encoding: .utf8)) ?? placeholderLicenseNote
        } else {
            ffmpegLicenseText = placeholderLicenseNote
        }
    }
}