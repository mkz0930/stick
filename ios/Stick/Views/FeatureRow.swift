import SwiftUI

/// 主页 3 行紧凑指标（左上角）：
///  - 心率那一行额外带一个 48×18 的 ECG 动画波形（图形 + 数据）
///  - 其他行：状态色点 + mono 标签 + 数值 + 副标
///
/// 设备能力：每个 metric 关联一个 MetricID。`deviceSet` 没有命中该 metric 的 required 设备时，
/// 整行置灰 + 锁图标 + 单击展示解锁提示。
struct FeatureRow: View {
    let state: StickState
    let deviceSet: Set<DeviceID>
    let healthStatuses: [MetricID: MetricDataStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FeatureLine(metric: state.primaryMetric,   accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses)
            FeatureLine(metric: state.secondaryMetric, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses)
            FeatureLine(metric: state.tertiaryMetric,  accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureLine: View {
    let metric: Metric
    let accent: Color
    let deviceSet: Set<DeviceID>
    let healthStatuses: [MetricID: MetricDataStatus]

    @State private var showLockHint: Bool = false

    private var isHeartRate: Bool { metric.label == "HEART RATE" }

    /// 该 metric 在当前 UI 下的呈现状态
    private var availability: MetricAvailability {
        guard let id = metric.metricID else { return .available }
        let status = healthStatuses[id] ?? .unknown
        return DeviceCapabilities.effective(id, status: status, deviceSet: deviceSet)
    }

    private var isLocked: Bool { availability.kind == .locked }
    private var isEmpty: Bool { availability.kind == .availableEmpty }

    var body: some View {
        HStack(spacing: 8) {
            // 状态色小点 (灰显时变灰)
            Circle()
                .fill(isLocked ? Theme.mist.opacity(0.5) : accent)
                .frame(width: 5, height: 5)

            // mono 标签（等宽对齐）
            Text(metric.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(isLocked ? Theme.mist : Theme.slate)
                .lineLimit(1)
                .frame(width: 68, alignment: .leading)

            // 心率专属：ECG 动画波形 (锁定时不再画)
            if isHeartRate && !isLocked {
                HeartRateSparkline(color: Color(red: 0.86, green: 0.21, blue: 0.27))
                    .frame(width: 52, height: 18)
            }

            // 数值 / 锁图标
            if isLocked {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("—")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundColor(Theme.mist)
            } else {
                Text(metric.value)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(isEmpty ? Theme.mist : Theme.navy)
                    .lineLimit(1)
            }

            // 副标 (灰显时用 availability.hint; 正常时用 metric.desc)
            Text(isLocked ? availability.hint : metric.desc)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundColor(Theme.mist)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked { showLockHint = true }
        }
        .popover(isPresented: $showLockHint, arrowEdge: .top) {
            LockHintPopover(metric: metric, availability: availability)
                .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - 解锁提示弹层

private struct LockHintPopover: View {
    let metric: Metric
    let availability: MetricAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.slate)
                Text(metric.metricID?.englishName ?? metric.label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(Theme.navy)
            }
            if let hint = availability.unlockHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.slate)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("当前设备无法呈现此数据")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.slate)
            }
        }
        .padding(12)
        .frame(maxWidth: 240, alignment: .leading)
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
