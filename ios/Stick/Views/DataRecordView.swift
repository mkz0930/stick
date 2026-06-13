//
//  DataRecordView.swift
//  数据记录 — 按设计稿重写
//

import SwiftUI
import Combine

@MainActor
final class DataRecordViewModel: ObservableObject {
    @Published var today: [HealthSnapshot] = []
    @Published var insights: [HealthInsight] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        refresh()
        HealthStore.shared.$today
            .receive(on: RunLoop.main)
            .sink { [weak self] snaps in
                guard let self else { return }
                self.today = snaps
                self.insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        HealthStore.shared.refreshToday()
        let snaps = HealthStore.shared.today
        today = snaps
        insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
    }

    var avgHeartRate: Int? {
        let hrs = today.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return Int((hrs.reduce(0, +) / Double(hrs.count)).rounded())
    }

    var totalSteps: Int {
        today.compactMap { $0.stepCount }.reduce(0, +)
    }

    var totalEnergy: Int {
        Int(today.compactMap { $0.activeEnergy }.reduce(0, +).rounded())
    }

    var sleepMinutes: Int {
        let sleeps = today.filter { $0.bodyState == "sleep" }
        guard let first = sleeps.first?.timestamp, let last = sleeps.last?.timestamp else { return 0 }
        return Int(last.timeIntervalSince(first) / 60)
    }
}

struct DataRecordView: View {
    var onClose: () -> Void

    @StateObject private var vm = DataRecordViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        todayInsight
                        dashboardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { vm.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("数据记录")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.navy)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 今日洞察

    private var todayInsight: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日洞察")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text(todayDateString())
                    .font(.system(size: 13))
                    .foregroundColor(Theme.slate)
            }
            Text(insightSummary)
                .font(.system(size: 13))
                .foregroundColor(Theme.slate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }

    private var insightSummary: String {
        "今日步数表现积极，结合周末放松节奏，适度活动有助于身心恢复，继续保持活力！"
    }

    private func todayDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE MM/dd"
        return f.string(from: Date())
    }

    // MARK: - 健康仪表盘

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("健康仪表盘")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                HStack(spacing: 4) {
                    Text("更新于 22:29")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.slate)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.slate)
                }
            }

            VStack(spacing: 10) {
                // 第一行: 睡眠 + 步数
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "moon.zzz.fill",
                        iconColor: Theme.dashSleep,
                        title: "睡眠",
                        sub: "暂无数据",
                        value: "--"
                    )
                    DashboardCard(
                        icon: "figure.walk",
                        iconColor: Theme.dashSteps,
                        title: "步数",
                        sub: "06-13 22:29",
                        value: "\(vm.totalSteps)",
                        valueUnit: "/10000"
                    )
                }

                // 第二行: 运动记录 + 饮食记录
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.run",
                        iconColor: Theme.dashSteps,
                        title: "运动记录",
                        sub: "06-13 08:57",
                        value: "10",
                        valueUnit: "分钟(其他运动)"
                    )
                    DashboardCard(
                        icon: "fork.knife",
                        iconColor: Theme.dashDiet,
                        title: "饮食记录",
                        sub: "暂无数据",
                        value: "--",
                        valueUnit: "kcal/--kcal"
                    )
                }

                // 身材管理 (通栏)
                BodyCard(
                    icon: "figure.arms.open",
                    iconColor: Theme.dashBody,
                    title: "身材管理",
                    sub: "暂无数据"
                )

                // 第三行: 血压 + 血糖
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "drop.fill",
                        iconColor: Theme.dashBlood,
                        title: "血压",
                        sub: "暂无数据",
                        value: "--",
                        valueUnit: "mmHg"
                    )
                    DashboardCard(
                        icon: "drop.fill",
                        iconColor: Theme.dashBlood,
                        title: "血糖",
                        sub: "暂无数据",
                        value: "--",
                        valueUnit: "mmol/L"
                    )
                }
            }
        }
    }
}

// MARK: - DashboardCard

private struct DashboardCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let sub: String
    let value: String
    var valueUnit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.navy)
            }
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Theme.mist)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.navy)
                if !valueUnit.isEmpty {
                    Text(valueUnit)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.slate)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }
}

// MARK: - BodyCard (通栏三栏)

private struct BodyCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.navy)
            }
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Theme.mist)

            HStack(alignment: .top, spacing: 0) {
                bodyColumn("--", "体重/KG")
                Spacer()
                bodyColumn("--", "BMI·暂无")
                Spacer()
                bodyColumn("--", "体脂率·暂无")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }

    private func bodyColumn(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.navy)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.slate)
        }
    }
}

#Preview {
    DataRecordView(onClose: {})
}
