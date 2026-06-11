import SwiftUI

/// 主页底部 3 张数据卡（ATLAS v6 风格）：
///  - 白底圆角卡 + 状态色左 border（3px 实色条）
///  - 顶部 label-row：mono 设备/类别 + mono 状态（着色）
///  - 中部 metric：大数字（accent 色）+ 单位说明
///  - 底部 desc（serif 中）+ hint（sans 小字）
///  - 卡片之间的连接用虚线分割线（编辑风）
struct FeatureRow: View {
    let state: StickState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            DataCard(metric: state.primaryMetric,   accent: state.accent)
            DataCard(metric: state.secondaryMetric, accent: state.accent)
            DataCard(metric: state.tertiaryMetric,  accent: state.accent)
        }
    }
}

private struct DataCard: View {
    let metric: Metric
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // label-row
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(Theme.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text(metric.status)
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }

            // metric
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
            }

            // desc (serif Chinese)
            Text(metric.desc)
                .font(.system(size: 11, weight: .heavy, design: .serif))
                .foregroundColor(Theme.navy)
                .lineLimit(1)

            // hint (sans small)
            Text(metric.hint)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundColor(Theme.slate)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.card)
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch metric.statusKind {
        case .ok:   return Color(red: 0.02, green: 0.59, blue: 0.41)  // #059669
        case .warn: return Color(red: 0.92, green: 0.34, blue: 0.05)  // #EA580C
        case .info: return Color(red: 0.06, green: 0.65, blue: 0.91)  // #0EA5E9
        }
    }
}
