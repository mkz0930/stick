import SwiftUI
import UIKit

/// 10 秒火柴人短片（播一遍后停在统计页，进度条可拖）：
///   起床伸懒腰 → 走到办公桌 → 坐下 → 敲键盘点鼠标 → 起身 → 离开工位
///   最后 1s 叠一行"今日工作/休息/活动"统计。
///
/// 不依赖 StickState — 自己跑一条时间线，骨骼化 Pose + 阶段间插值。
struct MiniFilmView: View {
    var durationSec: Double = 10
    /// 默认深色（适配浅色卡片背景）。要深色背景时改成 .white 即可。
    var lineColor: Color = Color(red: 0.10, green: 0.14, blue: 0.20)
    /// 场景（桌/椅/地面）的线色。
    var sceneColor: Color = Color(red: 0.45, green: 0.50, blue: 0.58)
    /// 进度回调（用来给 share sheet 显示当前状态文字）
    var onTimeUpdate: ((Double) -> Void)? = nil

    @State private var time: Double = 0
    @State private var isPlaying: Bool = true
    @State private var trackWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Canvas { gc, size in
                    let t = min(time, durationSec)
                    let phase = FilmTimeline.phase(at: t)
                    drawFilm(ctx: gc, size: size, t: t, phase: phase)
                }
            }
            .aspectRatio(280.0 / 320.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                time = 0
                isPlaying = true
            }

            progressBar
                .padding(.horizontal, 6)
        }
        .onReceive(Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()) { _ in
            guard isPlaying else { return }
            time += 1.0 / 60.0
            if time >= durationSec {
                time = durationSec
                isPlaying = false
            }
        }
        .onChange(of: time) { _, new in onTimeUpdate?(new) }
    }

    // MARK: - 进度条

    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                // 底
                Capsule()
                    .fill(Color.black.opacity(0.08))
                // 已播
                Capsule()
                    .fill(Color.black)
                    .frame(width: trackWidth * CGFloat(time / durationSec))
                // 阶段刻度
                ForEach(Array(FilmTimeline.breakpoints.dropFirst().dropLast().enumerated()), id: \.offset) { _, bp in
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: 1, height: 10)
                        .offset(x: trackWidth * CGFloat(bp / durationSec) - 0.5)
                }
                // thumb
                Circle()
                    .fill(Color.black)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .offset(x: max(0, trackWidth * CGFloat(time / durationSec) - 7))
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPlaying = false
                        let pct = min(1, max(0, value.location.x / trackWidth))
                        time = Double(pct) * durationSec
                    }
            )
            .onAppear { trackWidth = g.size.width }
            .onChange(of: g.size.width) { _, new in trackWidth = new }
        }
        .frame(height: 22)
    }
}

// MARK: - 阶段定义

/// 表情 / 状态
enum FilmMood: String {
    case excited  // 早上精力充沛、兴奋
    case focused  // 上午到下午专注
    case tired    // 下午傍晚疲惫

    var bodyState: String {
        switch self {
        case .excited: return "精力充沛"
        case .focused: return "专注"
        case .tired:   return "疲惫"
        }
    }
    var moodWord: String {
        switch self {
        case .excited: return "兴奋"
        case .focused: return "平静"
        case .tired:   return "低落"
        }
    }
    var period: String {
        switch self {
        case .excited: return "上午"
        case .focused: return "下午"
        case .tired:   return "傍晚"
        }
    }
}

struct FilmPhase: Equatable {
    var englishTag: String
    var caption: String
    var accent: Color
    var mood: FilmMood
}

private enum FilmTimeline {
    // 9 段 / 10s
    static let wakeEnd:   Double = 1.0   // 0.0  – 1.0  起床伸懒腰
    static let walkEnd:   Double = 3.0   // 1.0  – 3.0  走到办公桌
    static let sitEnd:    Double = 4.0   // 3.0  – 4.0  坐下 (过渡，1s)
    static let typeEnd:   Double = 5.0   // 4.0  – 5.0  敲键盘·上午 (1s)
    static let lieEnd:    Double = 5.5   // 5.0  – 5.5  趴到桌上 (过渡，0.5s)
    static let napEnd:    Double = 6.5   // 5.5  – 6.5  趴桌午休 (1s)
    static let wakeUpEnd: Double = 7.0   // 6.5  – 7.0  坐起 (过渡，0.5s)
    // 7.0  – 7.5  下午工作 (0.5s)
    static let standEnd:  Double = 8.5   // 7.5  – 8.5 起身 (过渡，1s)
    // 8.5  – 10.0  离开工位 (1.5s) — 期间 9.0–10.0 显示总结

    /// 进度条上的阶段刻度（去掉首尾）
    static let breakpoints: [Double] = [wakeEnd, walkEnd, sitEnd, typeEnd, lieEnd, napEnd, wakeUpEnd, standEnd]

    static let walkColor = Color(red: 0.20, green: 0.78, blue: 0.55)
    static let sitColor  = Color(red: 0.96, green: 0.62, blue: 0.10)
    static let wakeColor = Color(red: 0.62, green: 0.82, blue: 0.98)
    static let leaveColor = Color(red: 0.62, green: 0.55, blue: 0.98)
    static let napColor  = Color(red: 0.62, green: 0.55, blue: 0.98)

    /// 当前时间点的 mood (早上兴奋 → 下午疲惫，含午休低谷)
    static func mood(at t: Double) -> FilmMood {
        if t < 3.0        { return .excited }   // 起床 + 通勤
        if t < 5.0        { return .focused }   // 上午工作
        if t < 7.0        { return .tired }     // 趴下 + 午休 + 起身
        if t < 7.5        { return .focused }   // 下午工作刚开始
        return .tired                            // 起身 + 下班
    }

    static func phase(at t: Double) -> FilmPhase {
        let m = mood(at: t)
        if t < wakeEnd {
            return .init(englishTag: "WAKE",  caption: "起床·伸个懒腰",   accent: wakeColor, mood: m)
        } else if t < walkEnd {
            return .init(englishTag: "WALK",  caption: "走到办公桌",     accent: walkColor, mood: m)
        } else if t < sitEnd {
            return .init(englishTag: "SIT",   caption: "坐下",           accent: sitColor, mood: m)
        } else if t < typeEnd {
            return .init(englishTag: "TYPE",  caption: "敲键盘·上午",    accent: sitColor, mood: m)
        } else if t < lieEnd {
            return .init(englishTag: "LIE",   caption: "趴桌午休",       accent: napColor, mood: m)
        } else if t < napEnd {
            return .init(englishTag: "NAP",   caption: "Zzz...",         accent: napColor, mood: m)
        } else if t < wakeUpEnd {
            return .init(englishTag: "UP",    caption: "坐起",           accent: sitColor, mood: m)
        } else if t < standEnd {
            return .init(englishTag: "TYPE",  caption: "敲键盘·下午",    accent: sitColor, mood: m)
        } else if t < 8.5 {
            return .init(englishTag: "STAND", caption: "起身",           accent: sitColor, mood: m)
        } else {
            return .init(englishTag: "LEAVE", caption: "下班·回家",      accent: leaveColor, mood: m)
        }
    }
}

// MARK: - 骨骼

private struct Pose {
    var head: CGPoint
    var neck: CGPoint
    var shoulder: CGPoint
    var hip: CGPoint
    var lElbow: CGPoint
    var lHand: CGPoint
    var rElbow: CGPoint
    var rHand: CGPoint
    var lKnee: CGPoint
    var lAnkle: CGPoint
    var rKnee: CGPoint
    var rAnkle: CGPoint
    var headRot: Double = 0   // degrees
}

// MARK: - 渲染主入口

private extension MiniFilmView {
    func drawFilm(ctx: GraphicsContext, size: CGSize, t: Double, phase: FilmPhase) {
        var gc = ctx
        // 280x320 内部坐标系
        let canvasW: CGFloat = 280
        let canvasH: CGFloat = 320
        let scale = min(size.width / canvasW, size.height / canvasH)
        let dx = (size.width - canvasW * scale) / 2
        let dy = (size.height - canvasH * scale) / 2
        gc.translateBy(x: dx, y: dy)
        gc.scaleBy(x: scale, y: scale)

        drawScene(ctx: &gc, t: t, phase: phase)

        let pose = poseFor(t: t)
        drawFigure(ctx: &gc, pose: pose, accent: phase.accent, line: lineColor, mood: phase.mood)

        // 趴桌午休期：Z 浮起
        if t >= FilmTimeline.lieEnd && t < FilmTimeline.napEnd {
            let zT = (t - FilmTimeline.lieEnd) / (FilmTimeline.napEnd - FilmTimeline.lieEnd)
            drawZzz(ctx: &gc, t: zT)
        }

        // 最后 1s：叠一层今日统计
        let summaryStart: Double = durationSec - 1.0
        if t >= summaryStart {
            let alpha = min(1, max(0, (t - summaryStart) / 0.3))
            drawSummary(ctx: &gc, alpha: alpha)
        }
    }

    func poseFor(t: Double) -> Pose {
        if t < FilmTimeline.wakeEnd {
            let p = t / FilmTimeline.wakeEnd
            return wakePose(x: 50, p: p)
        } else if t < FilmTimeline.walkEnd {
            let p = (t - FilmTimeline.wakeEnd) / (FilmTimeline.walkEnd - FilmTimeline.wakeEnd)
            let x = 50 + easeInOut(p) * 90
            let cycle = (t - FilmTimeline.wakeEnd) * 1.5
            return walkPose(x: x, cycle: fract(cycle), facing: 1)
        } else if t < FilmTimeline.sitEnd {
            // 坐下分两段：站→半蹲→坐
            let p = (t - FilmTimeline.walkEnd) / (FilmTimeline.sitEnd - FilmTimeline.walkEnd)
            let standing = walkPose(x: 140, cycle: 0, facing: 1)
            let mid = midSitPose(x: 140)
            let sitting = sitPose(x: 140, typeT: 0, mouseT: 0)
            if p < 0.5 {
                return blendPose(standing, mid, t: easeInOut(p * 2))
            } else {
                return blendPose(mid, sitting, t: easeInOut((p - 0.5) * 2))
            }
        } else if t < FilmTimeline.typeEnd {
            // 上午敲键盘 (1s)
            let local = t - FilmTimeline.sitEnd
            return sitPose(x: 140, typeT: local * 4.0, mouseT: local * 2.3)
        } else if t < FilmTimeline.lieEnd {
            // 趴下：坐 → 趴桌 (0.5s)
            let p = (t - FilmTimeline.typeEnd) / (FilmTimeline.lieEnd - FilmTimeline.typeEnd)
            let sitting = sitPose(x: 140, typeT: 0, mouseT: 0)
            let lying = napPose(z: 0)
            return blendPose(sitting, lying, t: easeInOut(p))
        } else if t < FilmTimeline.napEnd {
            // 趴桌午休 (1s, Zzz 动画在里面)
            return napPose(z: t - FilmTimeline.lieEnd)
        } else if t < FilmTimeline.wakeUpEnd {
            // 坐起：趴桌 → 坐 (0.5s)
            let p = (t - FilmTimeline.napEnd) / (FilmTimeline.wakeUpEnd - FilmTimeline.napEnd)
            let lying = napPose(z: 0)
            let sitting = sitPose(x: 140, typeT: 0, mouseT: 0)
            return blendPose(lying, sitting, t: easeInOut(p))
        } else if t < 7.5 {
            // 下午敲键盘 (0.5s)
            let local = t - FilmTimeline.wakeUpEnd
            return sitPose(x: 140, typeT: local * 4.0, mouseT: local * 2.3)
        } else if t < FilmTimeline.standEnd {
            // 起身分两段：坐→半蹲→站
            let p = (t - 7.5) / (FilmTimeline.standEnd - 7.5)
            let sitting = sitPose(x: 140, typeT: 0, mouseT: 0)
            let mid = midStandPose(x: 140)
            let standing = walkPose(x: 140, cycle: 0, facing: 1)
            if p < 0.5 {
                return blendPose(sitting, mid, t: easeInOut(p * 2))
            } else {
                return blendPose(mid, standing, t: easeInOut((p - 0.5) * 2))
            }
        } else {
            // 下班走
            let p = (t - FilmTimeline.standEnd) / (10.0 - FilmTimeline.standEnd)
            let x = 140 + easeInOut(p) * 150
            let cycle = (t - FilmTimeline.standEnd) * 1.5
            return walkPose(x: x, cycle: fract(cycle), facing: 1)
        }
    }
}

// MARK: - Pose 构造

private func standingPose(x: Double, bob: Double = 0) -> Pose {
    Pose(
        head:     CGPoint(x: x,      y: 70 - bob),
        neck:     CGPoint(x: x,      y: 108 - bob * 0.4),
        shoulder: CGPoint(x: x,      y: 132),
        hip:      CGPoint(x: x - 2,  y: 238),
        lElbow:   CGPoint(x: x - 18, y: 178),
        lHand:    CGPoint(x: x - 22, y: 218),
        rElbow:   CGPoint(x: x + 18, y: 178),
        rHand:    CGPoint(x: x + 22, y: 218),
        lKnee:    CGPoint(x: x - 8,  y: 282),
        lAnkle:   CGPoint(x: x - 8,  y: 318),
        rKnee:    CGPoint(x: x + 8,  y: 282),
        rAnkle:   CGPoint(x: x + 8,  y: 318),
        headRot: 0
    )
}

private func wakePose(x: Double, p: Double) -> Pose {
    // p = 0..1, 中段双臂上举到极致
    let s = sin(p * .pi)              // 0→1→0
    let armUp = s
    let bob = sin(p * .pi * 6) * 0.4   // 轻微呼吸
    var pose = standingPose(x: x, bob: bob)
    pose.head    = CGPoint(x: x,                       y: 70 - bob - armUp * 6)
    pose.lElbow  = CGPoint(x: x - 20 - armUp * 4,      y: 178 - armUp * 60)
    pose.lHand   = CGPoint(x: x - 26 - armUp * 8,      y: 218 - armUp * 168)
    pose.rElbow  = CGPoint(x: x + 20 + armUp * 4,      y: 178 - armUp * 60)
    pose.rHand   = CGPoint(x: x + 26 + armUp * 8,      y: 218 - armUp * 168)
    pose.headRot = -armUp * 5
    return pose
}

private func walkPose(x: Double, cycle: Double, facing: Double) -> Pose {
    let θ = cycle * .pi * 2
    let stride: Double = 18
    let lift: Double = 12
    let bodyBob = abs(sin(θ * 2)) * 1.8

    // 沿前进方向给头一点 lead
    let headLead = 4.0 * facing

    let leftPhase = θ
    let rightPhase = θ + .pi
    let leftLift = max(0, sin(leftPhase))
    let rightLift = max(0, sin(rightPhase))

    return Pose(
        head:     CGPoint(x: x + headLead,                                       y: 72 - bodyBob),
        neck:     CGPoint(x: x + headLead * 0.5,                                 y: 110 - bodyBob * 0.4),
        shoulder: CGPoint(x: x,                                                  y: 132),
        hip:      CGPoint(x: x - 2,                                              y: 240),
        lElbow:   CGPoint(x: x - 16 - sin(rightPhase) * 6,                       y: 175),
        lHand:    CGPoint(x: x - 22 - sin(rightPhase) * 14,                      y: 212 + sin(rightPhase) * 4),
        rElbow:   CGPoint(x: x + 16 + sin(leftPhase) * 6,                        y: 175),
        rHand:    CGPoint(x: x + 22 + sin(leftPhase) * 14,                       y: 212 - sin(leftPhase) * 4),
        lKnee:    CGPoint(x: x - 4 + sin(leftPhase) * (stride * 0.55),           y: 280 - leftLift * 4),
        lAnkle:   CGPoint(x: x - 4 + sin(leftPhase - 0.25) * (stride + 4),       y: 318 - leftLift * lift),
        rKnee:    CGPoint(x: x + 4 + sin(rightPhase) * (stride * 0.55),          y: 280 - rightLift * 4),
        rAnkle:   CGPoint(x: x + 4 + sin(rightPhase - 0.25) * (stride + 4),      y: 318 - rightLift * lift),
        headRot: 6
    )
}

private func sitPose(x: Double, typeT: Double, mouseT: Double) -> Pose {
    // 坐椅子 (椅面在 y≈218)，左手敲键盘，右手握鼠标
    let typeBob = sin(typeT * .pi * 2) * 1.8
    let mouseBob = sin(mouseT * .pi * 2 + .pi / 2) * 1.0
    let mouseSlide = sin(mouseT * .pi) * 4
    let head = CGPoint(x: x + 12, y: 78)

    return Pose(
        head:     head,
        neck:     CGPoint(x: x + 6,  y: 108),
        shoulder: CGPoint(x: x,      y: 132),
        hip:      CGPoint(x: x - 6,  y: 224),
        // 左臂 → 键盘 (左手腕)
        lElbow:   CGPoint(x: x + 18, y: 178),
        lHand:    CGPoint(x: x + 40, y: 212 - typeBob),
        // 右臂 → 鼠标 (再往右)
        rElbow:   CGPoint(x: x + 32, y: 180),
        rHand:    CGPoint(x: x + 65 + mouseSlide, y: 214 - mouseBob),
        // 大腿水平 → 小腿垂直 (椅面 y=222)
        lKnee:    CGPoint(x: x + 45, y: 222),
        lAnkle:   CGPoint(x: x + 45, y: 295),
        rKnee:    CGPoint(x: x + 60, y: 222),
        rAnkle:   CGPoint(x: x + 60, y: 295),
        headRot: 18
    )
}

/// 坐下中途 — 身体下沉 + 膝盖弯曲 + 一手撑椅子
private func midSitPose(x: Double) -> Pose {
    Pose(
        head:     CGPoint(x: x - 2,  y: 95),
        neck:     CGPoint(x: x - 4,  y: 130),
        shoulder: CGPoint(x: x - 5,  y: 155),
        hip:      CGPoint(x: x - 5,  y: 232),
        // 左臂向后撑椅子
        lElbow:   CGPoint(x: x - 14, y: 188),
        lHand:    CGPoint(x: x - 22, y: 218),
        // 右臂前伸 (向桌面)
        rElbow:   CGPoint(x: x + 18, y: 175),
        rHand:    CGPoint(x: x + 50, y: 195),
        // 大腿稍下倾 + 小腿向前
        lKnee:    CGPoint(x: x + 18, y: 235),
        lAnkle:   CGPoint(x: x + 22, y: 305),
        rKnee:    CGPoint(x: x + 32, y: 235),
        rAnkle:   CGPoint(x: x + 38, y: 305),
        headRot: 10
    )
}

/// 起身后半段 — 身体推起 + 手还撑在椅子上
private func midStandPose(x: Double) -> Pose {
    Pose(
        head:     CGPoint(x: x - 2,  y: 90),
        neck:     CGPoint(x: x - 4,  y: 128),
        shoulder: CGPoint(x: x - 5,  y: 153),
        hip:      CGPoint(x: x - 4,  y: 235),
        // 左臂还压在椅子扶手上
        lElbow:   CGPoint(x: x - 12, y: 188),
        lHand:    CGPoint(x: x - 20, y: 220),
        // 右臂前伸 / 准备离开
        rElbow:   CGPoint(x: x + 18, y: 172),
        rHand:    CGPoint(x: x + 50, y: 192),
        // 腿快站直
        lKnee:    CGPoint(x: x + 5, y: 270),
        lAnkle:   CGPoint(x: x + 5, y: 318),
        rKnee:    CGPoint(x: x + 18, y: 268),
        rAnkle:   CGPoint(x: x + 18, y: 318),
        headRot: 6
    )
}

/// 趴桌午休：身体在桌面上，头朝右，脸朝下；双臂在头下作枕；腿从桌沿垂下
/// z: 进入午休后的时间，用于 Z 浮动
private func napPose(z: Double) -> Pose {
    Pose(
        // 头：圆心 y=152 → 椭圆底 y=176 刚好压在桌面上
        head:     CGPoint(x: 170, y: 152),
        // 颈在头右下
        neck:     CGPoint(x: 188, y: 172),
        // 肩在桌沿
        shoulder: CGPoint(x: 200, y: 178),
        // 髋在桌面右段（带点下垂）
        hip:      CGPoint(x: 232, y: 184),
        // 臂折叠在头下，左手垫头，右手略外
        lElbow:   CGPoint(x: 192, y: 180),
        lHand:    CGPoint(x: 172, y: 184),
        rElbow:   CGPoint(x: 200, y: 180),
        rHand:    CGPoint(x: 180, y: 186),
        // 大腿沿桌延展到桌沿，膝略弯
        lKnee:    CGPoint(x: 244, y: 188),
        lAnkle:   CGPoint(x: 256, y: 224),
        rKnee:    CGPoint(x: 246, y: 192),
        rAnkle:   CGPoint(x: 258, y: 232),
        headRot: 0
    )
}

private func blendPose(_ a: Pose, _ b: Pose, t: Double) -> Pose {
    let s = max(0, min(1, t))
    func l(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
        CGPoint(x: p.x + (q.x - p.x) * s, y: p.y + (q.y - p.y) * s)
    }
    return Pose(
        head:     l(a.head, b.head),
        neck:     l(a.neck, b.neck),
        shoulder: l(a.shoulder, b.shoulder),
        hip:      l(a.hip, b.hip),
        lElbow:   l(a.lElbow, b.lElbow),
        lHand:    l(a.lHand, b.lHand),
        rElbow:   l(a.rElbow, b.rElbow),
        rHand:    l(a.rHand, b.rHand),
        lKnee:    l(a.lKnee, b.lKnee),
        lAnkle:   l(a.lAnkle, b.lAnkle),
        rKnee:    l(a.rKnee, b.rKnee),
        rAnkle:   l(a.rAnkle, b.rAnkle),
        headRot:  a.headRot + (b.headRot - a.headRot) * s
    )
}

private func easeInOut(_ t: Double) -> Double {
    t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
}

// MARK: - 今日统计 (最后 1s 显示)

private enum FilmStats {
    static let work: String = {
        let mins = StickState.daySchedule
            .filter { $0.state == .sit }
            .reduce(0) { acc, seg in acc + seg.duration }
        return formatHM(mins)
    }()
    static let rest: String = {
        let mins = StickState.daySchedule
            .filter { $0.state == .sleep }
            .reduce(0) { acc, seg in acc + seg.duration }
        return formatHM(mins)
    }()
    static let move: String = {
        let mins = StickState.daySchedule
            .filter { $0.state == .walk }
            .reduce(0) { acc, seg in acc + seg.duration }
        return formatHM(mins)
    }()

    static func formatHM(_ m: Int) -> String {
        String(format: "%dh%02dm", m / 60, m % 60)
    }
}

/// 3 个 Z 浮起
private func drawZzz(ctx: inout GraphicsContext, t: Double) {
    // 头部位置：napPose.head 在 (188, 174)。Z 从头部飘到左上方
    let headY: CGFloat = 174
    let headX: CGFloat = 188
    let zConfigs: [(fontSize: CGFloat, delay: Double, drift: CGFloat)] = [
        (24, 0.0,  20),
        (18, 0.35, 16),
        (12, 0.7,  12),
    ]
    for (i, z) in zConfigs.enumerated() {
        let local = max(0, t - z.delay) * 1.6
        if local > 1 { continue }
        let fade = min(1, local) * (1 - max(0, local - 0.85) / 0.15)
        let y = headY - 14 - CGFloat(local) * z.drift
        let x = headX - 18 - CGFloat(i) * 7
        let txt = Text("Z")
            .font(.system(size: z.fontSize, weight: .heavy, design: .serif))
            .foregroundColor(.white.opacity(fade))
        ctx.draw(txt, at: CGPoint(x: x, y: y), anchor: .center)
    }
}

/// 叠在画面上：暗色背景 + 3 行统计
private func drawSummary(ctx: inout GraphicsContext, alpha: Double) {
    // 半透明遮罩
    ctx.fill(
        Path(CGRect(x: 0, y: 0, width: 280, height: 320)),
        with: .color(.black.opacity(0.55 * alpha))
    )

    // 顶部小标
    let title = Text("今日")
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .tracking(2.5)
        .foregroundColor(.white.opacity(0.7 * alpha))
    ctx.draw(title, at: CGPoint(x: 140, y: 78), anchor: .center)

    // 3 行：图标小圆点 + 标签 + 数值
    let rows: [(String, String, String, Color)] = [
        ("work", "工作", FilmStats.work, Color(red: 0.96, green: 0.62, blue: 0.10)),
        ("rest", "休息", FilmStats.rest, Color(red: 0.62, green: 0.55, blue: 0.98)),
        ("move", "活动", FilmStats.move, Color(red: 0.20, green: 0.78, blue: 0.55)),
    ]
    let baseY: CGFloat = 122
    let gap: CGFloat = 58
    for (i, row) in rows.enumerated() {
        let y = baseY + CGFloat(i) * gap
        let rowColor = row.3
        // 色点
        ctx.fill(
            Path(ellipseIn: CGRect(x: 38, y: y - 5, width: 10, height: 10)),
            with: .color(rowColor.opacity(alpha))
        )
        // 标签
        let label = Text(row.1)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.7 * alpha))
        ctx.draw(label, at: CGPoint(x: 58, y: y), anchor: .leading)
        // 数值
        let value = Text(row.2)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundColor(rowColor.opacity(alpha))
        ctx.draw(value, at: CGPoint(x: 220, y: y), anchor: .trailing)
    }
}

private func fract(_ x: Double) -> Double {
    x - floor(x)
}

// MARK: - 场景

private func drawScene(ctx: inout GraphicsContext, t: Double, phase: FilmPhase) {
    let sc = Color(red: 0.45, green: 0.50, blue: 0.58).opacity(0.55)
    let dim = sc.opacity(0.45)
    let groundY: CGFloat = 322

    // 地面
    ctx.stroke(
        Path { p in
            p.move(to: CGPoint(x: 0, y: groundY))
            p.addLine(to: CGPoint(x: 280, y: groundY))
        },
        with: .color(sc), lineWidth: 1.2
    )

    // 远景三角 (左侧两个，提示出门 → 室内)
    drawFar(ctx: &ctx, color: dim, base: 0, peak: 14, ground: groundY)
    drawFar(ctx: &ctx, color: dim.opacity(0.7), base: 22, peak: 8, ground: groundY)

    // 办公桌 (右侧)
    let deskTopY: CGFloat = 176
    let deskL: CGFloat = 150
    let deskR: CGFloat = 268
    let deskTop = Path { p in
        p.move(to: CGPoint(x: deskL, y: deskTopY))
        p.addLine(to: CGPoint(x: deskR, y: deskTopY))
        p.addLine(to: CGPoint(x: deskR, y: deskTopY + 5))
        p.addLine(to: CGPoint(x: deskL, y: deskTopY + 5))
        p.closeSubpath()
    }
    ctx.fill(deskTop, with: .color(sc.opacity(0.35)))
    ctx.stroke(deskTop, with: .color(sc), lineWidth: 1.3)
    // 桌腿
    for lx in [deskL + 4, deskR - 4] {
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: lx, y: deskTopY + 5))
                p.addLine(to: CGPoint(x: lx, y: groundY - 2))
            },
            with: .color(sc), lineWidth: 1.3
        )
    }

    // 显示器
    let monRect = CGRect(x: 174, y: 102, width: 64, height: 54)
    ctx.fill(Path(roundedRect: monRect, cornerRadius: 3), with: .color(Color.black))
    ctx.stroke(Path(roundedRect: monRect, cornerRadius: 3), with: .color(sc), lineWidth: 1.3)

    // 屏幕里的"内容线" — 敲键盘时闪烁
    let onScreen = t >= FilmTimeline.sitEnd && t < FilmTimeline.typeEnd
    let pulse = onScreen ? (sin(t * 6.0) * 0.4 + 0.6) : 0.35
    let screenAccent = phase.accent.opacity(pulse * 0.85)
    var sy: CGFloat = 113
    for width in [40.0, 34.0, 46.0, 28.0] {
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: 180, y: sy))
                p.addLine(to: CGPoint(x: 180 + width, y: sy))
            },
            with: .color(screenAccent), lineWidth: 1.6
        )
        sy += 9
    }
    // 屏幕底座
    ctx.stroke(
        Path { p in
            p.move(to: CGPoint(x: 200, y: 156))
            p.addLine(to: CGPoint(x: 212, y: 156))
            p.addLine(to: CGPoint(x: 212, y: 170))
            p.addLine(to: CGPoint(x: 192, y: 170))
            p.addLine(to: CGPoint(x: 212, y: 170))
        },
        with: .color(sc), lineWidth: 1.2
    )

    // 键盘 (扁矩形)
    let kb = CGRect(x: 158, y: 172, width: 50, height: 4)
    ctx.fill(Path(roundedRect: kb, cornerRadius: 1), with: .color(sc.opacity(0.7)))
    // 按键被按下时高亮一格
    if onScreen {
        let keyIdx = Int(t * 7) % 5
        let key = CGRect(x: 160 + Double(keyIdx) * 9.5, y: 173, width: 8, height: 2.4)
        ctx.fill(Path(roundedRect: key, cornerRadius: 0.6), with: .color(phase.accent))
    }
    // 鼠标 (椭圆)
    let mouseSlide = onScreen ? sin((t - FilmTimeline.sitEnd) * .pi * 2.3) * 3 : 0
    let mouseRect = CGRect(x: 220 + mouseSlide, y: 171, width: 10, height: 6)
    ctx.fill(Path(ellipseIn: mouseRect), with: .color(sc.opacity(0.85)))
    ctx.stroke(Path(ellipseIn: mouseRect), with: .color(sc), lineWidth: 1)

    // 椅子 (椅面 y=220 / 椅背曲线 / 升降柱 / 五星脚 / 滚轮)
    drawChair(ctx: &ctx, centerX: 160, sc: sc)
}

private func drawChair(ctx: inout GraphicsContext, centerX: Double, sc: Color) {
    let seatY: Double = 220
    // 椅面
    let seat = Path { p in
        p.addRoundedRect(in: CGRect(x: centerX - 26, y: seatY, width: 56, height: 4),
                         cornerSize: CGSize(width: 1, height: 1))
    }
    ctx.fill(seat, with: .color(sc.opacity(0.55)))
    ctx.stroke(seat, with: .color(sc), lineWidth: 1)
    // 椅背
    ctx.stroke(
        Path { p in
            p.move(to: CGPoint(x: centerX - 24, y: seatY))
            p.addQuadCurve(to: CGPoint(x: centerX - 30, y: 132),
                           control: CGPoint(x: centerX - 38, y: 180))
        },
        with: .color(sc), lineWidth: 1.5
    )
    // 升降柱
    ctx.stroke(
        Path { p in
            p.move(to: CGPoint(x: centerX + 4, y: seatY + 4))
            p.addLine(to: CGPoint(x: centerX + 4, y: 286))
        },
        with: .color(sc), lineWidth: 1.6
    )
    // 五星脚 (用 3 条腿表意)
    for (ex, ey) in [(-22.0, 308.0), (4.0, 312.0), (28.0, 308.0)] {
        ctx.stroke(
            Path { p in
                p.move(to: CGPoint(x: centerX + 4, y: 286))
                p.addLine(to: CGPoint(x: centerX + ex, y: ey))
            },
            with: .color(sc), lineWidth: 1.3
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: centerX + ex - 2.4, y: ey - 2.4, width: 5, height: 5)),
            with: .color(sc.opacity(0.85))
        )
    }
}

private func drawFar(ctx: inout GraphicsContext, color: Color, base: CGFloat, peak: CGFloat, ground: CGFloat) {
    let path = Path { p in
        p.move(to: CGPoint(x: base, y: ground))
        p.addLine(to: CGPoint(x: base + peak, y: ground - 24))
        p.addLine(to: CGPoint(x: base + peak * 2, y: ground))
        p.closeSubpath()
    }
    ctx.fill(path, with: .color(color))
}

// MARK: - Figure

private func drawFigure(ctx: inout GraphicsContext, pose: Pose, accent: Color, line: Color, mood: FilmMood) {
    var gc = ctx
    let w: CGFloat = 2.6

    // 头 (旋转用 transform)
    let hc = pose.head
    let headRect = CGRect(x: hc.x - 18, y: hc.y - 24, width: 36, height: 48)
    let saved = gc.transform
    if pose.headRot != 0 {
        gc.transform = saved
            .translatedBy(x: hc.x, y: hc.y)
            .rotated(by: Angle.degrees(pose.headRot).radians)
            .translatedBy(x: -hc.x, y: -hc.y)
    }
    let headPath = Path(ellipseIn: headRect)
    gc.fill(headPath, with: .color(.black))
    gc.stroke(headPath, with: .color(line), lineWidth: w)
    gc.transform = saved
    // 耳点
    drawDot(ctx: &gc, at: CGPoint(x: hc.x - 14, y: hc.y + 2), r: 1.8, color: line, filled: true)

    // 表情：眉 + 眼 + 嘴（不会随头旋转；放在 head 旋转外）
    drawFace(ctx: &gc, head: hc, mood: mood, line: line)

    // 颈
    strokeCurve(ctx: &gc, from: pose.head, to: pose.neck,
                control: CGPoint(x: (pose.head.x + pose.neck.x) / 2, y: (pose.head.y + pose.neck.y) / 2),
                color: line, width: w)

    // 肩
    drawDot(ctx: &gc, at: pose.shoulder, r: 4, color: accent, filled: true)

    // 躯干
    strokeLine(ctx: &gc, from: pose.shoulder, to: pose.hip, color: line, width: w + 0.4)
    // 胸前虚线
    strokeCurve(ctx: &gc, from: pose.shoulder,
                to: CGPoint(x: pose.hip.x + 18, y: pose.hip.y),
                control: CGPoint(x: pose.shoulder.x + 22, y: (pose.shoulder.y + pose.hip.y) / 2),
                color: line.opacity(0.5), width: 1.3, dashed: true)

    // 髋点 + 髋骨
    drawDot(ctx: &gc, at: pose.hip, r: 4, color: accent, filled: true)
    let hipL = CGPoint(x: pose.hip.x - 12, y: pose.hip.y)
    let hipR = CGPoint(x: pose.hip.x + 14, y: pose.hip.y)
    strokeLine(ctx: &gc, from: hipL, to: hipR, color: line, width: 1.8)

    // 左臂
    strokeLine(ctx: &gc, from: pose.shoulder, to: pose.lElbow, color: line, width: w)
    drawDot(ctx: &gc, at: pose.lElbow, r: 3, color: accent, filled: true)
    strokeLine(ctx: &gc, from: pose.lElbow, to: pose.lHand, color: line, width: w)
    drawHand(ctx: &gc, at: pose.lHand, color: line)

    // 右臂
    strokeLine(ctx: &gc, from: pose.shoulder, to: pose.rElbow, color: line, width: w)
    drawDot(ctx: &gc, at: pose.rElbow, r: 3, color: accent, filled: true)
    strokeLine(ctx: &gc, from: pose.rElbow, to: pose.rHand, color: line, width: w)
    drawHand(ctx: &gc, at: pose.rHand, color: line)

    // 左腿
    strokeLine(ctx: &gc, from: hipL, to: pose.lKnee, color: line, width: w + 0.4)
    drawDot(ctx: &gc, at: pose.lKnee, r: 4, color: accent, filled: true)
    strokeLine(ctx: &gc, from: pose.lKnee, to: pose.lAnkle, color: line, width: w + 0.4)
    drawFoot(ctx: &gc, at: pose.lAnkle, color: line)

    // 右腿
    strokeLine(ctx: &gc, from: hipR, to: pose.rKnee, color: line, width: w + 0.4)
    drawDot(ctx: &gc, at: pose.rKnee, r: 4, color: accent, filled: true)
    strokeLine(ctx: &gc, from: pose.rKnee, to: pose.rAnkle, color: line, width: w + 0.4)
    drawFoot(ctx: &gc, at: pose.rAnkle, color: line)
}

// MARK: - 脸 (眉 / 眼 / 嘴)

private func drawFace(ctx: inout GraphicsContext, head: CGPoint, mood: FilmMood, line: Color) {
    let cx = head.x
    let cy = head.y
    let eyeY = cy - 5
    let eyeOffset: CGFloat = 4.5
    let mouthY = cy + 9
    let browY = cy - 11

    switch mood {
    case .excited:
        // 眉：短弧上扬
        drawArcBrow(ctx: &ctx, center: CGPoint(x: cx - eyeOffset, y: browY + 1), radius: 4, startDeg: 200, endDeg: 340, color: line, width: 1.6)
        drawArcBrow(ctx: &ctx, center: CGPoint(x: cx + eyeOffset, y: browY + 1), radius: 4, startDeg: 200, endDeg: 340, color: line, width: 1.6)
        // 眼：大圆
        drawDot(ctx: &ctx, at: CGPoint(x: cx - eyeOffset, y: eyeY), r: 1.8, color: line, filled: true)
        drawDot(ctx: &ctx, at: CGPoint(x: cx + eyeOffset, y: eyeY), r: 1.8, color: line, filled: true)
        // 嘴：上扬曲线（笑）
        strokeCurve(ctx: &ctx, from: CGPoint(x: cx - 4, y: mouthY),
                    to: CGPoint(x: cx + 4, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY + 3),
                    color: line, width: 1.6)
    case .focused:
        // 眉：水平短直
        strokeLine(ctx: &ctx, from: CGPoint(x: cx - eyeOffset - 3, y: browY),
                    to: CGPoint(x: cx - eyeOffset + 3, y: browY), color: line, width: 1.6)
        strokeLine(ctx: &ctx, from: CGPoint(x: cx + eyeOffset - 3, y: browY),
                    to: CGPoint(x: cx + eyeOffset + 3, y: browY), color: line, width: 1.6)
        // 眼：实心小点
        drawDot(ctx: &ctx, at: CGPoint(x: cx - eyeOffset, y: eyeY), r: 1.3, color: line, filled: true)
        drawDot(ctx: &ctx, at: CGPoint(x: cx + eyeOffset, y: eyeY), r: 1.3, color: line, filled: true)
        // 嘴：平直
        strokeLine(ctx: &ctx, from: CGPoint(x: cx - 3, y: mouthY),
                    to: CGPoint(x: cx + 3, y: mouthY), color: line, width: 1.6)
    case .tired:
        // 眉：内侧高 / 外侧低（愁容）
        strokeLine(ctx: &ctx, from: CGPoint(x: cx - eyeOffset - 3, y: browY - 1.5),
                    to: CGPoint(x: cx - eyeOffset + 3, y: browY + 1.5), color: line, width: 1.6)
        strokeLine(ctx: &ctx, from: CGPoint(x: cx + eyeOffset - 3, y: browY + 1.5),
                    to: CGPoint(x: cx + eyeOffset + 3, y: browY - 1.5), color: line, width: 1.6)
        // 眼：眯成横线（闭眼疲态）
        strokeLine(ctx: &ctx, from: CGPoint(x: cx - eyeOffset - 2.5, y: eyeY),
                    to: CGPoint(x: cx - eyeOffset + 2.5, y: eyeY), color: line, width: 1.6)
        strokeLine(ctx: &ctx, from: CGPoint(x: cx + eyeOffset - 2.5, y: eyeY),
                    to: CGPoint(x: cx + eyeOffset + 2.5, y: eyeY), color: line, width: 1.6)
        // 嘴：下垂曲线
        strokeCurve(ctx: &ctx, from: CGPoint(x: cx - 4, y: mouthY),
                    to: CGPoint(x: cx + 4, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY - 3),
                    color: line, width: 1.6)
    }
}

/// 画一段圆弧（用于眉毛上扬）
private func drawArcBrow(ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                        startDeg: Double, endDeg: Double, color: Color, width: CGFloat) {
    var p = Path()
    let startRad = startDeg * .pi / 180
    let endRad = endDeg * .pi / 180
    p.addArc(
        center: center,
        radius: radius,
        startAngle: .radians(startRad),
        endAngle: .radians(endRad),
        clockwise: false
    )
    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
}

private func drawHand(ctx: inout GraphicsContext, at p: CGPoint, color: Color) {
    let rect = CGRect(x: p.x - 6, y: p.y - 3, width: 12, height: 6)
    let path = Path(ellipseIn: rect)
    ctx.fill(path, with: .color(.black))
    ctx.stroke(path, with: .color(color), lineWidth: 1.6)
}

private func drawFoot(ctx: inout GraphicsContext, at p: CGPoint, color: Color) {
    let path = Path { pa in
        pa.move(to: CGPoint(x: p.x - 4, y: p.y - 2))
        pa.addLine(to: CGPoint(x: p.x + 16, y: p.y - 2))
        pa.addQuadCurve(to: CGPoint(x: p.x + 18, y: p.y + 4), control: CGPoint(x: p.x + 18, y: p.y - 2))
        pa.addLine(to: CGPoint(x: p.x - 2, y: p.y + 4))
        pa.closeSubpath()
    }
    ctx.fill(path, with: .color(.black))
    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
}

private func strokeLine(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat) {
    var p = Path()
    p.move(to: a)
    p.addLine(to: b)
    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
}

private func strokeCurve(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, control: CGPoint,
                         color: Color, width: CGFloat, dashed: Bool = false) {
    var p = Path()
    p.move(to: a)
    p.addQuadCurve(to: b, control: control)
    let style = StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [3, 4] : [])
    ctx.stroke(p, with: .color(color), style: style)
}

private func drawDot(ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color, filled: Bool = false) {
    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    let path = Path(ellipseIn: rect)
    if filled {
        ctx.fill(path, with: .color(color))
    } else {
        ctx.stroke(path, with: .color(color), lineWidth: 1.4)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MiniFilmView()
            .frame(height: 420)
            .padding()
    }
}

// MARK: - 心跳图标 (脉冲)

private struct HeartPulseIcon: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Color(red: 0.92, green: 0.22, blue: 0.30))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    scale = 1.25
                }
            }
    }
}

// MARK: - 心情曲线 (1 天 0-10s 的心情得分 0-1)

private struct MoodCurveView: View {
    let currentTime: Double
    let duration: Double

    private let n = 30

    private func moodValue(at t: Double) -> Double {
        // 0 = 低落, 1 = 兴奋
        if t < 1.0  { return 0.55 + 0.40 * t }              // 起床：快速上扬到 0.95
        if t < 3.0  { return 0.95 - 0.03 * (t - 1.0) / 2 }  // 通勤：高位小幅
        if t < 4.0  { return 0.92 - 0.10 * (t - 3.0) }      // 坐下：略降到 0.82
        if t < 5.6  { return 0.82 - 0.12 * (t - 4.0) / 1.6 } // 上午工作：缓降到 0.70
        if t < 6.1  { return 0.70 - 0.45 * (t - 5.6) / 0.5 } // 午饭开始：急降到 0.25 (低谷)
        if t < 6.7  { return 0.25 + 0.50 * (t - 6.1) / 0.6 } // 午休结束：急升到 0.75
        if t < 7.5  { return 0.75 - 0.08 * (t - 6.7) }      // 下午工作：缓降到 0.67
        if t < 8.5  { return 0.67 - 0.32 * (t - 7.5) }      // 起身：低谷
        return max(0.18, 0.35 - 0.10 * (t - 8.5) / 1.5)     // 下班：低位
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let points: [CGPoint] = (0..<n).map { i in
                let t = duration * Double(i) / Double(n - 1)
                let v = moodValue(at: t)
                return CGPoint(x: w * CGFloat(i) / CGFloat(n - 1),
                               y: h * (1 - CGFloat(v)))
            }

            ZStack(alignment: .leading) {
                // 渐变填充
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for pt in points { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [Color.black.opacity(0.25), Color.black.opacity(0.04)],
                    startPoint: .top, endPoint: .bottom
                ))

                // 折线
                Path { p in
                    p.move(to: points[0])
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.black.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

                // 当前时间竖线
                let cx = w * CGFloat(min(1, currentTime / duration))
                Path { p in
                    p.move(to: CGPoint(x: cx, y: 0))
                    p.addLine(to: CGPoint(x: cx, y: h))
                }
                .stroke(Color(red: 0.92, green: 0.22, blue: 0.30), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                // 当前点
                let cy = h * (1 - CGFloat(moodValue(at: currentTime)))
                Circle()
                    .fill(Color(red: 0.92, green: 0.22, blue: 0.30))
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .position(x: cx, y: cy)
            }
        }
    }
}

// MARK: - 分享 Sheet 容器

/// 极简：浅色背景 + 顶部状态条 / X / 分享按钮 + 火柴人短片 + 进度条。
/// 状态条随当前播放进度刷新（早上→兴奋 / 下午→疲惫）。
struct MiniFilmShareSheet: View {
    @Binding var isPresented: Bool
    @State private var filmID: UUID = UUID()
    @State private var currentTime: Double = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 浅色背景
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.96, blue: 0.92), Color(red: 0.92, green: 0.92, blue: 0.88)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    statusPill
                    Spacer()
                    shareButton
                    closeButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                // 心率 + 心情曲线
                vitalsRow
                    .padding(.horizontal, 18)
                    .padding(.top, 6)

                Spacer(minLength: 0)

                MiniFilmView { currentTime = $0 }
                    .id(filmID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 18)
                    .onTapGesture { filmID = UUID() }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 心率 + 心情曲线

    private var vitalsRow: some View {
        HStack(spacing: 12) {
            heartRateView
            moodCurveView
        }
    }

    private var heartRateView: some View {
        HStack(spacing: 5) {
            HeartPulseIcon()
            VStack(alignment: .leading, spacing: 0) {
                Text("\(currentHeartRate)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.black)
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.black.opacity(0.05))
        )
        .overlay(
            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: currentHeartRate)
    }

    private var currentHeartRate: Int {
        let m = FilmTimeline.mood(at: currentTime)
        let base: Double
        switch m {
        case .excited: base = 92
        case .focused: base = 78
        case .tired:   base = 64
        }
        // 起床 / 起身段心率额外 +6
        let isTransition = currentTime < 1.0 || (currentTime > 7.5 && currentTime < 8.5)
        return Int(base + (isTransition ? 6 : 0))
    }

    private var moodCurveView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今日心情")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.black.opacity(0.45))
            MoodCurveView(currentTime: currentTime, duration: 10)
                .frame(height: 28)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// 左上状态条：时段 + 身体状态 + 心情（随 currentTime 变）
    private var statusPill: some View {
        let mood = FilmTimeline.mood(at: currentTime)
        let periodText = "\(mood.period)"
        let stateText = mood.bodyState
        let moodText = mood.moodWord
        let dotColor: Color = {
            switch mood {
            case .excited: return Color(red: 0.96, green: 0.62, blue: 0.10)
            case .focused: return Color(red: 0.20, green: 0.78, blue: 0.55)
            case .tired:   return Color(red: 0.42, green: 0.50, blue: 0.78)
            }
        }()
        return HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor, radius: 3)
            Text(periodText)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.black.opacity(0.85))
            Text("·")
                .foregroundColor(.black.opacity(0.3))
            Text(stateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.55))
            Text("·")
                .foregroundColor(.black.opacity(0.3))
            Text(moodText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.black.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.05))
        )
        .overlay(
            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.3), value: mood)
    }

    private var closeButton: some View {
        Button {
            isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var shareButton: some View {
        Button {
            shareFilm()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.black.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func shareFilm() {
        let mood = FilmTimeline.mood(at: currentTime)
        let text = """
        我的一天 · 10 秒
        \(mood.period) · \(mood.bodyState) · \(mood.moodWord)
        起床 → 走到办公桌 → 敲键盘 → 下班回家
        今日：工作 8h00m · 休息 9h00m · 活动 7h00m
        — 用 Stick 记录
        """
        let act = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            var top: UIViewController = root
            while let presented = top.presentedViewController { top = presented }
            top.present(act, animated: true)
        }
    }
}
