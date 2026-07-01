import SwiftUI

/// 24h 滑动窗口时间线 (ATLAS v6 编辑风)：
///  - 窗口 = [now - 24h, now]，右端 = 现在，左端 = 24h 前
///  - 走/坐/睡 三个时段按"过去 24h 内的最近一次"重新铺色条（按时钟相对 now 旋转）
///  - 状态色 thumb 可拖，0 = 右端（现在），1440 = 左端（24h 前）
///  - 拖离现在后右下出现"回到现在"按钮（spring 弹回）
///  - 状态名卡片右上角 "NOW" 区域也可点击 → 回现在
struct DayTimelineView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        // schedule 结构和内容稳定时视为相等；stepCount 不参与比较（步数实时变化不触发重绘）
        // 这样 24h 轴的视觉位置完全稳定，不会因 stepCount 抖动导致跳变
        let lhsSigs = lhs.schedule.map { "\($0.startMinute)-\($0.endMinute)-\($0.state)" }
        let rhsSigs = rhs.schedule.map { "\($0.startMinute)-\($0.endMinute)-\($0.state)" }
        let scheduleEqual = lhsSigs == rhsSigs
        let scrubEqual = lhs.scrubOffset == rhs.scrubOffset
        let manualEqual = lhs.manualStateOverride == rhs.manualStateOverride
        let showDeviceEqual = lhs.showDevicePicker == rhs.showDevicePicker
        return scheduleEqual && scrubEqual && manualEqual && showDeviceEqual
    }
    let schedule: [StickState.DaySegment]
    let now: Date
    @Binding var scrubOffset: Int?         // 0 = 现在；>0 表示过去多少分钟
    @Binding var showDevicePicker: Bool    // 点击 "+ 连接设备" 时弹出
    @Binding var manualStateOverride: StickState?  // swipe 切状态后的高亮目标；nil = 跟时间走

    @State private var hasInteracted: Bool = false   // 用户拖动后永久隐藏 hint
    @State private var pulse: Double = 0             // 0..1 循环，驱动 active 段脉冲
    @State private var autoResetWorkItem: DispatchWorkItem? = nil  // 10s 无操作自动回 now
    @State private var showPlayback: Bool = false    // 24h 回放 sheet
    @State private var frozenNowMinute: Int? = nil   // 拖动时冻结 now，避免坐标跳变

    private let dayMinutes: CGFloat = 1440
    private let trackWidth: CGFloat = 4        // 极细线（竖线宽度）
    private let trackLength: CGFloat = 200     // 竖线总长
    private let thumbSize: CGFloat = 14        // 圆环缩小
    private let segmentGap: CGFloat = 0.8
    private let snapStep: Int = 1          // 1 分钟一格（拖动更细腻）
    private let lineAlpha: Double = 0.88       // 竖线半透明（更饱和，各状态颜色更分明）
    private let thumbAlpha: Double = 0.92      // 圆环半透明

    // 步行段视觉强化（竖向方框 — 时长比例）
    private let walkBoxMinHeight: CGFloat = 20     // 最短步行固定最小高度（保证可见）
    private let walkBoxMaxHeight: CGFloat = 80     // >30min 步行 = 80pt 上限
    private let walkBoxWidth: CGFloat = 38         // 方框宽度（略宽，更醒目）
    private let walkBoxBorderWidth: CGFloat = 3.0  // 方框描边（更明显）
    private let walkLabelMinDuration: Int = 5       // ≥5min 才显示时刻标签
    private let walkMergeGapMinutes: Int = 3       // 间隔 ≤3min 的碎步行合并
    private let walkMinVisibleDuration: Int = 1      // ≥1min 的步行都显示（短步行用小框）
    private let walkMinVerticalSpacing: CGFloat = 8  // 最小纵向间距
    private let walkMinSteps: Int = 100              // <100 步的步行不显示

    /// 合并后仅用于时间线渲染的步行胶囊。
    private struct WalkVisualSegment: Identifiable {
        let id: String
        let startMinute: Int
        let endMinute: Int
        let duration: Int
        let stepCount: Int?  // 该段总步数（控制颜色深浅）
        var yCenter: CGFloat
        let accent: Color
    }

    /// 映射到过去 24h 窗口坐标后的单个步行片段。
    private struct WalkWindowPiece {
        let segmentId: Int       // 原始 DaySegment 的 id（稳定不变）
        let splitTag: String      // "single" / "upper" / "lower"（拆分标记）
        let startWin: Int
        let endWin: Int
        let startMinute: Int
        let endMinute: Int
        let duration: Int
        let stepCount: Int?      // 原始 segment 的总步数
        let accent: Color
    }

    /// 视觉合并过程中的可变步行片段。
    private struct MergedWalkWindow {
        let segmentId: Int
        let splitTag: String
        let startWin: Int
        var endWin: Int
        let startMinute: Int
        var endMinute: Int
        var duration: Int
        var stepCount: Int?      // 合并后的总步数
        let accent: Color
    }

    // MARK: - 派生

    /// 稳定的当前分钟（只在分钟边界变化，每秒 Date 变化不影响）
    /// 同时拖动时完全冻结
    private var stableNowMinute: Int {
        if let frozen = frozenNowMinute { return frozen }
        // 只取分钟级，忽略秒的抖动
        return StickState.minutesOfDay(now)
    }


    private var isScrubbing: Bool {
        guard let s = scrubOffset else { return false }
        return s > 0
    }

    private var displayOffset: Int {
        scrubOffset ?? 0
    }

    /// 当前正在看的时间点 (now - displayOffset 分钟)
    private var displayDate: Date {
        now.addingTimeInterval(-Double(displayOffset) * 60)
    }

    /// 稳定显示分钟（只在 stableNowMinute 变化时更新，拖动期间冻结）
    /// 这样时间线轴的视觉位置完全稳定，不会因 now 每秒跳动而跳变
    private var displayMinute: Int {
        (stableNowMinute - displayOffset + Int(dayMinutes)) % Int(dayMinutes)
    }

    /// 时间线高亮的目标 segment。优先级：
    /// 1. swipe 切状态后的 `manualStateOverride`：
    ///    a. 当前位置的段若 state 匹配 override → 用当前位置段（thumb 已经跳到该段附近）
    ///    b. 否则按时间正方向找 override state 之后最近的段；wrap 到 schedule 里该 state 的第一个段
    /// 2. 否则按当前 `displayMinute` 查 schedule
    private var displaySegment: StickState.DaySegment? {
        if let override = manualStateOverride {
            if let cur = schedule.first(where: {
                $0.startMinute <= displayMinute && displayMinute < $0.endMinute && $0.state == override
            }) {
                return cur
            }
            if let next = schedule.first(where: {
                $0.state == override && $0.startMinute > displayMinute
            }) {
                return next
            }
            return schedule.first { $0.state == override }
        }
        return schedule.first { $0.startMinute <= displayMinute && displayMinute < $0.endMinute }
    }

    private var displayState: StickState {
        if let override = manualStateOverride {
            return override
        }
        return schedule.first { $0.startMinute <= displayMinute && displayMinute < $0.endMinute }?.state ?? .walk
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                TimelineShareButton {
                    showPlayback = true
                }
                Spacer(minLength: 0)
            }
            .frame(width: 22, alignment: .leading)
            track()
                .frame(width: thumbSize, height: trackLength)
            // 时段起止范围（仅在用户主动查看时间 / swipe 切状态时显示）
            if isScrubbing || manualStateOverride != nil,
               let seg = displaySegment {
                Text("\(StickState.formatMinute(seg.startMinute)) – \(StickState.formatMinute(seg.endMinute))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(displayState.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: seg.startMinute)
            }
            // 竖线下方：短时间灰色显示（使用 displayMinute 而非 displayDate，保证拖动期间稳定不跳）
            Text(StickState.formatMinute(displayMinute))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(Theme.slate.opacity(0.55))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: displayMinute)
        }
        .animation(.easeInOut(duration: 0.25), value: isScrubbing)
        .animation(.easeInOut(duration: 0.4), value: hasInteracted)
        .animation(.easeInOut(duration: 0.25), value: manualStateOverride)
        .onAppear {
            startPulse()
        }
        .onChange(of: scrubOffset) { _, newValue in
            // 外部 (例如 "连接设备" 按钮) 把 scrubOffset 改回 nil/0 时，
            // 取消还没触发的 10s 自动回 now 任务
            if (newValue ?? 0) == 0 {
                autoResetWorkItem?.cancel()
                autoResetWorkItem = nil
            }
        }
        .onChange(of: isScrubbing) { _, scrubbing in
            // 拖动期间停止 pulse，避免 active 段呼吸与 thumb 拖动冲突造成视觉跳动
            if scrubbing {
                stopPulse()
            } else {
                startPulse()
            }
        }
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet()
                .presentationDetents([.height(420), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.disabled)
        }
        .fullScreenCover(isPresented: $showPlayback) {
            DayPlaybackSheet(schedule: schedule)
        }
    }

    // MARK: - 子视图

    private func track() -> some View {
        GeometryReader { geo in
            let height = max(1, geo.size.height)
            // 步行胶囊直接重算 — schedule 已通过 View.Equatable 稳定，
            // pulse 触发的重渲只影响 isActive 段视觉，walk 段坐标不需要缓存。
            // 旧版用 @State 缓存会触发 SwiftUI "Modifying state during view update" 警告。
            let walkSegments = computeWalkVisualSegments(in: height)
            return ZStack(alignment: .topLeading) {
                // 坐/睡 track（细线 + 睡虚线）
                ForEach(schedule.filter { $0.state != .walk }) { seg in
                    rotatedSegment(seg, in: height)
                }

                // 步行光点层（每次 body 重新计算，开销 <1ms，可忽略）
                ForEach(walkSegments) { seg in
                    walkBurst(seg)
                }

                // thumb (圆环) — 圆心落在竖线中心
                let yPos = windowY(forMinute: displayOffset, in: height)
                thumb()
                    .position(x: trackWidth / 2, y: yPos)
                    .opacity(thumbAlpha)
                    // 高 damping 让弹簧几乎线性,避免跟手时产生回弹"跳"
                    .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.95),
                               value: displayOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if frozenNowMinute == nil {
                            frozenNowMinute = StickState.minutesOfDay(now)  // 开始拖动时，冻结 now 坐标
                        }
                        let y = max(0, min(value.location.y, height))
                        // y=height → offset=0 (现在, 底); y=0 → offset=1440 (24h 前, 顶)
                        let raw = Int((1 - y / height) * dayMinutes)
                        let snapped = (raw / snapStep) * snapStep
                        let clamped = max(0, min(snapped, 1439))
                        scrubOffset = clamped == 0 ? nil : clamped
                        if !hasInteracted && scrubOffset != nil {
                            hasInteracted = true
                        }
                        scheduleAutoReset()
                    }
                    .onEnded { _ in
                        frozenNowMinute = nil  // 结束拖动，解冻 now
                        scheduleAutoReset()
                    }
            )
        }
    }

    // MARK: - 自动回 now

    /// 10s 内没有拖动 → scrubOffset 归零 (时间轴滑回最新)
    private func scheduleAutoReset() {
        autoResetWorkItem?.cancel()
        guard isScrubbing else { return }
        let item = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.45)) {
                scrubOffset = nil
                frozenNowMinute = nil  // 回 now 时解冻
            }
            autoResetWorkItem = nil
        }
        autoResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    // MARK: - pulse 控制

    /// 0..1 循环驱动 active 段的呼吸
    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            pulse = 1
        }
    }

    /// 拖动期间停止 pulse,避免 active 段阴影动画和 thumb 拖动冲突造成视觉跳动
    private func stopPulse() {
        withAnimation(.easeInOut(duration: 0.15)) {
            pulse = 0
        }
    }

    // MARK: - 组件

    /// 步行段 = 竖向方框，高度按步行时长比例，描边明显。
    private func walkBurst(_ seg: WalkVisualSegment) -> some View {
        let accent = seg.accent

        // 方框高度按时长比例：3min=最小，60+min=最大
        let boxHeight = walkBoxMinHeight
            + (walkBoxMaxHeight - walkBoxMinHeight)
            * CGFloat(min(seg.duration, 60)) / 60.0

        // 步数比例：控制填充透明度（少步=淡，多步=深），最低 0.35 保证短步行也可见
        let stepCount = seg.stepCount ?? 1000
        let stepRatio = min(1.0, max(0.35, Double(stepCount) / 2000.0))
        let fillOpacity = 0.45 * stepRatio
        let borderOpacity = 0.90 * stepRatio

        let showLabel = seg.duration >= walkLabelMinDuration

        return ZStack {
            // 方框整体（描边 + 淡填充）
            RoundedRectangle(cornerRadius: 3)
                .fill(accent.opacity(fillOpacity))
                .frame(width: walkBoxWidth, height: boxHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(accent.opacity(borderOpacity), lineWidth: walkBoxBorderWidth)
                )
                .shadow(color: accent.opacity(0.18 * stepRatio), radius: 2.5, x: 0, y: 0)

            // 步数标签（方框内部显示步数，少步时透明度更低）
            if let stepCount = seg.stepCount, stepCount > 0 {
                Text("\(stepCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.65 + 0.3 * stepRatio))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            // 时刻标签（方框右侧）
            if showLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Text(StickState.formatMinute(seg.startMinute))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent.opacity(0.55))
                    Text("\(seg.duration)min")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(accent.opacity(0.35))
                }
                .offset(x: walkBoxWidth / 2 + 14)
            }
        }
        .position(x: trackWidth / 2, y: seg.yCenter)
    }

    /// 把原 schedule 时段按"过去 24h 窗口"重新映射（竖向）
    /// 只处理坐/睡段（步行段在 walkBurst 里独立渲染）
    /// 窗口坐标系：顶 = 24h 前 (offset 1440)，底 = 现在 (offset 0)
    /// 段位置 = 该段在窗口里的窗口坐标 offset / 1440
    /// 跨过底边界（startWin > endWin）的段拆成两段画
    /// 睡段用虚线（dashed）
    @ViewBuilder
    private func rotatedSegment(_ seg: StickState.DaySegment, in height: CGFloat) -> some View {
        let totalMin = Int(dayMinutes)
        let startWin = ((seg.startMinute - stableNowMinute) + totalMin) % totalMin
        let endWin   = ((seg.endMinute   - stableNowMinute) + totalMin) % totalMin
        let thumbWin = totalMin - displayOffset
        let accent = seg.state.accent

        let isSleep = seg.state == .sleep

        if startWin <= endWin {
            let yTop = windowY(forMinute: endWin, in: height)
            let yBottom = windowY(forMinute: startWin, in: height)
            let segH = max(0, yBottom - yTop - segmentGap)
            let yMid = (yTop + yBottom) / 2
            let isActive = (startWin...endWin).contains(thumbWin)
            singlePiece(yTop: yTop, yMid: yMid, segH: segH, isActive: isActive, accent: accent, isSleep: isSleep)
        } else {
            let uTop = windowY(forMinute: endWin, in: height)
            let uBottom = height
            let uH = max(0, uBottom - uTop - segmentGap)
            let lTop = windowY(forMinute: startWin, in: height)
            let lBottom = windowY(forMinute: 0, in: height)
            let lH = max(0, lBottom - lTop - segmentGap)
            let upActive = thumbWin >= 0 && thumbWin < endWin
            let downActive = thumbWin >= startWin && thumbWin < totalMin

            ZStack {
                singlePiece(yTop: uTop, yMid: (uTop + uBottom) / 2, segH: uH, isActive: upActive, accent: accent, isSleep: isSleep)
                singlePiece(yTop: lTop, yMid: (lTop + lBottom) / 2, segH: lH, isActive: downActive, accent: accent, isSleep: isSleep)
            }
        }
    }

    /// 一段矩形（坐姿：实线；睡姿：虚线）— 竖向，接收压缩后的坐标
    @ViewBuilder
    private func singlePiece(
        yTop: CGFloat, yMid: CGFloat, segH: CGFloat,
        isActive: Bool, accent: Color,
        isSleep: Bool = false
    ) -> some View {
        ZStack {
            if isSleep {
                Rectangle()
                    .stroke(accent.opacity(0.72),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round, dash: [3, 2.5]))
                    .frame(width: trackWidth, height: max(0, segH))
                    .position(x: trackWidth / 2, y: yMid)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(lineAlpha))
                    .frame(width: trackWidth, height: max(0, segH))
                    .position(x: trackWidth / 2, y: yMid)
            }

            if isActive {
                let pulseAlpha = 0.25 + 0.25 * pulse
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(accent.opacity(0.7), lineWidth: 1.5)
                    .frame(width: trackWidth + 2, height: max(0, segH))
                    .position(x: trackWidth / 2, y: yMid)
                    .shadow(color: accent.opacity(pulseAlpha), radius: 4 + 2 * pulse, x: 0, y: 0)

                let dotSize: CGFloat = 2
                let dotX: CGFloat = trackWidth / 2
                Circle()
                    .fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: dotX, y: yTop)
                Circle()
                    .fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: dotX, y: yTop + max(0, segH))
            }
        }
    }

    private func thumb() -> some View {
        ZStack {
            Circle()
                .fill(Theme.card)
                .frame(width: thumbSize, height: thumbSize)
                .shadow(color: Theme.navy.opacity(0.25), radius: 4, y: 1)
            Circle()
                .stroke(displayState.accent, lineWidth: 2.5)
                .frame(width: thumbSize, height: thumbSize)
            Circle()
                .fill(displayState.accent)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - 几何

    /// 分钟映射到 y 坐标（原始 1440 等比）
    private func yPosition(forMinute m: Int, in height: CGFloat) -> CGFloat {
        CGFloat(1440 - m) / dayMinutes * height
    }

    /// 把窗口 minute 映射到 y
    private func windowY(forMinute m: Int, in height: CGFloat) -> CGFloat {
        // 窗口坐标系: winM=0 → 底(now), winM=1440 → 顶(24h前)
        // abs = (winM + nowMinute) % 1440
        let abs = (m + stableNowMinute) % 1440
        return yPosition(forMinute: abs, in: height)
    }

    /// 生成步行视觉胶囊：过滤极短段、合并相邻段，并做纵向避让。
    private func computeWalkVisualSegments(in height: CGFloat) -> [WalkVisualSegment] {
        let totalMin = Int(dayMinutes)
        let rawSegments = schedule
            .filter { $0.state == .walk }
            .flatMap { walkWindowPieces(for: $0, totalMin: totalMin) }
            .sorted { $0.startWin < $1.startWin }

        guard !rawSegments.isEmpty else { return [] }

        var merged: [MergedWalkWindow] = []
        for piece in rawSegments {
            if let last = merged.last, piece.startWin - last.endWin <= walkMergeGapMinutes {
                var updated = last
                updated.endWin = max(updated.endWin, piece.endWin)
                updated.duration += piece.duration
                updated.endMinute = piece.endMinute
                // 合并步数
                if let ls = last.stepCount, let ps = piece.stepCount {
                    updated.stepCount = ls + ps
                } else {
                    updated.stepCount = last.stepCount ?? piece.stepCount
                }
                merged[merged.count - 1] = updated
            } else {
                merged.append(
                    MergedWalkWindow(
                        segmentId: piece.segmentId,
                        splitTag: piece.splitTag,
                        startWin: piece.startWin,
                        endWin: piece.endWin,
                        startMinute: piece.startMinute,
                        endMinute: piece.endMinute,
                        duration: piece.duration,
                        stepCount: piece.stepCount,
                        accent: piece.accent
                    )
                )
            }
        }

        var visualSegments = merged
            .filter { $0.duration >= walkMinVisibleDuration }
            .filter { ($0.stepCount ?? 0) >= walkMinSteps }  // <100步不显示
            .map { item in
                let midWin = (item.startWin + item.endWin) / 2
                let rawY = windowY(forMinute: midWin, in: height)
                return WalkVisualSegment(
                    id: "walk-\(item.segmentId)-\(item.splitTag)",  // 完全稳定，不随 now 变化
                    startMinute: item.startMinute,
                    endMinute: item.endMinute,
                    duration: item.duration,
                    stepCount: item.stepCount,
                    yCenter: rawY,
                    accent: item.accent
                )
            }
            .sorted { $0.yCenter < $1.yCenter }

        applyWalkVerticalSpacing(to: &visualSegments, in: height)
        return visualSegments
    }

    /// 将一天内的 walk segment 映射到过去 24h 的窗口坐标，跨 now 边界时拆成上下两段。
    private func walkWindowPieces(for seg: StickState.DaySegment, totalMin: Int) -> [WalkWindowPiece] {
        let startWin = ((seg.startMinute - stableNowMinute) + totalMin) % totalMin
        let endWin = ((seg.endMinute - stableNowMinute) + totalMin) % totalMin
        let accent = seg.state.accent
        let baseId = seg.id  // 原始 segment 的 id，稳定不变
        let steps = seg.stepCount  // 传递原始步数

        if startWin <= endWin {
            return [
                WalkWindowPiece(
                    segmentId: baseId,
                    splitTag: "single",
                    startWin: startWin,
                    endWin: endWin,
                    startMinute: seg.startMinute,
                    endMinute: seg.endMinute,
                    duration: max(0, endWin - startWin),
                    stepCount: steps,
                    accent: accent
                )
            ]
        }

        return [
            WalkWindowPiece(
                segmentId: baseId,
                splitTag: "upper",
                startWin: 0,
                endWin: endWin,
                startMinute: seg.startMinute,  // 用原始值，不用 nowMinute
                endMinute: seg.endMinute,
                duration: max(0, endWin),
                stepCount: steps,
                accent: accent
            ),
            WalkWindowPiece(
                segmentId: baseId,
                splitTag: "lower",
                startWin: startWin,
                endWin: totalMin,
                startMinute: seg.startMinute,  // 用原始值，不用 nowMinute
                endMinute: seg.endMinute,
                duration: max(0, totalMin - startWin),
                stepCount: steps,
                accent: accent
            )
        ]
        .filter { $0.duration >= walkMinVisibleDuration }
    }

    /// 给过近的步行方框增加最小纵向距离，同时限制在时间线可见范围内。
    private func applyWalkVerticalSpacing(to segments: inout [WalkVisualSegment], in height: CGFloat) {
        guard !segments.isEmpty else { return }

        let minY = walkBoxMaxHeight / 2
        let maxY = max(minY, height - walkBoxMaxHeight / 2)

        for index in segments.indices {
            let lowerBound = index == segments.startIndex
                ? minY
                : segments[segments.index(before: index)].yCenter + walkMinVerticalSpacing
            segments[index].yCenter = min(max(segments[index].yCenter, lowerBound), maxY)
        }

        for index in segments.indices.reversed() {
            let upperBound = index == segments.index(before: segments.endIndex)
                ? maxY
                : segments[segments.index(after: index)].yCenter - walkMinVerticalSpacing
            segments[index].yCenter = max(min(segments[index].yCenter, upperBound), minY)
        }
    }

    private func formatClockOnly(_ date: Date) -> String {
        // 只显示 HH:MM (去掉 "今" / "周X" 前缀)
        let c = Calendar.current
        let h = c.component(.hour, from: date)
        let m = c.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - 分享按钮

private struct TimelineShareButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "play.rectangle")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.slate.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.slate.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 连接智能设备弹窗

/// 左下/中等高度弹起，显示可连接的智能设备列表
struct DevicePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false

    private let devices: [PairDevice] = [
        PairDevice(icon: "applewatch",        name: "Apple Watch",     brand: "Apple",       status: .ready),
        PairDevice(icon: "earbuds",           name: "AirPods Pro",     brand: "Apple",       status: .ready),
        PairDevice(icon: "circle.hexagongrid.fill", name: "左点戒指",    brand: "ZHIPO",       status: .ready),
        PairDevice(icon: "applewatch.side.right", name: "左点手环",      brand: "ZHIPO",       status: .ready),
        PairDevice(icon: "figure.mind.and.body", name: "智能护腰",     brand: "SKG",         status: .paired),
        PairDevice(icon: "shoeprints.fill",   name: "智能运动鞋",      brand: "咕咚",         status: .ready),
        PairDevice(icon: "scalemass",         name: "智能体脂秤",      brand: "云麦",         status: .ready),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: scanning ? "antenna.radiowaves.left.and.right" : "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .symbolEffect(.pulse, isActive: scanning)
                        Text(scanning ? "正在搜索附近的智能设备…" : "选择要连接的设备")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black.opacity(0.75))
                        Spacer()
                        Button(scanning ? "停止" : "重新扫描") {
                            withAnimation { scanning.toggle() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    }
                    .padding(.vertical, 4)
                }

                Section("可用设备") {
                    ForEach(devices) { d in
                        Button { pair(d) } label: {
                            DevicePickerRow(device: d, scanning: scanning)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("连接智能设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .task {
            // 假装扫一下
            withAnimation { scanning = true }
        }
    }

    private func pair(_ d: PairDevice) {
        // 触发一下反馈
        withAnimation { scanning = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { scanning = false }
        }
    }
}

private struct PairDevice: Identifiable {
    enum Status { case ready, paired }
    let id = UUID()
    let icon: String
    let name: String
    let brand: String
    let status: Status
}

private struct DevicePickerRow: View {
    let device: PairDevice
    let scanning: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.black.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.05)))
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                Text(device.brand)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.5))
            }
            Spacer()
            if device.status == .paired {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("已配对")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                Button {
                    // 按钮风格 - 实际配对在父 view 的 pair() 里
                } label: {
                    Text(scanning ? "配对中…" : "配对")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.black)
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(scanning)
            }
        }
        .contentShape(Rectangle())
    }
}
