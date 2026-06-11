import SwiftUI

/// 24h 可拖动时间线。ATLAS v6 编辑风格：
///  - 走/坐/睡 三个时段用对应 accent 颜色铺成连续色条
///  - 状态色 thumb（外白圈 + 中心状态色点），可拖动
///  - 拖离当前时间后显示"回到现在"按钮，点击 spring 动画回弹
///  - 整体米色 / navy 文字，mono 标签
struct DayTimelineView: View {
    let schedule: [StickState.DaySegment]
    let now: Date
    @Binding var scrubMinute: Int?

    private let dayMinutes: CGFloat = 1440
    private let trackHeight: CGFloat = 14
    private let thumbSize: CGFloat = 22
    private let segmentGap: CGFloat = 1.5
    private let snapStep: Int = 5        // 5 分钟一格

    // MARK: - 派生

    private var isScrubbing: Bool {
        guard let s = scrubMinute else { return false }
        return s != StickState.minutesOfDay(now)
    }

    private var displayMinute: Int {
        scrubMinute ?? StickState.minutesOfDay(now)
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
                Text(isScrubbing ? "SCRUBBING · 拖动以查看" : "TODAY · 24H TIMELINE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.slate)
                Text(StickState.formatMinute(displayMinute))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(isScrubbing ? displayState.accent : Theme.navy)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: displayMinute)
            }
            Spacer()
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
                .id(displayState)  // 状态切换时重绘以触发动画
                .transition(.opacity)
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                // 色条（按时段）
                ForEach(schedule) { seg in
                    segment(seg, in: width)
                }

                // thumb
                let xPos = xPosition(forMinute: displayMinute, in: width)
                thumb
                    .position(x: xPos, y: trackHeight / 2)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85),
                               value: displayMinute)
            }
            .frame(height: trackHeight + thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = max(0, min(value.location.x, width))
                        let raw = Int((x / width) * dayMinutes)
                        let snapped = (raw / snapStep) * snapStep
                        scrubMinute = max(0, min(snapped, 1439))
                    }
            )
        }
        .frame(height: trackHeight + thumbSize)
    }

    private var hourLabels: some View {
        HStack(spacing: 0) {
            ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { h in
                Text(h == 24 ? "24" : String(format: "%02d", h))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.slate.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
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
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    scrubMinute = nil
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

    @ViewBuilder
    private func segment(_ seg: StickState.DaySegment, in width: CGFloat) -> some View {
        let totalGap = CGFloat(schedule.count - 1) * segmentGap
        let usableW = max(0, width - totalGap)
        let xStart = CGFloat(seg.startMinute) / dayMinutes * width
            + CGFloat(schedule.prefix { $0.startMinute < seg.startMinute }.count) * segmentGap
        let segW = CGFloat(seg.duration) / dayMinutes * usableW
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
            // 中心点
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

    private func xPosition(forMinute m: Int, in width: CGFloat) -> CGFloat {
        CGFloat(m) / dayMinutes * width
    }
}
