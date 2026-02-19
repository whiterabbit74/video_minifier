import SwiftUI

struct StatisticsView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text(NSLocalizedString("Статистика", comment: ""))
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: NSLocalizedString("ТЕКУЩАЯ СЕССИЯ", comment: ""), icon: "clock.fill")

                    StatsGrid {
                        StatCard(title: NSLocalizedString("Всего", comment: ""), value: "\(viewModel.videoFiles.count)", icon: "film.fill", color: .blue)
                        StatCard(title: NSLocalizedString("Готово", comment: ""), value: "\(viewModel.fileCount(withStatus: .completed))", icon: "checkmark.circle.fill", color: .green)
                        StatCard(title: NSLocalizedString("В очереди", comment: ""), value: "\(viewModel.fileCount(withStatus: .pending))", icon: "clock.fill", color: .orange)
                        StatCard(title: NSLocalizedString("Ошибки", comment: ""), value: "\(failedCount)", icon: "xmark.octagon.fill", color: .red)
                    }
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: NSLocalizedString("РАЗМЕРЫ", comment: ""), icon: "internaldrive.fill")

                    VStack(spacing: 1) {
                        SizeRow(title: NSLocalizedString("Исходный", comment: ""), value: ByteCountFormatter.string(fromByteCount: viewModel.totalOriginalSize, countStyle: .file))
                        SizeRow(title: NSLocalizedString("Сжатый", comment: ""), value: ByteCountFormatter.string(fromByteCount: viewModel.totalCompressedSize, countStyle: .file))
                        SizeRow(title: NSLocalizedString("Экономия", comment: ""), value: savedSizeText)
                        SizeRow(title: NSLocalizedString("Сжатие", comment: ""), value: compressionRatioText)
                    }
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }

    private var failedCount: Int {
        viewModel.videoFiles.reduce(0) { partial, file in
            if case .failed = file.status {
                return partial + 1
            }
            return partial
        }
    }

    private var savedSizeText: String {
        let saved = max(Int64(0), viewModel.totalOriginalSize - viewModel.totalCompressedSize)
        return ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)
    }

    private var compressionRatioText: String {
        guard let ratio = viewModel.overallCompressionRatio else { return "-" }
        return String(format: "%.1f%%", ratio)
    }
}

private struct StatsGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14))
                Spacer()
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct SizeRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
