// ios/Stick/Views/MorningReportTab.swift
import SwiftUI

struct MorningReportTab: View {
    @StateObject private var store = MorningReportStore.shared
    @State private var selectedReport: MorningReport?

    var body: some View {
        NavigationStack {
            Group {
                if store.reports.isEmpty {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("报告")
            .navigationDestination(item: $selectedReport) { report in
                MorningReportDetailView(report: report)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("暂无报告")
                .font(.headline)
            Text("每天解锁后自动生成")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reportList: some View {
        List {
            ForEach(store.reports) { report in
                ReportRow(report: report)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedReport = report }
            }
        }
        .listStyle(.plain)
    }
}

struct ReportRow: View {
    let report: MorningReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formattedDate(report.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                scoreBadge
            }
            metricsRow
        }
        .padding(.vertical, 6)
    }

    private var scoreBadge: some View {
        Text("\(report.llmScore)分")
            .font(.headline)
            .foregroundColor(scoreColor)
    }

    private var metricsRow: some View {
        HStack(spacing: 16) {
            Label("\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m", systemImage: "moon.fill")
            Label("\(report.walkMinutes)m", systemImage: "figure.walk")
            Label("\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", systemImage: "chair.fill")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var scoreColor: Color {
        if report.llmScore >= 80 { return .green }
        if report.llmScore >= 60 { return .orange }
        return .red
    }

    private func formattedDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
}