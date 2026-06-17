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
    let moodScore: Double           // 0..100, 心情（高=好心情）
    let stressScore: Double         // 0..100, 压力 = 100 - moodScore（高=大压力；颜色逻辑反转）
    let bodyScore: Double           // 0..100, 身体打分（**第 1 行**，跟 MOOD 区分）
    let bodyScoreColor: Color
    let unifiedAlerts: [UnifiedAlert]
    let sitDurationText: String?      // 坐姿秒表 live MM:SS（sit 状态时为 "47:23" 这种，非 sit 时 nil）
    let todaySitDescription: String    // 今日累计久坐描述，如 "累计6小时23分"
    let todaySteps: Int               // 今日累计步数（HealthKit；模拟器 demo 注入 8000+）
    let todayWalkMinutes: Int         // 今日行走分钟数
    let todaySleepHours: Double?      // 今日睡眠小时数（HealthKit sleepAnalysis 汇总；nil = 未授权/无数据）
    @Binding var isExpanded: Bool       // 状态提升到 ContentView，让小人也能淡出
    var onAlertTap: (UnifiedAlert) -> Void = { _ in }
    var onLockTap: () -> Void = { }   // 点击锁 → 跳添加设备界面
    var onSedentaryTap: () -> Void = { }  // 点击坐姿秒表 → 跳坐姿详情/起身提醒
    var onWalkCardTap: () -> Void = { }  // 点击行走卡片 → 跳步态详情
    var onSleepCardTap: () -> Void = { }  // 点击睡眠卡片 → 跳睡眠详情
    var onCardTap: () -> Void = { }   // 点击卡片主体 → 打开对话

    @State private var alertsDetailExpanded: Bool = false
    @State private var pinnedMetricIds: Set<String> = []
    @State private var autoCollapseTimer: Timer? = nil

    private let pinnedMetricsKey = "stick.pinned.metrics"

    // MARK: - 10秒无操作自动收起

    private func resetAutoCollapseTimer(expanded: Binding<Bool>, alertsBinding: Binding<Bool>) {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.28)) {
                    expanded.wrappedValue = false
                    alertsBinding.wrappedValue = false
                }
            }
        }
    }

    private func cancelAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    private func loadPinned() {
        if let data = UserDefaults.standard.data(forKey: pinnedMetricsKey),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            pinnedMetricIds = ids
        }
    }

    private func savePinned() {
        if let data = try? JSONEncoder().encode(pinnedMetricIds) {
            UserDefaults.standard.set(data, forKey: pinnedMetricsKey)
        }
    }

    /// 走步状态下用真实累计分钟数替代硬编码值
    private var realTertiaryMetric: Metric {
        let m = state.tertiaryMetric
        let realValue = "\(todayWalkMinutes) min"
        return Metric(label: m.label, value: realValue, status: m.status, statusKind: m.statusKind, desc: m.desc, hint: "今日累计 \(todayWalkMinutes) 分钟行走", metricID: m.metricID)
    }

    /// 睡眠状态下用真实睡眠时长（小时）替代硬编码的"82 质量评分"
    private var realSleepPrimaryMetric: Metric {
        let m = state.primaryMetric
        let h = todaySleepHours ?? 0
        let hours = Int(h)
        let minutes = Int((h - Double(hours)) * 60)
        let realValue = "\(hours)h\(String(format: "%02d", minutes))m"
        return Metric(label: m.label, value: realValue, status: m.status, statusKind: m.statusKind, desc: "睡眠时长", hint: "今日累计 \(realValue)", metricID: m.metricID)
    }

    /// 状态的三项指标（walk 时 DURATION、sleep 时 SLEEP 使用真实值），去掉姿态（POSTURE）。
    /// walk 时再去掉心情（MOOD）—— 跟 StressLine（"压力值"）功能重叠（moodScore + stressScore = 100）。
    private var displayMetrics: [Metric] {
        let primary = state == .sleep ? realSleepPrimaryMetric : state.primaryMetric
        let tertiary = state == .walk ? realTertiaryMetric : state.tertiaryMetric
        let excluded: Set<String> = state == .walk
            ? ["POSTURE", "MOOD"]
            : ["POSTURE"]
        return [primary, state.secondaryMetric, tertiary].filter { !excluded.contains($0.label) }
    }

    /// 3 个指标中"心率"那行（任意位置）
    private var heartRateMetric: Metric? {
        displayMetrics.first(where: { $0.label == "HEART RATE" })
    }

    /// 3 个指标中"既不是心率也不是心情"那行（= 对应状态的核心数据）
    ///   walk: DURATION   sit: SEDENTARY   sleep: SLEEP
    private var stateSpecificMetric: Metric? {
        displayMetrics.first(where: { $0.label != "HEART RATE" && $0.label != "MOOD" })
    }

    /// 折叠时被隐藏的"其它指标"行（剩下的 1-2 个）
    private var hiddenMetrics: [Metric] {
        let visibleLabels = Set<String>(
            [heartRateMetric?.label, stateSpecificMetric?.label].compactMap { $0 }
        )
        return displayMetrics.filter { !visibleLabels.contains($0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ① 身体状态得分（**唯一默认可见** — 视觉锤）
            BodyScoreLine(score: bodyScore, color: bodyScoreColor)

            if isExpanded {
                // 展开态：所有行 + 📌 切换按钮
                if let m = moodLine {
                    StressLine(info: m, accent: state.accent, stressScore: stressScore, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                StepsLine(steps: todaySteps, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                if let ss = stateSpecificMetric {
                    FeatureLine(metric: ss, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, todaySitDescription: todaySitDescription, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap, onWalkCardTap: onWalkCardTap, onSleepCardTap: onSleepCardTap, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                ForEach(hiddenMetrics, id: \.label) { m in
                    FeatureLine(metric: m, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, todaySitDescription: todaySitDescription, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap, onWalkCardTap: onWalkCardTap, onSleepCardTap: onSleepCardTap, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                // 异常摘要 — 折叠默认显示前 2 项，>2 项时显示 chevron 可展开看全部
                if !unifiedAlerts.isEmpty {
                    AlertsSection(
                        alerts: unifiedAlerts,
                        isExpanded: $alertsDetailExpanded,
                        onAlertTap: onAlertTap,
                        pinnedIds: $pinnedMetricIds,
                        onPinToggle: savePinned
                    )
                }
            } else {
                // 折叠态：只显示固定行
                if let m = moodLine, pinnedMetricIds.contains("stress") {
                    StressLine(info: m, accent: state.accent, stressScore: stressScore, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                if pinnedMetricIds.contains("steps") {
                    StepsLine(steps: todaySteps, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                if let ss = stateSpecificMetric, pinnedMetricIds.contains(ss.label) {
                    FeatureLine(metric: ss, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, todaySitDescription: todaySitDescription, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap, onWalkCardTap: onWalkCardTap, onSleepCardTap: onSleepCardTap, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                ForEach(hiddenMetrics.filter { pinnedMetricIds.contains($0.label) }, id: \.label) { m in
                    FeatureLine(metric: m, accent: state.accent, deviceSet: deviceSet, healthStatuses: healthStatuses, sitDurationText: sitDurationText, todaySitDescription: todaySitDescription, onLockTap: onLockTap, onSedentaryTap: onSedentaryTap, onWalkCardTap: onWalkCardTap, onSleepCardTap: onSleepCardTap, pinnedIds: $pinnedMetricIds, onPinToggle: savePinned)
                }
                if pinnedMetricIds.contains("alerts") && !unifiedAlerts.isEmpty {
                    AlertsSection(
                        alerts: unifiedAlerts,
                        isExpanded: $alertsDetailExpanded,
                        onAlertTap: onAlertTap,
                        pinnedIds: $pinnedMetricIds,
                        onPinToggle: savePinned
                    )
                }
            }
            // 展开/折叠按键
            expandToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.35), value: moodLine)
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
        .onTapGesture {
            onCardTap()
            resetAutoCollapseTimer(expanded: $isExpanded, alertsBinding: $alertsDetailExpanded)
        }
        .onAppear {
            loadPinned()
            if isExpanded { resetAutoCollapseTimer(expanded: $isExpanded, alertsBinding: $alertsDetailExpanded) }
        }
        .onDisappear {
            cancelAutoCollapseTimer()
        }
    }

    /// 左下角按键：chevron + "more / less" 文字，整行可点
    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                isExpanded.toggle()
                if !isExpanded { alertsDetailExpanded = false }
            }
            if isExpanded {
                resetAutoCollapseTimer(expanded: $isExpanded, alertsBinding: $alertsDetailExpanded)
            } else {
                cancelAutoCollapseTimer()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                Text(isExpanded ? "收起" : "更多")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Theme.slate)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())  // 整行可点（不限于 chevron+文字小区域）
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 异常提示 section（可折叠：默认前 2 项，>2 项可展开全部）

/// 异常 section：
///  - 头部：色点 + "异常提示" + "N 项" + chevron（始终显示）
///  - 列表：默认隐藏（isExpanded = false），点击头部展开看全部
///  - 头部点击 → 折叠/展开
///  - 单项点击 → onAlertTap（弹详情 / AI 报告）
private struct AlertsSection: View {
    let alerts: [UnifiedAlert]
    @Binding var isExpanded: Bool
    var onAlertTap: (UnifiedAlert) -> Void = { _ in }
    var pinnedIds: Binding<Set<String>>
    var onPinToggle: () -> Void = { }

    private let metricId = "alerts"

    // 去掉 @State var alertsDetailExpanded — 用父组件传进来的 @Binding var isExpanded 即可
    // 之前错误地声明了 @State shadow 了 binding，导致 header toggle 操作的是本地 state，
    // 而 FeatureRow.expandToggle 设置的 alertsDetailExpanded 绑定更新触达不到这里。

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 头部
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    // 📌 固定按钮（热区 44×44pt）
                    Button {
                        if pinnedIds.wrappedValue.contains(metricId) {
                            pinnedIds.wrappedValue.remove(metricId)
                        } else if pinnedIds.wrappedValue.count < 3 {
                            pinnedIds.wrappedValue.insert(metricId)
                        }
                        onPinToggle()
                    } label: {
                        Image(systemName: pinnedIds.wrappedValue.contains(metricId) ? "pin.fill" : "pin")
                            .font(.system(size: 13))
                            .foregroundColor(pinnedIds.wrappedValue.contains(metricId) ? Theme.navy : Theme.mist)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())

                    Circle()
                        .fill(alerts.first?.severity.color ?? Theme.mist)
                        .frame(width: 6, height: 6)

                    Text("异常提示")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.slate)
                        .lineLimit(1)
                        .frame(width: 60, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("\(alerts.count) 项")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(alerts.first?.severity.color ?? Theme.mist)
                        .frame(width: 80, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.slate)

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            // 列表项（仅展开时显示）
            if isExpanded {
                ForEach(alerts, id: \.id) { alert in
                    AlertItemRow(alert: alert) {
                        onAlertTap(alert)
                    }
                }
            }
        }
    }
}

/// 单个异常项：缩进 + 小色点 + 标题 + chevron-right
private struct AlertItemRow: View {
    let alert: UnifiedAlert
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // 缩进：与 header 文字起点对齐（6pt 色点 + 8pt 间距 = 14pt）
                Color.clear.frame(width: 14)

                Circle()
                    .fill(alert.severity.color.opacity(0.7))
                    .frame(width: 4, height: 4)

                Text(alert.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.mist)
            }
            .padding(.vertical, 1)
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

/// 压力值行（替换原来的心情得分 — commit 22827c4）
///   - 标签: 心情得分 → 压力值
///   - 数值: 100 - moodScore（高=大压力）
///   - 颜色: 按 stressScore 数值 4 档（绿→黄绿→橙→红；**与 mood 逻辑反转**）
///   - 状态文字: tone 反转（good→轻松, calm→平稳, warn→紧张, excited→焦虑）
private struct StressLine: View {
    let info: MoodLineInfo
    let accent: Color
    let stressScore: Double      // 0..100, 高=大压力（与 moodScore 反向）
    var pinnedIds: Binding<Set<String>>
    var onPinToggle: () -> Void = { }

    private let metricId = "stress"

    /// 颜色按 stressScore 数值 4 档（与 mood 相反方向）
    private var dotColor: Color {
        switch stressScore {
        case ..<25:   return Color(red: 0.20, green: 0.65, blue: 0.45)   // 绿  低压力
        case ..<50:   return Color(red: 0.55, green: 0.71, blue: 0.06)   // 黄绿
        case ..<75:   return Color(red: 0.92, green: 0.55, blue: 0.20)   // 橙  中高压力
        default:      return Color(red: 0.93, green: 0.20, blue: 0.20)   // 红  高压力
        }
    }

    /// 状态文字：基于 tone（来自原始 mood 分类），但语义反转
    private var statusText: String {
        switch info.tone {
        case .good:    return "轻松"   // mood 好 → 压力低
        case .calm:    return "平稳"   // mood 平稳 → 压力平稳
        case .warn:    return "紧张"   // mood 警告 → 压力紧张
        case .excited: return "焦虑"   // mood 兴奋 → 压力焦虑
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // 📌 固定按钮（热区 44×44pt）
            Button {
                if pinnedIds.wrappedValue.contains(metricId) {
                    pinnedIds.wrappedValue.remove(metricId)
                } else if pinnedIds.wrappedValue.count < 3 {
                    pinnedIds.wrappedValue.insert(metricId)
                }
                onPinToggle()
            } label: {
                Image(systemName: pinnedIds.wrappedValue.contains(metricId) ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(pinnedIds.wrappedValue.contains(metricId) ? Theme.navy : Theme.mist)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

            // 状态色小点（跟 FeatureLine 一致）
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            // 主标签 — 15pt bold rounded（固定 60pt 宽，跨行对齐）
            Text("压力值")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            // 主数值 — 15pt heavy rounded（**固定 80pt 列宽** — 跨行起点对齐）
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(stressScore))")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(dotColor)
                    .monospacedDigit()
                    .lineLimit(1)
                Text("/100")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }
            .frame(width: 80, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)

            // 备注 — 11pt medium（清晰易读）
            HStack(spacing: 6) {
                Text(info.text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(dotColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 今日步数（独立行 — 不在 state.metrics 里，单独从 HealthKit 拉）

/// 紧凑单行：色点 + "今日步数" 标签 + 步数数值 + 进度备注（"目标 10,000" / "差 X 步"）
/// 颜色按今日完成度 4 档：<25% 灰 / <50% 蓝 / <100% 橙 / ≥100% 绿
private struct StepsLine: View {
    let steps: Int
    var pinnedIds: Binding<Set<String>>
    var onPinToggle: () -> Void = { }

    private let goal: Int = 10_000
    private let metricId = "steps"

    /// 颜色按步数完成度（跟 StressLine 同套 4 档体系）
    private var dotColor: Color {
        let pct = Double(steps) / Double(goal)
        switch pct {
        case ..<0.25: return Color(red: 0.65, green: 0.68, blue: 0.74)   // 灰  起步
        case ..<0.50: return Color(red: 0.30, green: 0.55, blue: 0.85)   // 蓝  进行中
        case ..<1.00: return Color(red: 0.92, green: 0.55, blue: 0.20)   // 橙  接近目标
        default:      return Color(red: 0.20, green: 0.65, blue: 0.45)   // 绿  达成
        }
    }

    /// 步数数值字符串（千分位逗号）
    private var stepsText: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    /// 备注（"目标 10,000" / "还差 1,766 步" / "已达成 +234"）
    private var noteText: String {
        if steps >= goal {
            return "已达成 +\(stepsText)"
        }
        let remain = goal - steps
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        let remainText = f.string(from: NSNumber(value: remain)) ?? "\(remain)"
        return "还差 \(remainText) 步"
    }

    var body: some View {
        HStack(spacing: 10) {
            // 📌 固定按钮（热区 44×44pt）
            Button {
                if pinnedIds.wrappedValue.contains(metricId) {
                    pinnedIds.wrappedValue.remove(metricId)
                } else if pinnedIds.wrappedValue.count < 3 {
                    pinnedIds.wrappedValue.insert(metricId)
                }
                onPinToggle()
            } label: {
                Image(systemName: pinnedIds.wrappedValue.contains(metricId) ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(pinnedIds.wrappedValue.contains(metricId) ? Theme.navy : Theme.mist)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

            // 状态色小点
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            // 主标签 — 15pt bold rounded（固定 60pt 宽，跨行对齐）
            Text("步数")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            // 主数值 — 15pt heavy rounded（**固定 80pt 列宽** — 跟其它数值起点对齐）
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stepsText)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(dotColor)
                    .monospacedDigit()
                    .lineLimit(1)
                Text("步")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.slate)
            }
            .frame(width: 80, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)

            // 备注 — 11pt regular（小一档，灰；剩余空间填满）
            Text(noteText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
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
                    .font(.system(size: 45, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
                Text("/100")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
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
    let todaySitDescription: String    // 今日累计久坐描述（用于 SEDENTARY 行非 sit 状态时）
    var onLockTap: () -> Void = { }
    var onSedentaryTap: () -> Void = { }
    var onWalkCardTap: () -> Void = { }
    var onSleepCardTap: () -> Void = { }
    var pinnedIds: Binding<Set<String>>
    var onPinToggle: () -> Void = { }

    @State private var showLockHint: Bool = false

    private var isHeartRate: Bool { metric.label == "HEART RATE" }
    private var isSedentary: Bool { metric.label == "SEDENTARY" }
    private var metricId: String { metric.label }

    /// 优先用 live 坐姿秒表（SEDENTARY 行 sit 时），否则用今日累计描述
    private var displayValue: String { sitDurationText ?? todaySitDescription }

    /// 该 metric 在当前 UI 下的呈现状态
    private var availability: MetricAvailability {
        guard let id = metric.metricID else { return .available }
        let status = healthStatuses[id] ?? .unknown
        return DeviceCapabilities.effective(id, status: status, deviceSet: deviceSet)
    }

    private var isLocked: Bool { availability.kind == .locked }
    private var isEmpty: Bool { availability.kind == .availableEmpty }

    var body: some View {
        HStack(spacing: 10) {
            // 📌 固定按钮（热区 44×44pt）
            Button {
                if pinnedIds.wrappedValue.contains(metricId) {
                    pinnedIds.wrappedValue.remove(metricId)
                } else if pinnedIds.wrappedValue.count < 3 {
                    pinnedIds.wrappedValue.insert(metricId)
                }
                onPinToggle()
            } label: {
                Image(systemName: pinnedIds.wrappedValue.contains(metricId) ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .foregroundColor(pinnedIds.wrappedValue.contains(metricId) ? Theme.navy : Theme.mist)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())

            // 状态色小点 (灰显时用 mist)
            Circle()
                .fill(isLocked ? Theme.mist : accent)
                .frame(width: 6, height: 6)

            // 主标签 — 15pt bold rounded（固定 60pt 宽，跨行对齐）
            Text(metric.chineseLabel)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(isLocked ? Theme.mist : Theme.slate)
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            // 主数值 / 锁图标（**固定 80pt 列宽** — 跟 StressLine 数值起点对齐）
            // 坐姿秒表（SEDENTARY 行）用 live 文本覆盖硬编码值
            // lock 和 text 分别 frame，避免 fixedSize 把 lock 缩到 11pt 导致列内错位
            // 心率行：ECG 波形叠加在数值列内部，不额外撑开布局
            ZStack {
                if isHeartRate && !isLocked {
                    HeartRateSparkline(color: Color(red: 0.86, green: 0.21, blue: 0.27))
                        .frame(width: 52, height: 18)
                }
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.mist)
                } else {
                    Text(displayValue)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(isEmpty ? Theme.mist : Theme.navy)
                        .lineLimit(1)
                        .monospacedDigit()  // 数字宽度固定，跨行对齐
                }
            }
            .frame(width: 80, alignment: .leading)

            // 备注 — 11pt regular（小一档，灰；剩余空间填满）
            Text(isLocked ? availability.hint : metric.desc)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(Theme.slate)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if isLocked { onLockTap() }
            else if metric.label == "SEDENTARY" { onSedentaryTap() }
            else if metric.label == "DURATION" { onWalkCardTap() }
            else if metric.label == "SLEEP" { onSleepCardTap() }
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
