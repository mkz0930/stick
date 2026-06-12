import SwiftUI

/// 统一异常面板：把 AI 实时报告 + HealthAnalyzer 历史洞察 (含参考睡眠异常)
/// 聚合成一列紧凑行，每行带严重度色 / 图标 / 时间 / 数值。
/// 点击行打开对应详情（AI 报告 sheet / 通用详情）。
struct AlertsPanel: View {
    let alerts: [UnifiedAlert]
    var onTap: (UnifiedAlert) -> Void

    /// 最多展示的条目（其他折叠到 N+）
    private let maxVisible: Int = 4

    private var visible: [UnifiedAlert] { Array(alerts.prefix(maxVisible)) }
    private var hiddenCount: Int { max(0, alerts.count - maxVisible) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(visible) { a in
                AlertRow(alert: a) { onTap(a) }
            }
            if hiddenCount > 0 {
                Text("+ \(hiddenCount) 项异常未展示")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.slate)
            Text("今日异常")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.slate)
            Spacer()
            Text("\(alerts.count) 项")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.navy)
                )
                .foregroundColor(.white)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - 单行

private struct AlertRow: View {
    let alert: UnifiedAlert
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                // 严重度色条 (左)
                Rectangle()
                    .fill(alert.severity.color)
                    .frame(width: 3, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 1))

                // 图标
                Image(systemName: alert.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(alert.severity.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(alert.title)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.navy)
                            .lineLimit(1)
                        if let nv = alert.numericValue {
                            Text(nv)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(alert.severity.color)
                        }
                    }
                    Text(alert.detail)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .foregroundColor(Theme.slate)
                        .lineLimit(2)
                        .lineSpacing(1.5)
                }

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 2) {
                    if let tr = alert.timestampRange {
                        Text(tr)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.slate)
                    }
                    Text(alert.severity.label)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(alert.severity.color)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.slate)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(alert.severity.color.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
