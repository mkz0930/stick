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
            // 右上角 "NOW" — 整块可点，回到现在
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    scrubOffset = nil
                }
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
                    Text("点击回现在 →")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
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

    /// 把原 schedule 时段按"过去 24h"重新映射
    @ViewBuilder
    private func rotatedSegment(_ seg: StickState.DaySegment, in width: CGFloat) -> some View {
        let totalMin = Int(dayMinutes)
        let startOff = ((seg.startMinute - nowMinute) + totalMin) % totalMin
        let endOff   = ((seg.endMinute   - nowMinute) + totalMin) % totalMin
        // 段宽（分钟），如果跨越右端（endOff < startOff）则视为整段（24h 跨度不会超过 1440）
        let dur = seg.duration
        // x 起点：从右端往左算
        let xStart = CGFloat(1440 - startOff) / dayMinutes * width
        let segW   = CGFloat(dur) / dayMinutes * width
        RoundedRectangle(cornerRadius: 3)
            .fill(seg.state.accent)
            .frame(width: segW, height: trackHeight)
            .offset(x: xStart, y: 0)
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
