import SwiftUI

// MARK: - 本地调色板（不属于 Theme，仅心率红用）
private extension Color {
    /// 心率红 (心率卡 / 心率行)
    static let detailHeartRed = Color(red: 0.86, green: 0.21, blue: 0.27)
}

// MARK: - 步态详情 sheet

struct WalkDetailSheet: View {
    let steps: Int
    let walkMinutes: Int
    let avgSpeed: Double?
    let gaitScore: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 步数卡片
                    DetailMetricCard(
                        title: "今日步数",
                        value: "\(steps)",
                        unit: "步",
                        icon: "figure.walk",
                        color: Theme.stateWalk
                    )

                    // 行走时长卡片
                    DetailMetricCard(
                        title: "行走时长",
                        value: "\(walkMinutes)",
                        unit: "分钟",
                        icon: "clock.fill",
                        color: Theme.stateWalk
                    )

                    // 平均步速卡片
                    DetailMetricCard(
                        title: "平均步速",
                        value: avgSpeed.map { String(format: "%.2f", $0) } ?? "--",
                        unit: "m/s",
                        icon: "speedometer",
                        color: Theme.stateWalk
                    )

                    // 步态评分卡片
                    DetailMetricCard(
                        title: "步态评分",
                        value: "\(gaitScore)",
                        unit: "/ 100",
                        icon: "star.fill",
                        color: Theme.stateWalk
                    )
                }
                .padding()
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("步态详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 久坐详情 sheet

struct SitDetailSheet: View {
    let sedentaryMinutes: Int
    let heartRate: Int?
    let bodyScore: Double

    private var formattedDuration: String {
        if sedentaryMinutes >= 60 {
            let h = sedentaryMinutes / 60
            let m = sedentaryMinutes % 60
            return "\(h)h\(m)m"
        }
        return "\(sedentaryMinutes) 分钟"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 累计久坐时长
                    DetailMetricCard(
                        title: "累计久坐",
                        value: formattedDuration,
                        unit: "",
                        icon: "chair.fill",
                        color: Theme.stateSit
                    )

                    // 当前心率
                    DetailMetricCard(
                        title: "心率",
                        value: heartRate.map { "\($0)" } ?? "--",
                        unit: "bpm",
                        icon: "heart.fill",
                        color: Color.detailHeartRed
                    )

                    // 身体状态评分
                    DetailMetricCard(
                        title: "身体状态",
                        value: "\(Int(bodyScore))",
                        unit: "/ 100",
                        icon: "bolt.fill",
                        color: Theme.dashSedentary
                    )
                }
                .padding()
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("久坐详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 睡眠详情 sheet

struct SleepDetailSheet: View {
    let sleepHours: Double
    let sleepQualityLabel: String
    let nightWakeCount: Int
    let nightWakeTotalMin: Int

    private var formattedSleep: String {
        let h = Int(sleepHours)
        let m = Int((sleepHours - Double(h)) * 60)
        return "\(h)h\(String(format: "%02d", m))m"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 睡眠时长卡片
                    DetailMetricCard(
                        title: "睡眠时长",
                        value: formattedSleep,
                        unit: "",
                        icon: "bed.double.fill",
                        color: Theme.stateSleep
                    )

                    // 睡眠质量标签
                    DetailMetricCard(
                        title: "睡眠质量",
                        value: sleepQualityLabel,
                        unit: "",
                        icon: "moon.stars.fill",
                        color: Theme.stateSleep
                    )

                    // 夜间清醒次数
                    DetailMetricCard(
                        title: "夜间清醒",
                        value: "\(nightWakeCount)",
                        unit: "次",
                        icon: "eye.fill",
                        color: Theme.stateSleep
                    )

                    // 夜间清醒总时长
                    DetailMetricCard(
                        title: "清醒时长",
                        value: "\(nightWakeTotalMin)",
                        unit: "分钟",
                        icon: "clock.fill",
                        color: Theme.stateSleep
                    )
                }
                .padding()
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("睡眠详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 通用 DetailMetricCard 组件

struct DetailMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
            }

            // 标题和数值
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.slate)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.navy)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.slate)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

#Preview("Walk") {
    WalkDetailSheet(steps: 8234, walkMinutes: 45, avgSpeed: 1.2, gaitScore: 82)
}

#Preview("Sit") {
    SitDetailSheet(sedentaryMinutes: 320, heartRate: 78, bodyScore: 55)
}

#Preview("Sleep") {
    SleepDetailSheet(sleepHours: 7.5, sleepQualityLabel: "良好", nightWakeCount: 2, nightWakeTotalMin: 15)
}
