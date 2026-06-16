import Foundation

@MainActor
final class MorningReportStore: ObservableObject {
    static let shared = MorningReportStore()

    @Published private(set) var reports: [MorningReport] = []

    private let reportsDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.reportsDir = docs.appendingPathComponent("MorningReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        loadAll()
    }

    func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: reportsDir, includingPropertiesForKeys: nil) else { return }
        reports = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MorningReport? in
                guard let data = try? Data(contentsOf: url),
                      let report = try? JSONDecoder().decode(MorningReport.self, from: data) else { return nil }
                return report
            }
            .sorted { $0.date > $1.date }
    }

    func save(_ report: MorningReport) {
        let url = reportsDir.appendingPathComponent("\(report.date).json")
        guard let data = try? JSONEncoder().encode(report) else { return }
        try? data.write(to: url, options: .atomic)
        loadAll()
    }

    func load(date: String) -> MorningReport? {
        let url = reportsDir.appendingPathComponent("\(date).json")
        guard let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder().decode(MorningReport.self, from: data) else { return nil }
        return report
    }

    func delete(date: String) {
        let url = reportsDir.appendingPathComponent("\(date).json")
        try? FileManager.default.removeItem(at: url)
        loadAll()
    }

    func cleanupOld() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date())!
        let cutoffStr = Self.dateFormatter.string(from: cutoff)
        reports.filter { $0.date < cutoffStr }.forEach { delete(date: $0.date) }
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
