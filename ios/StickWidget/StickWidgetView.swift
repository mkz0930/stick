import SwiftUI
import WidgetKit

// MARK: - Entry

struct StickEntry: TimelineEntry {
    let date: Date
    let state: SharedStickState
}

// MARK: - Provider

struct StickProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickEntry {
        StickEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StickEntry) -> Void) {
        completion(StickEntry(date: Date(), state: SharedStateStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StickEntry>) -> Void) {
        let now = Date()
        let entry = StickEntry(date: now, state: SharedStateStore.read())
        let next = now.addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Theme helpers

enum WidgetTheme {
    static func accent(for stateRaw: String) -> Color {
        switch stateRaw {
        case "sit":   return Color(red: 0.92, green: 0.34, blue: 0.05)
        case "sleep": return Color(red: 0.39, green: 0.40, blue: 0.95)
        default:      return Color(red: 0.02, green: 0.59, blue: 0.41)
        }
    }
}

// MARK: - 2x2 Widget View
// Live widget: 走路双腿/双臂摆动循环、睡觉 Z 飘起、心跳 BPM 同步脉冲、
// 时间问候（早/午/晚/深夜）、底部一句鼓励微文案。

struct StickWidgetView: View {
    let entry: StickEntry
    private var s: SharedStickState { entry.state }

    private var accent: Color { WidgetTheme.accent(for: s.stateRaw) }

    var body: some View {
        TimelineView(.animation) { tl in
            VStack(alignment: .leading, spacing: 3) {
                // 顶 row：状态徽章 + 时间问候
                HStack(spacing: 4) {
                    PulsingDot(color: accent, t: tl.date.timeIntervalSinceReferenceDate, bpm: s.heartRate)
                        .frame(width: 8, height: 8)
                    Text(s.englishName)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Spacer(minLength: 0)
                    Text(greeting(t: tl.date))
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                        .lineLimit(1)
                }

                // 动态火柴人
                AnimatedMiniFigure(
                    stateRaw: s.stateRaw,
                    accent: accent,
                    heartRate: s.heartRate,
                    durationMinutes: s.durationMinutes,
                    t: tl.date.timeIntervalSinceReferenceDate
                )
                .frame(maxWidth: .infinity)
                .frame(height: 50)

                // 标题
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(s.actionPhrase)
                        .font(.system(size: 13, weight: .black, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                // 底 row：心跳 + 心情 + 鼓励微文案
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    BeatingHeart(bpm: s.heartRate, t: tl.date.timeIntervalSinceReferenceDate)
                        .frame(width: 11, height: 11)
                    Text("\(s.heartRate)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    Text("·")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color(red: 0.62, green: 0.65, blue: 0.72))
                    Text(s.mood)
                        .font(.system(size: 10, weight: .medium, design: .serif))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                // 鼓励微文案（每次刷新换一句）
                Text(microCopy(t: tl.date))
                    .font(.system(size: 9, weight: .medium))
                    .italic()
                    .foregroundColor(accent.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Theme.bgTop, ambientTint(t: entry.date)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - 时间问候

    private func greeting(t: Date) -> String {
        let h = Calendar.current.component(.hour, from: t)
        let prefix: String
        switch h {
        case 5..<11:  prefix = "上午"
        case 11..<14: prefix = "中午"
        case 14..<18: prefix = "下午"
        case 18..<22: prefix = "晚上"
        default:      prefix = "深夜"
        }
        switch s.stateRaw {
        case "walk":  return "\(prefix)·走着"
        case "sit":   return "\(prefix)·坐着"
        case "sleep": return "\(prefix)·休息"
        default:      return prefix
        }
    }

    // MARK: - 鼓励微文案（按 state × 时段 × 时长 派发，每次刷新换一句）

    private func microCopy(t: Date) -> String {
        let h = Calendar.current.component(.hour, from: t)
        let period: String
        switch h {
        case 5..<11:  period = "morning"
        case 11..<14: period = "noon"
        case 14..<18: period = "afternoon"
        case 18..<22: period = "evening"
        default:      period = "night"
        }

        // 按时段分桶（每 5 分钟换一次文案）让用户感到"活着的"
        let bucket = Int(t.timeIntervalSinceReferenceDate / 300)
        let seed = bucket ^ abs(s.stateRaw.hashValue) ^ abs(s.mood.hashValue)

        let candidates: [String]
        switch (s.stateRaw, period) {
        case ("walk", "morning"):
            candidates = ["出门晒晒太阳", "晨光正好，继续", "心率在好区间", "今天已走 \(s.durationMinutes) 分"]
        case ("walk", "noon"):
            candidates = ["饭后走一走", "步数破 6k 了", "阳光正好", "走走消食"]
        case ("walk", "afternoon"):
            candidates = ["活动量够赞", "继续刷新记录", "散步灵感多", "保持节奏"]
        case ("walk", "evening"):
            candidates = ["夜风正好", "今日步数快到目标", "睡前走一走", "安静一下"]
        case ("walk", "night"):
            candidates = ["该回去休息了", "深夜散步小心", "准备睡觉吧", "别走太远"]

        case ("sit", "morning"):
            candidates = ["坐久了，伸个腰", "站一站接杯水", "久坐 30 分钟就起身", "颈椎前倾 +18°"]
        case ("sit", "noon"):
            candidates = ["别光盯着屏幕", "饭后站 10 分钟", "起来走两步", "腰背有点僵"]
        case ("sit", "afternoon"):
            candidates = ["🪑 久坐 \(s.durationMinutes) 分", "起身活动 5 分钟", "后仰拉伸 30s", "做个颈肩操"]
        case ("sit", "evening"):
            candidates = ["今天已坐了 N 小时", "睡前不要久坐", "拉一下腰", "明早多走点"]
        case ("sit", "night"):
            candidates = ["夜深该睡了", "久坐伤腰，躺一躺", "别熬太晚", "明天再战"]

        case ("sleep", "morning"):
            candidates = ["🛌 深睡 1h32m", "睡眠质量评分 82", "今早元气满满", "续睡一会也无妨"]
        case ("sleep", "noon"):
            candidates = ["不要午睡太久", "小憩 20 分钟即可", "午后易困，起身走", "开窗透透气"]
        case ("sleep", "afternoon"):
            candidates = ["💤 入睡 \(s.durationMinutes) 分", "今日睡眠健康", "枕边光线调暗", "晚安"]
        case ("sleep", "evening"):
            candidates = ["🌙 入睡中", "呼吸节律平稳", "祝你做个好梦", "放下手机"]
        case ("sleep", "night"):
            candidates = ["深睡中 · 状态平稳", "呼吸 13/分", "枕头该换了？", "夜深安静"]

        default:
            candidates = ["保持节奏", "状态平稳", "一切正常"]
        }

        return candidates[abs(seed) % candidates.count]
    }

    // MARK: - 时段色调（米色 → 暖黄/冷蓝）

    private func ambientTint(t: Date) -> Color {
        let h = Calendar.current.component(.hour, from: t)
        switch h {
        case 5..<11:  return Color(red: 0.99, green: 0.96, blue: 0.88)  // 上午 · 暖米黄
        case 11..<14: return Color(red: 0.99, green: 0.99, blue: 0.95)  // 中午 · 亮白
        case 14..<18: return Color(red: 0.97, green: 0.97, blue: 0.97)  // 下午 · 灰白
        case 18..<22: return Color(red: 0.92, green: 0.93, blue: 0.98)  // 晚上 · 冷蓝
        default:      return Color(red: 0.88, green: 0.90, blue: 0.96)  // 深夜 · 深蓝
        }
    }
}

// MARK: - 脉冲小点（live indicator，跟着心跳节奏）

struct PulsingDot: View {
    let color: Color
    let t: Double
    let bpm: Int

    private var period: Double {
        60.0 / Double(max(40, bpm))
    }

    private var phase: Double {
        (t.truncatingRemainder(dividingBy: period)) / period
    }

    private var ringScale: CGFloat {
        let pulse = max(0, 0.5 - abs(phase - 0.5)) * 2
        return 1.0 + 0.6 * pulse
    }

    private var ringOpacity: Double {
        1.0 - phase
    }

    /// 双脉冲（收缩-舒张）：0..0.15 缩、0.15..0.3 弹回、其余舒张
    private var dotScale: CGFloat {
        if phase < 0.15 { return 1.0 - 0.35 * (phase / 0.15) }
        if phase < 0.30 { return 0.65 + 0.35 * ((phase - 0.15) / 0.15) }
        return 1.0
    }

    var body: some View {
        ZStack {
            // 外环呼吸
            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1)
                .frame(width: 12, height: 12)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(dotScale)
        }
    }
}

// MARK: - 心跳心形

struct BeatingHeart: View {
    let bpm: Int
    let t: Double

    var body: some View {
        let period = 60.0 / Double(max(40, bpm))
        let phase = (t.truncatingRemainder(dividingBy: period)) / period
        let scale: CGFloat = {
            if phase < 0.18 { return 0.85 + 0.25 * (phase / 0.18) }
            if phase < 0.30 { return 1.10 - 0.10 * ((phase - 0.18) / 0.12) }
            return 0.95
        }()
        Image(systemName: "heart.fill")
            .font(.system(size: 11))
            .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
            .scaleEffect(scale)
            .shadow(color: Color(red: 0.86, green: 0.21, blue: 0.27).opacity(0.4), radius: 3, y: 0)
    }
}

// MARK: - 动态火柴人

struct AnimatedMiniFigure: View {
    let stateRaw: String
    let accent: Color
    let heartRate: Int
    let durationMinutes: Int
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            // widget 内部 Theme.navy 在 runtime 解析为透明 — 用 hardcode navy
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.6
            let midX = size.width / 2

            switch stateRaw {
            case "walk":
                drawWalk(ctx: &ctx, midX: midX, size: size, stroke: stroke, w: w, t: t)
            case "sit":
                drawSit(ctx: &ctx, midX: midX, size: size, stroke: stroke, w: w, t: t, minutes: durationMinutes)
            case "sleep":
                drawSleep(ctx: &ctx, midX: midX, size: size, stroke: stroke, w: w, t: t)
            default:
                break
            }
        }
    }

    private func polarPoint(x: CGFloat, y: CGFloat, length: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = Double(degrees) * .pi / 180
        return CGPoint(
            x: x + length * CGFloat(cos(radians)),
            y: y + length * CGFloat(sin(radians))
        )
    }

    private func strokeLine(
        ctx: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        stroke: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        ctx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
    }

    private func walkAngles(for frame: Int) -> (lArm: CGFloat, rArm: CGFloat, lLeg: CGFloat, rLeg: CGFloat) {
        switch frame {
        case 0:  return (-20, 20, -25, 25)
        case 1:  return (0, 0, -10, 10)
        case 2:  return (20, -20, 25, -25)
        default: return (0, 0, 10, -10)
        }
    }

    private func strokeWalkLeg(
        ctx: inout GraphicsContext,
        hip: CGPoint,
        angle: CGFloat,
        stroke: Color,
        lineWidth: CGFloat
    ) {
        let kneeLen: CGFloat = 6
        let footLen: CGFloat = 8
        let knee = polarPoint(x: hip.x, y: hip.y + 4, length: kneeLen, degrees: angle)
        let foot = polarPoint(x: knee.x, y: knee.y + 4, length: footLen, degrees: angle + 20)
        var path = Path()
        path.move(to: hip)
        path.addLine(to: knee)
        path.addLine(to: foot)
        ctx.stroke(path, with: .color(stroke), lineWidth: lineWidth)
    }

    // 走：4 帧步行循环，每帧腿/臂位置不同
    private func drawWalk(ctx: inout GraphicsContext, midX: CGFloat, size: CGSize, stroke: Color, w: CGFloat, t: Double) {
        // 周期 0.7s（≈ 90 步/分）
        let cycle = 0.7
        let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
        let frame = Int(phase * 4) % 4
        let bob = CGFloat(abs(sin(phase * .pi * 2)) * 1.2)
        let angles = walkAngles(for: frame)

        ctx.fill(
            Path(ellipseIn: CGRect(x: midX - 6, y: 2 - bob, width: 12, height: 12)),
            with: .color(stroke)
        )

        strokeLine(
            ctx: &ctx,
            from: CGPoint(x: midX, y: 14 - bob),
            to: CGPoint(x: midX, y: 32 - bob),
            stroke: stroke,
            lineWidth: w
        )

        let shoulder = CGPoint(x: midX, y: 20 - bob)
        strokeLine(
            ctx: &ctx,
            from: shoulder,
            to: polarPoint(x: shoulder.x, y: shoulder.y + 2, length: 8, degrees: angles.lArm),
            stroke: stroke,
            lineWidth: w
        )
        strokeLine(
            ctx: &ctx,
            from: shoulder,
            to: polarPoint(x: shoulder.x, y: shoulder.y + 2, length: 8, degrees: angles.rArm),
            stroke: stroke,
            lineWidth: w
        )

        let hip = CGPoint(x: midX, y: 32 - bob)
        strokeWalkLeg(ctx: &ctx, hip: hip, angle: angles.lLeg, stroke: stroke, lineWidth: w)
        strokeWalkLeg(ctx: &ctx, hip: hip, angle: angles.rLeg, stroke: stroke, lineWidth: w)
    }

    // 坐：身体随呼吸起伏，警告时变成橙色叹号
    private func drawSit(ctx: inout GraphicsContext, midX: CGFloat, size: CGSize, stroke: Color, w: CGFloat, t: Double, minutes: Int) {
        let breath = sin(t * 1.4) * 0.6
        let warn = minutes >= 30

        ctx.fill(
            Path(ellipseIn: CGRect(x: midX - 6, y: 2 + breath, width: 12, height: 12)),
            with: .color(stroke)
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX, y: 14 + breath))
                p.addLine(to: CGPoint(x: midX + 4, y: 32 + breath))
            },
            with: .color(stroke), lineWidth: w
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX + 4, y: 22 + breath))
                p.addLine(to: CGPoint(x: midX + 16, y: 30))
            },
            with: .color(stroke), lineWidth: w
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX + 4, y: 32 + breath))
                p.addLine(to: CGPoint(x: midX + 22, y: 32))
            },
            with: .color(stroke), lineWidth: w
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX + 22, y: 32))
                p.addLine(to: CGPoint(x: midX + 22, y: 44))
            },
            with: .color(stroke), lineWidth: w
        )

        // 警告时画一个感叹号（橙）
        if warn {
            let pulse = 0.5 + 0.5 * sin(t * 4)
            ctx.fill(
                Path(ellipseIn: CGRect(x: midX + 26, y: 4, width: 9, height: 9)),
                with: .color(Color(red: 0.92, green: 0.34, blue: 0.05).opacity(0.85 + 0.15 * pulse))
            )
            ctx.draw(
                Text("!").font(.system(size: 8, weight: .black))
                    .foregroundColor(.white),
                at: CGPoint(x: midX + 30.5, y: 8.5), anchor: .center
            )
        }
    }

    // 睡：身体水平、3 个 Z 飘起循环
    private func drawSleep(ctx: inout GraphicsContext, midX: CGFloat, size: CGSize, stroke: Color, w: CGFloat, t: Double) {
        ctx.fill(
            Path(ellipseIn: CGRect(x: midX - 14, y: 16, width: 12, height: 12)),
            with: .color(stroke)
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX - 2, y: 22))
                p.addLine(to: CGPoint(x: midX + 22, y: 24))
            },
            with: .color(stroke), lineWidth: w
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX + 22, y: 24))
                p.addLine(to: CGPoint(x: midX + 28, y: 30))
            },
            with: .color(stroke), lineWidth: w
        )
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: midX - 2, y: 22))
                p.addLine(to: CGPoint(x: midX - 10, y: 18))
            },
            with: .color(stroke), lineWidth: w
        )

        // 3 个 Z，每个延迟 0.7s，从头右上飘起
        for i in 0..<3 {
            let delay = Double(i) * 0.7
            let cycle = 2.1
            let p = ((t + delay).truncatingRemainder(dividingBy: cycle)) / cycle
            if p >= 1 { continue }
            let xOff: CGFloat = 4 + CGFloat(p) * 18
            let yOff: CGFloat = 6 - CGFloat(p) * 14
            let scale: CGFloat = 0.7 + CGFloat(p) * 0.5
            let opacity: CGFloat = 1 - CGFloat(p)
            let size: CGFloat = 8 + CGFloat(i) * 2

            ctx.draw(
                Text("Z").font(.system(size: size * scale, weight: .black, design: .serif))
                    .foregroundColor(accent.opacity(0.85 * opacity)),
                at: CGPoint(x: midX + xOff, y: yOff), anchor: .center
            )
        }
    }
}
