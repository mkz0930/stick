import SwiftUI

/// 首页：火柴人主舞台。视觉参考 ATLAS v6-dashboard-sleeping：
///  - 顶栏（品牌 mark + 名称 + session + LIVE）
///  - 主舞台（eyebrow + 大尺寸火柴人 + serif 标题 + mono 副标）
///  - 24h 可拖动时间线
///  - 3 张数据卡（白色卡 + 状态色左 border）
///  - 底部 dark action panel
///
/// 状态来源：`StickState.current(at: now)`。
/// 拖动时间线时 `scrubMinute` 临时覆盖，UI 全程跟着更新。
struct ContentView: View {
    @State private var now: Date = Date()
    @State private var scrubMinute: Int? = nil
    @State private var showFilm: Bool = false
    @State private var showPersonal: Bool = false
    @State private var openSpecialists: Bool = false

    // Chat
    @State private var showChat: Bool = false
    @State private var chatSeed: String = ""
    @State private var chatKey: Int = 0
    @State private var inputDraft: String = ""

    private var displayMinute: Int {
        scrubMinute ?? StickState.minutesOfDay(now)
    }

    private var displayState: StickState {
        StickState.currentSegment(at: minutesToDate(displayMinute))?.state ?? .walk
    }

    private var isScrubbing: Bool {
        guard let s = scrubMinute else { return false }
        return s != StickState.minutesOfDay(now)
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
                    openSpecialists: $openSpecialists
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
        }
        .sheet(isPresented: $showFilm) {
            MiniFilmShareSheet(isPresented: $showFilm)
                .presentationBackground(Color.black)
        }
    }

    // MARK: - 首页内容 (抽出来便于在 ZStack 中复用)

    private var homeBody: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                TopBarView(onMenuTap: { showPersonal = true })
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                Spacer(minLength: 0)

                StageHeroView(state: displayState, isScrubbing: isScrubbing)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { showFilm = true }

                Spacer(minLength: 0)

                DayTimelineView(
                    schedule: StickState.daySchedule,
                    now: now,
                    scrubMinute: $scrubMinute
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                FeatureRow(state: displayState)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

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
    let isScrubbing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 舞台区（火柴人 + 状态色背景 + 右上 scrubbing / 状态徽章）
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.border, lineWidth: 1)
                    )

                StickFigureView(state: state)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .id(state)
                    .transition(.opacity)

                // 状态名（画布右上）
                VStack {
                    HStack {
                        Spacer()
                        stateBadge
                    }
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
        HStack(spacing: 6) {
            Circle()
                .fill(state.accent)
                .frame(width: 7, height: 7)
            Text(state.englishName)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(Theme.navy)
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
}

#Preview {
    ContentView()
}
