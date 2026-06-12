import SwiftUI

/// 首页：火柴人主舞台。视觉参考 ATLAS v6-dashboard-sleeping：
///  - 顶栏（品牌 mark + 名称 + session + LIVE）
///  - 主舞台（eyebrow + 大尺寸火柴人 + serif 标题 + mono 副标）
///  - 24h 可拖动时间线
///  - 3 张数据卡（白色卡 + 状态色左 border）
///  - 底部 dark action panel
///
/// 状态来源：`StickState.current(at: now)`。
/// 拖动时间线时 `scrubOffset` 临时覆盖，UI 全程跟着更新。
struct ContentView: View {
    @StateObject private var hk = HealthKitService.shared
    @StateObject private var healthAuth = HealthAuthService.shared
    @State private var now: Date = Date()
    @State private var scrubOffset: Int? = nil   // 0 = 现在；>0 表示过去多少分钟（窗口起点 = now - 24h）
    @State private var showFilm: Bool = false
    @State private var showSleepReport: Bool = false
    @State private var showNeckReport: Bool = false
    @State private var showPersonal: Bool = false
    @State private var openSpecialists: Bool = false
    @State private var openDataRecord: Bool = false
    @State private var openWidgetPreview: Bool = false
    @State private var showDevicePicker: Bool = false
    @State private var showAIReport: Bool = false
    @State private var selectedAlert: UnifiedAlert? = nil
    @State private var deviceSet: Set<DeviceID> = [.iPhone]

    // HealthKit 状态推断（30s 重算一次）
    @State private var inference: StateInference.Result? = nil

    // Chat
    @State private var showChat: Bool = false
    @State private var chatSeed: String = ""
    @State private var chatKey: Int = 0
    @State private var inputDraft: String = ""

    private var displayOffset: Int {
        scrubOffset ?? 0
    }

    private var displayDate: Date {
        now.addingTimeInterval(-Double(displayOffset) * 60)
    }

    private var displayState: StickState {
        StickState.currentSegment(at: displayDate)?.state ?? .walk
    }

    private var isScrubbing: Bool {
        guard let s = scrubOffset else { return false }
        return s > 0
    }

    /// 上午 + 状态好 = 兴奋 UI。
    /// 上午 06:00–12:00 之内只有 .walk（07:00–08:30 通勤）是真正"好"的状态，
    /// 其余时段（睡 / 坐）状态不健康，不应触发兴奋装饰。
    private var isMorningEnergetic: Bool {
        let m = StickState.minutesOfDay(displayDate)
        return displayState == .walk && m >= 360 && m < 720
    }

    /// 上午工作（08:30–12:00）坐 = 平稳 / 专注。
    private var isMorningCalm: Bool {
        let m = StickState.minutesOfDay(displayDate)
        return displayState == .sit && m >= 510 && m < 720
    }

    /// 下午工作（13:30–18:00）坐 = 越坐越累。返回 0..1 强度。
    private var afternoonTiredness: Double {
        let m = StickState.minutesOfDay(displayDate)
        guard displayState == .sit, m >= 810, m < 1080 else { return 0 }
        return Double(m - 810) / 270.0
    }

    private var isAfternoonTired: Bool { afternoonTiredness > 0.05 }

    /// 给当前展示状态派生火柴人心情覆盖。
    private var figureMood: StickFigureMood {
        if isMorningEnergetic { return .excited }
        if isMorningCalm      { return .calm }
        if isAfternoonTired   { return .tired }
        return .normal
    }

    /// 疲惫强度（仅 .tired 用，0..1）。
    private var figureTiredness: Double {
        isAfternoonTired ? afternoonTiredness : 0
    }

    /// 白天心情监测：当前 mood 文本 + 色调。sleep 时返回 nil（行隐藏）。
    private var displayMoodLine: MoodLineInfo? {
        switch displayState {
        case .sleep:
            return nil
        case .walk:
            if isMorningEnergetic {
                return MoodLineInfo(text: "兴奋", tone: .excited, spark: .excited)
            }
            let m = StickState.minutesOfDay(displayDate)
            if m >= 720 && m < 810 {
                return MoodLineInfo(text: "轻松", tone: .good, spark: .relaxed)
            }
            if m >= 1080 {
                return MoodLineInfo(text: "愉悦", tone: .good, spark: .evening)
            }
            return MoodLineInfo(text: "良好", tone: .good, spark: .good)
        case .sit:
            if isMorningCalm {
                return MoodLineInfo(text: "专注", tone: .calm, spark: .focused)
            }
            if isAfternoonTired {
                return MoodLineInfo(text: "疲倦", tone: .warn, spark: .tired)
            }
            return MoodLineInfo(text: "平稳", tone: .good, spark: .stable)
        }
    }

    /// 颈椎压力过大提醒的可见度（0..1）。弯角 > 98° 开始出现，> 130° 完全显示。
    private var neckWarningOpacity: Double {
        let t = figureTiredness
        if t <= 0.6 { return 0 }
        if t >= 0.8 { return 1 }
        return (t - 0.6) / 0.2
    }

    /// 身体能量 0..100。综合 state + 时段 + tiredness：
    ///   - walk 兴奋(上午): 90 / walk 其他: 72
    ///   - sit 专注(上午): 78 / sit 疲倦(下午): 55→15 随 tiredness 衰减
    ///   - sit 其他: 55
    ///   - sleep: 8→45 随已睡时长缓慢回升（"充电中"）
    private var bodyEnergy: Double {
        switch displayState {
        case .walk:
            return isMorningEnergetic ? 90 : 72
        case .sit:
            if isMorningCalm    { return 78 }
            if isAfternoonTired { return 55 - 40 * figureTiredness }
            return 55
        case .sleep:
            let m = StickState.minutesOfDay(displayDate)
            let hoursSlept = max(0, min(8, Double(m) / 60.0))
            return min(45, 8 + hoursSlept * 5)
        }
    }

    /// 情绪数值 0..100。基于 mood 文字（"兴奋/良好/专注/疲倦/平稳"）映射。
    private var moodScore: Double {
        // walk: 兴奋 92, 良好 75, 愉悦 80
        // sit: 专注 82, 疲倦 30, 平稳 65
        // sleep: 25
        switch displayState {
        case .walk:
            if isMorningEnergetic { return 92 }
            let m = StickState.minutesOfDay(displayDate)
            if m >= 720 && m < 810 { return 78 }   // 午餐后轻松
            if m >= 1080            { return 80 }   // 晚间愉悦
            return 75                              // 普通 walk
        case .sit:
            if isMorningCalm      { return 82 }
            if isAfternoonTired   { return max(20, 50 - 30 * figureTiredness) }  // 50→20
            return 65
        case .sleep:
            return 25
        }
    }

    /// 能量条颜色：>75 绿 / >50 黄绿 / >30 橙 / ≤30 红
    private var energyColor: Color {
        let e = bodyEnergy
        if e >= 75 { return Color(red: 0.02, green: 0.59, blue: 0.41) }
        if e >= 50 { return Color(red: 0.55, green: 0.71, blue: 0.06) }
        if e >= 30 { return Color(red: 0.92, green: 0.55, blue: 0.06) }
        return Color(red: 0.93, green: 0.20, blue: 0.20)
    }

    /// Mood 颜色：跟 energyColor 同一套 4 档
    private var moodColor: Color { energyColor }

    // MARK: - 给 Widget 用的派生值

    private var primaryHeartRate: Int {
        // HEART RATE 行（walk）值形如 "92 bpm" → 92
        let v = displayState.primaryMetric.value
        return Int(v.split(separator: " ").first ?? "72") ?? 72
    }

    private var primaryDurationMinutes: Int {
        // DURATION 行（walk）值形如 "18 min" → 18
        let v = displayState.tertiaryMetric.value
        return Int(v.split(separator: " ").first ?? "0") ?? 0
    }

    // MARK: - 实时心率 + AI 风险分析

    /// 合成实时心率：晚间走路时随时间在 105–148 之间波动，
    /// 触发 "心率过高" 检测。接 HealthKit 后替换为真实读数即可。
    private var currentHeartRate: Int {
        let m = StickState.minutesOfDay(displayDate)
        switch displayState {
        case .walk:
            if m >= 1080 && m < 1320 {
                // 1080-1140: 中段 110-120
                // 1140-1200: 峰值段 130-148
                // 1200-1260: 缓降 125-140
                // 1260-1320: 回落 115-128
                let t = Double(m - 1080) / 240.0   // 0..1
                let base: Double
                if t < 0.25      { base = 115 + 8 * sin(t * .pi * 8) }
                else if t < 0.5  { base = 140 + 8 * sin(t * .pi * 8) }
                else if t < 0.75 { base = 132 + 8 * sin(t * .pi * 8) }
                else             { base = 120 + 8 * sin(t * .pi * 8) }
                return Int(base.rounded())
            }
            return 92
        case .sit:   return 78
        case .sleep: return 56
        }
    }

    /// 实时风险分析：仅在「晚间走路 + HR > 115」时返回报告
    private var aiReport: AIAnalysisReport? {
        AIRiskAnalyzer.analyze(
            state: displayState,
            heartRate: currentHeartRate,
            at: displayDate
        )
    }

    /// 今日所有异常（AI 实时 + HealthAnalyzer 历史 + 参考睡眠异常）
    private var unifiedAlerts: [UnifiedAlert] {
        AlertAggregator.aggregate(
            snapshots: HealthStore.shared.today,
            aiReport: aiReport
        )
    }

    /// 点击异常行：AI 实时报告 → AIAnalysisView；其他 → AlertDetailView
    private func handleAlertTap(_ a: UnifiedAlert) {
        if a.kind == .aiLive, a.aiReport != nil {
            showAIReport = true
        } else {
            selectedAlert = a
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mainContent

            if showChat {
                ChatOverlay(
                    state: displayState,
                    initialText: chatSeed,
                    onClose: { showChat = false }
                )
                .id(chatKey)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.28), value: showChat)
    }

    /// 主页（被外层 ZStack 包了一层）— GeometryReader + 个人面板
    private var mainContent: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width * 0.78

            ZStack(alignment: .leading) {
                // 1. 首页 (永远在底层, 面板打开时露在右侧 22%)
                homeBody
                    .frame(width: geo.size.width)

                // 2. 黑色蒙层 (仅显示在右侧 22% 的 home 上)
                if showPersonal {
                    HStack(spacing: 0) {
                        Spacer().frame(width: panelWidth)
                        Color.black.opacity(0.35)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.32)) { showPersonal = false }
                            }
                    }
                    .transition(.opacity)
                }

                // 3. 左侧滑出的个人面板 (78% 宽)
                PersonalView(
                    onClose: { withAnimation(.easeInOut(duration: 0.32)) { showPersonal = false } },
                    openSpecialists: $openSpecialists,
                    openDataRecord: $openDataRecord,
                    openWidgetPreview: $openWidgetPreview,
                    deviceSet: $deviceSet,
                    healthAuth: healthAuth
                )
                .frame(width: panelWidth)
                .offset(x: showPersonal ? 0 : -panelWidth)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.32), value: showPersonal)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard showPersonal else { return }
                        // 左滑超 60pt 关闭
                        if value.translation.width < -60 {
                            withAnimation(.easeInOut(duration: 0.32)) { showPersonal = false }
                        }
                    }
            )
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            // 30s 校准一次实际时间
            now = Date()
            // 30s 重新跑一次 HealthKit 抓取 + 状态推断（.today 持续增长）
            Task {
                _ = await HealthKitService.shared.captureSnapshot()
                inference = HealthKitService.shared.currentInference
            }
        }
        .onChange(of: displayState) { _ in
            // 状态切换时把当前快照写给 Widget
            let snap = SharedStickState(
                stateRaw: displayState.rawValue,
                englishName: displayState.englishName,
                actionPhrase: displayState.actionPhrase,
                heartRate: primaryHeartRate,
                mood: displayState.secondaryMetric.value,
                durationMinutes: primaryDurationMinutes,
                subLine: displayState.subLine,
                updatedAt: Date()
            )
            SharedStateStore.write(snap)
            // 通知 WidgetKit 立刻刷新 widget timeline (不等到 5min 后)
            // widget 暂时屏蔽；恢复后再启用
            // #if canImport(WidgetKit)
            // WidgetCenter.shared.reloadAllTimelines()
            // #endif
        }
        .onOpenURL { url in
            // widget tap 深链：stick://open?state=walk|sit|sleep
            // （.widgetURL 已经把状态带回来，这里只是占位接收）
            _ = url
        }
        .sheet(isPresented: $showFilm) {
            MiniFilmShareSheet(isPresented: $showFilm)
                .presentationBackground(Color.black)
        }
        // Chat 改到外层 ZStack（贴底）
        .sheet(isPresented: $showAIReport) {
            if let r = aiReport {
                AIAnalysisView(report: r, onClose: { showAIReport = false })
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $selectedAlert) { a in
            alertDetailView(for: a)
        }
        .sheet(isPresented: $showSleepReport) {
            SleepReportView(onClose: { showSleepReport = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNeckReport) {
            NeckPressureReportView(
                tiredness: figureTiredness,
                bendAngle: 20.0 + figureTiredness * 130.0,
                onClose: { showNeckReport = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // 启动 HealthKit 抓取 (1 分钟一次, 写到本地)
            Task {
                #if targetEnvironment(simulator)
                // 模拟器: 跳过 requestAuthorization (会无限阻塞等用户点弹窗), 直接注入 demo 数据
                HealthKitService.shared.startAutoCapture(interval: 60)
                await HealthKitDemoData.shared.injectIfNeeded()
                inference = HealthKitService.shared.currentInference
                #else
                // 真机: 弹系统授权弹窗
                await HealthKitService.shared.requestAuthorization()
                HealthKitService.shared.startAutoCapture(interval: 60)
                inference = HealthKitService.shared.currentInference
                #endif
            }
            // 检查各 metric 真实授权状态 (有/无/拒绝)
            healthAuth.refresh()
            // 注入数据写入需要时间, 1.5s / 3s 后再 refresh 确认
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                healthAuth.refresh()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                healthAuth.refresh()
            }
        }
    }

    // MARK: - 首页内容 (抽出来便于在 ZStack 中复用)

    private var homeBody: some View {
        ZStack {
            background

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    TopBarView(onMenuTap: { showPersonal = true })
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    // 徽章组（顶部右上方 — 跟 FeatureRow 卡片同一行）
                    HStack {
                        Spacer(minLength: 0)
                        EnergyBadge(
                            state: displayState,
                            level: bodyEnergy,
                            color: energyColor,
                            onTap: { showFilm = true }
                        )
                        MoodBadge(score: moodScore, color: moodColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)

                    // 3 行数据 + 心情 + 异常提示 (单行，不展开)
                    FeatureRow(
                        state: displayState,
                        deviceSet: deviceSet,
                        healthStatuses: healthAuth.statuses,
                        moodLine: displayMoodLine,
                        unifiedAlerts: unifiedAlerts,
                        onAlertTap: handleAlertTap
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)

                    // 主舞台 + 24h 竖向时间轴 (小人 + 右侧时间轴 侧边栏)
                    HStack(alignment: .top, spacing: 10) {
                        StageHeroView(
                            state: displayState,
                            mood: figureMood,
                            tiredness: figureTiredness,
                            neckWarningOpacity: neckWarningOpacity,
                            bodyEnergy: 0.6,
                            energyColor: Color.orange,
                            isScrubbing: isScrubbing,
                            inference: inference,
                            showDevicePicker: $showDevicePicker,
                            scrubOffset: $scrubOffset,
                            onPreview: { showFilm = true },
                            onSleepAlert: { showSleepReport = true },
                            onNeckWarningTap: { showNeckReport = true }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 400)

                        DayTimelineView(
                            schedule: StickState.daySchedule,
                            now: now,
                            scrubOffset: $scrubOffset,
                            showDevicePicker: $showDevicePicker
                        )
                        .frame(width: 22)
                        .frame(height: 400)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)

                    InputBar(
                        state: displayState,
                        text: $inputDraft,
                        onOpenChat: openChat
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func openChat(_ seed: String) {
        chatSeed = seed
        chatKey += 1
        showChat = true
    }

    // MARK: - 背景（v6 米色渐变 + 弱网格 + 状态柔光）

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // 弱网格（v6 style）
            Canvas { ctx, size in
                let step: CGFloat = 36
                var x: CGFloat = 0
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(Theme.grid), lineWidth: 0.5)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(Theme.grid), lineWidth: 0.5)
                    y += step
                }
            }
            .allowsHitTesting(false)

            // 顶部状态柔光
            RadialGradient(
                colors: [displayState.accentSoft.opacity(0.55), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 30,
                endRadius: 360
            )
            .animation(.easeInOut(duration: 0.45), value: displayState)
        }
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        let c = Calendar.current
        let nowComps = c.dateComponents([.year, .month, .day], from: Date())
        var comps = DateComponents()
        comps.year = nowComps.year
        comps.month = nowComps.month
        comps.day = nowComps.day
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return c.date(from: comps) ?? Date()
    }

    /// 通用异常详情 sheet — 历史洞察（睡眠不足 / 久坐 / 步数等）使用
    @ViewBuilder
    private func alertDetailView(for a: UnifiedAlert) -> some View {
        AlertDetailView(alert: a) { selectedAlert = nil }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - 颈椎压力 AI 分析报告

/// 用户点击"颈椎压力过大"徽章后弹出的 sheet。
/// 根据当前 tiredness 等级（0..1）和 head 弯曲角度（20° + 130°×t）生成 AI 分析报告。
/// 内容为本地模拟（没接 LLM），但风格、风险评估、建议都根据 level 动态生成。
private struct NeckPressureReportView: View {
    let tiredness: Double
    let bendAngle: Double
    let onClose: () -> Void

    /// 风险等级（0..1 → 低/中/高/严重）
    private var riskLevel: (label: String, color: Color) {
        switch tiredness {
        case ..<0.5:  return ("低", Color(red: 0.02, green: 0.59, blue: 0.41))
        case ..<0.7:  return ("中", Color(red: 0.92, green: 0.34, blue: 0.05))
        case ..<0.85: return ("高", Color(red: 0.93, green: 0.20, blue: 0.20))
        default:      return ("严重", Color(red: 0.72, green: 0.05, blue: 0.05))
        }
    }

    private var durationHours: Double { 0.5 + tiredness * 4.0 }

    private var currentTime: String {
        let c = Calendar.current
        let d = Date()
        let h = c.component(.hour, from: d)
        let m = c.component(.minute, from: d)
        return String(format: "%02d:%02d", h, m)
    }

    private var analysisBody: String {
        switch tiredness {
        case ..<0.5:
            return "过去 30 分钟你的头部前倾角度维持在 \(Int(bendAngle))° 左右，颈椎承受的额外压力约为正常直立姿势的 1.5 倍。当前属于轻度疲劳，建议每小时起身活动 2-3 分钟，避免进一步累积。"
        case ..<0.7:
            return "过去 1.5 小时内你的头部持续前倾 \(Int(bendAngle))°，相当于在颈椎上挂了约 12 公斤的沙袋（正常直立约 4.5 公斤）。这个角度会导致颈后肌群持续紧张，肩部也开始代偿。建议立刻做一组颈部拉伸，并把屏幕抬高到视线平行位置。"
        case ..<0.85:
            return "⚠️ 高风险：你的头部已经前倾 \(Int(bendAngle))° 长达近 \(String(format: "%.1f", durationHours)) 小时。颈椎承受的压力是正常的 3 倍以上（约 15-18 公斤），相当于一个 6 岁小孩坐在你的脖子上。椎间盘突出、肩颈僵硬、头晕恶心的风险显著上升。请立刻：① 离开工位 ② 做 5 分钟米字操 ③ 调整显示器高度 ④ 之后每 30 分钟强制起身。"
        default:
            return "🚨 严重警告：头部前倾达到 \(Int(bendAngle))°，已经进入可能造成颈椎反弓的角度。肌肉韧带长期被牵拉、椎动脉供血受影响，风险包括：颈椎曲度变直、椎间盘突出、神经根压迫、头晕手麻。不要再继续这个姿势。建议立即离开屏幕，去做专业理疗或就医检查。如果只是暂时性疲劳，请至少：① 缓慢做颈部米字操 ② 热敷颈后 15 分钟 ③ 把椅子降低让视线平视屏幕。"
        }
    }

    private var recommendations: [String] {
        switch tiredness {
        case ..<0.5:
            return [
                "保持当前姿势每小时起身一次",
                "做 30 秒颈部米字操",
                "喝一杯水补充水分",
            ]
        case ..<0.7:
            return [
                "立刻离开工位 3-5 分钟",
                "做 1 分钟米字操（前后左右各 5 次）",
                "调整显示器：上沿与视线平齐",
                "考虑加装笔记本支架",
            ]
        case ..<0.85:
            return [
                "立即停止当前工作，休息 5-10 分钟",
                "米字操 1 分钟 + 肩部环绕 30 秒",
                "热敷颈后 10 分钟",
                "调整工位：屏幕抬高、椅子升高、键盘下沉",
                "接下来每 30 分钟强制起身",
                "下班后做专业颈部按摩 / 推拿",
            ]
        default:
            return [
                "立即停止所有屏幕工作",
                "去最近的医院或理疗店做一次专业评估",
                "近期考虑颈椎 X 光 / MRI 检查",
                "暂停高强度脑力工作至少 1 天",
                "如伴随手麻、头晕、恶心，立即就医",
                "工位全面改造：升降桌 + 显示器支架 + 人体工学椅",
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 顶部风险条
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(riskLevel.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(riskLevel.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("风险等级")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundColor(Theme.slate)
                                Text(riskLevel.label)
                                    .font(.system(size: 16, weight: .heavy, design: .serif))
                                    .foregroundColor(riskLevel.color)
                            }
                            Text("采集时间 · \(currentTime)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.slate)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(riskLevel.color.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(riskLevel.color.opacity(0.4), lineWidth: 1)
                    )

                    sectionHeader("当前数据")
                    dataRow("头部前倾角度", "\(Int(bendAngle))°")
                    dataRow("不良姿势持续", String(format: "%.1f 小时", durationHours))
                    dataRow("颈椎承受压力", "约 \(Int(4.5 + tiredness * 18)) kg")
                    dataRow("疲劳强度", "\(Int(tiredness * 100))%")

                    sectionHeader("AI 分析")
                    Text(analysisBody)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundColor(Theme.navy)
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    sectionHeader("建议")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(recommendations.enumerated()), id: \.offset) { idx, rec in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                    .foregroundColor(riskLevel.color)
                                    .frame(width: 20, alignment: .trailing)
                                Text(rec)
                                    .font(.system(size: 13, weight: .regular, design: .serif))
                                    .foregroundColor(Theme.navy)
                                    .lineSpacing(3)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    Text("⚠️ 本报告为系统根据姿态信号估算，仅供参考；如有持续不适请咨询专业医师。")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("颈椎压力分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", action: onClose)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Theme.slate)
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 0.5)
        }
        .padding(.top, 4)
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(Theme.slate)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.navy)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - 主舞台（v6 风格）

private struct StageHeroView: View {
    let state: StickState
    let mood: StickFigureMood
    let tiredness: Double
    let neckWarningOpacity: Double
    let bodyEnergy: Double
    let energyColor: Color
    let isScrubbing: Bool
    let inference: StateInference.Result?
    @Binding var showDevicePicker: Bool
    @Binding var scrubOffset: Int?            // 接收时间线 binding，stage 也可拖
    var onPreview: () -> Void
    var onSleepAlert: () -> Void
    var onNeckWarningTap: () -> Void

    /// 拖动起点 + 起始 offset (用于把横向 delta 换算成分钟)
    @State private var dragStartOffset: Int? = nil
    @State private var dragWidth: CGFloat = 0
    @State private var isStageScrubbing: Bool = false

    /// 主舞台水平滑动 → 切时间。手势灵敏度：1 pt = 4 min（24h / iPhone 17 Pro 屏幕宽 ≈ 393 pt）
    /// - 左滑（delta.x > 0）→ 回到过去（offset 增加）
    /// - 右滑（delta.x < 0）→ 回到现在（offset 减少）
    private func handleStageDrag(translation: CGFloat, width: CGFloat) {
        dragWidth = width
        let baseOffset = dragStartOffset ?? scrubOffset ?? 0
        // 1 pt ≈ 4 min；24h=1440min ≈ 360pt full width
        let minutesPerPoint: CGFloat = 4
        let deltaMinutes = Int((translation / width) * 1440)
        let newOffset = max(0, min(1440, baseOffset + deltaMinutes))
        // snap 到 5 min
        scrubOffset = (newOffset / 5) * 5
    }

    /// 把 inference 副标拼成单行 mono 文本：CONF xx% · <first reason>
    private var inferenceSubline: String {
        guard let inf = inference else { return "INFERRING…" }
        let pct = Int((inf.confidence * 100).rounded())
        let reason = inf.reasons.first ?? "无数据"
        return "CONF \(pct)% · \(reason)"
    }

    /// 缺数据：inference 没跑出来，或跑出来但 reason 是 "无数据"
    private var hasNoData: Bool {
        guard let inf = inference else { return true }
        return inf.reasons.first == "无数据"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 舞台区（火柴人 + 透明背景，跟整页一个底色）
            ZStack {
                if hasNoData {
                    noDataStage
                        .transition(.opacity)
                } else {
                    StickFigureView(state: state, mood: mood, tiredness: tiredness, neckWarning: neckWarningOpacity)
                        .padding(.horizontal, 4)
                        .padding(.top, 0)
                        .padding(.bottom, 0)
                        .id(state)
                        .transition(.opacity)
                }

                // 颈椎压力过大提醒（左上角；tiredness > 0.6 开始淡入；点击弹 AI 报告）
                if neckWarningOpacity > 0.01 {
                    VStack {
                        HStack {
                            Button(action: onNeckWarningTap) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("颈椎压力过大")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .tracking(0.4)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color(red: 0.92, green: 0.34, blue: 0.05).opacity(0.92))
                                )
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .opacity(neckWarningOpacity)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: neckWarningOpacity)
                }

                // 右上角：状态名 + 副标（能量徽章已搬到顶部卡片区）
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            if state == .sleep {
                                SleepAlertChip(count: 2, onTap: onSleepAlert)
                                    .transition(.scale.combined(with: .opacity))
                            }
                            if hasNoData {
                                noDataBadge
                            }
                        }
                        // CONF xx% · 无数据 副标已去掉
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.45), value: state)
            .animation(.easeInOut(duration: 0.35), value: hasNoData)
            // 主舞台水平滑动 → 切换时间
            .contentShape(Rectangle())
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { dragWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, new in dragWidth = new }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        if dragStartOffset == nil {
                            dragStartOffset = scrubOffset ?? 0
                        }
                        isStageScrubbing = true
                        // 优先用 GeometryReader 拿到的真实宽度，回落到 320 防 nil
                        let width = dragWidth > 0 ? dragWidth : 320
                        handleStageDrag(translation: value.translation.width, width: width)
                    }
                    .onEnded { _ in
                        isStageScrubbing = false
                        dragStartOffset = nil
                    }
            )
            // 拖动时显示当前时间
            .overlay(alignment: .center) {
                if isStageScrubbing {
                    stageScrubBadge
                }
            }
        }
    }

    /// 拖动时主舞台中央显示的当前时间徽章
    private var stageScrubBadge: some View {
        let offset = scrubOffset ?? 0
        let m = StickState.minutesOfDay(Date().addingTimeInterval(-Double(offset) * 60))
        let hh = (m / 60) % 24
        let mm = m % 60
        return VStack(spacing: 2) {
            Text(String(format: "%02d:%02d", hh, mm))
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(Theme.navy)
            Text("← 左右滑动切换时间 →")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(Theme.slate)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.card.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - 缺数据状态（柔色，提示连接设备）

    private var noDataStage: some View {
        Button {
            showDevicePicker = true
        } label: {
            VStack(spacing: 10) {
                // 虚线小火柴人占位
                ZStack {
                    Circle()
                        .stroke(Theme.slate.opacity(0.25), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .frame(width: 56, height: 56)
                    Image(systemName: "iphone.badge.plus")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(Theme.slate.opacity(0.35))
                }
                Text("暂无数据")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Theme.slate.opacity(0.55))
                Text("连接智能设备以开始记录")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.slate.opacity(0.4))
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("连接设备")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundColor(Theme.slate.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    Capsule()
                        .stroke(Theme.slate.opacity(0.25), lineWidth: 0.8)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.slate.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.slate.opacity(0.12), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noDataBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.slate.opacity(0.4))
            Text("NO DATA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(Theme.slate.opacity(0.5))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.slate.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.slate.opacity(0.18), lineWidth: 0.8)
        )
    }

    private var stateBadge: some View {
        Button(action: onPreview) {
            HStack(spacing: 5) {
                Circle()
                    .fill(state.accent)
                    .frame(width: 7, height: 7)
                Text(state.englishName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundColor(Theme.navy)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(state.accent)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(state.accentSoft.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state.accent, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}

// MARK: - 能量徽章

private struct EnergyBadge: View {
    let state: StickState
    let level: Double           // 0..100
    let color: Color
    var onTap: () -> Void

    private let bodyW: CGFloat = 42
    private let bodyH: CGFloat = 14

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BODY ENERGY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(Theme.slate)
                // 手机电池：圆角外框 + 内部填充 + 右边小帽
                HStack(spacing: 1) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color.opacity(0.18))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(color)
                            .frame(width: max(0, (bodyW - 2) * CGFloat(level) / 100.0))
                            .padding(1)
                    }
                    .frame(width: bodyW, height: bodyH)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5)
                            .stroke(color.opacity(0.7), lineWidth: 0.9)
                    )
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.85))
                        .frame(width: 2.2, height: 6)
                }
                // 大数字（放在电池下方）
                Text("\(Int(level))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            // 徽章整体无框：只留 4×2 padding 贴边
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 心情数值徽章

/// 简单数字徽章：MOOD 标签 + 0-100 数字。无电池图标、无框 — 跟 BODY ENERGY 并列。
/// 颜色跟 bodyEnergy 同一套 4 档（绿/黄绿/橙/红）。
private struct MoodBadge: View {
    let score: Double      // 0..100
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MOOD")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Theme.slate)
            Text("\(Int(score))")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

// MARK: - AI 风险预警横幅

/// 主页上半部一条横向警示条，提示「晚间走路 + 心率过高」。
/// 点击整条进入 `AIAnalysisView` 看完整报告。
private struct AIRiskBanner: View {
    let report: AIAnalysisReport
    var onTap: () -> Void

    private var timeText: String {
        StickState.formatMinute(StickState.minutesOfDay(report.timestamp))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 左侧 ECG 图标
                ZStack {
                    Circle()
                        .fill(report.risk.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(report.risk.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("AI 风险预警")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(report.risk.color)
                        Text("·")
                            .foregroundColor(Theme.slate)
                        Text(timeText)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.slate)
                    }
                    Text("心率 \(report.heartRate) bpm · \(report.risk.label)度风险")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.navy)
                        .lineLimit(1)
                    Text(report.headline)
                        .font(.system(size: 10, weight: .regular, design: .serif))
                        .foregroundColor(Theme.slate)
                        .lineLimit(2)
                        .lineSpacing(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(report.risk.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(report.risk.color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(report.risk.color.opacity(0.32), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
