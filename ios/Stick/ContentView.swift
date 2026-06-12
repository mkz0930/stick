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
    @State private var showPersonal: Bool = false
    @State private var openSpecialists: Bool = false
    @State private var openDataRecord: Bool = false
    @State private var openWidgetPreview: Bool = false
    @State private var showDevicePicker: Bool = false
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

    var body: some View {
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
        // Chat 改成主页底栏 ZStack 叠加（不是 sheet）— 真正贴底
        .overlay(alignment: .bottom) {
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
        .animation(.easeInOut(duration: 0.28), value: showChat)
        .sheet(isPresented: $showSleepReport) {
            SleepReportView(onClose: { showSleepReport = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // 启动 HealthKit 抓取 (1 分钟一次, 写到本地)
            Task {
                await HealthKitService.shared.requestAuthorization()
                HealthKitService.shared.startAutoCapture(interval: 60)
                // 首屏立刻算一次 inference，让徽章副标有内容
                inference = HealthKitService.shared.currentInference
            }
            // 检查各 metric 真实授权状态 (有/无/拒绝)
            healthAuth.refresh()
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

                    // 三行数据：左上角，top bar 下方
                    FeatureRow(state: displayState, deviceSet: deviceSet, healthStatuses: healthAuth.statuses)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)

                    StageHeroView(
                        state: displayState,
                        mood: figureMood,
                        tiredness: figureTiredness,
                        isScrubbing: isScrubbing,
                        inference: inference,
                        onPreview: { showFilm = true },
                        onSleepAlert: { showSleepReport = true }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .padding(.horizontal, 16)

                    DayTimelineView(
                        schedule: StickState.daySchedule,
                        now: now,
                        scrubOffset: $scrubOffset,
                        showDevicePicker: $showDevicePicker
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

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
}

// MARK: - 主舞台（v6 风格）

private struct StageHeroView: View {
    let state: StickState
    let mood: StickFigureMood
    let tiredness: Double
    let isScrubbing: Bool
    let inference: StateInference.Result?
    var onPreview: () -> Void
    var onSleepAlert: () -> Void

    /// 把 inference 副标拼成单行 mono 文本：CONF xx% · <first reason>
    private var inferenceSubline: String {
        guard let inf = inference else { return "INFERRING…" }
        let pct = Int((inf.confidence * 100).rounded())
        let reason = inf.reasons.first ?? "无数据"
        return "CONF \(pct)% · \(reason)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 舞台区（火柴人 + 透明背景，跟整页一个底色）
            ZStack {
                StickFigureView(state: state, mood: mood, tiredness: tiredness)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .id(state)
                    .transition(.opacity)

                // 状态名（画布右上）— 点击弹出 10s 短片预览
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        if state == .sleep {
                            SleepAlertChip(count: 2, onTap: onSleepAlert)
                                .transition(.scale.combined(with: .opacity))
                        }
                        stateBadge
                    }
                    Text(inferenceSubline)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundColor(Theme.slate)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220, alignment: .trailing)
                    Spacer()
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.45), value: state)
        }
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
