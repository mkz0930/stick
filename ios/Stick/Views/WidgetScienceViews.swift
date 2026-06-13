//
//  WidgetScienceViews.swift
//  Widget Gallery 点击跳转的科普界面
//
//  4 个 widget 各对应一个科普页（除了 2 个久坐卡走 SedentaryScienceView）：
//   - PostWorkoutIceWaterScienceView  运动后冰水告警
//   - WalkingScienceView             WALK · 状态卡
//   - SittingScienceView             SIT · 状态卡
//   - SedentaryMoodScienceView       4x2 久坐 + 心情
//
//  每个页面 5 段：当前身体状态 / 科普好坏 / 建议 / 医疗服务 / 硬件产品
//

import SwiftUI

// MARK: - 公共组件

/// 科普页面的统一外壳：背景 + 关闭按钮 + ScrollView
struct SciencePageScaffold<Content: View>: View {
    let bg: Color
    let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(bg: Color = Color(red: 0.96, green: 0.94, blue: 0.88),
         @ViewBuilder content: @escaping () -> Content) {
        self.bg = bg
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                    Spacer(minLength: 30)
                }
                .padding(20)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(red: 0.10, green: 0.15, blue: 0.25)))
                    .overlay(Circle().stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            }
            .padding(16)
        }
    }
}

/// 节标题
struct ScienceSectionLabel: View {
    let emoji: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 18))
            Text(text)
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundColor(color)
        }
    }
}

/// 厚黑边卡片
struct ScienceCard<Content: View>: View {
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5)
            )
    }
}

/// 大序号 + 标题的科普卡（用在 5 大危险 / 5 步科普）
struct ScienceNumberedCard: View {
    let n: String
    let title: String
    let detail: String
    let color: Color
    let emoji: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.system(size: 26, weight: .black, design: .serif))
                .foregroundColor(color)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(emoji).font(.system(size: 16))
                    Text(title)
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 硬件产品模型
struct HardwareProduct: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let tagline: String
    let price: String      // e.g. "¥199"
    let color: Color
}

/// 医疗服务
struct MedicalService: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String        // 心血管内科 / 骨科 / 心理科
    let when: String        // 出现什么症状时建议去
    let color: Color
}

// MARK: - 当前身体状态卡

struct CurrentStateCard: View {
    let stateEmoji: String
    let stateName: String       // 走路 / 坐着 / 睡眠
    let englishName: String
    let summary: String         // 一句话总结
    let metrics: [(String, String)]   // [(标签, 值), ...]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                    Text(stateEmoji).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(stateName)
                            .font(.system(size: 16, weight: .black, design: .serif))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                        Text("· \(englishName)")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(color)
                    }
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            // 3 个数据格
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { idx, m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.0)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(0.8)
                            .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
                        Text(m.1)
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if idx < metrics.count - 1 {
                        Rectangle()
                            .fill(Color(red: 0.10, green: 0.15, blue: 0.25).opacity(0.15))
                            .frame(width: 0.5, height: 28)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - 医疗服务卡

struct MedicalServiceCard: View {
    let service: MedicalService
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(service.color.opacity(0.12))
                Text(service.emoji).font(.system(size: 22))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(service.when)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineLimit(2)
                    .lineSpacing(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
        }
    }
}

// MARK: - 硬件产品卡

struct HardwareProductCard: View {
    let product: HardwareProduct
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(product.color.opacity(0.14))
                    Text(product.emoji).font(.system(size: 22))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                        .lineLimit(1)
                    Text(product.tagline)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                        .lineLimit(2)
                        .lineSpacing(1)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text(product.price)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(product.color)
                Spacer()
                Text("查看详情")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
            }
            .padding(.top, 2)
        }
    }
}

// ===================================================================
// MARK: - 1. 运动后冰水告警
// ===================================================================

struct PostWorkoutIceWaterScienceView: View {
    private let red = Color(red: 0.92, green: 0.22, blue: 0.15)
    private let accent = Color(red: 0.40, green: 0.65, blue: 0.95)
    private let green = Color(red: 0.02, green: 0.59, blue: 0.41)

    /// 5 步因果链
    private let chain: [(String, String, String, String, Color)] = [
        ("01", "猛灌冰水", "口腔/食道/胃瞬间降温 5-10°C", "❄", Color(red: 0.45, green: 0.75, blue: 0.95)),
        ("02", "血管剧缩", "体表 + 胃肠毛细血管急速收缩", "🩸", Color(red: 0.85, green: 0.45, blue: 0.55)),
        ("03", "内脏缺血", "血液被「赶」回内脏，心脏回血骤减", "🫀", Color(red: 0.92, green: 0.34, blue: 0.20)),
        ("04", "心率失常", "迷走神经反射 → 心率 ↓ + 血压 ↓", "⚡", Color(red: 0.92, green: 0.22, blue: 0.15)),
        ("05", "晕厥倒地", "大脑供血不足 → 头晕 / 黑朦 / 摔伤", "💫", Color(red: 0.55, green: 0.10, blue: 0.20)),
    ]

    private let services: [MedicalService] = [
        MedicalService(emoji: "🫀", name: "心血管内科",
                       when: "运动后喝冰水出现胸闷、心悸、眼前发黑",
                       color: Color(red: 0.92, green: 0.34, blue: 0.20)),
        MedicalService(emoji: "🧑‍⚕️", name: "急诊科",
                       when: "已经晕倒、意识模糊、摔伤头部",
                       color: Color(red: 0.85, green: 0.10, blue: 0.30)),
    ]

    private let products: [HardwareProduct] = [
        HardwareProduct(emoji: "🥤", name: "智能保温水杯",
                        tagline: "app 控制温度，运动后只给 35-40°C 温水",
                        price: "¥199 起",
                        color: Color(red: 0.40, green: 0.65, blue: 0.95)),
        HardwareProduct(emoji: "⌚", name: "运动手表",
                        tagline: "实时心率 + 体温异常提醒，运动后自动提示补水",
                        price: "¥899 起",
                        color: Color(red: 0.30, green: 0.55, blue: 0.85)),
    ]

    var body: some View {
        SciencePageScaffold(bg: Color(red: 0.99, green: 0.95, blue: 0.92)) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("⚠").font(.system(size: 22))
                    Text("运动后猛灌冰水 = 晕厥套餐？")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text("去年急诊室收的「运动后晕厥」案例，1/3 是冰水引起的。下面是 5 步因果链。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
            }

            // 当前身体状态
            VStack(alignment: .leading, spacing: 10) {
                ScienceSectionLabel(emoji: "🩺", text: "你当前的身体状态", color: red)
                ScienceCard(color: red) {
                    CurrentStateCard(
                        stateEmoji: "🏃",
                        stateName: "走路中",
                        englishName: "WALKING",
                        summary: "心率偏高 + 体温上升 + 出汗散热中",
                        metrics: [
                            ("心率", "148 bpm"),
                            ("体温", "+1.2°C"),
                            ("水分", "已流失 0.4L"),
                        ],
                        color: red
                    )
                }
            }

            // 5 步因果链
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "⛓", text: "5 步因果链", color: red)
                VStack(spacing: 10) {
                    ForEach(Array(chain.enumerated()), id: \.offset) { _, step in
                        ScienceNumberedCard(
                            n: step.0, title: step.1, detail: step.2,
                            color: step.4, emoji: step.3
                        )
                    }
                }
            }

            // 建议
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "✨", text: "正确做法", color: green)
                VStack(spacing: 10) {
                    tipRow(emoji: "🚰", text: "喝 35-40°C 温水", sub: "不刺激胃肠，心血管零负担。", color: accent)
                    tipRow(emoji: "⏱", text: "运动后 30 分钟再大量喝", sub: "心率降到 100 以下再补水更安全。", color: green)
                    tipRow(emoji: "🧂", text: "加点电解质", sub: "出汗多时只喝水会稀释血钠，更危险。", color: Color(red: 0.95, green: 0.50, blue: 0.05))
                    tipRow(emoji: "🥛", text: "小口慢咽", sub: "一次 100-150ml，每 5 分钟一次。", color: Color(red: 0.55, green: 0.40, blue: 0.95))
                }
            }

            // 医疗服务
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🏥", text: "推荐医疗服务", color: red)
                VStack(spacing: 10) {
                    ForEach(services) { s in
                        ScienceCard(color: s.color) {
                            MedicalServiceCard(service: s)
                        }
                    }
                }
            }

            // 硬件产品
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🛒", text: "推荐硬件产品", color: accent)
                VStack(spacing: 10) {
                    ForEach(products) { p in
                        ScienceCard(color: p.color) {
                            HardwareProductCard(product: p)
                        }
                    }
                }
            }
        }
    }

    private func tipRow(emoji: String, text: String, sub: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(sub).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5))
    }
}

// ===================================================================
// MARK: - 2. WALK 状态卡
// ===================================================================

struct WalkingScienceView: View {
    private let green = Color(red: 0.02, green: 0.59, blue: 0.41)
    private let orange = Color(red: 0.95, green: 0.50, blue: 0.05)
    private let red = Color(red: 0.92, green: 0.22, blue: 0.15)

    private let pros: [(String, String, String, String, Color)] = [
        ("01", "心肺变强", "每天 8000 步，心血管疾病风险 ↓ 51%", "❤️", Color(red: 0.85, green: 0.30, blue: 0.35)),
        ("02", "脑子更灵", "步行的节奏感让前额叶活跃，决策力 ↑ 23%", "🧠", Color(red: 0.55, green: 0.40, blue: 0.95)),
        ("03", "心情更好", "阳光 + 步频 = 内啡肽飙升，焦虑 ↓ 40%", "😊", Color(red: 0.30, green: 0.85, blue: 0.50)),
        ("04", "代谢起飞", "激活棕色脂肪，基础代谢率 ↑ 7%", "🔥", Color(red: 0.95, green: 0.50, blue: 0.05)),
    ]

    private let watchOuts: [(String, String, String, String, Color)] = [
        ("01", "走太多伤膝", "日行 2 万步以上，膝关节软骨磨损 +30%", "🦵", Color(red: 0.92, green: 0.34, blue: 0.20)),
        ("02", "饭后立刻走", "血液集中在胃，影响消化 → 胃下垂风险", "🍚", Color(red: 0.85, green: 0.65, blue: 0.30)),
    ]

    private let services: [MedicalService] = [
        MedicalService(emoji: "🫁", name: "心肺功能评估",
                       when: "想了解自己的有氧能力 / 运动耐量",
                       color: Color(red: 0.30, green: 0.55, blue: 0.85)),
        MedicalService(emoji: "🦴", name: "运动医学科",
                       when: "走路 / 跑步后膝盖、踝关节反复疼痛",
                       color: Color(red: 0.45, green: 0.65, blue: 0.50)),
    ]

    private let products: [HardwareProduct] = [
        HardwareProduct(emoji: "⌚", name: "智能运动手环",
                        tagline: "实时计步 + 心率 + 久坐提醒，目标 8000 步",
                        price: "¥299 起",
                        color: Color(red: 0.30, green: 0.85, blue: 0.50)),
        HardwareProduct(emoji: "👟", name: "智能跑鞋",
                        tagline: "足压传感器 + 步态分析，保护膝盖",
                        price: "¥799 起",
                        color: Color(red: 0.20, green: 0.50, blue: 0.85)),
    ]

    var body: some View {
        SciencePageScaffold(bg: Color(red: 0.94, green: 0.97, blue: 0.92)) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("🚶").font(.system(size: 22))
                    Text("走路是「最便宜的药」")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text("WHO 数据：每周 150 分钟中等强度走路，全因死亡率 ↓ 23%。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
            }

            // 当前状态
            VStack(alignment: .leading, spacing: 10) {
                ScienceSectionLabel(emoji: "🩺", text: "你当前的身体状态", color: green)
                ScienceCard(color: green) {
                    CurrentStateCard(
                        stateEmoji: "🚶",
                        stateName: "散步中",
                        englishName: "WALKING",
                        summary: "心率在好区间 · 心情好 · 步频稳",
                        metrics: [
                            ("心率", "78 bpm"),
                            ("步频", "112 spm"),
                            ("心情", "好"),
                        ],
                        color: green
                    )
                }
            }

            // 4 大好处
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "✅", text: "4 大好处", color: green)
                VStack(spacing: 10) {
                    ForEach(Array(pros.enumerated()), id: \.offset) { _, p in
                        ScienceNumberedCard(n: p.0, title: p.1, detail: p.2, color: p.4, emoji: p.3)
                    }
                }
            }

            // 2 个注意
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "⚠", text: "2 个注意", color: orange)
                VStack(spacing: 10) {
                    ForEach(Array(watchOuts.enumerated()), id: \.offset) { _, w in
                        ScienceNumberedCard(n: w.0, title: w.1, detail: w.2, color: w.4, emoji: w.3)
                    }
                }
            }

            // 建议
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "✨", text: "走路建议", color: green)
                VStack(spacing: 10) {
                    tipRow(emoji: "🎯", text: "每天 8000 步", sub: "WHO 推荐的最低有效剂量。", color: green)
                    tipRow(emoji: "🍱", text: "饭后 30 分钟再走", sub: "避免血液分配冲突。", color: orange)
                    tipRow(emoji: "👟", text: "穿缓冲好的鞋", sub: "硬地面日行 1 万步，膝关节等于跑半马。", color: Color(red: 0.20, green: 0.50, blue: 0.85))
                    tipRow(emoji: "🎵", text: "配节拍 110-130 BPM", sub: "最佳燃脂步频，对应热门流行歌节拍。", color: Color(red: 0.55, green: 0.40, blue: 0.95))
                }
            }

            // 医疗服务
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🏥", text: "推荐医疗服务", color: green)
                VStack(spacing: 10) {
                    ForEach(services) { s in
                        ScienceCard(color: s.color) { MedicalServiceCard(service: s) }
                    }
                }
            }

            // 硬件产品
            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🛒", text: "推荐硬件产品", color: green)
                VStack(spacing: 10) {
                    ForEach(products) { p in
                        ScienceCard(color: p.color) { HardwareProductCard(product: p) }
                    }
                }
            }
        }
    }

    private func tipRow(emoji: String, text: String, sub: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji).font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(sub).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5))
    }
}

// ===================================================================
// MARK: - 3. SIT 状态卡
// ===================================================================

struct SittingScienceView: View {
    private let orange = Color(red: 0.92, green: 0.34, blue: 0.05)
    private let red = Color(red: 0.92, green: 0.22, blue: 0.15)
    private let green = Color(red: 0.02, green: 0.59, blue: 0.41)
    private let blue = Color(red: 0.20, green: 0.50, blue: 0.85)

    private let dangers: [(String, String, String, String, Color)] = [
        ("01", "心血管报废", "每坐 1 小时，血流速度慢 50%", "❤️", Color(red: 0.92, green: 0.34, blue: 0.20)),
        ("02", "腰肌劳损", "腰椎压力比站立时 +40%", "🪑", Color(red: 0.95, green: 0.50, blue: 0.05)),
        ("03", "脑子变慢", "血流变慢 → 大脑供血 ↓ → 反应迟钝", "🧠", Color(red: 0.55, green: 0.40, blue: 0.95)),
        ("04", "血栓堵血管", "久坐 4h，肺栓塞风险 +30%", "🩸", Color(red: 0.85, green: 0.10, blue: 0.30)),
        ("05", "抑郁焦虑", "久坐人群抑郁风险 +31%", "🫥", Color(red: 0.20, green: 0.50, blue: 0.85)),
    ]

    private let services: [MedicalService] = [
        MedicalService(emoji: "🦴", name: "骨科 / 康复科",
                       when: "腰背持续酸痛 2 周以上，腿麻无力",
                       color: Color(red: 0.45, green: 0.65, blue: 0.50)),
        MedicalService(emoji: "🫀", name: "心血管内科",
                       when: "胸闷、气短、久坐后头晕",
                       color: Color(red: 0.92, green: 0.34, blue: 0.20)),
        MedicalService(emoji: "🧠", name: "心理科 / 精神科",
                       when: "长期疲倦、对事情失去兴趣",
                       color: Color(red: 0.55, green: 0.40, blue: 0.95)),
    ]

    private let products: [HardwareProduct] = [
        HardwareProduct(emoji: "🪑", name: "站立办公桌",
                        tagline: "一键升降，每小时站立 15 分钟，腰椎减负 30%",
                        price: "¥899 起",
                        color: Color(red: 0.20, green: 0.50, blue: 0.85)),
        HardwareProduct(emoji: "💆", name: "腰椎按摩仪",
                        tagline: "EMS 脉冲 + 热敷，午休 15 分钟缓解腰肌",
                        price: "¥399 起",
                        color: Color(red: 0.95, green: 0.50, blue: 0.05)),
        HardwareProduct(emoji: "🥤", name: "智能水杯",
                        tagline: "久坐提醒 + 喝水打卡，逼自己每 30 分钟起身",
                        price: "¥199 起",
                        color: Color(red: 0.40, green: 0.65, blue: 0.95)),
    ]

    var body: some View {
        SciencePageScaffold(bg: Color(red: 0.99, green: 0.96, blue: 0.88)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("🪑").font(.system(size: 22))
                    Text("久坐 = 慢性自杀")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text("WHO 把「久坐」列为十大致死致疾元凶之一。下面这些，不是吓你。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                ScienceSectionLabel(emoji: "🩺", text: "你当前的身体状态", color: orange)
                ScienceCard(color: orange) {
                    CurrentStateCard(
                        stateEmoji: "🪑",
                        stateName: "久坐中",
                        englishName: "SITTING",
                        summary: "已连续坐 45 分钟 · 心率偏低 · 腰椎承压",
                        metrics: [
                            ("坐姿", "45 min"),
                            ("心率", "70 bpm"),
                            ("疲劳", "中"),
                        ],
                        color: orange
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "☠", text: "5 大危险", color: red)
                VStack(spacing: 10) {
                    ForEach(Array(dangers.enumerated()), id: \.offset) { _, d in
                        ScienceNumberedCard(n: d.0, title: d.1, detail: d.2, color: d.4, emoji: d.3)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "✨", text: "5 大应对", color: green)
                VStack(spacing: 10) {
                    tipRow(emoji: "⏰", text: "每 30 分钟起身", sub: "哪怕站 1 分钟，血流立刻恢复。", color: orange)
                    tipRow(emoji: "🚶", text: "每小时走 2 分钟", sub: "去倒水、上厕所、看窗外 30 秒。", color: Color(red: 0.95, green: 0.65, blue: 0.05))
                    tipRow(emoji: "🧍", text: "站立办公 15 分钟", sub: "腰椎减负 30%，精力恢复。", color: Color(red: 0.55, green: 0.40, blue: 0.95))
                    tipRow(emoji: "💪", text: "做 5 个深蹲", sub: "激活臀腿，血液重新泵回心脏。", color: blue)
                    tipRow(emoji: "💧", text: "喝杯水", sub: "一举两得：补水 + 逼自己起身去厕所。", color: green)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🏥", text: "推荐医疗服务", color: red)
                VStack(spacing: 10) {
                    ForEach(services) { s in
                        ScienceCard(color: s.color) { MedicalServiceCard(service: s) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🛒", text: "推荐硬件产品", color: blue)
                VStack(spacing: 10) {
                    ForEach(products) { p in
                        ScienceCard(color: p.color) { HardwareProductCard(product: p) }
                    }
                }
            }
        }
    }

    private func tipRow(emoji: String, text: String, sub: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji).font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(sub).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5))
    }
}

// ===================================================================
// MARK: - 4. 4x2 久坐 + 心情
// ===================================================================

struct SedentaryMoodScienceView: View {
    private let orange = Color(red: 0.92, green: 0.34, blue: 0.05)
    private let purple = Color(red: 0.55, green: 0.40, blue: 0.95)
    private let green = Color(red: 0.02, green: 0.59, blue: 0.41)
    private let blue = Color(red: 0.20, green: 0.50, blue: 0.85)

    private let chain: [(String, String, String, String, Color)] = [
        ("01", "身体不动", "血液循环减慢 → 大脑供血 ↓", "🪑", Color(red: 0.92, green: 0.34, blue: 0.05)),
        ("02", "多巴胺 ↓", "运动不足 → 快乐激素分泌减半", "🧪", Color(red: 0.55, green: 0.40, blue: 0.95)),
        ("03", "血清素 ↓", "阳光接触 ↓ → 情绪调节失衡", "☀", Color(red: 0.95, green: 0.65, blue: 0.05)),
        ("04", "皮质醇 ↑", "压力激素持续分泌 → 疲倦 + 易怒", "😤", Color(red: 0.92, green: 0.34, blue: 0.20)),
        ("05", "情绪低落", "对事情失去兴趣 → 抑郁风险 +31%", "😔", Color(red: 0.40, green: 0.20, blue: 0.55)),
    ]

    private let services: [MedicalService] = [
        MedicalService(emoji: "🧠", name: "心理科 / 精神科",
                       when: "持续 2 周以上情绪低落、兴趣丧失",
                       color: Color(red: 0.55, green: 0.40, blue: 0.95)),
        MedicalService(emoji: "🧑‍⚕️", name: "神经内科",
                       when: "长期疲倦、注意力涣散、记忆下降",
                       color: Color(red: 0.20, green: 0.50, blue: 0.85)),
        MedicalService(emoji: "💆", name: "康复理疗科",
                       when: "肩颈僵硬、头痛、睡不好",
                       color: Color(red: 0.30, green: 0.85, blue: 0.50)),
    ]

    private let products: [HardwareProduct] = [
        HardwareProduct(emoji: "🎧", name: "冥想降噪耳机",
                        tagline: "5 分钟引导冥想，呼吸 + 身体扫描",
                        price: "¥499 起",
                        color: Color(red: 0.55, green: 0.40, blue: 0.95)),
        HardwareProduct(emoji: "💡", name: "智能日光灯",
                        tagline: "5000K 冷光上午模拟阳光，调节血清素",
                        price: "¥299 起",
                        color: Color(red: 0.95, green: 0.65, blue: 0.05)),
        HardwareProduct(emoji: "🔊", name: "智能音箱",
                        tagline: "语音引导 5 分钟拉伸 + 呼吸训练",
                        price: "¥199 起",
                        color: Color(red: 0.20, green: 0.50, blue: 0.85)),
    ]

    var body: some View {
        SciencePageScaffold(bg: Color(red: 0.96, green: 0.94, blue: 0.98)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("😔").font(.system(size: 22))
                    Text("久坐的人，为什么越来越不开心？")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text("身体不动 → 心情不好 → 更不想动 → 身体更差。死循环。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                ScienceSectionLabel(emoji: "🩺", text: "你当前的身体状态", color: purple)
                ScienceCard(color: purple) {
                    CurrentStateCard(
                        stateEmoji: "😔",
                        stateName: "久坐 + 疲倦",
                        englishName: "SITTING · TIRED",
                        summary: "心率偏低 · 心情指数 30/100 · 久坐 45 分",
                        metrics: [
                            ("心情", "30/100"),
                            ("坐姿", "45 min"),
                            ("心率", "70 bpm"),
                        ],
                        color: purple
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "⛓", text: "5 步死循环", color: purple)
                VStack(spacing: 10) {
                    ForEach(Array(chain.enumerated()), id: \.offset) { _, c in
                        ScienceNumberedCard(n: c.0, title: c.1, detail: c.2, color: c.4, emoji: c.3)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "✨", text: "破局 5 招", color: green)
                VStack(spacing: 10) {
                    tipRow(emoji: "🧘", text: "5 分钟呼吸", sub: "4-7-8 呼吸法：吸 4 秒、屏 7 秒、呼 8 秒。", color: purple)
                    tipRow(emoji: "☀", text: "走出房间晒 5 分钟", sub: "阳光直接刺激血清素分泌。", color: Color(red: 0.95, green: 0.65, blue: 0.05))
                    tipRow(emoji: "💃", text: "听歌动一动", sub: "120 BPM 节奏，3 分钟就有效。", color: blue)
                    tipRow(emoji: "📞", text: "打给朋友聊 5 分钟", sub: "社会连接是抗抑郁的强效药。", color: green)
                    tipRow(emoji: "✍", text: "写下 3 件感恩的事", sub: "激活前额叶，阻断反刍思维。", color: orange)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🏥", text: "推荐医疗服务", color: purple)
                VStack(spacing: 10) {
                    ForEach(services) { s in
                        ScienceCard(color: s.color) { MedicalServiceCard(service: s) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScienceSectionLabel(emoji: "🛒", text: "推荐硬件产品", color: purple)
                VStack(spacing: 10) {
                    ForEach(products) { p in
                        ScienceCard(color: p.color) { HardwareProductCard(product: p) }
                    }
                }
            }
        }
    }

    private func tipRow(emoji: String, text: String, sub: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji).font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(sub).font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5))
    }
}
