import SwiftUI

struct StartView: View {
    @State private var selectedOpenItem: PreviewStartData.Flow?

    private let data = PreviewStartData.sample

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PreviewHeader(title: "Start", subtitle: data.year)

                    if proxy.size.width < 760 {
                        VStack(spacing: 12) {
                            metric(label: "Einnahmen", value: data.incomeText, tone: .positive)
                            metric(label: "Ausgaben", value: data.expenseText, tone: .warning)
                            metric(label: "Ergebnis", value: data.resultText, tone: .accent)
                        }
                    } else {
                        HStack(spacing: 12) {
                            metric(label: "Einnahmen", value: data.incomeText, tone: .positive)
                            metric(label: "Ausgaben", value: data.expenseText, tone: .warning)
                            metric(label: "Ergebnis", value: data.resultText, tone: .accent)
                        }
                    }

                    if proxy.size.width < 760 {
                        VStack(alignment: .leading, spacing: 28) {
                            openSection
                            upcomingSection
                        }
                    } else {
                        HStack(alignment: .top, spacing: 32) {
                            openSection
                            upcomingSection
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Start")
        .navigationSubtitle(Text("Statische Jahresübersicht"))
    }

    private func metric(label: String, value: String, tone: PreviewTone) -> some View {
        PreviewMetric(label: label, value: value, tone: tone)
    }

    private var openSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionTitle("Offen", detail: "12 Einträge")
            ForEach(data.openItems) { item in
                Button {
                    selectedOpenItem = item
                } label: {
                    PreviewFlowRow(item: item, showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(item: $selectedOpenItem) { selectedItem in
            PreviewOpenDetail(item: selectedItem)
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreviewSectionTitle("Anstehend", detail: "eigene Beispieltermine")
            ForEach(data.upcoming) { item in
                PreviewUpcomingRow(item: item)
            }
            Text("Nicht aus gesetzlichen Fristen abgeleitet.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
