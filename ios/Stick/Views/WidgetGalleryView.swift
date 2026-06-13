import SwiftUI
import WidgetKit

// MARK: - Widget Gallery
// 调试用：在主 app 内直接渲染 widget 视图的 mock，验证视觉设计。
// 用纯 SwiftUI 重画 widget 内容（不走 ImageRenderer，避开 widget 上下文差异）。

struct WidgetGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    /// 点击任意卡片：关掉 gallery，打开聊天（seed = 预填输入框的文字）
    var onOpenChat: (String) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Widget Gallery")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                        Text("所有 2×2 / 4×2 widget 真机渲染 · 点击卡片打开聊天")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.6))
                    }

                    // 久坐血小板 widget (V3 血管图)
                    VStack(alignment: .leading, spacing: 16) {
                        sectionLabel("久坐血小板 · 点我看「久坐风险」")
                        HStack(spacing: 14) {
                            VStack(spacing: 6) {
                                SedentaryPlateletWidget()
                                    .frame(width: 158, height: 158)
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                                    .onTapGesture {
                                        dismiss()
                                        onOpenChat("久坐风险")
                                    }
                                Text("血小板堆积")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(red: 0.79, green: 0.17, blue: 0.0))
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(white: 0.2)))
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.5)
            .foregroundColor(Color(white: 0.55))
    }
}

// MARK: - WALK 2x2 Mock（跟 StickWidgetView 的 walk 状态一致）

struct WalkWidgetMock: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.88), Color(red: 0.91, green: 0.94, blue: 0.90)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    GalleryPulsingDot(color: Color(red: 0.02, green: 0.59, blue: 0.41))
                        .frame(width: 8, height: 8)
                    Text("WALKING")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Spacer()
                    Text("上午·走着")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                }
                Spacer()
                WalkFigure()
                    .frame(height: 60)
                Text("散步中")
                    .font(.system(size: 13, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                    Text("78")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Text("·")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
                    Text("好心情")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    Spacer()
                }
                Text("心率在好区间")
                    .font(.system(size: 9, weight: .medium))
                    .italic()
                    .foregroundColor(Color(red: 0.02, green: 0.59, blue: 0.41).opacity(0.85))
                    .lineLimit(1)
            }
            .padding(10)
        }
    }
}

// MARK: - SIT 2x2 Mock

struct SitWidgetMock: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.96, blue: 0.88), Color(red: 0.98, green: 0.93, blue: 0.88)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    GalleryPulsingDot(color: Color(red: 0.92, green: 0.34, blue: 0.05))
                        .frame(width: 8, height: 8)
                    Text("SITTING")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Spacer()
                    Text("下午·坐着")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                }
                Spacer()
                SitFigure(showWarn: true)
                    .frame(height: 60)
                Text("久坐中")
                    .font(.system(size: 13, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                    Text("70")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Text("·")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
                    Text("疲倦")
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    Spacer()
                }
                Text("🪑 久坐 45 分")
                    .font(.system(size: 9, weight: .medium))
                    .italic()
                    .foregroundColor(Color(red: 0.92, green: 0.34, blue: 0.05).opacity(0.85))
                    .lineLimit(1)
            }
            .padding(10)
        }
    }
}

// MARK: - RISK 2x2 Mock（腰肌劳损 · 直不起腰 夸张版）

struct RiskWidgetMock: View {
    let minutes: Int
    let level: RiskLevel

    enum RiskLevel { case mid, high }

    private var riskColor: Color {
        switch level {
        case .mid:  return Color(red: 0.96, green: 0.45, blue: 0.05)
        case .high: return Color(red: 0.92, green: 0.22, blue: 0.15)
        }
    }

    private var gradient: [Color] {
        switch level {
        case .mid:  return [Color(red: 1.00, green: 0.96, blue: 0.90), Color(red: 0.98, green: 0.86, blue: 0.80)]
        case .high: return [Color(red: 1.00, green: 0.94, blue: 0.90), Color(red: 0.98, green: 0.82, blue: 0.76)]
        }
    }

    private var levelText: String {
        switch level {
        case .mid:  return minutes >= 75 ? "🚨 腰要断了" : "⚠️ 腰肌劳损"
        case .high: return "🚨 腰要断了"
        }
    }

    private var subtitle: String {
        switch level {
        case .mid:  return minutes >= 75 ? "腰椎间盘在哭泣" : "腰肌开始痉挛"
        case .high: return "直不起腰 · 腰椎在报警"
        }
    }

    private var cta: String {
        switch level {
        case .mid:  return "🚑 站起来 · 甩甩腰"
        case .high: return "🚑 立刻站起来 · 甩腰"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                // 顶 row
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(riskColor)
                    Text(levelText)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(riskColor)
                    Spacer()
                    Text("坐 \(minutes)m")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                }

                // 弯腰火柴人 + 痛点
                HunchedBackFigure(riskColor: riskColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)

                // 文案
                Text("腰肌劳损！")
                    .font(.system(size: 14, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.45, green: 0.10, blue: 0.10))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(riskColor.opacity(0.95))
                    .lineLimit(1)

                Spacer(minLength: 0)

                // CTA
                HStack(spacing: 4) {
                    Text(cta)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(riskColor))
            }
            .padding(8)
        }
    }
}

// MARK: - 弯腰火柴人

struct HunchedBackFigure: View {
    let riskColor: Color
    @State private var phase: Double = 0
    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.8
            let midX = size.width / 2
            let headY: CGFloat = 6
            let pulse = 0.5 + 0.5 * sin(phase * 4.5)
            let sweatPulse = 0.5 + 0.5 * sin(phase * 3.0 + 1.0)
            let boltPulse = 0.5 + 0.5 * sin(phase * 6.0)

            // 头
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 4, y: headY, width: 9, height: 9)), with: .color(stroke))
            // 痛苦表情
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 2.5, y: headY + 4, width: 1, height: 1)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: midX + 0.5, y: headY + 4, width: 1, height: 1)), with: .color(.white))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX - 3, y: headY + 3))
                p.addLine(to: CGPoint(x: midX - 1, y: headY + 3.5))
            }, with: .color(.white), lineWidth: 0.5)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 1, y: headY + 3.5))
                p.addLine(to: CGPoint(x: midX + 3, y: headY + 3))
            }, with: .color(.white), lineWidth: 0.5)

            // 身体 - 弯腰前倾
            let neck = CGPoint(x: midX, y: headY + 9)
            let shoulder = CGPoint(x: midX - 6, y: headY + 13)
            let spine1 = CGPoint(x: midX - 8, y: headY + 20)
            let spine2 = CGPoint(x: midX - 7, y: headY + 27)
            let hip = CGPoint(x: midX - 4, y: headY + 33)
            ctx.stroke(Path { p in
                p.move(to: neck)
                p.addLine(to: shoulder)
                p.addLine(to: spine1)
                p.addLine(to: spine2)
                p.addLine(to: hip)
            }, with: .color(stroke), lineWidth: w)

            // 双手托腰
            ctx.stroke(Path { p in
                p.move(to: spine1)
                p.addLine(to: CGPoint(x: midX - 14, y: headY + 17))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: spine1)
                p.addLine(to: CGPoint(x: midX - 1, y: headY + 17))
            }, with: .color(stroke), lineWidth: w)

            // 腿
            ctx.stroke(Path { p in
                p.move(to: hip)
                p.addLine(to: CGPoint(x: midX + 6, y: headY + 36))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 6, y: headY + 36))
                p.addLine(to: CGPoint(x: midX + 6, y: size.height))
            }, with: .color(stroke), lineWidth: w)

            // 痛点光晕
            let painX = midX - 7
            let painY = headY + 23
            ctx.fill(Path(ellipseIn: CGRect(x: painX - 8, y: painY - 6, width: 16, height: 12)),
                     with: .color(riskColor.opacity(0.25 + 0.15 * pulse)))
            // 中心红点
            ctx.fill(Path(ellipseIn: CGRect(x: painX - 3, y: painY - 3, width: 6, height: 6)),
                     with: .color(riskColor))
            // 周围小点
            for i in 0..<3 {
                let dx: CGFloat = CGFloat(i - 1) * 5
                let dy: CGFloat = CGFloat(i % 2) * 3
                ctx.fill(Path(ellipseIn: CGRect(x: painX + dx - 1.5, y: painY + dy - 1.5, width: 3, height: 3)),
                         with: .color(riskColor.opacity(0.7)))
            }

            // 闪电
            if boltPulse > 0.3 {
                let bx = painX - 16
                let by = painY - 4
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: bx, y: by))
                    p.addLine(to: CGPoint(x: bx - 2, y: by + 2))
                    p.addLine(to: CGPoint(x: bx, y: by + 4))
                    p.addLine(to: CGPoint(x: bx - 2, y: by + 6))
                }, with: .color(riskColor), lineWidth: 1.2)
            }

            // 汗滴
            if sweatPulse > 0.2 {
                ctx.fill(Path(ellipseIn: CGRect(x: midX + 6, y: headY + 2, width: 2.5, height: 3)),
                         with: .color(riskColor.opacity(0.8)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 6.28
            }
        }
    }
}

// MARK: - 4x2 Medium Mock

struct MediumWidgetMock: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 0.97, green: 0.98, blue: 0.99)],
                           startPoint: .top, endPoint: .bottom)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Circle().fill(Color(red: 0.92, green: 0.34, blue: 0.05)).frame(width: 5, height: 5)
                        Text("SITTING")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    }
                    Text("久坐中")
                        .font(.system(size: 14, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Spacer().frame(height: 2)
                    SitFigure(showWarn: false)
                        .frame(width: 60, height: 60)
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                        Text("70")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                        Text("bpm")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    }
                }
                .frame(maxWidth: 95, alignment: .leading)

                Rectangle().fill(Color(red: 0.84, green: 0.86, blue: 0.88)).frame(width: 0.5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 8))
                            .foregroundColor(Color(red: 0.92, green: 0.34, blue: 0.05))
                        Text("心情")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                        Spacer()
                        Text("疲倦")
                            .font(.system(size: 11, weight: .heavy, design: .serif))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    }
                    // 折线
                    MiniSparkline()
                        .frame(height: 30)
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(Color(red: 0.92, green: 0.34, blue: 0.05))
                        Text("久坐 45 分 · 建议起身")
                            .font(.system(size: 9, weight: .semibold, design: .serif))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(red: 0.92, green: 0.34, blue: 0.05), lineWidth: 0.5))
                }
            }
            .padding(10)
        }
    }
}

// MARK: - 辅助：脉冲点

struct GalleryPulsingDot: View {
    let color: Color
    @State private var phase: Double = 0

    private var ringScale: CGFloat {
        let pulse = max(0, 0.5 - abs(phase - 0.5)) * 2
        return 1.0 + 0.6 * pulse
    }

    private var ringOpacity: Double {
        1.0 - phase
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1)
                .frame(width: 12, height: 12)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - 辅助：火柴人图形

struct WalkFigure: View {
    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.6
            let midX = size.width / 2
            // 头
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 6, y: 0, width: 12, height: 12)), with: .color(stroke))
            // 身体
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 12))
                p.addLine(to: CGPoint(x: midX, y: 32))
            }, with: .color(stroke), lineWidth: w)
            // 双臂
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 18))
                p.addLine(to: CGPoint(x: midX - 8, y: 26))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 18))
                p.addLine(to: CGPoint(x: midX + 8, y: 22))
            }, with: .color(stroke), lineWidth: w)
            // 双腿
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 32))
                p.addLine(to: CGPoint(x: midX - 8, y: size.height))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 32))
                p.addLine(to: CGPoint(x: midX + 8, y: size.height))
            }, with: .color(stroke), lineWidth: w)
        }
    }
}

struct SitFigure: View {
    let showWarn: Bool
    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.6
            let midX = size.width / 2
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 6, y: 0, width: 12, height: 12)), with: .color(stroke))
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 12))
                p.addLine(to: CGPoint(x: midX + 4, y: 28))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 4, y: 18))
                p.addLine(to: CGPoint(x: midX + 18, y: 24))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 4, y: 28))
                p.addLine(to: CGPoint(x: midX + 22, y: 28))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 22, y: 28))
                p.addLine(to: CGPoint(x: midX + 22, y: size.height))
            }, with: .color(stroke), lineWidth: w)
            if showWarn {
                ctx.fill(Path(ellipseIn: CGRect(x: midX + 26, y: 0, width: 9, height: 9)),
                         with: .color(Color(red: 0.92, green: 0.34, blue: 0.05).opacity(0.9)))
            }
        }
    }
}

struct RiskFigure: View {
    let riskColor: Color
    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.8
            let midX = size.width / 2
            // 头
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 5, y: 0, width: 10, height: 10)), with: .color(stroke))
            // 身体
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 10))
                p.addLine(to: CGPoint(x: midX + 2, y: 25))
            }, with: .color(stroke), lineWidth: w)
            // 左臂
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX, y: 14))
                p.addLine(to: CGPoint(x: midX - 12, y: 12))
            }, with: .color(stroke), lineWidth: w)
            // 右臂
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 2, y: 16))
                p.addLine(to: CGPoint(x: midX + 12, y: 22))
            }, with: .color(stroke), lineWidth: w)
            // 大腿
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 2, y: 25))
                p.addLine(to: CGPoint(x: midX + 18, y: 25))
            }, with: .color(stroke), lineWidth: w)
            // 小腿
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 18, y: 25))
                p.addLine(to: CGPoint(x: midX + 18, y: size.height))
            }, with: .color(stroke), lineWidth: w)
            // 警告光晕
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 16, y: 18, width: 18, height: 12)),
                     with: .color(riskColor.opacity(0.22)))
            // 血小板点
            for i in 0..<4 {
                let px = midX - 13 + CGFloat(i) * 4
                let py = 22 + CGFloat(i % 2) * 4
                ctx.fill(Path(ellipseIn: CGRect(x: px, y: py, width: 2.5, height: 2.5)), with: .color(riskColor))
            }
        }
    }
}

struct MiniSparkline: View {
    var body: some View {
        Canvas { ctx, size in
            let accent = Color(red: 0.92, green: 0.34, blue: 0.05)
            let midY = size.height * 0.5
            let amp = size.height * 0.4
            let points: [Double] = [0.45, 0.50, 0.48, 0.42, 0.40, 0.38, 0.35, 0.30]
            let stepX = size.width / CGFloat(points.count - 1)
            var path = Path()
            for (i, v) in points.enumerated() {
                let x = CGFloat(i) * stepX
                let y = midY - CGFloat(v - 0.5) * 2 * amp
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            // 末点
            let lastX = size.width
            let lastY = midY - CGFloat(0.30 - 0.5) * 2 * amp
            ctx.fill(Path(ellipseIn: CGRect(x: lastX - 3.5, y: lastY - 3.5, width: 7, height: 7)), with: .color(accent))
            ctx.fill(Path(ellipseIn: CGRect(x: lastX - 1.5, y: lastY - 1.5, width: 3, height: 3)), with: .color(.white))
        }
    }
}

// MARK: - 腰断了 Widget（聊骚夸张版 · 红橙渐变）

struct BrokenBackWidget: View {
    @State private var phase: Double = 0

    private var gradient: [Color] {
        [Color(red: 1.0, green: 0.85, blue: 0.71), Color(red: 1.0, green: 0.48, blue: 0.30)]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                // 顶栏
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(red: 0.79, green: 0.17, blue: 0.0))
                    Text("腰断了")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(Color(red: 0.79, green: 0.17, blue: 0.0))
                    Spacer()
                }

                // 弯腰火柴人
                BrokenBackFigure(phase: phase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)

                // CTA
                Text("腰疼怎么办")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 0.79, green: 0.17, blue: 0.0))
                    )
            }
            .padding(10)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 6.28
            }
        }
    }
}

// MARK: - 弯腰断腰火柴人

struct BrokenBackFigure: View {
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 2.0
            let midX = size.width / 2
            let pulse = 0.5 + 0.5 * sin(phase * 4.5)
            let sweatPulse = 0.5 + 0.5 * sin(phase * 3.0 + 1.0)
            let boltPulse = 0.5 + 0.5 * sin(phase * 6.0)

            // 头 (弯腰前倾)
            let headX = midX - 18
            let headY: CGFloat = 2
            ctx.fill(Path(ellipseIn: CGRect(x: headX - 7, y: headY, width: 14, height: 14)), with: .color(Color(red: 1.0, green: 0.88, blue: 0.71)))
            ctx.stroke(Path(ellipseIn: CGRect(x: headX - 7, y: headY, width: 14, height: 14)), with: .color(stroke), lineWidth: 2)

            // 痛苦表情
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: headX - 5, y: headY + 4))
                p.addLine(to: CGPoint(x: headX - 2, y: headY + 6))
            }, with: .color(stroke), lineWidth: 1.5)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: headX + 2, y: headY + 6))
                p.addLine(to: CGPoint(x: headX + 5, y: headY + 4))
            }, with: .color(stroke), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: headX - 3, y: headY + 9, width: 6, height: 5)), with: .color(stroke))

            // 颈 → 肩膀
            let neckX = headX - 2
            let neckY = headY + 14
            let shoulderX = midX - 20
            let shoulderY = headY + 20
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: neckX, y: neckY))
                p.addLine(to: CGPoint(x: shoulderX, y: shoulderY))
            }, with: .color(stroke), lineWidth: w)

            // 上半身 (前倾)
            let spineX = midX - 24
            let spineY = headY + 30
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: shoulderX, y: shoulderY))
                p.addLine(to: CGPoint(x: spineX, y: spineY))
            }, with: .color(stroke), lineWidth: w)

            // 双手抱腰
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: spineX, y: spineY - 5))
                p.addCurve(to: CGPoint(x: spineX - 10, y: spineY + 8),
                           control1: CGPoint(x: spineX - 15, y: spineY - 2),
                           control2: CGPoint(x: spineX - 14, y: spineY + 5))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: spineX, y: spineY - 5))
                p.addCurve(to: CGPoint(x: spineX + 8, y: spineY + 8),
                           control1: CGPoint(x: spineX + 12, y: spineY - 2),
                           control2: CGPoint(x: spineX + 10, y: spineY + 5))
            }, with: .color(stroke), lineWidth: w)

            // === 腰断点 ===
            let breakX = spineX
            let breakY = spineY

            // 断点光晕
            ctx.fill(Path(ellipseIn: CGRect(x: breakX - 12, y: breakY - 8, width: 24, height: 16)),
                     with: .color(Color(red: 1.0, green: 0.3, blue: 0.18).opacity(0.3 + 0.15 * pulse)))

            // 断点红圆
            ctx.fill(Path(ellipseIn: CGRect(x: breakX - 8, y: breakY - 6, width: 16, height: 12)),
                     with: .color(Color(red: 1.0, green: 0.3, blue: 0.18)))
            ctx.stroke(Path(ellipseIn: CGRect(x: breakX - 8, y: breakY - 6, width: 16, height: 12)),
                       with: .color(stroke), lineWidth: 2)

            // X 断裂线
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: breakX - 5, y: breakY - 4))
                p.addLine(to: CGPoint(x: breakX + 5, y: breakY + 4))
            }, with: .color(.white), lineWidth: 2)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: breakX + 5, y: breakY - 4))
                p.addLine(to: CGPoint(x: breakX - 5, y: breakY + 4))
            }, with: .color(.white), lineWidth: 2)

            // 骨头碎片
            ctx.fill(Path(ellipseIn: CGRect(x: breakX + 8, y: breakY - 10, width: 4, height: 4)),
                     with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: breakX - 14, y: breakY - 8, width: 3, height: 3)),
                     with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: breakX + 10, y: breakY + 6, width: 2.5, height: 2.5)),
                     with: .color(.white))

            // 下半身 (瘫软)
            let hipX = breakX + 6
            let hipY = breakY + 6
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: breakX + 4, y: breakY + 4))
                p.addLine(to: CGPoint(x: hipX, y: hipY))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: hipX, y: hipY))
                p.addLine(to: CGPoint(x: hipX + 8, y: hipY + 20))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: hipX, y: hipY))
                p.addLine(to: CGPoint(x: hipX + 16, y: hipY + 18))
            }, with: .color(stroke), lineWidth: w)

            // 汗滴
            if sweatPulse > 0.3 {
                ctx.fill(Path { p in
                    p.move(to: CGPoint(x: headX + 16, y: headY))
                    p.addQuadCurve(to: CGPoint(x: headX + 14, y: headY + 8),
                                   control: CGPoint(x: headX + 18, y: headY + 4))
                    p.addQuadCurve(to: CGPoint(x: headX + 16, y: headY),
                                   control: CGPoint(x: headX + 12, y: headY + 4))
                }, with: .color(Color(red: 0.31, green: 0.76, blue: 0.97)))
            }

            // 闪电
            if boltPulse > 0.4 {
                let bx = headX - 20
                let by = headY + 2
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: bx, y: by))
                    p.addLine(to: CGPoint(x: bx + 4, y: by + 6))
                    p.addLine(to: CGPoint(x: bx + 1, y: by + 8))
                    p.addLine(to: CGPoint(x: bx + 5, y: by + 14))
                }, with: .color(Color(red: 1.0, green: 0.85, blue: 0.24)), lineWidth: 2)
            }

            // 痛气泡
            let bubbleX = midX + 20
            let bubbleY = headY + 10
            ctx.fill(Path(ellipseIn: CGRect(x: bubbleX - 22, y: bubbleY - 8, width: 44, height: 20)),
                     with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: bubbleX - 22, y: bubbleY - 8, width: 44, height: 20)),
                       with: .color(stroke), lineWidth: 1.5)
        }
    }
}

// MARK: - 久坐血小板 Widget (V3 血管图 · 跟 widget-platelet-v3.html 完全一致)

struct SedentaryPlateletWidget: View {
    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.97, blue: 0.91)   // #FFF7E8

            VStack(spacing: 14) {
                // 标题区: 久坐大字
                Text("久坐")
                    .font(.system(size: 56, weight: .black))
                    .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .tracking(-2)

                // 血管 + 血小板 (跟 widget extension 用同一份设计)
                PlateletVessel()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2/1, contentMode: .fit)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - 血管 + 血小板 Canvas (跟 widget extension 里 VesselCanvas 一致)

struct PlateletVessel: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let SVG_W: CGFloat = 320
                let SVG_H: CGFloat = 160

                let scaleX = size.width / SVG_W
                let scaleY = size.height / SVG_H
                let scale = min(scaleX, scaleY)

                func sx(_ x: CGFloat) -> CGFloat { x * scale }
                func sy(_ y: CGFloat) -> CGFloat { y * scale }
                let sw: (CGFloat) -> CGFloat = { $0 * scale }

                let dark         = Color(red: 0.10, green: 0.10, blue: 0.12)
                let vesselFill   = Color(red: 1.0,  green: 0.89, blue: 0.82)  // #FFE4D0
                let vesselInner  = Color(red: 1.0,  green: 0.80, blue: 0.66)  // #FFCBA8
                let plateletRed  = Color(red: 1.0,  green: 0.30, blue: 0.18)  // #FF4D2E
                let clotRed      = Color(red: 0.79, green: 0.16, blue: 0.0)   // #C92A00

                // ── 血管外壁 ──
                let outer = Path { p in
                    p.move(to: CGPoint(x: sx(20), y: sy(100)))
                    p.addLine(to: CGPoint(x: sx(20), y: sy(70)))
                    p.addQuadCurve(to: CGPoint(x: sx(35), y: sy(55)),
                                   control: CGPoint(x: sx(20),  y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(285), y: sy(55)))
                    p.addQuadCurve(to: CGPoint(x: sx(300), y: sy(70)),
                                   control: CGPoint(x: sx(300), y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(300), y: sy(130)))
                    p.addQuadCurve(to: CGPoint(x: sx(285), y: sy(145)),
                                   control: CGPoint(x: sx(300), y: sy(145)))
                    p.addLine(to: CGPoint(x: sx(35), y: sy(145)))
                    p.addQuadCurve(to: CGPoint(x: sx(20), y: sy(130)),
                                   control: CGPoint(x: sx(20),  y: sy(145)))
                    p.closeSubpath()
                }
                ctx.fill(outer, with: .color(vesselFill))
                ctx.stroke(outer, with: .color(dark), lineWidth: sw(3.5))

                // ── 血管内壁 ──
                let inner = Path { p in
                    p.move(to: CGPoint(x: sx(32), y: sy(100)))
                    p.addLine(to: CGPoint(x: sx(32), y: sy(77)))
                    p.addLine(to: CGPoint(x: sx(288), y: sy(77)))
                    p.addLine(to: CGPoint(x: sx(288), y: sy(123)))
                    p.addLine(to: CGPoint(x: sx(32), y: sy(123)))
                    p.closeSubpath()
                }
                ctx.fill(inner, with: .color(vesselInner))

                // ── 时间刻度线 + 标签 ──
                let markers: [(x: CGFloat, label: String, isWarn: Bool)] = [
                    (55,  "0'",   false),
                    (115, "30'",  false),
                    (175, "60'",  false),
                    (235, "90'",  false),
                    (280, "120'", true),
                ]
                for m in markers {
                    let x = sx(m.x)
                    let color = m.isWarn ? plateletRed : dark.opacity(0.3)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: sy(55)))
                    line.addLine(to: CGPoint(x: x, y: sy(145)))
                    ctx.stroke(line, with: .color(color),
                               style: StrokeStyle(lineWidth: m.isWarn ? sw(1.5) : sw(1),
                                                   dash: [sw(2), sw(3)]))

                    let label = Text(m.label)
                        .font(.system(size: 11 * scaleX, weight: m.isWarn ? .heavy : .bold,
                                     design: .monospaced))
                        .foregroundColor(m.isWarn ? plateletRed : dark.opacity(0.6))
                    ctx.draw(label, at: CGPoint(x: x, y: sy(48)), anchor: .center)

                    if m.x == 55 {
                        let normalLabel = Text("正常")
                            .font(.system(size: 9 * scaleX, weight: .bold, design: .monospaced))
                            .foregroundColor(dark.opacity(0.5))
                        ctx.draw(normalLabel, at: CGPoint(x: x, y: sy(158)), anchor: .center)
                    }
                }

                // ── 血小板: 0' 1 颗, 30' 3 颗, 60' 6 颗, 90' 10 颗, 120' 10 颗血栓 + 标 ──
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(53),  y: sy(100)), r: sw(6),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(115), y: sy(93)),  r: sw(5.5), color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(127), y: sy(105)), r: sw(5),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(103), y: sy(103)), r: sw(4.5), color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(175), y: sy(90)),  r: sw(5),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(187), y: sy(100)), r: sw(5.5), color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(180), y: sy(110)), r: sw(5),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(167), y: sy(100)), r: sw(4),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(195), y: sy(95)),  r: sw(4),   color: plateletRed, scale: scaleX)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(165), y: sy(110)), r: sw(3.5), color: plateletRed, scale: scaleX)

                let pos90: [(CGFloat, CGFloat, CGFloat)] = [
                    (235, 88, 5), (247, 96, 5), (230, 98, 5), (252, 106, 5),
                    (240, 105, 4.5), (225, 105, 3.5), (256, 98, 3.5), (234, 110, 3), (249, 90, 3), (243, 98, 4)
                ]
                for (px, py, pr) in pos90 {
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(pr), color: plateletRed, scale: scaleX)
                }

                let clot: [(CGFloat, CGFloat, CGFloat)] = [
                    (278, 85, 4.5), (285, 93, 4.5), (280, 100, 5), (286, 105, 4.5),
                    (278, 110, 4.5), (288, 110, 3.5), (290, 100, 3), (284, 89, 3), (292, 108, 2.5), (295, 96, 2.5)
                ]
                for (px, py, pr) in clot {
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(pr), color: clotRed, scale: scaleX)
                }

                // ── 血栓! 爆炸标 ──
                let badgeCenter = CGPoint(x: sx(285), y: sy(100))
                let badgeR = sw(26)
                let badge = Path(ellipseIn: CGRect(
                    x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR,
                    width: badgeR * 2, height: badgeR * 2))
                ctx.fill(badge, with: .color(plateletRed))
                ctx.stroke(badge, with: .color(dark), lineWidth: sw(3.5))
                let badgeText = Text("血栓!")
                    .font(.system(size: 16 * scaleX, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                ctx.draw(badgeText, at: CGPoint(x: badgeCenter.x, y: badgeCenter.y + sw(2)), anchor: .center)
            }
        }
    }

    private func drawPlatelet(ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color, scale: CGFloat) {
        let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(Color(red: 0.10, green: 0.10, blue: 0.12)),
                   lineWidth: max(1, 2 * scale))
    }
}
