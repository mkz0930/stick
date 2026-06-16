import SwiftUI
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    /// 来自 widget 点击（stick://chat?seed=...），由 StickApp 写入，本视图消费后清空
    @Binding var pendingChatSeed: String?

    // HealthKit + HealthAuth 在 Xcode Preview (Canvas) 里会让预览变卡甚至 5s 超时
    // (HKHealthStore 构造 + 真实 framework import)。Preview 注入 Noop 替代，真 app
    // runtime 仍然用真 shared 单例。
    @StateObject private var hk: HealthKitService = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil {
            return HealthKitService.noop
        }
        #endif
        return HealthKitService.shared
    }()
    @StateObject private var healthAuth: HealthAuthService = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil {
            return HealthAuthService.noop
        }
        #endif
        return HealthAuthService.shared
    }()
    @StateObject private var chatHistory = ChatHistoryStore.shared
    @State private var now: Date = Date()
    @State private var scrubOffset: Int? = nil   // 0 = 现在；>0 表示过去多少分钟（窗口起点 = now - 24h）
    @State private var showFilm: Bool = false
    @State private var showSleepReport: Bool = false
    @State private var showNeckReport: Bool = false
    @State private var showSedentaryDetail: Bool = false
    @State private var showPersonal: Bool = false
    @State private var openDataRecord: Bool = false
    @State private var openWidgetPreview: Bool = false
    @State private var showDevicePicker: Bool = false
    @State private var showAIReport: Bool = false
    @State private var selectedAlert: UnifiedAlert? = nil
    @State private var deviceSet: Set<DeviceID> = [.iPhone]
    /// 场景相位（前台/后台/非活跃）
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    /// 上次切到后台的时间（用于黑屏期间久坐反推）
    @State private var backgroundedAt: Date? = nil
    /// FeatureRow 展开态（提升到 ContentView，让 StageHeroView 也能读到 — 控制小人淡出）
    @State private var featureRowExpanded: Bool = false
    /// 订阅 HealthStore：30s 一次 captureSnapshot() 会把 HealthSnapshot 写到 .today，
    /// 触发本视图重渲 → todaySteps computed property 重新求和，FeatureRow StepsLine 实时刷新。
    @ObservedObject private var healthStore: HealthStore = HealthStore.shared
    /// 观察 HealthKitService：步数打断久坐时立即响应
    @ObservedObject private var hkService: HealthKitService = .shared

    // HealthKit 状态推断（30s 重算一次）
    @State private var inference: StateInference.Result? = nil

    /// 首页久坐分钟数（从 HealthKit 直接查询，与数据记录一致）
    @State private var homeSedentaryMinutes: Int = 0
    /// 睡眠数据是否有效（用于判断久坐累计是否可信）
    @State private var hasValidSleepData: Bool = false

    /// 基于真实快照分析的当前连续久坐分钟数（每30秒更新一次）
    @State private var currentSitMinutes: Int = 0
    /// 当前久坐 session 开始时刻（从快照时间推算，用于秒级跳动）
    @State private var currentSitStartTime: Date? = nil
    /// 上次分析时间（控制30秒刷新一次）
    @State private var lastSitAnalysisTime: Date = .distantPast
    /// Timer 触发器，每秒 +1 驱动 live 秒表刷新
    @State private var tick: Int = 0

    // Chat
    @State private var showChat: Bool = false
    @State private var chatSeed: String = ""
    @State private var chatKey: Int = 0
    @State private var inputDraft: String = ""
    /// 主页 + 按钮触发：开 chat + 标记让 ChatOverlay 自动打开相册/相机选图
    @State private var chatPendingPhoto: Bool = false
    /// 点击历史记录 → 滚动到该消息的 UUID
    @State private var targetScrollId: UUID? = nil
    /// 滚动触发器：每次历史导航 +1，overlay 用 onChange 响应（不重建 overlay）
    @State private var scrollTrigger: Int = 0
    @State private var showCamera: Bool = false
    @State private var capturedImage: UIImage?

    private var displayOffset: Int {
        scrubOffset ?? 0
    }

    private var displayDate: Date {
        now.addingTimeInterval(-Double(displayOffset) * 60)
    }

    /// 小人显示状态：基于真实 HealthKit 步数数据生成的时刻表 + 快照兜底
    /// 优先级：真实时刻表 (realDaySchedule) > 实时快照 > 时段硬编码
    private var displayState: StickState {
        let dt = displayDate
        let m = StickState.minutesOfDay(dt)

        // 0. 真实数据驱动的 24h 时刻表（最高优先级）
        if let rs = hk.realDaySchedule, let seg = rs.first(where: { $0.contains(m) }) {
            return seg.state
        }

        let hour = Calendar.current.component(.hour, from: dt)
        let minute = Calendar.current.component(.minute, from: dt)
        let isSleepHour = hour >= 23 || hour < 7
        let isNapHour = hour == 13 && minute >= 0 && minute < 30

        // 1. 近期的真实快照：walk 始终覆盖时段默认
        if let latest = HealthStore.shared.today.sorted(by: { $0.timestamp > $1.timestamp }).first {
            let age = Date().timeIntervalSince(latest.timestamp)
            if age < 90, let mapped = mapBodyState(latest.bodyState) {
                if mapped == .walk { return .walk }
                if !isSleepHour && !isNapHour { return mapped }
            }
        }

        // 2. 睡眠时段 → sleep
        if isSleepHour { return .sleep }
        if isNapHour { return .sleep }

        // 3. 默认坐着
        return .sit
    }

    /// 把 HealthStore 的 bodyState 字符串映射到 StickState
    private func mapBodyState(_ raw: String) -> StickState? {
        switch raw {
        case "walk":  return .walk
        case "sit":   return .sit
        case "stand": return .stand
        case "sleep": return .sleep
        default:      return nil
        }
    }

    private var isScrubbing: Bool {
        guard let s = scrubOffset else { return false }
        return s > 0
    }

    /// 判断 chatSeed 是否为 widget 风险提醒触发（格式：久坐风险提醒:XX分钟）
    private func isWidgetRiskSeed(_ seed: String) -> Bool {
        seed.hasPrefix("久坐风险提醒:")
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
        case .stand:
            return MoodLineInfo(text: "待机", tone: .calm, spark: .stable)
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

    /// 腰椎压力过大提醒的可见度（0..1）。弯角 > 98° 开始出现，> 130° 完全显示。
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
        case .stand:
            return 65   // 站立待机中，能量平稳
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

    /// 今日累计久坐分钟数（来自 healthStore.today 的快照统计）
    private var todaySitMinutes: Int {
        healthStore.today.filter { $0.bodyState == "sit" }.count
    }

    /// 当前久坐 session live 时长（M:SS），基于 currentSitStartTime 每秒跳动
    var sitDurationText: String? {
        _ = tick  // 每秒触发重算
        guard let startTime = currentSitStartTime, displayState == .sit else { return nil }
        let elapsed = Date().timeIntervalSince(startTime)
        let totalSeconds = Int(elapsed)
        let mm = totalSeconds / 60
        let ss = totalSeconds % 60
        return String(format: "%d:%02d", mm, ss)
    }

    /// 今日累计久坐描述文本（供 FeatureRow 显示）- X.Xh 格式
    var todaySitDescription: String {
        // 睡眠数据无效时（用户未在健康 App 记录睡眠），久坐值不可信，显示 "--"
        guard hasValidSleepData else { return "--" }
        let m = homeSedentaryMinutes
        if m == 0 { return "暂无久坐" }
        return String(format: "%.1fh", Double(m) / 60.0)
    }

    private var moodScore: Double {
        // walk: 兴奋 92, 良好 75, 愉悦 80
        // stand: 平稳 70
        // sit: 专注 82, 疲倦 30, 平稳 65
        // sleep: 25
        switch displayState {
        case .walk:
            if isMorningEnergetic { return 92 }
            let m = StickState.minutesOfDay(displayDate)
            if m >= 720 && m < 810 { return 78 }   // 午餐后轻松
            if m >= 1080            { return 80 }   // 晚间愉悦
            return 75                              // 普通 walk
        case .stand:
            return 70                              // 平稳待机
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
        case .stand: return 70   // 站立待机：平稳静息
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

    /// 今日累计步数：取最后一条 snapshot 的 cumulativeStepCount（全天累计值）。
    /// 每条 snapshot 的 cumulativeStepCount = recentSum(dayStart→now)，是全天累计而非增量，
    /// 所以取最新一条即为今日总步数，无需 sum。
    private var todaySteps: Int {
        healthStore.today.last?.cumulativeStepCount ?? 0
    }

    /// 今日行走分钟数：bodyState == "walk" 的快照数
    private var todayWalkMinutes: Int {
        healthStore.today.filter { $0.bodyState == "walk" }.count
    }

    /// 点击异常行：AI 实时报告 → AIAnalysisView；其他 → AlertDetailView
    private func handleAlertTap(_ a: UnifiedAlert) {
        if a.kind == .aiLive, a.aiReport != nil {
            showAIReport = true
        } else {
            selectedAlert = a
        }
    }

    /// Preview 模式检测 — Xcode 跑 #Preview 时设了这个环境变量
    fileprivate static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil
    }

    var body: some View {
        mainContent
            .fullScreenCover(isPresented: $showChat) {
                ChatOverlay(
                    state: displayState,
                    initialText: chatSeed,
                    riskSeed: isWidgetRiskSeed(chatSeed) ? chatSeed : nil,
                    targetScrollId: targetScrollId,
                    scrollTrigger: scrollTrigger,
                    pendingPhotoUpload: chatPendingPhoto,
                    onClose: {
                        dismissKeyboard()
                        showChat = false
                        chatPendingPhoto = false   // 重置标记，下次开 chat 不再自动开图
                    }
                )
                .id(chatKey)
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                // 调试用：env STICK_TEST_OPEN_CHAT=1 → 启动时自动开 chat
                if ProcessInfo.processInfo.environment["STICK_TEST_OPEN_CHAT"] != nil {
                    openChat("")
                }
                // 模拟器调试：env STICK_MOCK_HEALTH=1 → 启动时自动载入 Documents/MockHealth.json
                #if targetEnvironment(simulator)
                if ProcessInfo.processInfo.environment["STICK_MOCK_HEALTH"] != nil {
                    let n = MockHealthDataLoader.shared.loadBundledIfExists()
                    print("[ContentView] 🧪 Mock 健康数据载入: \(n) 条")
                    // 触发一次今天的久坐重算
                    Task { @MainActor in
                        homeSedentaryMinutes = await HealthKitService.shared.todaySedentaryMinutes()
                        currentSitMinutes = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                    }
                }
                #endif
            }
            .onChange(of: pendingChatSeed) { _, newSeed in
                // widget 点击 → 打开 chat（预填 seed）→ 清空避免重复触发
                guard let seed = newSeed, !seed.isEmpty else { return }
                openChat(seed)
                pendingChatSeed = nil
            }
            .onChange(of: showChat) { _, isShowing in
                // 关闭 ChatOverlay 时强制收键盘；打开时不需要主动弹（依赖 ChatOverlay 内部 onAppear）
                if !isShowing {
                    dismissKeyboard()
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(image: $capturedImage)
                    .ignoresSafeArea()
            }
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
                    openDataRecord: $openDataRecord,
                    openWidgetPreview: $openWidgetPreview,
                    deviceSet: $deviceSet,
                    healthAuth: healthAuth,
                    chatHistory: chatHistory,
                    onHistoryTap: { id in
                        targetScrollId = id
                        scrollTrigger += 1
                        withAnimation(.easeInOut(duration: 0.28)) { showChat = true }
                    },
                    onOpenChat: { seed in
                        // 关掉个人面板，打开聊天
                        withAnimation(.easeInOut(duration: 0.32)) { showPersonal = false }
                        openChat(seed)
                    },
                    currentSitDuration: sitDurationText,
                    currentBodyState: displayState.rawValue
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Preview 模式跳过 — 不让 Timer 反复触发重渲染
            guard !Self.isRunningForPreviews else { return }
            // 1s 校准一次（让坐姿秒表 / DURATION 等 live 数据每秒跳一次）
            now = Date()
            // 每 30 秒基于真实快照重新分析连续久坐时长
            if Date().timeIntervalSince(lastSitAnalysisTime) >= 30 {
                lastSitAnalysisTime = Date()
                let prevMinutes = currentSitMinutes
                Task {
                    let newMinutes = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                    // 如果新分析结果比当前记录更长，说明session在延续，更新开始时刻
                    if newMinutes > prevMinutes {
                        // session 延长：从当前时刻往前推 newMinutes 分钟作为开始时刻
                        currentSitStartTime = Date().addingTimeInterval(-Double(newMinutes) * 60)
                    }
                    currentSitMinutes = newMinutes
                    if newMinutes == 0 {
                        currentSitStartTime = nil
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            // Preview 模式跳过 — 不让 Timer 反复触发重渲染
            guard !Self.isRunningForPreviews else { return }
            // 30s 重新跑一次 HealthKit 抓取 + 状态推断（.today 持续增长）
            Task {
                _ = await HealthKitService.shared.captureSnapshot()
                inference = HealthKitService.shared.currentInference
                // 每 5 分钟重新生成一次 24h 时刻表（不必 30s 一次，太重）
                if Calendar.current.component(.minute, from: Date()) % 5 == 0 {
                    await HealthKitService.shared.computeDaySchedule()
                }
            }
        }
        .onChange(of: displayState) { oldValue, newValue in
            // 久坐被打断或恢复时，立即分析一次
            if newValue == .sit {
                // 进入坐姿：立即触发一次快照分析，获取最新连续久坐时长
                Task {
                    let sitMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                    currentSitMinutes = sitMins
                    if sitMins > 0 {
                        currentSitStartTime = Date().addingTimeInterval(-Double(sitMins) * 60)
                    } else {
                        currentSitStartTime = nil
                    }
                    lastSitAnalysisTime = Date()
                }
            } else {
                // 离开坐姿：立即清空计时
                currentSitMinutes = 0
                currentSitStartTime = nil
            }
            // Preview 模式跳过 — Widget reload 在 Preview 里会卡死
            guard !Self.isRunningForPreviews else { return }
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
            // 通知 WidgetKit 立刻刷新 widget timeline（不等到 5min 后）
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // 切到后台：记录时间
            if newPhase != .active {
                backgroundedAt = Date()
            }
            // 回到前台：从 HealthKit 直接查询今日累计久坐分钟数，反推开始时刻
            if oldPhase != .active && newPhase == .active {
                guard !Self.isRunningForPreviews else { return }
                Task {
                    // 从 HealthKit 直接读今日累计久坐（考虑睡眠校正）
                    let sedentary = await HealthKitService.shared.todaySedentaryMinutes()
                    let sleepHours = await HealthKitService.shared.todaySleepHours()
                    let validSleep = sleepHours ?? 0 > 0
                    let adjustedSedentary = validSleep ? max(0, sedentary - Int((sleepHours ?? 0) * 60)) : 0

                    if adjustedSedentary > 0 {
                        // 从 HealthKit 今日累计久坐反推 session 开始时刻
                        currentSitStartTime = Date().addingTimeInterval(-Double(adjustedSedentary) * 60)
                        currentSitMinutes = adjustedSedentary
                        hasValidSleepData = true
                    } else {
                        currentSitStartTime = nil
                        currentSitMinutes = 0
                        hasValidSleepData = false
                    }
                    // 同时刷新一次快照分析
                    let snapMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                    if snapMins > 0 {
                        currentSitMinutes = snapMins
                        currentSitStartTime = Date().addingTimeInterval(-Double(snapMins) * 60)
                    }
                    lastSitAnalysisTime = Date()
                    // 回到前台时也重算时刻表（黑屏期间可能有新数据）
                    await HealthKitService.shared.computeDaySchedule()
                }
            }
        }
        .onChange(of: hkService.lastMovementTime) { oldValue, newValue in
            // HealthKit 检测到明显步数增加 → 立即打断久坐，重新计时
            guard let newMovement = newValue, oldValue != newValue else { return }
            guard !Self.isRunningForPreviews else { return }
            // 只要检测到新的大步数（>30步/分钟），立即清零计时器
            // 下一次 currentSedentarySessionMinutes 分析会基于新的快照重新计算
            currentSitMinutes = 0
            currentSitStartTime = nil
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
                .presentationDetents([.medium, .large])        // 弹到底 + 拖到中间
                .presentationDragIndicator(.visible)            // 顶部小横条
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))  // 半屏时点外部能交互主页
                .presentationCornerRadius(28)                  // 顶部圆角
        }
        .sheet(isPresented: $showSleepReport) {
            SleepReportView(onClose: { showSleepReport = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNeckReport) {
            NeckPressureReportView(
                onClose: { showNeckReport = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Preview 模式完全短路 — 不跑 HealthKit / Timer / refresh
            guard !Self.isRunningForPreviews else { return }
            // 启动 HealthKit 抓取 (1 分钟一次, 写到本地)
            Task {
                // 真机: 弹系统授权弹窗
                await HealthKitService.shared.requestAuthorization()
                HealthKitService.shared.startAutoCapture(interval: 60)
                inference = HealthKitService.shared.currentInference
                // 加载今日久坐分钟数（从 HealthKit 直接查询，与数据记录一致）
                homeSedentaryMinutes = await HealthKitService.shared.todaySedentaryMinutes()
                // 减去睡眠时间（只有睡眠数据有效时才做校正，否则久坐值不可信）
                if let sleepHours = await HealthKitService.shared.todaySleepHours(), sleepHours > 0 {
                    let sleepMinutes = Int(sleepHours * 60)
                    homeSedentaryMinutes = max(0, homeSedentaryMinutes - sleepMinutes)
                    hasValidSleepData = true
                } else {
                    // 睡眠数据为空，久坐累计不可信，置零但不显示（用 "--" 代替）
                    hasValidSleepData = false
                }
                // 初始加载当前连续久坐时长（基于真实快照分析）
                let sitMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                currentSitMinutes = sitMins
                if sitMins > 0 {
                    currentSitStartTime = Date().addingTimeInterval(-Double(sitMins) * 60)
                }
                lastSitAnalysisTime = Date()
                // 计算今天真实的 24h 时刻表（驱动时间轴 + 小人状态）
                await HealthKitService.shared.computeDaySchedule()
            }
            // 检查各 metric 真实授权状态 (有/无/拒绝)
            healthAuth.refresh()
        }
    }

    // MARK: - 首页内容 (抽出来便于在 ZStack 中复用)

    private var homeBody: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                background

                // ① 顶部固定层：TopBar + FeatureRow（叠加在小人上方，展开时覆盖不下推）
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 0) {
                        TopBarView(onMenuTap: { showPersonal = true })
                        Spacer(minLength: 0)
                        #if targetEnvironment(simulator)
                        // 模拟器调试按钮：载入 Documents/MockHealth.json 当真实数据用
                        Button {
                            Task { @MainActor in
                                let n = MockHealthDataLoader.shared.loadBundledIfExists()
                                print("[ContentView] 🧪 载入 mock 数据: \(n) 条")
                                homeSedentaryMinutes = await HealthKitService.shared.todaySedentaryMinutes()
                                currentSitMinutes = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                            }
                        } label: {
                            Image(systemName: "flask")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.slate)
                                .padding(8)
                        }
                        #endif
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    FeatureRow(
                        state: displayState,
                        deviceSet: deviceSet,
                        healthStatuses: healthAuth.statuses,
                        moodLine: displayMoodLine,
                        moodScore: moodScore,
                        stressScore: 100 - moodScore,
                        bodyScore: bodyEnergy,
                        bodyScoreColor: energyColor,
                        unifiedAlerts: unifiedAlerts,
                        sitDurationText: sitDurationText,
                        todaySitDescription: todaySitDescription,
                        todaySteps: todaySteps,
                        todayWalkMinutes: todayWalkMinutes,
                        isExpanded: $featureRowExpanded,
                        onAlertTap: handleAlertTap,
                        onLockTap: { showDevicePicker = true },
                        onSedentaryTap: { showSedentaryDetail = true },
                        onCardTap: { showChat = true }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }
                .zIndex(2)
                .fixedSize(horizontal: false, vertical: true)  // 高度固定，展开时覆盖小人

                // ② ScrollView 内容（小人 + 时间轴；在下层）
                let scrollContent = VStack(spacing: 0) {
                    // 为 FeatureRow 折叠态预留高度（190pt — 小人 + 时间轴整体下移 120pt，大小不变）
                    Color.clear.frame(height: 190)

                    HStack(alignment: .top, spacing: 10) {
                        StageHeroView(
                            state: displayState,
                            mood: figureMood,
                            tiredness: figureTiredness,
                            neckWarningOpacity: neckWarningOpacity,
                            bodyEnergy: bodyEnergy,
                            energyColor: energyColor,
                            isScrubbing: isScrubbing,
                            inference: inference,
                            showDevicePicker: $showDevicePicker,
                            scrubOffset: $scrubOffset,
                            onPreview: { showFilm = true },
                            onSleepAlert: { showSleepReport = true },
                            onNeckWarningTap: { showNeckReport = true }
                        )
                        .opacity(featureRowExpanded ? 0.04 : 1.0)
                        .animation(.easeInOut(duration: 0.28), value: featureRowExpanded)
                        .frame(maxWidth: .infinity)
                        .frame(height: 400)

                        DayTimelineView(
                            schedule: hk.realDaySchedule ?? StickState.daySchedule,
                            now: now,
                            scrubOffset: $scrubOffset,
                            showDevicePicker: $showDevicePicker
                        )
                        .frame(width: 50)
                        .frame(height: 400)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)

                    Spacer().frame(height: 96)
                }

                if Self.isRunningForPreviews {
                    scrollContent
                } else {
                    ScrollView(.vertical, showsIndicators: false) { scrollContent }
                }

                // ③ InputBar 钉在屏幕 0.9 位置
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geo.size.height * 0.9 - 44)
                    InputBar(
                        state: displayState,
                        text: $inputDraft,
                        onOpenChat: openChat,
                        onOpenCamera: openCamera,
                        onPlusTap: openChatWithPhoto,
                        lastHistoryPrompt: chatHistory.loadedMessages.last(where: { $0.role == "user" })?.content
                    )
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func openChat(_ seed: String) {
        chatSeed = seed
        chatKey += 1
        showChat = true
    }

    /// InputBar + 按钮触发：开 chat + 让 ChatOverlay 自动打开相册/相机选图给 LLM 视觉分析
    private func openChatWithPhoto() {
        chatSeed = ""
        chatKey += 1
        chatPendingPhoto = true
        showChat = true
    }

    private func openCamera() {
        showCamera = true
    }

    /// 强制收起系统键盘
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - 背景（v6 米色渐变 + 弱网格 + 状态柔光）

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            // Preview 跳过网格 Canvas + RadialGradient（这两个是最重的渲染源）
            if !Self.isRunningForPreviews {
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

// MARK: - 腰椎压力 AI 分析报告

/// 用户点击"腰椎压力过大"徽章后弹出的 sheet。
/// **改为基于真实 HealthKit 数据**（久坐/HR/HRV/步数/睡眠），没有异常就不显示风险
/// 取代之前基于 tiredness（姿态估算）的硬编码分级。
private struct NeckPressureReportView: View {
    let onClose: () -> Void

    @State private var report: RealHealthReport = RealHealthAnalyzer.shared.analyze()

    private var currentTime: String {
        let c = Calendar.current
        let d = Date()
        let h = c.component(.hour, from: d)
        let m = c.component(.minute, from: d)
        return String(format: "%02d:%02d", h, m)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 顶部风险条
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(report.risk.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: report.risk == .normal ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(report.risk.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("风险等级")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .tracking(0.6)
                                    .foregroundColor(Theme.slate)
                                Text(report.risk.label)
                                    .font(.system(size: 16, weight: .heavy, design: .serif))
                                    .foregroundColor(report.risk.color)
                            }
                            Text("数据来源 · HealthKit · \(currentTime)")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.slate)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(report.risk.color.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(report.risk.color.opacity(0.4), lineWidth: 1)
                    )

                    sectionHeader("HealthKit 真实数据")
                    if report.keyMetrics.isEmpty {
                        Text("暂无 HealthKit 数据")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.slate)
                            .padding(14)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(Array(report.keyMetrics.enumerated()), id: \.offset) { _, metric in
                                HStack {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(metric.isAbnormal ? Color(red: 0.93, green: 0.20, blue: 0.20) : Color(red: 0.02, green: 0.59, blue: 0.41))
                                            .frame(width: 6, height: 6)
                                        Text(metric.label)
                                            .font(.system(size: 13, weight: .regular, design: .serif))
                                            .foregroundColor(Theme.slate)
                                    }
                                    Spacer()
                                    Text(metric.value)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundColor(metric.isAbnormal ? Color(red: 0.93, green: 0.20, blue: 0.20) : Theme.navy)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6).fill(Theme.card)
                                )
                            }
                        }
                    }

                    sectionHeader("AI 分析")
                    Text(report.analysisText)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundColor(Theme.navy)
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5)
                        )

                    sectionHeader("建议")
                    if report.recommendations.isEmpty {
                        Text("当前无需特别建议")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.slate)
                            .padding(14)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(report.recommendations.enumerated()), id: \.offset) { idx, rec in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                        .foregroundColor(report.risk.color)
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
                            RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 0.5)
                        )
                    }

                    Text("⚠️ 本报告基于 HealthKit 真实数据（HR / HRV / 步数 / 久坐 / 静息心率）。如有持续不适请咨询专业医师。")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("健康分析")
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
        VStack(alignment: .center, spacing: 0) {
            // 舞台区（火柴人 + 透明背景，跟整页一个底色）
            ZStack {
                // 永远画小人（让用户看到 30° 低头 + 低落表情等所有视觉）
                StickFigureView(state: state, mood: mood, tiredness: tiredness, neckWarning: neckWarningOpacity)
                    .padding(.horizontal, 4)
                    .padding(.top, 70)
                    .padding(.bottom, 0)
                    .id(state)
                    .transition(.opacity)

                // 腰椎压力过大提醒（小人腰椎位置；tiredness > 0.6 开始淡入；点击弹 AI 报告）
                if neckWarningOpacity > 0.01 {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer().frame(height: 250)
                        HStack {
                            Button(action: onNeckWarningTap) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text("腰椎压力过大")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                Group {
                    if ContentView.isRunningForPreviews {
                        // Preview 跳过嵌套 GeometryReader；用 360 作为 iPhone 17 宽度估计
                        Color.clear.onAppear { dragWidth = 360 }
                    } else {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { dragWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, new in dragWidth = new }
                        }
                    }
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
                    Image(systemName: "square.and.arrow.up")
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

// MARK: - Preview (轻量 stub)
// 真 ContentView 含 1100 行 SwiftUI + HealthKit + Timer + onAppear Task，
// 渲染时间 > 5s 会触发 Xcode "Updating took more than 5 seconds" 超时。
// 这里渲染一个 stub：顶栏 / FeatureRow / 主舞台 / 时间线 / 输入栏 静态组合，
// 不挂 onAppear / 不用 StateObject / 不 import HealthKit framework。
private struct ContentViewPreviewStub: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶栏
                HStack {
                    Capsule().fill(Theme.navy).frame(width: 22, height: 2.5)
                    Spacer()
                    Capsule().fill(Theme.navy).frame(width: 22, height: 2.5)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // FeatureRow 4 行静态
                VStack(alignment: .leading, spacing: 4) {
                    featureLine("SEDENTARY", "0:00", "持续久坐")
                    featureLine("POSTURE",   "POOR",  "姿态·前倾")
                    featureLine("HEART RATE", "78 bpm", "心率·静息")
                    featureLine("MOOD",      "良好",   "心情·愉悦")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                // 主舞台 stub（简化版 StickFigure）
                ZStack {
                    StickFigureView(state: .sit, mood: .normal, tiredness: 0.2, neckWarning: 0)
                        .padding(.horizontal, 32)
                }
                .frame(height: 280)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom))
                )

                // 时间线 stub
                HStack(spacing: 1) {
                    ForEach(0..<24, id: \.self) { i in
                        Rectangle()
                            .fill([Color.green, .orange, .purple][i % 3])
                            .frame(maxWidth: .infinity)
                            .frame(height: 8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                // 输入栏 stub
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundColor(Theme.mist)
                    Text("安排任务, Stick 帮你完成")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.slate)
                    Spacer()
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(Theme.mist)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.card)
                )
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }

    private func featureLine(_ label: String, _ value: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(StickState.sit.accent).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Theme.slate)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.navy)
            Text(desc)
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundColor(Theme.mist)
            Spacer()
        }
    }
}

#Preview {
    ContentView(pendingChatSeed: .constant(nil))
}

// MARK: - 能量徽章
/* [已注释] 能量徽章下线
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
*/  // [已注释] 能量徽章下线

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
