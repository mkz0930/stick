import SwiftUI

/// 主页 3 行紧凑指标（左上角）：
///  - 心率那一行额外带一个 48×18 的 ECG 动画波形（图形 + 数据）
///  - 其他行：状态色点 + mono 标签 + 数值 + 副标
struct FeatureRow: View {
    let state: StickState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FeatureLine(metric: state.primaryMetric,   accent: state.accent)
            FeatureLine(metric: state.secondaryMetric, accent: state.accent)
            FeatureLine(metric: state.tertiaryMetric,  accent: state.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureLine: View {
    let metric: Metric
    let accent: Color

    private var isHeartRate: Bool { metric.label == "HEART RATE" }

    var body: some View {
        HStack(spacing: 8) {
            // 状态色小点
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)

            // mono 标签（等宽对齐）
            Text(metric.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 68, alignment: .leading)

            // 心率专属：ECG 动画波形
            if isHeartRate {
                HeartRateSparkline(color: Color(red: 0.86, green: 0.21, blue: 0.27))
                    .frame(width: 52, height: 18)
            }

            // 数值
            Text(metric.value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.navy)
                .lineLimit(1)

            // 副标
            Text(metric.desc)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundColor(Theme.mist)
                .lineLimit(1)
        }
    }
}

// MARK: - ECG 波形（动画）

/// 极简 ECG 心率波形：P-Q-R-S-T 周期循环，从右往左滚动
private struct HeartRateSparkline: View {
    let color: Color
    private let cycleW: CGFloat = 30   // 一个心电周期占的水平像素

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let cycleSec: Double = 0.85   // ≈ 70 BPM 的视觉速度
                let phase = (t.truncatingRemainder(dividingBy: cycleSec)) / cycleSec
                let offset = CGFloat(phase) * cycleW

                let midY = size.height / 2
                let count = Int(size.width / cycleW) + 2

                var path = Path()
                for i in 0..<count {
                    let x0 = CGFloat(i) * cycleW - offset
                    // baseline
                    path.move(to: CGPoint(x: x0, y: midY))
                    // P 波（小鼓包）
                    path.addQuadCurve(
                        to: CGPoint(x: x0 + cycleW * 0.18, y: midY),
                        control: CGPoint(x: x0 + cycleW * 0.08, y: midY - 3)
                    )
                    // 回到基线
                    path.addLine(to: CGPoint(x: x0 + cycleW * 0.28, y: midY))
                    // Q（小下凹）
                    path.addLine(to: CGPoint(x: x0 + cycleW * 0.32, y: midY + 1))
                    // R 峰（高耸）
                    path.addLine(to: CGPoint(x: x0 + cycleW * 0.40, y: -size.height * 0.05))
                    // S 谷
                    path.addLine(to: CGPoint(x: x0 + cycleW * 0.46, y: size.height + size.height * 0.05))
                    // 回到基线
                    path.addLine(to: CGPoint(x: x0 + cycleW * 0.54, y: midY))
                    // T 波（圆缓）
                    path.addQuadCurve(
                        to: CGPoint(x: x0 + cycleW * 0.72, y: midY),
                        control: CGPoint(x: x0 + cycleW * 0.63, y: midY - 3)
                    )
                    // 余下基线
                    path.addLine(to: CGPoint(x: x0 + cycleW, y: midY))
                }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))

                // 末端小圆点（心跳跟随）
                let lastX = cycleW - offset + CGFloat(count - 1) * cycleW
                if lastX > -cycleW && lastX < size.width + cycleW {
                    let dotX = size.width + 4
                    let dotY = midY
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX - 2, y: dotY - 2, width: 4, height: 4)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
