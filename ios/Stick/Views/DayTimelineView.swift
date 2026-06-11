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

    private let dayMinutes: CGFloat = 1440
    private let trackHeight: CGFloat = 14
    private let thumbSize: CGFloat = 22
    private let segmentGap: CGFloat = 1.5
    private let snapStep: Int = 5          // 5 分钟一格

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
        VStack(alignment: .leading, spacing: 12) {
            header
            track
            hourLabels
            if isScrubbing {
                backToNowButton
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(cardBackground)
        .animation(.easeInOut(duration: 0.25), value: isScrubbing)
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isScrubbing ? "SCRUBBING · 拖动以查看" : "今日 · 24H 滑动窗口")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.slate)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(formatDisplayClock(displayDate))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(isScrubbing ? displayState.accent : Theme.navy)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: displayDate)
                    if isScrubbing {
                        Text("(- \(displayOffset / 60)h\(displayOffset % 60)m)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.slate)
                    }
                }
            }
            Spacer()
            // 右上角 "NOW" — 整块可点，弹出连接设备弹窗
            Button {
                showDevicePicker = true
            } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("NOW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Theme.slate)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(displayState.accent)
                            .frame(width: 8, height: 8)
                        Text(displayState.rawValue)
                            .font(.system(size: 26, weight: .black, design: .serif))
                            .foregroundColor(displayState.accent)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("连接设备")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(Theme.slate.opacity(0.55))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                // 色条（按"过去 24h"重新映射）
                ForEach(schedule) { seg in
                    rotatedSegment(seg, in: width)
                }

                // thumb
                let xPos = xPosition(forOffset: displayOffset, in: width)
                thumb
                    .position(x: xPos, y: trackHeight / 2)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85),
                               value: displayOffset)
            }
            .frame(height: trackHeight + thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = max(0, min(value.location.x, width))
                        // x=width → offset=0 (现在); x=0 → offset=1440 (24h 前)
                        let raw = Int((1 - x / width) * dayMinutes)
                        let snapped = (raw / snapStep) * snapStep
                        scrubOffset = max(0, min(snapped, 1440))
                    }
            )
        }
        .frame(height: trackHeight + thumbSize)
    }

    /// 7 个刻度，按窗口相对位置 (0h 在右、24h 在左)，与 track 同公式
    private var hourLabels: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { i in
                    let offMin = (6 - i) * 4 * 60          // 0, 4h, ..., 24h 前
                    let xPos = CGFloat(1440 - offMin) / 1440 * width
                    let labelDate = now.addingTimeInterval(-Double(offMin) * 60)
                    VStack(spacing: 2) {
                        // 竖刻线 (与 track 对齐)
                        Rectangle()
                            .fill(offMin == 0 ? displayState.accent : Theme.slate.opacity(0.25))
                            .frame(width: offMin == 0 ? 1.5 : 0.5, height: 4)
                        // 文字 (居中于 xPos)
                        Text(formatHourLabel(labelDate))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(offMin == 0 ? displayState.accent : Theme.slate.opacity(0.7))
                            .fixedSize()
                            .position(x: xPos, y: 11)
                    }
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
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
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    scrubOffset = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("回到现在")
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

    // MARK: - 组件

    /// 把原 schedule 时段按"过去 24h 窗口"重新映射
    /// 窗口坐标系：左 = 24h 前 (offset 0)，右 = 现在 (offset 1440)
    /// 段位置 = 该段在窗口里的窗口坐标 offset / 1440
    /// 跨过右边界（startWin > endWin）的段拆成两段画
    @ViewBuilder
    private func rotatedSegment(_ seg: StickState.DaySegment, in width: CGFloat) -> some View {
        let totalMin = Int(dayMinutes)
        let startWin = ((seg.startMinute - nowMinute) + totalMin) % totalMin
        let endWin   = ((seg.endMinute   - nowMinute) + totalMin) % totalMin
        let thumbWin = totalMin - displayOffset
        let gap: CGFloat = 1.5
        let total = CGFloat(totalMin)
        let accent = seg.state.accent

        if startWin <= endWin {
            // 普通段（不跨边）
            let xStart = CGFloat(startWin) / total * width
            let segW   = CGFloat(endWin - startWin) / total * width
            let isActive = (startWin...endWin).contains(thumbWin)
            singlePiece(
                xStart: xStart, segW: segW,
                fillX: xStart + gap / 2, fillW: max(0, segW - gap),
                isActive: isActive, accent: accent
            )
        } else {
            // 跨右边界：拆成两段
            // 右半段：startWin → totalMin (右端)
            let rX = CGFloat(startWin) / total * width
            let rW = CGFloat(totalMin - startWin) / total * width
            // 左半段：0 → endWin (左端)
            let lX = CGFloat(0)
            let lW = CGFloat(endWin) / total * width
            let rightActive = thumbWin >= startWin && thumbWin < totalMin
            let leftActive  = thumbWin >= 0 && thumbWin < endWin
            ZStack {
                singlePiece(
                    xStart: rX, segW: rW,
                    fillX: rX + gap / 2, fillW: max(0, rW - gap / 2),
                    isActive: rightActive, accent: accent
                )
                singlePiece(
                    xStart: lX, segW: lW,
                    fillX: lX + gap / 2, fillW: max(0, lW - gap / 2),
                    isActive: leftActive, accent: accent
                )
            }
        }
    }

    /// 一段矩形（带可选 active 描边）
    @ViewBuilder
    private func singlePiece(
        xStart: CGFloat, segW: CGFloat,
        fillX: CGFloat, fillW: CGFloat,
        isActive: Bool, accent: Color
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: max(0, fillW), height: trackHeight)
                .offset(x: fillX, y: 0)
            if isActive {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(accent.opacity(0.55), lineWidth: 2.2)
                    .frame(width: max(0, fillW), height: trackHeight)
                    .offset(x: fillX, y: -1.8)
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

    private func xPosition(forOffset m: Int, in width: CGFloat) -> CGFloat {
        // offset 0 → 右边；1440 → 左边
        CGFloat(1440 - m) / dayMinutes * width
    }

    private func formatDisplayClock(_ date: Date) -> String {
        // 显示日期 + 时分 (如 "周一 21:00" 或 "今 21:00")
        let c = Calendar.current
        let isToday = c.isDateInToday(date)
        let prefix = isToday ? "今" : weekdayShort(date) // 周一/二/...
        let h = c.component(.hour, from: date)
        let m = c.component(.minute, from: date)
        return String(format: "%@ %02d:%02d", prefix, h, m)
    }

    private func formatHourLabel(_ date: Date) -> String {
        let c = Calendar.current
        let h = c.component(.hour, from: date)
        return String(format: "%02d", h)
    }

    private func weekdayShort(_ date: Date) -> String {
        let c = Calendar.current
        let weekday = c.component(.weekday, from: date) // 1=Sun ... 7=Sat
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return "周" + names[weekday - 1]
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
