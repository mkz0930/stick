import SwiftUI

// MARK: - 数据模型（从 widget URL 解析）

struct WidgetRiskAlertData: Identifiable {
    let id = UUID()
    let sitDurationMinutes: Int
    let heartRate: Int
}

// MARK: - 久坐风险告警 Sheet

struct WidgetRiskAlertSheet: View {
    let data: WidgetRiskAlertData

    private var riskLevel: (label: String, color: Color, emoji: String) {
        let min = data.sitDurationMinutes
        if min >= 75 { return ("严重 · 腰要断了", Color(red: 0.82, green: 0.10, blue: 0.10), "🚨") }
        if min >= 60 { return ("高 · 腰肌劳损", Color(red: 0.92, green: 0.22, blue: 0.15), "⚠️") }
        if min >= 45 { return ("中 · 腰开始抗议", Color(red: 0.96, green: 0.45, blue: 0.05), "⚠") }
        if min >= 30 { return ("低 · 该动动了", Color(red: 0.95, green: 0.65, blue: 0.05), "⏰") }
        return ("轻微", Color(red: 0.95, green: 0.70, blue: 0.10), "⏰")
    }

    private var bodyText: String {
        let min = data.sitDurationMinutes
        if min >= 75 {
            return "你已经连续坐了 \(min) 分钟！\n腰椎间盘正在哭泣 😢\n椎间盘承受的压力是站姿的 3 倍以上！\n请立即站起来活动！"
        }
        if min >= 60 {
            return "你已经坐了 \(min) 分钟！\n腰肌开始疲劳，腰椎在报警 🚨\n久坐会让腰椎间盘压力升高 40%！"
        }
        if min >= 45 {
            return "已经 \(min) 分钟没起来动了！\n腰肌开始痉挛，血液不流通 ⚠️\n每坐 45 分钟就该起来走走！"
        }
        if min >= 30 {
            return "你已经坐了 \(min) 分钟！\n久坐族请注意 ⏰\n持续久坐会让下肢血流速度降低 50%！"
        }
        return "你已经坐了 \(min) 分钟。\n别让久坐成为习惯，站起来走走吧！"
    }

    private var recommendations: [String] {
        let min = data.sitDurationMinutes
        if min >= 75 {
            return [
                "立刻站起来，离开座位 5-10 分钟",
                "甩甩腰，做米字操 1 分钟",
                "喝一杯水，补充水分",
                "接下来每 30 分钟强制起身一次",
                "下班后热敷腰部 15 分钟",
            ]
        } else if min >= 60 {
            return [
                "站起来活动 3-5 分钟",
                "做腰部拉伸：双手叉腰向后仰",
                "调整坐姿：腰靠椅背，脚掌着地",
            ]
        } else if min >= 45 {
            return [
                "站起来伸个懒腰",
                "原地踏步 30 秒，促进血液循环",
            ]
        } else {
            return [
                "站起来活动一下",
                "眺望远方 20 秒，放松眼睛",
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 顶部风险条
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(riskLevel.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Text(riskLevel.emoji)
                                .font(.system(size: 28))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("久坐风险")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundColor(Theme.slate)
                                Text(riskLevel.label)
                                    .font(.system(size: 16, weight: .heavy, design: .serif))
                                    .foregroundColor(riskLevel.color)
                            }
                            Text("持续坐 \(data.sitDurationMinutes) 分钟 · 心率 \(data.heartRate) bpm")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.slate)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(riskLevel.color.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(riskLevel.color.opacity(0.4), lineWidth: 1)
                    )

                    // 身体数据
                    sectionHeader("当前数据")
                    dataRow("持续久坐", "\(data.sitDurationMinutes) 分钟")
                    dataRow("心率", "\(data.heartRate) bpm")

                    // AI 分析
                    sectionHeader("风险提示")
                    Text(bodyText)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundColor(Theme.navy)
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    // 建议
                    sectionHeader("建议")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(recommendations.enumerated()), id: \.offset) { idx, rec in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundColor(riskLevel.color)
                                    .frame(width: 20, alignment: .trailing)
                                Text(rec)
                                    .font(.system(size: 13, weight: .regular, design: .serif))
                                    .foregroundColor(Theme.navy)
                                    .lineSpacing(3)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    Text("⚠️ 本提示仅供参考，如有持续不适请咨询专业医师。")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("久坐风险")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Theme.slate)
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
        .padding(.top, 4)
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(Theme.slate)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.navy)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

#Preview {
    WidgetRiskAlertSheet(data: WidgetRiskAlertData(sitDurationMinutes: 60, heartRate: 78))
}
