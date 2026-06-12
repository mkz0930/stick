//
//  SleepReportView.swift
//  睡眠报告 (v6 风格) — 昨晚 24h sleep bar + 阶段汇总 + 总结
//
//  数据来源: SleepAnalyzer.shared.fetchLastNight() (HealthKit sleep analysis 聚合)
//  - 真实数据: 从 HealthKit 拉昨晚 sleep analysis 类别, 聚合成 SleepSession
//  - 当前实现: 直接消费 SleepSession (无 HealthKit 数据时, .empty 状态显示 "等待同步")
//

import SwiftUI

// MARK: - Stage color extension (从已有 SleepStage 派生 v6 调色板)

extension SleepStage {
    /// v6 调色板 (匹配任务定义)
    var color: Color {
        switch self {
        case .awake:  return Color(red: 0.906, green: 0.298, blue: 0.235)  // #E74C3C 橙红
        case .inBed:  return Color(red: 0.722, green: 0.722, blue: 0.784)  // #B8B8C8 灰
        case .asleep: return Color(red: 0.612, green: 0.627, blue: 0.847)  // #9CA0D8 淡紫
        case .rem:    return Color(red: 0.486, green: 0.227, blue: 0.929)  // #7C3AED 紫
        case .core:   return Color(red: 0.357, green: 0.431, blue: 0.910)  // #5B6EE8 蓝靛
        case .deep:   return Color(red: 0.239, green: 0.310, blue: 0.722)  // #3D4FB8 深靛
        }
    }

    /// 全英文短码 (UI 显示用)
    var shortName: String {
        switch self {
        case .awake:  return "AWAKE"
        case .inBed:  return "IN BED"
        case .asleep: return "ASLEEP"
        case .rem:    return "REM"
        case .core:   return "CORE"
        case .deep:   return "DEEP"
        }
    }
}

// MARK: - StageCardData (4 张阶段卡)

/// 单张阶段卡 (DEEP / REM / CORE / AWAKE)
struct StageCardData: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let duration: Int   // 分钟
    let color: Color

    /// "1h32m" / "27m" / "—" 格式
    var formatted: String {
        if duration <= 0 { return "—" }
        let h = duration / 60
        let m = duration % 60
        if h > 0 { return "\(h)h\(String(format: "%02dm", m))" }
        return "\(m)m"
    }

    /// 占"实际睡眠"总时长的百分比 (0–1)
    func percent(of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(duration) / Double(total)
    }
}

// MARK: - Bar segment (横条用的色段)

/// 横条显示用的色段 (按分钟起止)
struct BarSegment: Identifiable, Equatable {
    let id = UUID()
    let stage: SleepStage
    let startMinute: Int   // 自午夜起的分钟数 (允许 0–2880 跨夜, 见 expand)
    let endMinute: Int
    var duration: Int { endMinute - startMinute }
}

// MARK: - 报告模型 (把 SleepSession 拍平为 view-friendly)

/// 4 张阶段卡的数据
struct StageBreakdown: Equatable {
    let deep: Int
    let rem: Int
    let core: Int
    let awake: Int

    /// 占总睡眠 (deep+rem+core+awake) 的百分比
    var total: Int { deep + rem + core + awake }

    var cards: [StageCardData] {
        [
            StageCardData(stage: .deep,  duration: deep,  color: SleepStage.deep.color),
            StageCardData(stage: .rem,   duration: rem,   color: SleepStage.rem.color),
            StageCardData(stage: .core,  duration: core,  color: SleepStage.core.color),
            StageCardData(stage: .awake, duration: awake, color: SleepStage.awake.color),
        ]
    }

    /// 把 SleepSession 拆成 4 段累计分钟
    init(_ session: SleepSession) {
        self.deep  = session.deepMinutes
        self.rem   = session.remMinutes
        self.core  = session.coreMinutes
        self.awake = session.awakeMinutes
    }

    init() {
        self.deep = 0; self.rem = 0; self.core = 0; self.awake = 0
    }
}

// MARK: - ViewModel

@MainActor
final class SleepReportViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(SleepSession)
        case empty
    }

    @Published var state: State = .loading

    func load() async {
        state = .loading
        #if DEBUG
        // DEBUG: 模拟器无 HealthKit 数据, 注入一段 mock 睡眠会话用于演示
        if ProcessInfo.processInfo.environment["STICK_MOCK_SLEEP"] != "0" {
            try? await Task.sleep(nanoseconds: 600_000_000)
            state = .loaded(Self.mockSession())
            return
        }
        #endif
        let session = await SleepAnalyzer.shared.fetchLastNight()
        if let session {
            state = .loaded(session)
        } else {
            state = .empty
        }
    }

    #if DEBUG
    /// 演示用 mock: 昨晚 23:42 → 今早 06:18, 6h36m
    private static func mockSession() -> SleepSession {
        let cal = Calendar.current
        let today2am = cal.startOfDay(for: Date()).addingTimeInterval(2 * 3600)
        let yesterday23 = today2am.addingTimeInterval(-3 * 3600 + 12 * 60)  // 23:12
        // 简化为: 23:42 → 06:18
        let start = today2am.addingTimeInterval(-3 * 3600 - 18 * 60)      // 22:42
        let end   = today2am.addingTimeInterval(4 * 3600 + 18 * 60)        // 06:18
        // 6 段, 总 6h36m = 396 min
        let segs: [(SleepStage, Int)] = [
            (.inBed, 8),     // 22:42-22:50 准备
            (.asleep, 25),   // 22:50-23:15 浅睡
            (.core, 60),     // 23:15-00:15 核心
            (.deep, 90),     // 00:15-01:45 深睡
            (.core, 75),     // 01:45-03:00 核心
            (.rem, 60),      // 03:00-04:00 REM
            (.awake, 6),     // 04:00-04:06 醒
            (.core, 45),     // 04:06-04:51 核心
            (.rem, 15),      // 04:51-05:06 REM
            (.deep, 30),     // 05:06-05:36 深睡
            (.awake, 12),    // 05:36-05:48 醒
        ]
        var cursor = start
        var segments: [SleepSegment] = []
        for (stage, mins) in segs {
            let s = cursor
            let e = cursor.addingTimeInterval(TimeInterval(mins * 60))
            segments.append(SleepSegment(stage: stage, start: s, end: e))
            cursor = e
        }
        return SleepSession(start: start, end: end, segments: segments)
    }
    #endif
}

// MARK: - 主视图

struct SleepReportView: View {
    var onClose: () -> Void
    @StateObject private var vm = SleepReportViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                content
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(StickState.sleep.accent)
                    Text("睡眠报告")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.navy)
                }
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.slate)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    /// 副标题 (随数据状态变化)
    private var headerSubtitle: String {
        switch vm.state {
        case .loading:
            return "正在分析昨晚的睡眠数据…"
        case .loaded(let session):
            let total = session.totalMinutes
            let h = total / 60
            let m = total % 60
            return "昨晚 \(formatTime(session.start)) – \(formatTime(session.end)) · 总时长 \(h)h\(String(format: "%02dm", m))"
        case .empty:
            return "等待 HealthKit 同步"
        }
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            loadingState
        case .loaded(let session):
            loadedContent(session: session)
        case .empty:
            emptyState
        }
    }

    private func loadedContent(session: SleepSession) -> some View {
        let breakdown = StageBreakdown(session)
        let segments = barSegments(from: session)
        let efficiency = Int((session.efficiency * 100).rounded())
        let qualityLabel = qualityForEfficiency(session.efficiency)

        return ScrollView {
            VStack(spacing: 18) {
                SleepStageBar(segments: segments)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                stageGrid(breakdown: breakdown)
                    .padding(.horizontal, 20)

                summaryLine(efficiency: efficiency, quality: qualityLabel)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                adviceLine
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .refreshable { await vm.load() }
    }

    /// 把 SleepSession.segments 转成 BarSegment (按分钟起止)
    private func barSegments(from session: SleepSession) -> [BarSegment] {
        let cal = Calendar.current
        return session.segments.map { seg in
            let sMin = cal.component(.hour, from: seg.start) * 60 + cal.component(.minute, from: seg.start)
            let eMin = cal.component(.hour, from: seg.end) * 60 + cal.component(.minute, from: seg.end)
            // 跨夜: 早于 start hour 的早上段 +1440
            let sExp: Int
            let eExp: Int
            let startHour = cal.component(.hour, from: session.start)
            if cal.component(.hour, from: seg.start) < startHour {
                sExp = sMin + 1440
            } else {
                sExp = sMin
            }
            if cal.component(.hour, from: seg.end) <= cal.component(.hour, from: seg.start) &&
               cal.component(.hour, from: seg.end) < startHour + 4 {
                eExp = eMin + 1440
            } else {
                eExp = eMin
            }
            return BarSegment(stage: seg.stage, startMinute: sExp, endMinute: max(eExp, sExp + 1))
        }
    }

    private func qualityForEfficiency(_ eff: Double) -> String {
        switch eff {
        case 0.85...:   return "GOOD"
        case 0.70..<0.85: return "FAIR"
        default:        return "POOR"
        }
    }

    // MARK: - 加载中

    private var loadingState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("分析中…")
                .font(.system(size: 12))
                .foregroundColor(Theme.slate)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Theme.mist)
            Text("无睡眠记录")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.navy)
            Text("等待 HealthKit 同步")
                .font(.system(size: 12))
                .foregroundColor(Theme.slate)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 阶段汇总 (2x2)

    private func stageGrid(breakdown: StageBreakdown) -> some View {
        let cards = breakdown.cards
        let cols = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(cards) { card in
                StageCard(
                    card: card,
                    totalMinutes: breakdown.total
                )
            }
        }
    }

    // MARK: - 一句话总结

    private func summaryLine(efficiency: Int, quality: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(StickState.sleep.accent)
                .frame(width: 3, height: 14)
            Text("EFFICIENCY \(efficiency)% · QUALITY \(quality)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(Theme.navy)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(StickState.sleep.accentSoft.opacity(0.6))
        )
    }

    // MARK: - 建议

    private var adviceLine: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.mist)
                .padding(.top, 1)
            Text("入睡时间稳定, 深睡比例正常, 建议保持")
                .font(.system(size: 12))
                .foregroundColor(Theme.slate)
                .lineSpacing(2)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 24h 风格 sleep bar (Canvas)

/// 横条: 跨夜 23:00 → 11:00 (次日), 高度 60pt, 圆角 8, 段间 1.5pt gap, 顶部时间刻度 23 00 03 06 09
private struct SleepStageBar: View {
    let segments: [BarSegment]

    private let barHeight: CGFloat = 60
    private let cornerRadius: CGFloat = 8
    private let gap: CGFloat = 1.5

    /// 横条展示的窗口 (跨夜): 23:00 起到次日 11:00 止, 共 12 小时 = 720 分钟
    private let windowStart: Int = 23 * 60   // 1380
    private let windowEnd: Int   = 35 * 60   // 2100 (次日 11:00, 用 24+11=35 编码)
    private var windowMinutes: Int { windowEnd - windowStart }   // 720

    /// 横条显示的刻度
    private let ticks: [Int] = [23, 0, 3, 6, 9]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题
            HStack {
                Text("24h SLEEP TIMELINE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.slate)
                Spacer()
                Text("23:00 → 11:00")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.mist)
            }

            // 刻度尺 + 横条
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // 横条
                    Canvas { ctx, size in
                        let barW = size.width
                        let barH = barHeight
                        let r = cornerRadius

                        for seg in segments {
                            // 跳过完全在窗口外的段
                            guard seg.endMinute > windowStart, seg.startMinute < windowEnd else { continue }
                            let lo = max(seg.startMinute, windowStart)
                            let hi = min(seg.endMinute, windowEnd)
                            let x0 = CGFloat(lo - windowStart) / CGFloat(windowMinutes) * barW
                            let x1 = CGFloat(hi - windowStart) / CGFloat(windowMinutes) * barW
                            let rect = CGRect(
                                x: x0 + gap / 2,
                                y: 0,
                                width: max(2, x1 - x0 - gap),
                                height: barH
                            )
                            let path = Path(roundedRect: rect, cornerRadius: r)
                            ctx.fill(path, with: .color(seg.stage.color))
                        }
                    }
                    .frame(height: barHeight)

                    // 刻度 + 标签 (覆盖在条下方)
                    Canvas { ctx, size in
                        let barW = size.width
                        for tick in ticks {
                            let x = CGFloat(tick * 60 - windowStart) / CGFloat(windowMinutes) * barW
                            // 刻度线 (短)
                            var line = Path()
                            line.move(to: CGPoint(x: x, y: barHeight))
                            line.addLine(to: CGPoint(x: x, y: barHeight + 4))
                            ctx.stroke(line, with: .color(Theme.mist), lineWidth: 0.5)

                            // 文字
                            let label = String(format: "%02d", tick == 0 ? 0 : (tick < 24 ? tick : tick - 24))
                            let text = Text(label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Theme.slate)
                            ctx.draw(text, at: CGPoint(x: x, y: barHeight + 16))
                        }
                    }
                    .frame(height: barHeight + 24)
                }
                .frame(width: w, height: barHeight + 26)
            }
            .frame(height: barHeight + 26)

            // 图例
            HStack(spacing: 12) {
                ForEach([SleepStage.awake, .rem, .core, .deep], id: \.self) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 6, height: 6)
                        Text(s.shortName)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(Theme.slate)
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.borderSoft, lineWidth: 1)
        )
    }
}

// MARK: - 阶段卡 (2x2)

private struct StageCard: View {
    let card: StageCardData
    let totalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部: 圆点 + 阶段名
            HStack(spacing: 6) {
                Circle()
                    .fill(card.color)
                    .frame(width: 8, height: 8)
                Text(card.stage.shortName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Theme.slate)
                Spacer()
            }

            // 时长
            Text(card.formatted)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.navy)

            // 占比进度条
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let p = card.percent(of: totalMinutes)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.borderSoft)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(card.color)
                            .frame(width: max(2, w * p), height: 4)
                    }
                }
                .frame(height: 4)

                Text(percentString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Theme.mist)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.borderSoft, lineWidth: 1)
        )
    }

    private var percentString: String {
        let p = card.percent(of: totalMinutes) * 100
        return String(format: "%.0f%%", p)
    }
}

#Preview {
    SleepReportView(onClose: {})
}
