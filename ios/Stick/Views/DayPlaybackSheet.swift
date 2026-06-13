import SwiftUI

/// 1 天回放 sheet（点击分享按钮后弹出）
///  - 10 秒内播放完 24h 火柴人状态变化
///  - 顶栏：动态时间（00:00 → 24:00）+ 关闭
///  - 中央：火柴人按 schedule 切换状态
///  - 底部：进度条 + 当前状态文字
///  - 结束后右下角出现 "分享" 按钮 (ShareLink)
struct DayPlaybackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let schedule: [StickState.DaySegment]

    @State private var startTime: Date = .init()
    @State private var elapsed: Double = 0
    @State private var isFinished: Bool = false
    @State private var showSummary: Bool = false    // 播放完后显示总结封面
    private let duration: Double = 5   // 5s 走完 24h (提速)

    private var progress: Double { min(elapsed / duration, 1) }

    /// 模拟当天分钟数 (0..1440)
    private var simulatedMinute: Int {
        Int(progress * 1440)
    }

    private var displayState: StickState {
        schedule.first { $0.startMinute <= simulatedMinute && simulatedMinute < $0.endMinute }?.state ?? .walk
    }

    private var displaySegment: StickState.DaySegment? {
        schedule.first { $0.startMinute <= simulatedMinute && simulatedMinute < $0.endMinute }
    }

    private var displayTime: String {
        let m = simulatedMinute
        let h = (m / 60) % 24
        let mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }

    var body: some View {
        ZStack {
            // 浅色背景
            Color(red: 0.98, green: 0.98, blue: 0.97).ignoresSafeArea()

            if showSummary {
                summaryView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                playbackView
                    .transition(.opacity)
            }
        }
        .onAppear {
            startTime = .init()
            elapsed = 0
            isFinished = false
            showSummary = false
        }
        .onChange(of: isFinished) { _, finished in
            if finished {
                // 播放完后等 0.6s 切到总结封面 (留出收尾时间)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSummary = true
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard !isFinished else { return }
            elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= duration {
                elapsed = duration
                isFinished = true
            }
        }
    }

    // MARK: - 播放视图 (10s 回放)

    private var playbackView: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer(minLength: 12)

            // 状态名 (eyebrow)
            Text(displayState.eyebrow)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundColor(displayState.accent.opacity(0.85))
                .lineLimit(1)

            // 火柴人
            StickFigureView(
                state: displayState,
                lineColor: Color(red: 0.10, green: 0.14, blue: 0.20),
                fillColor: Color(red: 0.98, green: 0.98, blue: 0.97)
            )
            .frame(maxWidth: 240, maxHeight: 320)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.3), value: displayState)

            // 副标
            Text(displayState.subLine)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                .lineLimit(1)
                .padding(.horizontal, 32)

            Spacer(minLength: 12)

            bottomControls
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
    }

    // MARK: - 总结封面 (最后一页)

    /// 各状态累计分钟（按 schedule 聚合）
    private var distribution: [(state: StickState, minutes: Int)] {
        var dict: [StickState: Int] = [:]
        for seg in schedule {
            dict[seg.state, default: 0] += seg.duration
        }
        // 固定顺序: 走 / 坐 / 睡
        return [.walk, .sit, .sleep].map { ($0, dict[$0] ?? 0) }
    }

    private var totalMinutes: Int { distribution.reduce(0) { $0 + $1.minutes } }

    private var summaryView: some View {
        VStack(spacing: 0) {
            summaryTopBar
                .padding(.horizontal, 20)
                .padding(.top, 20)

            // 标题
            VStack(spacing: 2) {
                Text("TODAY · 24H")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.45, green: 0.50, blue: 0.55))
                Text("今日 24h")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.20))
            }
            .padding(.top, 4)

            Spacer(minLength: 4)

            // 火柴人（主体）
            StickFigureView(
                state: .walk,
                lineColor: Color(red: 0.10, green: 0.14, blue: 0.20),
                fillColor: Color(red: 0.98, green: 0.98, blue: 0.97)
            )
            .frame(maxWidth: 280, maxHeight: 280)
            .padding(.vertical, 4)

            // 时间分布堆叠条
            VStack(spacing: 8) {
                DistributionStackedBar(distribution: distribution, total: totalMinutes)
                    .frame(height: 14)
                    .clipShape(Capsule())

                // 图例
                HStack(spacing: 14) {
                    ForEach(distribution.indices, id: \.self) { i in
                        let item = distribution[i]
                        let pct = totalMinutes > 0 ? Int(round(Double(item.minutes) / Double(totalMinutes) * 100)) : 0
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.state.accent)
                                .frame(width: 6, height: 6)
                            Text("\(item.state.rawValue) \(pct)%")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                        }
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 8)

            summaryShareButton
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
    }

    private var summaryTopBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("回放结束")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                Text(todayText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.20))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryShareButton: some View {
        ShareLink(item: shareMessage) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                Text("分享今日")
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Capsule().fill(Color(red: 0.10, green: 0.14, blue: 0.20))
            )
        }
        .buttonStyle(.plain)
    }

    private var todayText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    private func formatHM(_ m: Int) -> String {
        let h = m / 60
        let mm = m % 60
        return "\(h)h\(String(format: "%02d", mm))m"
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日回放")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                Text(displayTime)
                    .font(.system(size: 38, weight: .black, design: .monospaced))
                    .foregroundColor(displayState.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.18), value: displayTime)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.30, green: 0.35, blue: 0.40))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 底部控件 (进度条 + 状态文字 + 分享按钮)

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(displayState.accent)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.linear(duration: 0.05), value: progress)
                    // thumb
                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, geo.size.width * progress - 5))
                }
            }
            .frame(height: 10)

            // 状态文字 + 分享按钮
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let seg = displaySegment {
                        Text("位于 \(seg.state.rawValue) · \(StickState.formatMinute(seg.startMinute))–\(StickState.formatMinute(seg.endMinute))")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(Color(red: 0.40, green: 0.45, blue: 0.50))
                            .lineLimit(1)
                    }
                    Text(isFinished ? "回放结束" : "正在播放…")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.20))
                }
                Spacer()
                if isFinished {
                    ShareLink(item: shareMessage) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .bold))
                            Text("分享")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(displayState.accent)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shareMessage: String {
        let parts = distribution.map { "\($0.state.rawValue) \(formatHM($0.minutes))" }
        return "今日 24h · " + parts.joined(separator: " · ")
    }

    private var stepsCount: Int {
        schedule.count
    }
}

// MARK: - 总结封面子组件

/// 甜甜圈图：按 schedule 聚合的 state × 分钟，按 [走, 坐, 睡] 顺序
///  - 中心 13% 区域画白色圆形留空
///  - 段间 2pt 白色 gap
///  - 中心文字：总小时
private struct DistributionDonut: View {
    let distribution: [(state: StickState, minutes: Int)]
    let total: Int

    private let lineWidth: CGFloat = 28
    private let gap: CGFloat = 0.018   // 段间 gap (≈ 6.5°)

    var body: some View {
        ZStack {
            // 浅灰底环 (空状态)
            Circle()
                .stroke(Color.black.opacity(0.06), lineWidth: lineWidth)

            // 各状态段
            ForEach(distribution.indices, id: \.self) { i in
                let item = distribution[i]
                let start = startAngle(for: i)
                let end = endAngle(for: i)
                Circle()
                    .trim(from: start, to: end)
                    .stroke(item.state.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            // 中心信息
            VStack(spacing: 2) {
                Text("\(total / 60)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.20))
                    .monospacedDigit()
                Text("小时")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(red: 0.45, green: 0.50, blue: 0.55))
            }
        }
    }

    private func startAngle(for i: Int) -> CGFloat {
        let before = distribution.prefix(i).reduce(0) { $0 + $1.minutes }
        return total > 0 ? CGFloat(before) / CGFloat(total) + gap / 2 : 0
    }

    private func endAngle(for i: Int) -> CGFloat {
        let through = distribution.prefix(i + 1).reduce(0) { $0 + $1.minutes }
        return total > 0 ? CGFloat(through) / CGFloat(total) - gap / 2 : 0
    }
}

/// 总结封面图例行：色点 + 状态名 + 时长 + 百分比
private struct SummaryLegendRow: View {
    let state: StickState
    let durationText: String
    let percent: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.accent)
                .frame(width: 8, height: 8)
            Text(state.rawValue)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.20))
                .frame(width: 24, alignment: .leading)
            Text(durationText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.20, green: 0.24, blue: 0.30))
                .monospacedDigit()
            Spacer()
            Text("\(percent)%")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundColor(state.accent)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

/// 总结封面：横向堆叠条 (走 / 坐 / 睡)
private struct DistributionStackedBar: View {
    let distribution: [(state: StickState, minutes: Int)]
    let total: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(distribution.indices, id: \.self) { i in
                    let item = distribution[i]
                    let width = total > 0
                        ? geo.size.width * CGFloat(item.minutes) / CGFloat(total)
                        : 0
                    Rectangle()
                        .fill(item.state.accent)
                        .frame(width: width)
                }
            }
        }
    }
}
