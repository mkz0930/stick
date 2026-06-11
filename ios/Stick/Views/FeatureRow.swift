import SwiftUI

/// 主页 3 行紧凑指标（ATLAS v6 风格，简约版）：
///  - 左上对齐，三行竖排
///  - 每行：状态色点 + mono 标签 + 数值 + 副标
///  - 无卡片底色 / 描边，纯文字
struct FeatureRow: View {
    let state: StickState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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

    var body: some View {
        HStack(spacing: 6) {
            // 状态色小点
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)

            // mono 标签
            Text(metric.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            // 数值
            Text(metric.value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.navy)
                .lineLimit(1)

            // 副标（serif 中文）
            Text(metric.desc)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundColor(Theme.mist)
                .lineLimit(1)
        }
    }
}
