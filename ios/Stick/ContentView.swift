import SwiftUI
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 步态质量数据（从 HealthKit 步速等指标综合计算）
struct WalkingQualityData {
    /// 平均步速 (m/s)
    let avgSpeed: Double?
    /// 双支撑时间占比 (%)
    let avgDoubleSupport: Double?
    /// 步态评分 (0-100)
    let gaitScore: Int
    /// 睡眠质量标签
    let sleepQualityLabel: String
    /// 夜间清醒次数
    let nightWakeCount: Int
    /// 夜间清醒总分钟数
    let nightWakeTotalMin: Int

    /// 从真实 HealthKitService.WalkingQuality 构造
    static func from(_ wq: HealthKitService.WalkingQuality?) -> WalkingQualityData {
        guard let wq else {
            return WalkingQualityData(
                avgSpeed: nil,
                avgDoubleSupport: nil,
                gaitScore: 60,
                sleepQualityLabel: "--",
                nightWakeCount: 0,
                nightWakeTotalMin: 0
            )
        }
        return WalkingQualityData(
            avgSpeed: wq.avgSpeed,
            avgDoubleSupport: wq.avgDoubleSupport,
            gaitScore: wq.gaitScore,
            sleepQualityLabel: wq.sleepQualityLabel,
            nightWakeCount: wq.nightWakeCount,
            nightWakeTotalMin: wq.nightWakeTotalMin
        )
    }
}

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
    /// swipe gesture 强制覆盖的状态（nil = 跟时间走）。StageHeroView 在 onEnded 命中 swipe 时写入，
    /// 同时把 scrubOffset 跳到该 state 第一个 segment 的中点；scrubOffset 归零时自动清空。
    @State private var manualStateOverride: StickState? = nil
    @State private var showFilm: Bool = false
    @State private var showSleepReport: Bool = false
    @State private var showPersonal: Bool = false
    @State private var openDataRecord: Bool = false
    /// 真机调试：注入 7 天 mock 数据到 HealthKit（让"导出最近 7 天"按钮能看到多天数据）
    @State private var showInjectConfirm: Bool = false
    @State private var injectStatus: String? = nil
    @State private var openWidgetPreview: Bool = false
    @State private var showDevicePicker: Bool = false
    @State private var showSedentaryDetail: Bool = false
    @State private var featureRowExpanded: Bool = false
    @State private var showAIReport: Bool = false
    @State private var selectedAlert: UnifiedAlert? = nil
    @State private var deviceSet: Set<DeviceID> = [.iPhone]
    /// 场景相位（前台/后台/非活跃）
    @Environment(\.scenePhase) private var scenePhase: ScenePhase
    /// 上次切到后台的时间（用于黑屏期间久坐反推）
    @State private var backgroundedAt: Date? = nil
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
    /// 主页相机按钮 / 相机 chip（拍食物、报告解读）触发：开 chat + 标记让 ChatOverlay 自动激活 chip + 开相机
    @State private var chatPendingCamera: Bool = false
    /// autoTopic chip（饮食建议）触发：开 chat + 标记让 ChatOverlay 自动调 LLM 给出个性化建议
    @State private var chatPendingTopic: String? = nil
    /// 点击历史记录 → 滚动到该消息的 UUID
    @State private var targetScrollId: UUID? = nil
    /// 滚动触发器：每次历史导航 +1，overlay 用 onChange 响应（不重建 overlay）
    @State private var scrollTrigger: Int = 0
    @State private var showCamera: Bool = false
    @State private var capturedImage: UIImage?
    /// 步态质量数据（实时从 HealthKit 读取）
    @State private var walkingQuality: WalkingQualityData? = nil
    /// 当前心率（实时从 HealthKit 读取）
    @State private var realHeartRate: Int? = nil
    /// 今日睡眠时长（小时，HealthKit sleepAnalysis 汇总；nil = 未授权或无数据）
    @State private var todaySleepHours: Double? = nil

    private var displayOffset: Int {
        scrubOffset ?? 0
    }

    private var displayDate: Date {
        now.addingTimeInterval(-Double(displayOffset) * 60)
    }

    /// 小人显示状态：基于真实 HealthKit 步数数据生成的时刻表 + 快照兜底
    /// 优先级：manualStateOverride（swipe 强制覆盖）> 真实时刻表 (realDaySchedule) > 实时快照 > 时段硬编码
    private var displayState: StickState {
        // swipe 切状态后强制使用 override，直到用户点 "回到现在"
        if let override = manualStateOverride {
            return override
        }
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

    /// 真实数据驱动的副标文字（优先使用实时 HealthKit 数据）
    private var realSubLine: String {
        let state = displayState
        let hr = realHeartRate.map { "\($0) bpm" } ?? "-- bpm"
        let steps = todaySteps > 0 ? "\(todaySteps) 步" : ""

        switch state {
        case .walk:
            var parts: [String] = []
            if let wq = walkingQuality {
                if let sp = wq.avgSpeed {
                    parts.append(String(format: "步速 %.2f m/s", sp))
                }
                parts.append("心率 \(hr)")
                if !steps.isEmpty { parts.append(steps) }
            } else {
                parts = ["步态稳定 · 心率 \(hr)"]
            }
            return parts.joined(separator: " · ")
        case .sit:
            let sitMins = homeSedentaryMinutes > 0 ? "\(homeSedentaryMinutes) 分" : "--"
            return "久坐 \(sitMins) · 心率 \(hr)"
        case .stand:
            return "无活动 · 心率 \(hr)"
        case .sleep:
            if let wq = walkingQuality {
                return "\(wq.sleepQualityLabel) · 夜间清醒 \(wq.nightWakeTotalMin) 分钟"
            }
            return "已入睡 · 心率 \(hr)"
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

    private var aiReport: AIAnalysisReport? { nil }

    private func handleAlertTap(_ a: UnifiedAlert) {
        if a.kind == .aiLive, a.aiReport != nil {
            showAIReport = true
        } else {
            selectedAlert = a
        }
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
            return MoodLineInfo(text: "平稳", tone: .good, spark: .stable)
        }
    }

    /// 给当前展示状态派生火柴人心情覆盖。
    private var figureMood: StickFigureMood {
        if isMorningEnergetic { return .excited }
        if isMorningCalm      { return .calm }
        return .normal
    }

    /// 身体能量 0..100。综合真实步态评分 + 状态：
    ///   - walk + gaitScore ≥ 80: 80-95 (步态好 → 能量高)
    ///   - walk + gaitScore < 80: 65-79
    ///   - sit: 真实久坐分或 60
    ///   - sleep: 基于夜间清醒评分
    private var bodyEnergy: Double {
        guard let wq = walkingQuality else {
            // fallback to hardcoded
            switch displayState {
            case .walk: return 72
            case .stand: return 65
            case .sit: return 55
            case .sleep: return 25
            }
        }

        switch displayState {
        case .walk:
            if wq.gaitScore >= 80 { return 90 }
            if wq.gaitScore >= 60 { return 75 }
            return 60
        case .stand:
            return 65
        case .sit:
            // 久坐时长越长能量越低
            let sit = Double(homeSedentaryMinutes)
            let sitPenalty = min(30, sit / 6.0)  // 每6分钟久坐扣1分，上限30分
            return max(25, 75 - sitPenalty)
        case .sleep:
            // 夜间清醒越多睡眠修复效果越差
            if wq.nightWakeCount == 0 { return 40 }
            if wq.nightWakeCount == 1 { return 30 }
            return 20
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

    /// 心情得分 0..100。综合步态评分 + 状态：
    private var moodScore: Double {
        guard let wq = walkingQuality else {
            switch displayState {
            case .walk: return 75
            case .stand: return 70
            case .sit: return 65
            case .sleep: return 25
            }
        }

        switch displayState {
        case .walk:
            if wq.gaitScore >= 85 { return 92 }
            if wq.gaitScore >= 70 { return 80 }
            return 70
        case .stand:
            return 70
        case .sit:
            if homeSedentaryMinutes > 120 { return 55 }  // 久坐超2小时 → 心情差
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
                    pendingCamera: chatPendingCamera,
                    pendingTopic: chatPendingTopic,
                    onClose: {
                        dismissKeyboard()
                        showChat = false
                        chatPendingPhoto = false   // 重置标记，下次开 chat 不再自动开图
                        chatPendingCamera = false  // 重置标记
                        chatPendingTopic = nil     // 重置标记
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { nowVal in
            // Preview 模式跳过 — 不让 Timer 反复触发重渲染
            guard !Self.isRunningForPreviews else { return }
            // 更新 now（每秒都在变，但 DayTimelineView 用 Equatable 只在分钟边界触发重绘）
            let oldMin = StickState.minutesOfDay(now)
            let newMin = StickState.minutesOfDay(nowVal)
            // 分钟边界、或刚启动时（now 与 nowVal 相差 >60s）才写 now，大幅减少 ContentView body 重绘
            if oldMin != newMin || nowVal.timeIntervalSince(now) > 60 {
                now = nowVal
            }
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
                    // 定期写入 SharedState（同步到 Widget）
                    if displayState == .sit && newMinutes > 0 {
                        let startTime = Date().addingTimeInterval(-Double(newMinutes) * 60)
                        let snap = SharedStickState(
                            stateRaw: displayState.rawValue,
                            englishName: displayState.englishName,
                            actionPhrase: displayState.actionPhrase,
                            heartRate: realHeartRate ?? primaryHeartRate,
                            mood: walkingQuality.map { "\($0.gaitScore)" } ?? displayState.secondaryMetric.value,
                            durationMinutes: primaryDurationMinutes,
                            subLine: realSubLine,
                            updatedAt: Date(),
                            currentSedentarySeconds: newMinutes * 60,
                            sedentaryStartTime: startTime
                        )
                        SharedStateStore.write(snap)
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
                // 实时读取步态质量 + 心率
                let wq = await HealthKitService.shared.todayWalkingQuality()
                walkingQuality = WalkingQualityData.from(wq)
                let hr = await HealthKitService.shared.todayHeartRate()
                realHeartRate = hr
                // 持续更新 SharedState（让 Widget 始终显示最新的久坐秒数）
                let sessionMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                let snap = SharedStickState(
                    stateRaw: displayState.rawValue,
                    englishName: displayState.englishName,
                    actionPhrase: displayState.actionPhrase,
                    heartRate: hr ?? realHeartRate ?? primaryHeartRate,
                    mood: walkingQuality.map { "\($0.gaitScore)" } ?? displayState.secondaryMetric.value,
                    durationMinutes: primaryDurationMinutes,
                    subLine: realSubLine,
                    updatedAt: Date(),
                    currentSedentarySeconds: sessionMins * 60,
                    sedentaryStartTime: sessionMins > 0 ? Date().addingTimeInterval(-Double(sessionMins) * 60) : nil
                )
                SharedStateStore.write(snap)
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
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
            } else if !isScrubbing {
                // 离开坐姿：立即清空计时（预览模式不改真实计时器）
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
                heartRate: realHeartRate ?? primaryHeartRate,
                mood: walkingQuality.map { "\($0.gaitScore)" } ?? displayState.secondaryMetric.value,
                durationMinutes: primaryDurationMinutes,
                subLine: realSubLine,
                updatedAt: Date(),
                currentSedentarySeconds: currentSitMinutes * 60,
                sedentaryStartTime: currentSitStartTime
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
            // 回到前台（解锁）：优先刷久坐秒表，其他查询并行
            if oldPhase != .active && newPhase == .active {
                guard !Self.isRunningForPreviews else { return }
                Task {
                    // 1) 先抓一次最新快照 — 把黑屏期间走的步数写进 HealthStore
                    //    （这是关键，否则 HealthStore 里的步数还是锁屏前的）
                    _ = await HealthKitService.shared.captureSnapshot()

                    // 2) **优先** 算当前 session 久坐（live 秒表要的数）
                    //    基于"最后一次明显步数时间"，黑屏期间走动过 → 自动截断/重置
                    let sessionMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                    if sessionMins > 0 {
                        currentSitStartTime = Date().addingTimeInterval(-Double(sessionMins) * 60)
                        currentSitMinutes = sessionMins
                    } else {
                        // 最近 4h 有走动/活动，重置
                        currentSitStartTime = nil
                        currentSitMinutes = 0
                    }
                    lastSitAnalysisTime = Date()

                    // 3) 累计 + 心率 + 步态 + 时刻表 — 并行刷新（不再阻塞秒表）
                    async let sedentaryTask: (minutes: Int, hasValidSleep: Bool) = {
                        let sed = await HealthKitService.shared.todaySedentaryMinutes()
                        let sleep = await HealthKitService.shared.todaySleepHours()
                        let valid = (sleep ?? 0) > 0
                        let minutes = valid ? max(0, sed - Int((sleep ?? 0) * 60)) : 0
                        return (minutes, valid)
                    }()
                    async let scheduleTask: Void = {
                        await HealthKitService.shared.computeDaySchedule()
                    }()
                    async let qualityTask: (walkingQuality: WalkingQualityData, heartRate: Int?) = {
                        let wq = await HealthKitService.shared.todayWalkingQuality()
                        let heartRate = await HealthKitService.shared.todayHeartRate()
                        return (WalkingQualityData.from(wq), heartRate)
                    }()
                    let (sedentary, _, quality) = await (sedentaryTask, scheduleTask, qualityTask)
                    homeSedentaryMinutes = sedentary.minutes
                    hasValidSleepData = sedentary.hasValidSleep
                    walkingQuality = quality.walkingQuality
                    realHeartRate = quality.heartRate
                }
            }
        }
        .onChange(of: hkService.lastMovementTime) { oldValue, newValue in
            // HealthKit 检测到明显步数增加 → 立即打断久坐，重新计时
            guard newValue != nil, oldValue != newValue else { return }
            guard !Self.isRunningForPreviews else { return }
            // 只要检测到新的大步数（>30步/分钟），立即清零计时器
            // 下一次 currentSedentarySessionMinutes 分析会基于新的快照重新计算
            currentSitMinutes = 0
            currentSitStartTime = nil
        }
        .onChange(of: scrubOffset) { _, newValue in
            // scrubOffset 归零（"回到现在" 按钮 / DayTimelineView 自动 10s 复位）→ 释放 swipe override，
            // 让 displayState 重新回到基于时间的真实状态。
            if (newValue ?? 0) == 0 {
                manualStateOverride = nil
            }
        }
        .sheet(isPresented: $showFilm) {
            MiniFilmShareSheet(isPresented: $showFilm)
                .presentationBackground(Color.black)
        }
        // Chat 改到外层 ZStack（贴底）
        .sheet(isPresented: $showSleepReport) {
            SleepReportView(onClose: { showSleepReport = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "注入过去 7 天的 mock 数据到 HealthKit？\n\n将申请 HealthKit 写权限，并写入步数 / 心率 / 距离 / 能量 / 睡眠。\n\n⚠️ 仅用于调试 — 真机数据会被污染。",
            isPresented: $showInjectConfirm,
            titleVisibility: .visible
        ) {
            Button("注入 7 天数据") {
                Task { @MainActor in
                    let count = await HealthKitService.shared.injectMockDataIntoHealthKit(days: 7)
                    injectStatus = count > 0 ? "✅ 注入成功：\(count) 条样本" : "❌ 注入失败（请检查写权限）"
                    print("[ContentView] \(injectStatus ?? "")")
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            if let s = injectStatus { Text(s) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChatWithPhoto)) { note in
            if let seed = note.object as? String {
                chatSeed = seed
                chatKey += 1
                chatPendingPhoto = true
                showChat = true
            }
        }
        .onAppear {
            // Preview 模式完全短路 — 不跑 HealthKit / Timer / refresh
            guard !Self.isRunningForPreviews else { return }
            // 启动 HealthKit 抓取 (1 分钟一次, 写到本地)
            // 查询分批错开执行（stagger），避免启动瞬间并发 10+ HK 请求阻塞主线程
            Task {
                // 1. 先授权（必须立即执行，可能弹系统弹窗）
                await HealthKitService.shared.requestAuthorization()
                // 延迟 500ms 启动定时抓取（给首帧渲染让路）
                try? await Task.sleep(nanoseconds: 500_000_000)
                HealthKitService.shared.startAutoCapture(interval: 60)
                inference = HealthKitService.shared.currentInference

                // 2. 第一组：久坐核心数据（UI 上最显眼的两行）
                homeSedentaryMinutes = await HealthKitService.shared.todaySedentaryMinutes()
                if let sleepHours = await HealthKitService.shared.todaySleepHours(), sleepHours > 0 {
                    let sleepMinutes = Int(sleepHours * 60)
                    homeSedentaryMinutes = max(0, homeSedentaryMinutes - sleepMinutes)
                    hasValidSleepData = true
                } else {
                    hasValidSleepData = false
                }
                let sitMins = await HealthKitService.shared.currentSedentarySessionMinutes(hours: 4)
                currentSitMinutes = sitMins
                if sitMins > 0 {
                    currentSitStartTime = Date().addingTimeInterval(-Double(sitMins) * 60)
                }
                lastSitAnalysisTime = Date()

                // 3. 写入 SharedState（Widget 同步）
                let snap = SharedStickState(
                    stateRaw: displayState.rawValue,
                    englishName: displayState.englishName,
                    actionPhrase: displayState.actionPhrase,
                    heartRate: realHeartRate ?? primaryHeartRate,
                    mood: walkingQuality.map { "\($0.gaitScore)" } ?? displayState.secondaryMetric.value,
                    durationMinutes: primaryDurationMinutes,
                    subLine: realSubLine,
                    updatedAt: Date(),
                    currentSedentarySeconds: sitMins * 60,
                    sedentaryStartTime: sitMins > 0 ? Date().addingTimeInterval(-Double(sitMins) * 60) : nil
                )
                SharedStateStore.write(snap)
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif

                // 4. 第二组：24h 时刻表 + 步态质量（延迟 250ms，非首屏立即显示）
                try? await Task.sleep(nanoseconds: 250_000_000)
                await HealthKitService.shared.computeDaySchedule()
                let wq = await HealthKitService.shared.todayWalkingQuality()
                walkingQuality = WalkingQualityData.from(wq)
                realHeartRate = await HealthKitService.shared.todayHeartRate()
                todaySleepHours = await HealthKitService.shared.todaySleepHours()
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
                        // 模拟器调试按钮：注入过去 7 天的 mock 数据到 HealthKit
                        // 让"导出最近 7 天"按钮能看到多天数据（无需等 7 天累积）
                        Button {
                            showInjectConfirm = true
                        } label: {
                            Image(systemName: "syringe")
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
                        todaySleepHours: todaySleepHours,
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
                            bodyEnergy: bodyEnergy,
                            energyColor: energyColor,
                            isScrubbing: isScrubbing,
                            inference: inference,
                            showDevicePicker: $showDevicePicker,
                            scrubOffset: $scrubOffset,
                            manualStateOverride: $manualStateOverride,
                            onPreview: { showFilm = true },
                            onSleepAlert: { showSleepReport = true },
                            subLine: realSubLine,
                            schedule: hk.realDaySchedule ?? StickState.daySchedule
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 400)

                        DayTimelineView(
                            schedule: hk.realDaySchedule ?? StickState.daySchedule,
                            now: now,
                            scrubOffset: $scrubOffset,
                            showDevicePicker: $showDevicePicker,
                            manualStateOverride: $manualStateOverride
                        )
                        .equatable()  // schedule 内容稳定时跳过 body 重绘，杜绝轴乱变
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
                        lastHistoryPrompt: chatHistory.loadedMessages.last(where: { $0.role == "user" })?.content,
                        autoTopics: ["饮食建议"],
                        onAutoTopic: openChatWithTopic
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
        // 打开 ChatOverlay + 让 ChatOverlay 内部自动激活相机 chip + 开相机
        // 与首页"拍食物"chip 走同一条路径
        chatSeed = ""
        chatKey += 1
        chatPendingCamera = true
        showChat = true
    }

    /// autoTopic chip（饮食建议）触发：开 chat + 让 ChatOverlay 自动调 LLM 给出个性化建议
    private func openChatWithTopic(_ title: String, _ seed: String) {
        chatSeed = seed
        chatKey += 1
        chatPendingTopic = title
        showChat = true
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
}

// MARK: - 主舞台（v6 风格）

private struct StageHeroView: View {
    let state: StickState
    let mood: StickFigureMood
    let bodyEnergy: Double
    let energyColor: Color
    let isScrubbing: Bool
    let inference: StateInference.Result?
    @Binding var showDevicePicker: Bool
    @Binding var scrubOffset: Int?            // 接收时间线 binding，stage 也可拖
    @Binding var manualStateOverride: StickState?  // swipe 切状态后的强制状态
    var onPreview: () -> Void
    var onSleepAlert: () -> Void
    let subLine: String
    let schedule: [StickState.DaySegment]    // 真实时刻表（用于按时间正方向查找下一个 state 的段）

    /// 拖动起点 + 起始 offset (用于把横向 delta 换算成分钟)
    @State private var dragStartOffset: Int? = nil
    @State private var dragWidth: CGFloat = 0
    @State private var isStageScrubbing: Bool = false
    /// swipe 命中阈值：|translation.width| > 30pt 视为切状态手势
    private let swipeThreshold: CGFloat = 30

    /// 主舞台水平滑动 → 切时间。手势灵敏度：1 pt = 4 min（24h / iPhone 17 Pro 屏幕宽 ≈ 393 pt）
    /// - 左滑（delta.x > 0）→ 回到过去（offset 增加）
    /// - 右滑（delta.x < 0）→ 回到现在（offset 减少）
    private func handleStageDrag(translation: CGFloat, width: CGFloat) {
        dragWidth = width
        let baseOffset = dragStartOffset ?? scrubOffset ?? 0
        // 24h=1440min，按舞台宽度线性换算
        let deltaMinutes = Int((translation / width) * 1440)
        let newOffset = max(0, min(1440, baseOffset + deltaMinutes))
        // snap 到 5 min
        scrubOffset = (newOffset / 5) * 5
    }

    /// 快速 swipe → 切到 `allCases` 里相邻 state，并跳 thumb 到该 state 在当前时间之后最近的 segment 中点。
    /// 找不到则 wrap 到 schedule 里该 state 的第一个 segment。
    /// direction: +1 = 右滑 (下一个 state), -1 = 左滑 (上一个 state)
    private func cycleState(direction: Int) {
        let allCases = StickState.allCases
        guard !allCases.isEmpty else { return }
        let current = manualStateOverride ?? state
        let currentIndex = allCases.firstIndex(of: current) ?? 0
        let nextIndex = ((currentIndex + direction) + allCases.count) % allCases.count
        let nextState = allCases[nextIndex]

        // 计算当前 thumb 所在分钟（处理跨午夜 + 边界 clamp）
        let nowMin = StickState.minutesOfDay(Date())
        let rawDisplayMin = (nowMin - (scrubOffset ?? 0) + 1440) % 1440
        let currentDisplayMin = max(0, min(rawDisplayMin, 1439))

        // 在 schedule 里按时间正方向找 nextState 之后最近的段；找不到则 wrap 到第一个
        let targetSeg = nextSegment(for: nextState, after: currentDisplayMin, in: schedule)
        let jumpMinute = targetSeg.map { (($0.startMinute + $0.endMinute) / 2) } ?? nowMin
        // 让 scrubOffset 落点刚好让 displayMinute = jumpMinute（处理跨午夜）
        let rawOffset = (nowMin - jumpMinute + 1440) % 1440
        let snappedOffset = (rawOffset / 5) * 5

        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            manualStateOverride = nextState
            scrubOffset = snappedOffset == 0 ? nil : snappedOffset
        }
    }

    /// 在 `schedule` 里按 startMinute 升序找 `state` 第一个 `startMinute > after` 的段；
    /// 找不到则 wrap 到 schedule 里该 state 的第一个段。
    /// 用于 swipe 切状态时按时间正方向跳 thumb。
    private func nextSegment(
        for state: StickState,
        after minute: Int,
        in schedule: [StickState.DaySegment]
    ) -> StickState.DaySegment? {
        schedule.first(where: { $0.state == state && $0.startMinute > minute })
            ?? schedule.first { $0.state == state }
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
        VStack(alignment: .center, spacing: 20) {
            // 舞台区（火柴人 + 透明背景，跟整页一个底色）
            ZStack {
                // 永远画小人（让用户看到 30° 低头 + 低落表情等所有视觉）
                StickFigureView(state: state, mood: mood)
                    .padding(.horizontal, 4)
                    .padding(.top, 70)
                    .padding(.bottom, 0)
                    .id(state)
                    .transition(.opacity)

                // 右上角：状态名 + 副标（睡眠异常 chip 已移除 — 暂无真实数据源）
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        // 睡眠 chip 已删除，避免误提示
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
                    .onEnded { value in
                        let dx = value.translation.width
                        // |dx| > threshold → swipe 切状态；否则保留 onChanged 已写入的 scrub 结果
                        if abs(dx) > swipeThreshold {
                            // 右滑 dx > 0 → 下一个 state (cycleState 内部方向约定 +1 = 右滑 = 下一个)
                            cycleState(direction: dx > 0 ? 1 : -1)
                        }
                        isStageScrubbing = false
                        dragStartOffset = nil
                    }
            )

            // 拖动时显示当前时间 / swipe 后显示状态 + 时段范围
            if isStageScrubbing || manualStateOverride != nil {
                stageScrubBadge
            }
        }
    }

    /// 主舞台中央徽章：
    /// - swipe 切状态后 → `状态 · HH:MM–HH:MM`（按当前 thumb 位置定位到该 state 的最近段）
    /// - 仅拖动时间 → `HH:MM`
    private var stageScrubBadge: some View {
        let offset = scrubOffset ?? 0
        let m = StickState.minutesOfDay(Date().addingTimeInterval(-Double(offset) * 60))
        let targetState = manualStateOverride ?? state
        // 按当前 thumb 位置定位 segment；override state 时优先找当前位置匹配的段，否则取该 state 之后的最近段
        let seg: StickState.DaySegment? = {
            if let cur = schedule.first(where: {
                $0.startMinute <= m && m < $0.endMinute && $0.state == targetState
            }) {
                return cur
            }
            return nextSegment(for: targetState, after: m, in: schedule)
        }()
        let isOverride = manualStateOverride != nil
        return VStack(spacing: 2) {
            if isOverride, let seg = seg {
                Text("\(StickState.formatMinute(seg.startMinute))–\(StickState.formatMinute(seg.endMinute)) · \(state.rawValue)")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(Theme.navy)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            } else {
                let hh = (m / 60) % 24
                let mm = m % 60
                Text(String(format: "%02d:%02d", hh, mm))
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.navy)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }
            Text("← 左右滑动切换状态 →")
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
        .animation(.easeInOut(duration: 0.2), value: isOverride)
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
