import SwiftUI

extension PreviewTone {
    var color: Color {
        switch self {
        case .accent:
            .accentColor
        case .positive:
            .green
        case .warning:
            .orange
        case .neutral:
            .secondary
        }
    }
}

struct PreviewMarker: View {
    var body: some View {
        Label("Statische Vorschau", systemImage: "eye")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

struct PreviewHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            PreviewMarker()
        }
    }
}

struct PreviewSectionTitle: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
    }
}

struct PreviewMetric: View {
    let label: String
    let value: String
    let tone: PreviewTone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PreviewFlowRow: View {
    let item: PreviewStartData.Flow
    var showsChevron = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .foregroundStyle(item.tone.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(item.count)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct PreviewUpcomingRow: View {
    let item: PreviewStartData.Upcoming

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(item.date)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

struct PreviewOpenDetail: View {
    let item: PreviewStartData.Flow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(item.title, systemImage: item.symbol)
                .font(.headline)
                .foregroundStyle(item.tone.color)
            Text("\(item.count) offene Punkte")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(item.detail)
                .foregroundStyle(.secondary)
            Text("Nur statische Vorschau, keine echte Verknüpfung.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 280, alignment: .leading)
    }
}
