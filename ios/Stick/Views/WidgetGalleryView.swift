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

// MARK: - 久坐血小板 Widget (V3 血管图)

struct SedentaryPlateletWidget: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.97, blue: 0.91)   // #FFF7E8

            VStack(spacing: 0) {
                // 顶栏: 久坐标题 + 提醒
                HStack {
                    Text("久坐")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Spacer()
                    Text("120' 血栓!")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.30, blue: 0.18))
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                // 血管 + 血小板
                PlateletVessel(phase: phase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 6.28
            }
        }
    }
}

// MARK: - 血管 + 血小板 Canvas

struct PlateletVessel: View {
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let pulse = 0.5 + 0.5 * sin(phase * 3.0)
            let throbPulse = 0.5 + 0.5 * sin(phase * 5.0)

            // 血管外壁 (左上角略圆, 右上角略圆, 右下角略圆, 左下角略圆)
            let vesselH: CGFloat = 44
            let vesselY = size.height * 0.30
            let vesselRect = CGRect(x: 8, y: vesselY, width: size.width - 16, height: vesselH)
            let outerPath = Path(roundedRect: vesselRect, cornerRadius: 6)
            ctx.fill(outerPath, with: .color(Color(red: 1.0, green: 0.89, blue: 0.82)))
            ctx.stroke(outerPath, with: .color(stroke), lineWidth: 1.5)

            // 血管内壁
            let innerRect = vesselRect.insetBy(dx: 4, dy: 6)
            let innerPath = Path(roundedRect: innerRect, cornerRadius: 4)
            ctx.fill(innerPath, with: .color(Color(red: 1.0, green: 0.80, blue: 0.66)))

            // 时间刻度 (0', 30', 60', 90', 120')
            let ticks = [(0, "0'"), (15, "30'"), (40, "60'"), (65, "90'"), (88, "120'")]
            for (i, tick) in ticks.enumerated() {
                let xRatio = CGFloat(tick.0) / 100.0
                let x = 8 + (size.width - 16) * xRatio
                let isCritical = tick.1 == "120'"
                let tickColor = isCritical ? Color(red: 1.0, green: 0.30, blue: 0.18) : stroke.opacity(0.3)
                let lineWidth: CGFloat = isCritical ? 1.0 : 0.5
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: vesselY - 4))
                    p.addLine(to: CGPoint(x: x, y: vesselY + vesselH + 4))
                }, with: .color(tickColor), style: StrokeStyle(lineWidth: lineWidth, dash: [1.5, 2]))
            }

            // 时间标签
            let labelY = vesselY - 7
            let fontSize: CGFloat = 7
            for tick in ticks {
                let xRatio = CGFloat(tick.0) / 100.0
                let x = 8 + (size.width - 16) * xRatio
                let isCritical = tick.1 == "120'"
                let labelColor = isCritical ? Color(red: 1.0, green: 0.30, blue: 0.18) : stroke.opacity(0.6)
                let text = Text(tick.1)
                    .font(.system(size: fontSize, weight: isCritical ? .black : .bold, design: .monospaced))
                    .foregroundColor(labelColor)
                ctx.draw(text, at: CGPoint(x: x, y: labelY))
            }

            // 血小板 - 0' 位置: 1 颗
            drawPlatelet(ctx: ctx, stroke: stroke,
                         pos: CGPoint(x: 8 + (size.width - 16) * 0.0, y: vesselY + vesselH/2),
                         radius: 4)

            // 血小板 - 30' 位置: 3 颗
            let x30 = 8 + (size.width - 16) * 0.15
            drawPlatelet(ctx: ctx, stroke: stroke,
                         pos: CGPoint(x: x30, y: vesselY + vesselH/2 - 4), radius: 3.5)
            drawPlatelet(ctx: ctx, stroke: stroke,
                         pos: CGPoint(x: x30 + 8, y: vesselY + vesselH/2 + 3), radius: 3)
            drawPlatelet(ctx: ctx, stroke: stroke,
                         pos: CGPoint(x: x30 - 8, y: vesselY + vesselH/2 + 3), radius: 2.5)

            // 血小板 - 60' 位置: 6 颗
            let x60 = 8 + (size.width - 16) * 0.40
            let platelets60: [(CGFloat, CGFloat, CGFloat)] = [
                (0, -5, 3.5), (6, 0, 4), (3, 6, 3.5),
                (-4, 0, 2.5), (10, -2, 2.5), (-2, 5, 2.5)
            ]
            for (dx, dy, r) in platelets60 {
                drawPlatelet(ctx: ctx, stroke: stroke,
                             pos: CGPoint(x: x60 + dx, y: vesselY + vesselH/2 + dy), radius: r)
            }

            // 血小板 - 90' 位置: 10+ 颗
            let x90 = 8 + (size.width - 16) * 0.65
            let platelets90: [(CGFloat, CGFloat, CGFloat)] = [
                (0, -6, 3.5), (7, -3, 3.5), (-3, 0, 3.5),
                (10, 4, 3.5), (4, 5, 3.2), (-8, 4, 2.5),
                (12, -1, 2.5), (-1, 7, 2.2), (8, -7, 2.2)
            ]
            for (dx, dy, r) in platelets90 {
                drawPlatelet(ctx: ctx, stroke: stroke,
                             pos: CGPoint(x: x90 + dx, y: vesselY + vesselH/2 + dy), radius: r)
            }

            // 血栓! 120' 位置 (砖红)
            let x120 = 8 + (size.width - 16) * 0.88
            let thrombusCenter = CGPoint(x: x120, y: vesselY + vesselH/2)
            let platelets120: [(CGFloat, CGFloat, CGFloat)] = [
                (-3, -8, 3.2), (3, -5, 3.2), (-2, 0, 3.5),
                (4, 4, 3.2), (-4, 6, 3.2), (6, 6, 2.5),
                (8, 0, 2.2), (2, -10, 2.2), (10, 8, 2)
            ]
            for (dx, dy, r) in platelets120 {
                ctx.fill(Path(ellipseIn: CGRect(x: thrombusCenter.x + dx - r, y: thrombusCenter.y + dy - r, width: r*2, height: r*2)),
                         with: .color(Color(red: 0.79, green: 0.17, blue: 0.0)))
                ctx.stroke(Path(ellipseIn: CGRect(x: thrombusCenter.x + dx - r, y: thrombusCenter.y + dy - r, width: r*2, height: r*2)),
                           with: .color(stroke), lineWidth: 1.2)
            }

            // 血栓! 爆炸标 (在血管下方)
            let boomY = vesselY + vesselH + 12
            let boomR: CGFloat = 10
            ctx.fill(Path(ellipseIn: CGRect(x: x120 - boomR, y: boomY - boomR, width: boomR*2, height: boomR*2)),
                     with: .color(Color(red: 1.0, green: 0.30, blue: 0.18).opacity(0.7 + 0.3 * throbPulse)))
            ctx.stroke(Path(ellipseIn: CGRect(x: x120 - boomR, y: boomY - boomR, width: boomR*2, height: boomR*2)),
                       with: .color(stroke), lineWidth: 1.5)
            let boomText = Text("血栓!")
                .font(.system(size: 7, weight: .black))
                .foregroundColor(.white)
            ctx.draw(boomText, at: CGPoint(x: x120, y: boomY + 1))
        }
    }

    private func drawPlatelet(ctx: GraphicsContext, stroke: Color, pos: CGPoint, radius: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: pos.x - radius, y: pos.y - radius, width: radius*2, height: radius*2)),
                 with: .color(Color(red: 1.0, green: 0.30, blue: 0.18)))
        ctx.stroke(Path(ellipseIn: CGRect(x: pos.x - radius, y: pos.y - radius, width: radius*2, height: radius*2)),
                   with: .color(stroke), lineWidth: 1.2)
    }
}
