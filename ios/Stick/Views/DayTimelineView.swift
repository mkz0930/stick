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

    @State private var hasInteracted: Bool = false   // 用户拖动后永久隐藏 hint
    @State private var pulse: Double = 0             // 0..1 循环，驱动 active 段脉冲
    @State private var autoResetWorkItem: DispatchWorkItem? = nil  // 10s 无操作自动回 now
    @State private var showPlayback: Bool = false    // 24h 回放 sheet

    private let dayMinutes: CGFloat = 1440
    private let trackWidth: CGFloat = 4        // 极细线（竖线宽度）
    private let trackLength: CGFloat = 200     // 竖线总长
    private let thumbSize: CGFloat = 14        // 圆环缩小
    private let segmentGap: CGFloat = 0.8
    private let snapStep: Int = 5          // 5 分钟一格
    private let lineAlpha: Double = 0.65       // 竖线半透明 (稍亮，跟动画同色系)
    private let thumbAlpha: Double = 0.85      // 圆环半透明

    // MARK: - 派生

    private var nowMinute: Int { StickState.minutesOfDay(now) }

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

    private var displayState: StickState {
        schedule.first { $0.startMinute <= displayMinute && displayMinute < $0.endMinute }?.state ?? .walk
    }

    private var displaySegment: StickState.DaySegment? {
        schedule.first { $0.startMinute <= displayMinute && displayMinute < $0.endMinute }
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 12) {
            shareButton
            track
                .frame(width: thumbSize, height: trackLength)
            // 竖线下方：短时间灰色显示
            Text(formatClockOnly(displayDate))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
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

    /// 竖线上方的小分享按钮（点开 → 1-day 回放 sheet，播完后可分享）
    private var shareButton: some View {
        Button {
            showPlayback = true
        } label: {
            Image(systemName: "play.rectangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.slate.opacity(0.55))
                .frame(width: 16, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.slate.opacity(0.06))
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
                // 色条（按"过去 24h"重新映射，竖向）
                ForEach(schedule) { seg in
                    rotatedSegment(seg, in: height)
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
                        let y = max(0, min(value.location.y, height))
                        // y=height → offset=0 (现在, 底); y=0 → offset=1440 (24h 前, 顶)
                        let raw = Int((1 - y / height) * dayMinutes)
                        let snapped = (raw / snapStep) * snapStep
                        scrubOffset = max(0, min(snapped, 1440))
                        if !hasInteracted && scrubOffset != nil {
                            hasInteracted = true
                        }
                        scheduleAutoReset()
                    }
                    .onEnded { _ in
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
            }
            autoResetWorkItem = nil
        }
        autoResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    // MARK: - 组件

    /// 把原 schedule 时段按"过去 24h 窗口"重新映射（竖向）
    /// 窗口坐标系：顶 = 24h 前 (offset 1440)，底 = 现在 (offset 0)
    /// 段位置 = 该段在窗口里的窗口坐标 offset / 1440
    /// 跨过底边界（startWin > endWin）的段拆成两段画
    @ViewBuilder
    private func rotatedSegment(_ seg: StickState.DaySegment, in height: CGFloat) -> some View {
        let totalMin = Int(dayMinutes)
        let startWin = ((seg.startMinute - nowMinute) + totalMin) % totalMin
        let endWin   = ((seg.endMinute   - nowMinute) + totalMin) % totalMin
        let thumbWin = totalMin - displayOffset
        let gap: CGFloat = 1.5
        let total = CGFloat(totalMin)
        let accent = seg.state.accent

        if startWin <= endWin {
            // 普通段（不跨边）
            let yTop = CGFloat(totalMin - endWin) / total * height
            let segH = CGFloat(endWin - startWin) / total * height
            let isActive = (startWin...endWin).contains(thumbWin)
            singlePiece(
                yTop: yTop, segH: segH,
                fillY: yTop + gap / 2, fillH: max(0, segH - gap),
                isActive: isActive, accent: accent
            )
        } else {
            // 跨底边界：拆成两段
            // 上半段：0 → endWin (顶)
            let uY = CGFloat(totalMin - endWin) / total * height
            let uH = CGFloat(endWin) / total * height
            // 下半段：startWin → totalMin (底)
            let lY = CGFloat(0)
            let lH = CGFloat(totalMin - startWin) / total * height
            let upActive = thumbWin >= 0 && thumbWin < endWin
            let downActive = thumbWin >= startWin && thumbWin < totalMin
            ZStack {
                singlePiece(
                    yTop: uY, segH: uH,
                    fillY: uY + gap / 2, fillH: max(0, uH - gap / 2),
                    isActive: upActive, accent: accent
                )
                singlePiece(
                    yTop: lY, segH: lH,
                    fillY: lY + gap / 2, fillH: max(0, lH - gap / 2),
                    isActive: downActive, accent: accent
                )
            }
        }
    }

    /// 一段矩形（带可选 active 描边）— 竖向
    @ViewBuilder
    private func singlePiece(
        yTop: CGFloat, segH: CGFloat,
        fillY: CGFloat, fillH: CGFloat,
        isActive: Bool, accent: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent.opacity(lineAlpha))
                .frame(width: trackWidth, height: max(0, fillH))
                .offset(x: 0, y: fillY)
            if isActive {
                let pulseAlpha = 0.25 + 0.25 * pulse
                RoundedRectangle(cornerRadius: 3)
                    .stroke(accent.opacity(0.7), lineWidth: 2)
                    .frame(width: trackWidth, height: max(0, fillH))
                    .offset(x: -1.5, y: fillY)
                    .shadow(color: accent.opacity(pulseAlpha), radius: 4 + 2 * pulse, x: 0, y: 0)
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
