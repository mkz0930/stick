import SwiftUI

/// 通用异常详情 sheet — 用于历史洞察（睡眠不足 / 久坐 / 步数等）。
/// AI 实时报告有更详细的 `AIAnalysisView`，这里只展示简化版。
struct AlertDetailView: View {
    let alert: UnifiedAlert
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    refCard
                    actionsCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("异常详情")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundColor(Theme.slate)
                Text(alert.title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Theme.bgTop)
    }

    // MARK: - 概览

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: alert.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(alert.severity.color)
                Text("SUMMARY · 概览")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(alert.severity.color)
                Spacer()
                severityBadge
            }
            Text(alert.detail)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundColor(Theme.navy)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if let tr = alert.timestampRange {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                    Text(tr)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                }
                .foregroundColor(Theme.slate)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(alert.severity.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(alert.severity.color.opacity(0.32), lineWidth: 1)
        )
    }

    private var severityBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(alert.severity.color)
                .frame(width: 7, height: 7)
            Text(alert.severity.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(alert.severity.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(alert.severity.color.opacity(0.12))
        )
    }

    // MARK: - 参考

    private var refCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("参考 · REFERENCE", icon: "scope")
            refContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
    }

    @ViewBuilder
    private var refContent: some View {
        switch alert.source {
        case .sleep:
            VStack(alignment: .leading, spacing: 8) {
                refRow("推荐时长", "7-9h (成人)", "WHO / NSF")
                refRow("测量来源", "HealthStore", "近 24h 睡眠窗口")
                if let nv = alert.numericValue {
                    refRow("实测", nv, "vs. 参考下限 7.0h")
                }
            }
        case .activity:
            VStack(alignment: .leading, spacing: 8) {
                refRow("推荐步数", "≥ 6000 步/日", "WHO")
                refRow("推荐锻炼", "≥ 30 min 中等强度", "WHO")
                if let nv = alert.numericValue {
                    refRow("实测", nv, "vs. 推荐值")
                }
            }
        case .heartRate:
            VStack(alignment: .leading, spacing: 8) {
                refRow("静息基线", "60-80 bpm", "AHA")
                refRow("走路区间", "95-115 bpm", "中等强度")
                if let nv = alert.numericValue {
                    refRow("实测", nv, "实时")
                }
            }
        case .posture, .mood, .respiratory, .generic:
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text("更多维度数据接入中...")
                    .font(.system(size: 11, weight: .regular, design: .serif))
            }
            .foregroundColor(Theme.slate)
        }
    }

    private func refRow(_ k: String, _ v: String, _ src: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.slate)
                .frame(width: 70, alignment: .leading)
            Text(v)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.navy)
            Spacer()
            Text(src)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.mist)
        }
    }

    // MARK: - 建议

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("建议 · ACTIONS", icon: "lightbulb")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(actionsForAlert.enumerated()), id: \.offset) { idx, txt in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(alert.severity.color)
                            .frame(width: 18, alignment: .leading)
                        Text(txt)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundColor(Theme.navy)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
    }

    private var actionsForAlert: [String] {
        switch alert.source {
        case .sleep:
            return [
                "今晚 22:30 前进入卧室，关掉强光屏幕",
                "卧室温度 18-22°C，避免咖啡因与酒精",
                "次日 07:00 后自然光照射 15 分钟以重置节律",
            ]
        case .activity:
            return [
                "每坐 50 分钟起身活动 5-10 分钟",
                "饭后 10-15 分钟轻度散步",
                "累计每日 6000 步；至少 30 分钟中等强度",
            ]
        case .heartRate:
            return [
                "立即降低活动强度至散步级别",
                "4-7-8 呼吸法 4 个循环（约 90 秒）",
                "持续 > 30 分钟未恢复建议联系医师",
            ]
        case .posture, .mood, .respiratory, .generic:
            return [
                "保持观察，下一时间窗口复核",
                "如持续出现请咨询专业医师",
            ]
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9, weight: .bold))
                Text("数据由本地规则引擎生成")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Theme.slate)
            Text("本提示仅供参考，不构成医疗建议。如有持续不适请咨询专业医师。")
                .font(.system(size: 9, weight: .regular, design: .serif))
                .foregroundColor(Theme.mist)
                .lineSpacing(2)
        }
        .padding(.top, 4)
    }

    // MARK: - 组件

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(alert.severity.color)
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.slate)
        }
    }

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}
