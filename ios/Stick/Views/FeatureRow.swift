import SwiftUI

/// 主页 3-5 行紧凑指标（左上角）：
///  - 心率那一行额外带一个 48×18 的 ECG 动画波形（图形 + 数据）
///  - 心情那一行（白天）额外带一个 48×18 的心情曲线（图形 + 数据）
///  - 异常那一行（≥1 项时显示）以单行紧凑形式提示最严重的异常
///  - 其他行：状态色点 + mono 标签 + 数值 + 副标
///
/// 设备能力：每个 metric 关联一个 MetricID。`deviceSet` 没有命中该 metric 的 required 设备时，
/// 整行置灰 + 锁图标 + 单击展示解锁提示。
struct FeatureRow: View {
    let state: StickState
    let deviceSet: Set<DeviceID>
    let healthStatuses: [MetricID: MetricDataStatus]
    let moodLine: MoodLineInfo?
    let moodScore: Double           // 0..100, 跟 MOOD 标签一起显示
    let bodyScore: Double           // 0..100, 身体打分（**第 1 行**，跟 MOOD 区分）
    let bodyScoreColor: Color
    let unifiedAlerts: [UnifiedAlert]
    let sitDurationText: String?      // 坐姿秒表 live MM:SS（sit 状态时为 "47:23" 这种，非 sit 时 nil）
    var onAlertTap: (UnifiedAlert) -> Void = { _ in }
    var onLockTap: () -> Void = { }   // 点击锁 → 跳添加设备界面
    var onSedentaryTap: () -> Void = { }  // 点击坐姿秒表 → 跳坐姿详情/起身提醒

    @State private var isExpanded: Bool = false
    @State private var alertsDetailExpanded: Bool = false

    /// 3 个指标中"心率"那行（任意位置）
    private var heartRateMetric: Metric? {
        [state.primaryMetric, state.secondaryMetric, state.tertiaryMetric]
            .first(where: { $0.label == "HEART RATE" })
    }

    /// 3 个指标中"既不是心率也不是心情"那行（= 对应状态的核心数据）
    ///   walk: DURATION   sit: SEDENTARY   sleep: SLEEP
    private var stateSpecificMetric: Metric? {
        [state.primaryMetric, state.secondaryMetric, state.tertiaryMetric]
            .first(where: { $0.label != "HEART RATE" && $0.label != "MOOD" })
    }

    /// 折叠时被隐藏的"其它指标"行（剩下的 1-2 个）
    private var hiddenMetrics: [Metric] {
        let visibleLabels = Set<String>(
            [heartRateMetric?.label, stateSpecificMetric?.label].compactMap { $0 }
        )
        return [state.primaryMetric, state.secondaryMetric, state.tertiaryMetric]
            .filter { !visibleLabels.contains($0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ① 身体状态得分（视觉焦点，22pt 数字）
            BodyScoreLine(score: bodyScore, color: bodyScoreColor)
            // ② 心情（默认可见，自带 0-100 分数，13pt 数字）
            if let m = moodLine {
                MoodLine(info: m, accent: state.accent, moodScore: moodScore)
            }
            // ③ 对应状态的核心数据（心率隐藏到展开区 — 3 行限制）
            if let ss = stateSpecificMetric {
                FeatureLine(metric: ss, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap)
            }
            // ④ 展开后：剩下的指标行 + 异常计数
            if isExpanded {
                ForEach(hiddenMetrics, id: \.label) { m in
                    FeatureLine(metric: m, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap)
                }
                // 异常摘要：默认只显示计数 + 最严重项标题
                if !unifiedAlerts.isEmpty {
                    if alertsDetailExpanded {
                        // 展开态：每条异常独立一行
                        ForEach(Array(unifiedAlerts.enumerated()), id: \.offset) { idx, alert in
                            AlertsLine(
                                top: alert,
                                totalCount: unifiedAlerts.count,
                                isFirst: idx == 0
                            ) { onAlertTap(alert) }
                        }
                    } else {
                        // 折叠态：只显示计数 + 第 1 项标题
                        if let top = unifiedAlerts.first {
                            AlertsLine(
                                top: top,
                                totalCount: unifiedAlerts.count,
                                isFirst: true
                            ) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    alertsDetailExpanded = true
                                }
                            }
                        }
                    }
                }
            }
            // ⑤ 展开/折叠按键
            expandToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.35), value: moodLine)
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
    }

    /// 左下角小按键：chevron + "more / less" 文字
    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                isExpanded.toggle()
                if !isExpanded { alertsDetailExpanded = false }
            }
        } label: {
            HStack(spacing: 3) {
                Text(isExpanded ? "LESS" : "MORE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
            }
            .foregroundColor(Theme.slate)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)  // 靠左
    }
}

// MARK: - 异常提示行（单行紧凑，不展开）

/// 单行异常提示：色点 + 标签 + 计数 + 最严重项标题。
/// 点击整行 → onAlertTap，由调用方决定弹什么详情。
private struct AlertsLine: View {
    let top: UnifiedAlert
    let totalCount: Int
    var isFirst: Bool = true   // 第一条显示 "ALERTS · N 项" 标题，后续只显示标题
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(top.severity.color)
                    .frame(width: 5, height: 5)

                if isFirst {
                    Text("ALERTS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(Theme.slate)
                        .lineLimit(1)
                        .frame(width: 68, alignment: .leading)

                    Text("\(totalCount) 项")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(top.severity.color)
                }

                Text(top.title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 心情监测（白天）

struct MoodLineInfo: Equatable {
    enum Tone { case good, calm, warn, excited }
    enum Spark { case excited, relaxed, evening, good, focused, tired, stable }

    let text: String
    let tone: Tone
    let spark: Spark
}

private struct MoodLine: View {
    let info: MoodLineInfo
    let accent: Color
    let moodScore: Double      // 0..100 数值，跟 "MOOD" 标签放一起

    private var dotColor: Color {
        switch info.tone {
        case .good:    return Color(red: 0.20, green: 0.65, blue: 0.45)   // 绿
        case .calm:    return Color(red: 0.30, green: 0.55, blue: 0.85)   // 蓝
        case .warn:    return Color(red: 0.92, green: 0.55, blue: 0.20)   // 橙
        case .excited: return Color(red: 0.95, green: 0.40, blue: 0.55)   // 粉
        }
    }

    private var statusText: String {
        switch info.tone {
        case .good:    return "STABLE"
        case .calm:    return "FOCUS"
        case .warn:    return "WARN"
        case .excited: return "PEAK"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // 状态色小点（跟 FeatureLine 一致）
            Circle()
                .fill(dotColor)
                .frame(width: 5, height: 5)

            // mono 标签 — "MOOD" → "心情得分"（4 个中文字，跟"身体状态得分"对称）
            Text("心情得分")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            // 心情曲线 — 已删除（用户要求）

            // 数值 — 13→11pt（再缩一档，跟下面 3rd 行 FeatureLine 节奏一致）
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(moodScore))")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(dotColor)
                    .monospacedDigit()
                    .lineLimit(1)
                Text("/100")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }

            // 副标 — 缩小 11→10pt regular（去掉 heavy，节省视觉重量）
            HStack(spacing: 6) {
                Text(info.text)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(dotColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 白天心情曲线：根据当前状态画 4 小时内的典型心情走势（无动画，纯静态）
private struct MoodSparkline: View {
    let kind: MoodLineInfo.Spark
    let color: Color

    /// y 值 0..1, 0 = 谷, 1 = 峰
    private var samples: [Double] {
        switch kind {
        case .excited:
            // 上午通勤: 从中位上冲到顶再微降
            return [0.55, 0.72, 0.92, 0.85, 0.78]
        case .relaxed:
            // 午餐后: 平稳 → 上升 → 峰值 → 缓降
            return [0.65, 0.70, 0.82, 0.78, 0.70]
        case .evening:
            // 晚间: 缓慢上行，临近峰值
            return [0.50, 0.60, 0.72, 0.82, 0.88]
        case .good:
            // 良好: 平稳中高
            return [0.70, 0.74, 0.72, 0.76, 0.74]
        case .focused:
            // 专注: 起步平 → 稳高
            return [0.68, 0.74, 0.78, 0.80, 0.78]
        case .tired:
            // 疲倦: 缓降
            return [0.80, 0.74, 0.66, 0.55, 0.42]
        case .stable:
            // 平稳: 几乎不变
            return [0.68, 0.70, 0.68, 0.72, 0.70]
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let pts = samples
            let stepX = size.width / CGFloat(pts.count - 1)
            let points: [CGPoint] = pts.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * stepX, y: size.height * (1 - CGFloat(v)))
            }

            // 平滑路径
            var path = Path()
            path.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1]
                let cur  = points[i]
                let c1 = CGPoint(x: prev.x + stepX * 0.5, y: prev.y)
                let c2 = CGPoint(x: cur.x  - stepX * 0.5, y: cur.y)
                path.addCurve(to: cur, control1: c1, control2: c2)
            }

            // 填充：曲线下到 baseline
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.22)))

            // 描边
            ctx.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            )

            // 末点小圆
            if let last = points.last {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)),
                    with: .color(color)
                )
            }
        }
    }
}

// MARK: - 身体打分（第 1 行专用 — 跟 FeatureLine / MoodLine 同视觉风格）

/// 紧凑单行：色点 + BODY 标签 + 大数字 + /100 + 副标
/// 颜色由 `bodyScoreColor` 传（4 档绿/黄绿/橙/红）。
private struct BodyScoreLine: View {
    let score: Double           // 0..100
    let color: Color

    private var intScore: Int { Int(score.rounded()) }
    private var tier: String {
        switch score {
        case 75...: return "充沛"
        case 30..<75: return "偏低"
        default: return "告急"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("身体状态得分")
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            // 大数字 + /100（**第 1 行视觉重点**，字号比 FeatureLine 数值还大）
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(intScore)")
                    .font(.system(size: 35, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                Text("/100")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }
            // [tier 文字去掉 — 颜色 + 数字已经传达档位信息]
        }
        .padding(.vertical, 3)
    }
}

private struct FeatureLine: View {
    let metric: Metric
    let accent: Color
    let deviceSet: Set<DeviceID>
    let healthStatuses: [MetricID: MetricDataStatus]
    let sitDurationText: String?      // 坐姿秒表 live（覆盖 SEDENTARY 行的硬编码值）
    var onLockTap: () -> Void = { }
    var onSedentaryTap: () -> Void = { }

    @State private var showLockHint: Bool = false

    private var isHeartRate: Bool { metric.label == "HEART RATE" }
    private var isSedentary: Bool { metric.label == "SEDENTARY" }

    /// 优先用 live 坐姿秒表（SEDENTARY 行），否则用硬编码 metric.value
    private var displayValue: String { sitDurationText ?? metric.value }

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
                .frame(width: 6, height: 6)

            // mono 标签（等宽对齐）— 缩小到 9pt 跟 MOOD 节奏一致
            Text(metric.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(isLocked ? Theme.mist : Theme.slate)
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)

            // 心率专属：ECG 动画波形 (锁定时不再画)
            if isHeartRate && !isLocked {
                HeartRateSparkline(color: Color(red: 0.86, green: 0.21, blue: 0.27))
                    .frame(width: 52, height: 18)
            }

            // 数值 / 锁图标（**等宽列对齐 + 字号 11pt 统一**）
            // 坐姿秒表（SEDENTARY 行）用 live 文本覆盖硬编码值
            Group {
                if isLocked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("—")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(Theme.mist)
                } else {
                    Text(displayValue)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(isEmpty ? Theme.mist : Theme.navy)
                        .lineLimit(1)
                        .monospacedDigit()  // 数字宽度固定，跨行对齐
                }
            }
            .frame(width: 60, alignment: .leading)

            // 副标 (灰显时用 availability.hint; 正常时用 metric.desc) — 9pt 缩小
            Text(isLocked ? availability.hint : metric.desc)
                .font(.system(size: 9, weight: .regular, design: .serif))
                .foregroundColor(Theme.mist)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked { onLockTap() }
            else if metric.label == "SEDENTARY" { onSedentaryTap() }
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
