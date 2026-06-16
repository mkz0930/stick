import SwiftUI

/// 24h 滑动窗口时间线 (ATLAS v6 编辑风)：
///  - 窗口 = [now - 24h, now]，右端 = 现在，左端 = 24h 前
///  - 走/坐/睡 三个时段按"过去 24h 内的最近一次"重新铺色条（按时钟相对 now 旋转）
///  - 状态色 thumb 可拖，0 = 右端（现在），1440 = 左端（24h 前）
///  - 拖离现在后右下出现"回到现在"按钮（spring 弹回）
///  - 状态名卡片右上角 "NOW" 区域也可点击 → 回现在
struct DayTimelineView: View {
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
    private let lineAlpha: Double = 0.65       // 竖线半透明 (稍亮，跟动画同色系)
    private let thumbAlpha: Double = 0.85      // 圆环半透明

    // 步行段视觉强化（横向胶囊 — Bold Burst 修订）
    private let walkPillMinWidth: CGFloat = 8       // 1min 短步行 = 8pt 胶囊（更窄）
    private let walkPillMaxWidth: CGFloat = 24      // >10min 长步行 = 24pt（更紧凑）
    private let walkPillHeight: CGFloat = 5         // 胶囊更细
    private let walkHaloWidth: CGFloat = 30         // halo 同步缩小
    private let walkHaloHeight: CGFloat = 15        // halo 高度
    private let walkLabelMinDuration: Int = 8       // ≥8min 长步行才显示时刻标签
    private let walkMergeGapMinutes: Int = 3        // 间隔 ≤3min 的碎步行合并（减少数量）
    private let walkMinVisibleDuration: Int = 3     // <3min 的碎步行不显示独立胶囊
    private let walkMinVerticalSpacing: CGFloat = 12

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

    private var nowMinute: Int {
        // 拖动时冻结 now，避免坐标跳变
        if let frozen = frozenNowMinute { return frozen }
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

    private var displayMinute: Int {
        StickState.minutesOfDay(displayDate)
    }

    /// 时间线高亮的目标 segment。优先级：
    /// 1. swipe 切状态后的 `manualStateOverride`：取 schedule 里第一个匹配 state 的 segment
    ///    （schedule 没该 state 就回退到第一个非空段，保证 timeline 始终有可视范围）
    /// 2. 否则按当前 `displayMinute` 查 schedule
    private var displaySegment: StickState.DaySegment? {
        if let override = manualStateOverride,
           let seg = schedule.first(where: { $0.state == override }) {
            return seg
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
                shareButton
                Spacer(minLength: 0)
            }
            .frame(width: 22, alignment: .leading)
            track
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
            // 竖线下方：短时间灰色显示
            Text(formatClockOnly(displayDate))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundColor(Theme.slate.opacity(0.55))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: displayDate)
        }
        .animation(.easeInOut(duration: 0.25), value: isScrubbing)
        .animation(.easeInOut(duration: 0.4), value: hasInteracted)
        .animation(.easeInOut(duration: 0.25), value: manualStateOverride)
        .onAppear {
            // 0..1 循环驱动 active 段的呼吸
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = 1
            }
        }
        .onChange(of: scrubOffset) { newValue in
            // 外部 (例如 "连接设备" 按钮) 把 scrubOffset 改回 nil/0 时，
            // 取消还没触发的 10s 自动回 now 任务
            if (newValue ?? 0) == 0 {
                autoResetWorkItem?.cancel()
                autoResetWorkItem = nil
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

    /// 竖线上方的分享按钮（点开 → 1-day 回放 sheet，播完后可分享）
    private var shareButton: some View {
        Button {
            showPlayback = true
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

    private var shareMessage: String {
        "我在 Stick 上的当前状态 · \(displayState.englishName) · \(formatClockOnly(displayDate))"
    }

    private var header: some View {
        HStack(alignment: .center) {
            Spacer()
            // 右上：状态色点 + + 按钮 (纯图标，无文字)
            Button {
                showDevicePicker = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(displayState.accent)
                        .frame(width: 7, height: 7)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.slate.opacity(0.6))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.slate.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                // 坐/睡 track（细线 + 睡虚线）
                ForEach(schedule.filter { $0.state != .walk }) { seg in
                    rotatedSegment(seg, in: height)
                }

                // 步行光点层：先合并碎步行，再做最小纵向避让，避免糖葫芦式堆叠。
                ForEach(walkVisualSegments(in: height)) { seg in
                    walkBurst(seg)
                }

                // thumb (圆环) — 圆心落在竖线中心
                let yPos = yPosition(forOffset: displayOffset, in: height)
                thumb
                    .position(x: trackWidth / 2, y: yPos)
                    .opacity(thumbAlpha)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85),
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
                        let clamped = max(0, min(snapped, 1440))
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

    /// 7 个刻度短线（无数字）+ thumb 旁边的"可拖动"提示
    private var hourLabelsColumn: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { i in
                    let offMin = i * 4 * 60
                    let isNow = offMin == 0
                    let yPos = yPosition(forOffset: offMin, in: height)
                    // 短刻线 (无数字)
                    Rectangle()
                        .fill(isNow ? displayState.accent : Theme.slate.opacity(0.3))
                        .frame(width: isNow ? 5 : 3, height: 0.5)
                        .position(x: 6, y: yPos)
                }
            }
        }
        .frame(height: trackLength)
    }

    /// 拖动提示：thumb 旁的 "可拖动" 小标 (仅未交互时显示)
    @ViewBuilder
    private var thumbHint: some View {
        if !isScrubbing && !hasInteracted {
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7, weight: .bold))
                Text("拖动")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(Theme.slate.opacity(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.card)
                    .shadow(color: Theme.navy.opacity(0.12), radius: 2, y: 1)
            )
        }
    }

    private var backToNowButton: some View {
        HStack {
            if let seg = displaySegment {
                Text("位于 \(seg.state.rawValue) 时段 · \(StickState.formatMinute(seg.startMinute))–\(StickState.formatMinute(seg.endMinute))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button {
                // 回到现在的同时弹设备连接
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    scrubOffset = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showDevicePicker = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .bold))
                    Text("连接设备")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Theme.darkText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.navy)
                )
            }
            .buttonStyle(.plain)
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

    // MARK: - 组件

    /// 步行段 = 发光横向胶囊；相邻碎步行已在渲染前合并。
    @ViewBuilder
    private func walkBurst(_ seg: WalkVisualSegment) -> some View {
        let pillWidth = walkPillMinWidth
            + (walkPillMaxWidth - walkPillMinWidth)
            * CGFloat(min(seg.duration, 10)) / 10.0
        let accent = seg.accent
        let showLabel = seg.duration >= walkLabelMinDuration

        // 根据步数计算透明度：步越少越淡，步越多越深
        // 500步以下：极淡；2000步以上：全深度；中间线性插值
        let stepCount = seg.stepCount ?? 1000
        let stepRatio = min(1.0, max(0.1, Double(stepCount) / 2000.0))

        // 基础透明度乘步数比例
        let baseOpacityCore = 0.35 * stepRatio
        let baseOpacityHaloOuter = 0.04 * stepRatio
        let baseOpacityHaloInner = 0.08 * stepRatio
        let baseOpacityShadow = 0.12 * stepRatio
        let baseOpacityLabel = 0.35 * stepRatio

        return ZStack {
            // halo 外层（横向矩形柔光）
            Rectangle()
                .fill(accent.opacity(baseOpacityHaloOuter))
                .frame(width: walkHaloWidth, height: walkHaloHeight)

            // halo 内层（更实一点）
            Rectangle()
                .fill(accent.opacity(baseOpacityHaloInner))
                .frame(width: walkHaloWidth - 4, height: walkHaloHeight - 6)

            // 核心矩形（绿色实色 + 阴影）
            Rectangle()
                .fill(accent.opacity(baseOpacityCore))
                .frame(width: pillWidth, height: walkPillHeight)
                .shadow(color: accent.opacity(baseOpacityShadow), radius: 3, x: 0, y: 0)

            // 白色高光（左侧小亮）
            Rectangle()
                .fill(Color.white.opacity(0.15 * stepRatio))
                .frame(width: pillWidth * 0.35, height: walkPillHeight * 0.35)
                .offset(x: -pillWidth * 0.18, y: -walkPillHeight * 0.12)

            if showLabel {
                Text(StickState.formatMinute(seg.startMinute))
                    .font(.system(size: 9, weight: .regular, design: .serif).italic())
                    .foregroundColor(accent.opacity(baseOpacityLabel))
                    .offset(x: walkHaloWidth / 2 + 6, y: 0)
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
        let startWin = ((seg.startMinute - nowMinute) + totalMin) % totalMin
        let endWin   = ((seg.endMinute   - nowMinute) + totalMin) % totalMin
        let thumbWin = totalMin - displayOffset
        let total = CGFloat(totalMin)
        let accent = seg.state.accent

        let isSleep = seg.state == .sleep

        if startWin <= endWin {
            // 普通段（不跨边）
            let yTop = CGFloat(totalMin - endWin) / total * height
            let segH = CGFloat(endWin - startWin) / total * height
            let isActive = (startWin...endWin).contains(thumbWin)

            singlePiece(yTop: yTop, segH: segH, isActive: isActive, accent: accent, isSleep: isSleep)
        } else {
            // 跨底边界：拆成两段
            let uY = CGFloat(totalMin - endWin) / total * height
            let uH = CGFloat(endWin) / total * height
            let lY: CGFloat = 0
            let lH = CGFloat(totalMin - startWin) / total * height
            let upActive = thumbWin >= 0 && thumbWin < endWin
            let downActive = thumbWin >= startWin && thumbWin < totalMin

            ZStack {
                singlePiece(yTop: uY, segH: uH, isActive: upActive, accent: accent, isSleep: isSleep)
                singlePiece(yTop: lY, segH: lH, isActive: downActive, accent: accent, isSleep: isSleep)
            }
        }
    }

    /// 一段矩形（坐姿：实线；睡姿：虚线）— 竖向
    @ViewBuilder
    private func singlePiece(
        yTop: CGFloat, segH: CGFloat,
        isActive: Bool, accent: Color,
        isSleep: Bool = false
    ) -> some View {
        let gap: CGFloat = 1.5
        let fillY = yTop + gap / 2
        let fillH = max(0, segH - gap)

        ZStack {
            // 睡段用虚线（stroke dashed）
            if isSleep {
                Rectangle()
                    .stroke(accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round, dash: [2.5, 2.5]))
                    .frame(width: trackWidth, height: max(0, fillH))
                    .offset(x: 0, y: fillY)
            } else {
                // 坐段：实色细线
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(lineAlpha))
                    .frame(width: trackWidth, height: max(0, fillH))
                    .offset(x: 0, y: fillY)
            }

            if isActive {
                let pulseAlpha = 0.25 + 0.25 * pulse
                RoundedRectangle(cornerRadius: 1.5)
                    .stroke(accent.opacity(0.7), lineWidth: 1.5)
                    .frame(width: trackWidth + 2, height: max(0, fillH))
                    .offset(x: -1, y: fillY)
                    .shadow(color: accent.opacity(pulseAlpha), radius: 4 + 2 * pulse, x: 0, y: 0)

                // 段两端角标：让 active 范围起止更显眼
                let dotSize: CGFloat = 2
                let dotX: CGFloat = trackWidth / 2
                let dotYTop = fillY
                let dotYBottom = fillY + max(0, fillH)
                Circle()
                    .fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: dotX, y: dotYTop)
                Circle()
                    .fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: dotX, y: dotYBottom)
            }
        }
    }

    private var thumb: some View {
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }

    // MARK: - 几何

    private func yPosition(forOffset m: Int, in height: CGFloat) -> CGFloat {
        // offset 0 → 底 (现在); 1440 → 顶 (24h 前)
        CGFloat(1440 - m) / dayMinutes * height
    }

    /// 生成步行视觉胶囊：过滤极短段、合并相邻段，并做纵向避让。
    private func walkVisualSegments(in height: CGFloat) -> [WalkVisualSegment] {
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

        let total = CGFloat(totalMin)
        var visualSegments = merged
            .filter { $0.duration >= walkMinVisibleDuration }
            .map { item in
                let midWin = (item.startWin + item.endWin) / 2
                let rawY = CGFloat(totalMin - midWin) / total * height
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
        let startWin = ((seg.startMinute - nowMinute) + totalMin) % totalMin
        let endWin = ((seg.endMinute - nowMinute) + totalMin) % totalMin
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

    /// 给过近的步行胶囊增加最小纵向距离，同时限制在时间线可见范围内。
    private func applyWalkVerticalSpacing(to segments: inout [WalkVisualSegment], in height: CGFloat) {
        guard !segments.isEmpty else { return }

        let minY = walkHaloHeight / 2
        let maxY = max(minY, height - walkHaloHeight / 2)

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
        .onAppear {
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
