import SwiftUI

/// 火柴人心情/姿态覆盖层。在基础状态之上叠加"有活力"等情绪效果。
///   - .normal   默认，无额外装饰
///   - .excited  兴奋（微笑 + 闪光 + ♪ + 更欢的颠步），用于"上午通勤 / 状态好"
enum StickFigureMood: Hashable {
    case normal
    case excited
}

/// 火柴人主页的核心视图。
/// 3 状态（走/坐/睡）侧视线框火柴人，参考 ATLAS 项目风格：
///  - 关节处小圆点
///  - 头/手/脚为椭圆
///  - 胸前轮廓用虚线
///  - 道具（地面、椅子、床）用细实线
///
/// 坐标系固定 240×320，调用方决定实际尺寸，Canvas 内自动等比缩放。
struct StickFigureView: View {
    let state: StickState
    var mood: StickFigureMood = .normal             // 心情覆盖：.excited = 兴奋 UI
    var lineColor: Color = Theme.figureStroke       // navy
    var fillColor: Color = Theme.figureFill          // 米白
    var jointColor: Color? = nil                    // nil = 用 state.accent
    var accentColor: Color? = nil                   // 道具/标注的强调色
    var lineWidth: CGFloat = 2.6
    var showScene: Bool = true                      // 地面/椅子/床等环境元素

    var body: some View {
        // SwiftUI 内置 TimelineView 提供时间信号，驱动状态专属动效
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
            Canvas { context, size in
                let joint = jointColor ?? state.accent
                let accent = accentColor ?? state.accent
                let t = tl.date.timeIntervalSinceReferenceDate

                // 等比缩放 + 居中到 240×320 画布
                let scale = min(size.width / 240, size.height / 320)
                let tx = (size.width - 240 * scale) / 2
                let ty = (size.height - 320 * scale) / 2

                var ctx = context
                ctx.translateBy(x: tx, y: ty)
                ctx.scaleBy(x: scale, y: scale)

                drawScene(ctx: &ctx, state: state, accent: accent, t: t, show: showScene)
                drawFigure(ctx: &ctx, state: state, mood: mood, stroke: lineColor, fill: fillColor, joint: joint, w: lineWidth, t: t)
            }
            .drawingGroup()  // 离屏渲染保持线条锐利
        }
        .animation(.easeInOut(duration: 0.45), value: state)
    }
}

// MARK: - 场景元素（地面/椅子/床）

private func drawScene(ctx: inout GraphicsContext, state: StickState, accent: Color, t: Double, show: Bool) {
    guard show else { return }
    let ground: CGFloat = 322

    switch state {
    case .walk:
        // 地面
        strokeLine(ctx: &ctx, from: CGPoint(x: 10, y: ground), to: CGPoint(x: 230, y: ground),
                   color: accent.opacity(0.45), width: 1.2)
        // 脚步"运动线" — 1.5s 循环：从左向右漂移 + 淡入淡出
        let speedCycle = 1.5
        for i in 0..<3 {
            let phase = ((t + Double(i) * 0.5).truncatingRemainder(dividingBy: speedCycle)) / speedCycle
            let xOffset = CGFloat(phase) * 36 - 18
            let alpha = (1 - abs(CGFloat(phase) - 0.5) * 2) * 0.55
            let yPos = CGFloat(290 + i * 10)
            let len: CGFloat = 18
            strokeLine(ctx: &ctx, from: CGPoint(x: 200 + xOffset, y: yPos),
                       to: CGPoint(x: 200 + xOffset + len, y: yPos),
                       color: accent.opacity(max(0, alpha)), width: 1, dashed: true)
        }
        // 远景小三角（暗示户外）
        let far = Path { p in
            p.move(to: CGPoint(x: 20, y: ground))
            p.addLine(to: CGPoint(x: 38, y: 295))
            p.addLine(to: CGPoint(x: 56, y: ground))
            p.closeSubpath()
        }
        ctx.fill(far, with: .color(accent.opacity(0.18)))
        let far2 = Path { p in
            p.move(to: CGPoint(x: 188, y: ground))
            p.addLine(to: CGPoint(x: 210, y: 290))
            p.addLine(to: CGPoint(x: 230, y: ground))
            p.closeSubpath()
        }
        ctx.fill(far2, with: .color(accent.opacity(0.12)))

    case .sit:
        // 椅子：座面 + 椅背 + 升降柱 + 五星脚
        let seatY: CGFloat = 218
        // 座面（厚度）
        let seat = Path { p in
            p.move(to: CGPoint(x: 60, y: seatY))
            p.addLine(to: CGPoint(x: 195, y: seatY))
            p.addLine(to: CGPoint(x: 195, y: seatY + 5))
            p.addLine(to: CGPoint(x: 60, y: seatY + 5))
            p.closeSubpath()
        }
        ctx.stroke(seat, with: .color(accent.opacity(0.55)), lineWidth: 1.5)
        // 椅背（曲线）
        let back = Path { p in
            p.move(to: CGPoint(x: 62, y: seatY))
            p.addQuadCurve(to: CGPoint(x: 58, y: 130), control: CGPoint(x: 52, y: 175))
        }
        ctx.stroke(back, with: .color(accent.opacity(0.55)), lineWidth: 1.5)
        // 升降柱
        strokeLine(ctx: &ctx, from: CGPoint(x: 128, y: seatY + 5), to: CGPoint(x: 128, y: 282),
                   color: accent.opacity(0.55), width: 1.5)
        // 五星脚
        strokeLine(ctx: &ctx, from: CGPoint(x: 128, y: 282), to: CGPoint(x: 80, y: 300),
                   color: accent.opacity(0.55), width: 1.5)
        strokeLine(ctx: &ctx, from: CGPoint(x: 128, y: 282), to: CGPoint(x: 176, y: 300),
                   color: accent.opacity(0.55), width: 1.5)
        strokeLine(ctx: &ctx, from: CGPoint(x: 128, y: 282), to: CGPoint(x: 110, y: 312),
                   color: accent.opacity(0.55), width: 1.5)
        strokeLine(ctx: &ctx, from: CGPoint(x: 128, y: 282), to: CGPoint(x: 146, y: 312),
                   color: accent.opacity(0.55), width: 1.5)
        // 滚轮
        drawDot(ctx: &ctx, at: CGPoint(x: 80, y: 302), r: 3, color: accent.opacity(0.7))
        drawDot(ctx: &ctx, at: CGPoint(x: 176, y: 302), r: 3, color: accent.opacity(0.7))
        drawDot(ctx: &ctx, at: CGPoint(x: 110, y: 314), r: 2.5, color: accent.opacity(0.7))
        drawDot(ctx: &ctx, at: CGPoint(x: 146, y: 314), r: 2.5, color: accent.opacity(0.7))
        // 地面
        strokeLine(ctx: &ctx, from: CGPoint(x: 10, y: ground), to: CGPoint(x: 230, y: ground),
                   color: accent.opacity(0.45), width: 1.2)
        // 显示器（远景，提示工位）
        let screen = CGRect(x: 165, y: 130, width: 50, height: 32)
        ctx.stroke(Path(roundedRect: screen, cornerRadius: 2),
                   with: .color(accent.opacity(0.5)), lineWidth: 1.2)
        let screenBase = Path { p in
            p.move(to: CGPoint(x: 175, y: 162))
            p.addLine(to: CGPoint(x: 205, y: 162))
            p.move(to: CGPoint(x: 190, y: 162))
            p.addLine(to: CGPoint(x: 190, y: 170))
            p.addLine(to: CGPoint(x: 175, y: 170))
        }
        ctx.stroke(screenBase, with: .color(accent.opacity(0.5)), lineWidth: 1.2)

    case .sleep:
        // 床垫顶
        let mattress = CGRect(x: 8, y: 250, width: 224, height: 18)
        ctx.fill(Path(roundedRect: mattress, cornerRadius: 3), with: .color(accent.opacity(0.35)))
        ctx.stroke(Path(roundedRect: mattress, cornerRadius: 3),
                   with: .color(accent.opacity(0.7)), lineWidth: 1.3)
        // 床框
        let frame = CGRect(x: 4, y: 268, width: 232, height: 14)
        ctx.fill(Path { p in p.addRect(frame) }, with: .color(accent.opacity(0.55)))
        // 床腿
        strokeLine(ctx: &ctx, from: CGPoint(x: 16, y: 282), to: CGPoint(x: 16, y: 312),
                   color: accent.opacity(0.6), width: 2)
        strokeLine(ctx: &ctx, from: CGPoint(x: 224, y: 282), to: CGPoint(x: 224, y: 312),
                   color: accent.opacity(0.6), width: 2)
        // 地面
        strokeLine(ctx: &ctx, from: CGPoint(x: 0, y: 318), to: CGPoint(x: 240, y: 318),
                   color: accent.opacity(0.45), width: 1.2)
        // 枕头
        let pillow = Path { p in
            p.move(to: CGPoint(x: 12, y: 215))
            p.addQuadCurve(to: CGPoint(x: 70, y: 215), control: CGPoint(x: 12, y: 180))
            p.addQuadCurve(to: CGPoint(x: 75, y: 250), control: CGPoint(x: 80, y: 220))
            p.addLine(to: CGPoint(x: 14, y: 250))
            p.closeSubpath()
        }
        ctx.fill(pillow, with: .color(accent.opacity(0.5)))
        ctx.stroke(pillow, with: .color(accent.opacity(0.85)), lineWidth: 1.3)
        // 月光（呼吸式弱脉冲 0.95→1.0 半径）
        let moonPulse = 1.0 + sin(t * 1.5) * 0.04
        let moon = CGRect(x: 175, y: 50, width: 36 * moonPulse, height: 36 * moonPulse)
        ctx.fill(Path(ellipseIn: moon), with: .color(accent.opacity(0.18)))

        // 飘动的 Z：3 个错相，3.0s 一个生命期
        //   - 起点（头右上 80,170）→ 终点（180,30）
        //   - 正弦横摆（呼吸同步的风感）
        //   - 缓入缓出 alpha
        //   - 渐大 scale
        let zPeriod = 3.0
        let zCount = 3
        let baseSizes: [CGFloat] = [14, 19, 24]
        for i in 0..<zCount {
            let localT = t - Double(i) * 1.0
            let raw = localT.truncatingRemainder(dividingBy: zPeriod * 2) / zPeriod
            let p = max(0, min(1, raw))
            if p < 0.05 || p > 0.95 { continue }
            // 0..0.15 淡入；0.15..0.75 满；0.75..1.0 淡出
            let alpha: CGFloat
            if p < 0.15 { alpha = p / 0.15 * 0.92 }
            else if p > 0.75 { alpha = (1 - p) / 0.25 * 0.92 }
            else { alpha = 0.92 }
            let scale = 0.55 + p * 0.55
            let wobble = CGFloat(sin(t * 2.0 + Double(i) * 1.3) * 4) * p
            let xPos: CGFloat = 80 + (180 - 80) * p + wobble
            let yPos: CGFloat = 170 + (30 - 170) * p
            let size = baseSizes[i] * scale
            let zPoint = CGPoint(x: xPos, y: yPos)
            let saved = ctx.transform
            ctx.transform = saved
                .translatedBy(x: zPoint.x, y: zPoint.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -zPoint.x, y: -zPoint.y)
            drawZ(ctx: &ctx, at: zPoint, size: size, color: accent.opacity(alpha))
            ctx.transform = saved
        }
    }
}

// MARK: - 走

private func drawWalk(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double, mood: StickFigureMood = .normal) {
    let isExcited = mood == .excited

    // 步态相位：~0.7 Hz 一周期
    let phase = t * 4.5
    let armSwing: CGFloat = CGFloat(sin(phase) * (isExcited ? 0.36 : 0.30))        // 兴奋时摆臂更大
    let legSwing: CGFloat = CGFloat(sin(phase + .pi) * (isExcited ? 0.28 : 0.24)) // 腿与臂反相
    let bobAmp: CGFloat = isExcited ? 2.8 : 2.0                                    // 兴奋时颠得更欢
    let bob: CGFloat = CGFloat(abs(sin(phase * 2)) * Double(bobAmp))               // 上下颠 0~bobAmp px
    let rFootLift: CGFloat = CGFloat(max(0, sin(phase + .pi / 2)) * 4)  // 右脚抬起

    // 整体上抬
    let savedTop = ctx.transform
    ctx.transform = savedTop.translatedBy(x: 0, y: -bob)

    // 头（前倾 8°，椭圆）
    let headCenter = CGPoint(x: 115, y: 75)
    let head = CGRect(x: headCenter.x - 24, y: headCenter.y - 30, width: 48, height: 60)
    let saved = ctx.transform
    ctx.transform = saved
        .translatedBy(x: headCenter.x, y: headCenter.y)
        .rotated(by: Angle.degrees(8).radians)
        .translatedBy(x: -headCenter.x, y: -headCenter.y)
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w)
    ctx.transform = saved
    drawDot(ctx: &ctx, at: CGPoint(x: 100, y: 78), r: 2, color: stroke)
    if isExcited {
        // 微笑：眼下一条小弧线
        strokeCurve(ctx: &ctx,
                    from: CGPoint(x: 100, y: 91),
                    to: CGPoint(x: 114, y: 91),
                    control: CGPoint(x: 107, y: 96),
                    color: stroke, width: 1.4)
    }

    // 颈椎
    strokeCurve(ctx: &ctx, from: CGPoint(x: 113, y: 105), to: CGPoint(x: 111, y: 128),
                control: CGPoint(x: 111, y: 116), color: stroke, width: w)

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 111, y: 130), r: 4, color: joint, filled: true)
    let shoulder: CGPoint = CGPoint(x: 111, y: 130)

    // 躯干
    strokeLine(ctx: &ctx, from: shoulder, to: CGPoint(x: 108, y: 238),
               color: stroke, width: w + 0.4)
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 128, y: 238),
                control: CGPoint(x: 130, y: 180),
                color: stroke.opacity(0.55), width: 1.4, dashed: true)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 108, y: 240), r: 4, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: CGPoint(x: 95, y: 240), to: CGPoint(x: 122, y: 240),
               color: stroke, width: 1.8)

    // 右臂（绕肩旋转摆动）
    let rBase = ctx.transform
    ctx.transform = rBase
        .translatedBy(x: shoulder.x, y: shoulder.y)
        .rotated(by: -armSwing)
        .translatedBy(x: -shoulder.x, y: -shoulder.y)
    let rElbow = CGPoint(x: 152, y: 170)
    let rHand  = CGPoint(x: 172, y: 218)
    strokeLine(ctx: &ctx, from: shoulder, to: rElbow, color: stroke, width: w)
    drawDot(ctx: &ctx, at: rElbow, r: 3, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: rElbow, to: rHand, color: stroke, width: w)
    drawEllipse(ctx: &ctx, rect: CGRect(x: rHand.x - 8, y: rHand.y - 4, width: 16, height: 8),
                fill: fill, stroke: stroke, width: 1.8)
    ctx.transform = rBase

    // 左臂（反相摆动）
    let lBase = ctx.transform
    ctx.transform = lBase
        .translatedBy(x: shoulder.x, y: shoulder.y)
        .rotated(by: +armSwing)
        .translatedBy(x: -shoulder.x, y: -shoulder.y)
    let lElbow = CGPoint(x: 76, y: 168)
    let lHand  = CGPoint(x: 60, y: 205)
    strokeLine(ctx: &ctx, from: shoulder, to: lElbow, color: stroke, width: w)
    drawDot(ctx: &ctx, at: lElbow, r: 3, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: lElbow, to: lHand, color: stroke, width: w)
    drawEllipse(ctx: &ctx, rect: CGRect(x: lHand.x - 7, y: lHand.y - 3, width: 14, height: 7),
                fill: fill, stroke: stroke, width: 1.8)
    ctx.transform = lBase

    // 右腿（绕髋旋转 + 抬起）
    let rHipPivot = CGPoint(x: 122, y: 240)
    let rBase2 = ctx.transform
    ctx.transform = rBase2
        .translatedBy(x: rHipPivot.x, y: rHipPivot.y)
        .rotated(by: +legSwing)
        .translatedBy(x: -rHipPivot.x, y: -rHipPivot.y)
    let rKnee   = CGPoint(x: 158, y: 275 - rFootLift)
    let rAnkle  = CGPoint(x: 168, y: 310 - rFootLift)
    strokeLine(ctx: &ctx, from: rHipPivot, to: rKnee, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: rKnee, r: 4, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: rKnee, to: rAnkle, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: rAnkle, r: 3.5, color: joint, filled: true)
    let rFoot = Path { p in
        p.move(to: CGPoint(x: 168, y: 312 - rFootLift))
        p.addLine(to: CGPoint(x: 198, y: 312 - rFootLift))
        p.addQuadCurve(to: CGPoint(x: 200, y: 320 - rFootLift), control: CGPoint(x: 200, y: 312 - rFootLift))
        p.addLine(to: CGPoint(x: 170, y: 320 - rFootLift))
        p.closeSubpath()
    }
    ctx.stroke(rFoot, with: .color(stroke), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(rFoot, with: .color(fill))
    ctx.transform = rBase2

    // 左腿（反相）
    let lHipPivot = CGPoint(x: 95, y: 240)
    let lBase2 = ctx.transform
    ctx.transform = lBase2
        .translatedBy(x: lHipPivot.x, y: lHipPivot.y)
        .rotated(by: -legSwing)
        .translatedBy(x: -lHipPivot.x, y: -lHipPivot.y)
    let lKnee   = CGPoint(x: 78, y: 285)
    let lAnkle  = CGPoint(x: 80, y: 320)
    strokeLine(ctx: &ctx, from: lHipPivot, to: lKnee, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: lKnee, r: 4, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: lKnee, to: lAnkle, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: lAnkle, r: 3.5, color: joint, filled: true)
    let lFoot = Path { p in
        p.move(to: CGPoint(x: 80, y: 322))
        p.addLine(to: CGPoint(x: 110, y: 322))
        p.addQuadCurve(to: CGPoint(x: 112, y: 318), control: CGPoint(x: 110, y: 322))
        p.addLine(to: CGPoint(x: 82, y: 318))
        p.closeSubpath()
    }
    ctx.stroke(lFoot, with: .color(stroke), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(lFoot, with: .color(fill))
    ctx.transform = lBase2

    // 兴奋装饰：4 个十字闪光（与身体一起轻微颠簸，更贴合"身上"）
    if isExcited {
        drawExcitedSparkles(ctx: &ctx, color: joint, t: t)
    }

    // 还原整体平移
    ctx.transform = savedTop

    // 兴奋装饰：飘动的 ♪ 音符（独立于身体颠簸，"附近"飘升）
    if isExcited {
        drawExcitedNote(ctx: &ctx, color: joint, t: t)
    }
}

// MARK: - 坐

private func drawSit(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double) {
    // 头（前倾 20°，含颌）
    let headCenter = CGPoint(x: 108, y: 75)
    let head = CGRect(x: headCenter.x - 24, y: headCenter.y - 30, width: 48, height: 60)
    let saved = ctx.transform
    ctx.transform = saved
        .translatedBy(x: headCenter.x, y: headCenter.y)
        .rotated(by: Angle.degrees(20).radians)
        .translatedBy(x: -headCenter.x, y: -headCenter.y)
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w)
    ctx.transform = saved
    drawDot(ctx: &ctx, at: CGPoint(x: 92, y: 80), r: 2, color: stroke)

    // 颈椎（明显前倾）
    strokeCurve(ctx: &ctx, from: CGPoint(x: 105, y: 105), to: CGPoint(x: 100, y: 128),
                control: CGPoint(x: 100, y: 118), color: stroke, width: w + 0.4)

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 100, y: 130), r: 4, color: joint, filled: true)
    let shoulder: CGPoint = CGPoint(x: 100, y: 130)

    // 躯干（靠椅背但腰部略离）
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 96, y: 222),
                control: CGPoint(x: 78, y: 175), color: stroke, width: w + 0.4)
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 116, y: 222),
                control: CGPoint(x: 118, y: 175),
                color: stroke.opacity(0.55), width: 1.4, dashed: true)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 96, y: 224), r: 4, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: CGPoint(x: 84, y: 224), to: CGPoint(x: 110, y: 224),
               color: stroke, width: 1.8)

    // 右臂（伸向键盘，敲击时手腕上下颤动）
    let rElbow = CGPoint(x: 140, y: 175)
    let rHand  = CGPoint(x: 175, y: 200)
    strokeLine(ctx: &ctx, from: shoulder, to: rElbow, color: stroke, width: w)
    drawDot(ctx: &ctx, at: rElbow, r: 3, color: joint, filled: true)
    // 敲击节奏：~3 Hz 主拍 + 快速抖动叠加
    let tapPhase = t * 8.0
    let tapBump: CGFloat = CGFloat(max(0, sin(tapPhase)) * pow(sin(tapPhase * 0.5) * 0.5 + 0.5, 2) * 3.5)
    let rBase = ctx.transform
    ctx.transform = rBase
        .translatedBy(x: rElbow.x, y: rElbow.y)
        .rotated(by: CGFloat(sin(tapPhase) * 0.08))
        .translatedBy(x: -rElbow.x, y: -rElbow.y)
    strokeLine(ctx: &ctx, from: rElbow, to: CGPoint(x: rHand.x, y: rHand.y + tapBump), color: stroke, width: w)
    drawEllipse(ctx: &ctx, rect: CGRect(x: rHand.x - 9, y: rHand.y - 3 + tapBump, width: 18, height: 7),
                fill: fill, stroke: stroke, width: 1.8)
    ctx.transform = rBase

    // 左臂（垂在身侧）
    let lElbow = CGPoint(x: 92, y: 195)
    let lHand  = CGPoint(x: 90, y: 230)
    strokeLine(ctx: &ctx, from: shoulder, to: lElbow, color: stroke, width: w)
    drawDot(ctx: &ctx, at: lElbow, r: 3, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: lElbow, to: lHand, color: stroke, width: w)
    drawEllipse(ctx: &ctx, rect: CGRect(x: lHand.x - 5, y: lHand.y - 3, width: 10, height: 6),
                fill: fill, stroke: stroke, width: 1.8)

    // 大腿（水平）
    let rHip   = CGPoint(x: 110, y: 224)
    let rKnee  = CGPoint(x: 185, y: 222)
    strokeLine(ctx: &ctx, from: rHip, to: rKnee, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: rKnee, r: 4, color: joint, filled: true)

    // 小腿（垂直）
    let rAnkle = CGPoint(x: 185, y: 295)
    strokeLine(ctx: &ctx, from: rKnee, to: rAnkle, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: rAnkle, r: 3.5, color: joint, filled: true)

    // 脚
    let foot = Path { p in
        p.move(to: CGPoint(x: 180, y: 297))
        p.addLine(to: CGPoint(x: 202, y: 297))
        p.addQuadCurve(to: CGPoint(x: 205, y: 305), control: CGPoint(x: 204, y: 297))
        p.addLine(to: CGPoint(x: 178, y: 305))
        p.closeSubpath()
    }
    ctx.stroke(foot, with: .color(stroke), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(foot, with: .color(fill))
}

// MARK: - 睡

private func drawSleep(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double) {
    // 呼吸：3.2s 周期，0.4 吸气 + 0.6 呼气（自然节奏），smoothstep 缓动
    //  - 整体上下 0~1.6px
    //  - 横向轻微 sway（睡中微动）
    //  - 整体 Y 微缩放（胸腔起伏感）
    let breathPeriod: Double = 3.2
    let p = t.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
    let eased: Double
    if p < 0.4 {
        let u = p / 0.4
        eased = u * u * (3 - 2 * u)        // smoothstep 0→1
    } else {
        let u = (p - 0.4) / 0.6
        eased = 1 - (u * u * (3 - 2 * u))  // smoothstep 1→0
    }
    let breath: CGFloat = CGFloat(eased) * 1.6
    let breathSway: CGFloat = CGFloat(sin(t * 0.6) * 0.5)
    let breathScale: CGFloat = 1 + CGFloat(eased) * 0.012

    let savedTop = ctx.transform
    // 整体平移 + 缩放（绕中心）
    ctx.transform = savedTop
        .translatedBy(x: 120, y: 200)
        .scaledBy(x: 1, y: breathScale)
        .translatedBy(x: -120, y: -200)
        .translatedBy(x: breathSway, y: -breath)

    // 头（侧放枕上，朝右）
    let head = CGRect(x: 22, y: 178, width: 50, height: 40)
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w)
    // 闭眼线
    strokeLine(ctx: &ctx, from: CGPoint(x: 52, y: 192), to: CGPoint(x: 62, y: 192),
               color: stroke, width: 1.4)
    // 嘴角
    strokeLine(ctx: &ctx, from: CGPoint(x: 64, y: 207), to: CGPoint(x: 70, y: 207),
               color: stroke.opacity(0.6), width: 1.2)

    // 颈
    strokeLine(ctx: &ctx, from: CGPoint(x: 72, y: 200), to: CGPoint(x: 92, y: 210),
               color: stroke, width: w)

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 92, y: 212), r: 4, color: joint, filled: true)
    let shoulder: CGPoint = CGPoint(x: 92, y: 212)

    // 躯干（水平）
    strokeLine(ctx: &ctx, from: shoulder, to: CGPoint(x: 215, y: 220),
               color: stroke, width: w + 0.4)
    // 胸前轮廓
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 215, y: 215),
                control: CGPoint(x: 150, y: 205),
                color: stroke.opacity(0.55), width: 1.4, dashed: true)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 215, y: 222), r: 4, color: joint, filled: true)

    // 上臂（屈，置胸前）
    let fElbow = CGPoint(x: 122, y: 232)
    let fHand  = CGPoint(x: 148, y: 230)
    strokeLine(ctx: &ctx, from: shoulder, to: fElbow, color: stroke, width: w)
    drawDot(ctx: &ctx, at: fElbow, r: 3, color: joint, filled: true)
    strokeLine(ctx: &ctx, from: fElbow, to: fHand, color: stroke, width: w)
    drawEllipse(ctx: &ctx, rect: CGRect(x: fHand.x - 6, y: fHand.y - 3, width: 12, height: 6),
                fill: fill, stroke: stroke, width: 1.8)

    // 下臂（垫头下）
    let bElbow = CGPoint(x: 72, y: 234)
    let bHand  = CGPoint(x: 52, y: 222)
    strokeLine(ctx: &ctx, from: shoulder, to: bElbow, color: stroke.opacity(0.7), width: w * 0.85)
    strokeLine(ctx: &ctx, from: bElbow, to: bHand, color: stroke.opacity(0.7), width: w * 0.85)
    drawDot(ctx: &ctx, at: bElbow, r: 2.5, color: joint.opacity(0.7), filled: true)

    // 大腿
    let knee = CGPoint(x: 240, y: 226)
    strokeLine(ctx: &ctx, from: CGPoint(x: 215, y: 222), to: knee, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: knee, r: 4, color: joint, filled: true)
    // 小腿（略屈）
    let ankle = CGPoint(x: 240, y: 248)
    strokeLine(ctx: &ctx, from: knee, to: ankle, color: stroke, width: w + 0.4)
    drawDot(ctx: &ctx, at: ankle, r: 3.5, color: joint, filled: true)
    // 脚
    let foot = Path { p in
        p.move(to: CGPoint(x: 232, y: 240))
        p.addLine(to: CGPoint(x: 252, y: 240))
        p.addQuadCurve(to: CGPoint(x: 256, y: 250), control: CGPoint(x: 254, y: 240))
        p.addLine(to: CGPoint(x: 234, y: 250))
        p.closeSubpath()
    }
    ctx.stroke(foot, with: .color(stroke), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(foot, with: .color(.black))

    // 还原
    ctx.transform = savedTop
}

// MARK: - 路由

private func drawFigure(ctx: inout GraphicsContext, state: StickState, mood: StickFigureMood, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double) {
    switch state {
    case .walk:  drawWalk(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t, mood: mood)
    case .sit:   drawSit(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t)
    case .sleep: drawSleep(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t)
    }
}

// MARK: - 基本图元

private func strokeLine(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                        color: Color, width: CGFloat, dashed: Bool = false) {
    var p = Path()
    p.move(to: a)
    p.addLine(to: b)
    let style = StrokeStyle(lineWidth: width, lineCap: .round,
                            dash: dashed ? [3, 4] : [])
    ctx.stroke(p, with: .color(color), style: style)
}

private func strokeCurve(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, control: CGPoint,
                         color: Color, width: CGFloat, dashed: Bool = false) {
    var p = Path()
    p.move(to: a)
    p.addQuadCurve(to: b, control: control)
    let style = StrokeStyle(lineWidth: width, lineCap: .round,
                            dash: dashed ? [3, 4] : [])
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

private func drawEllipse(ctx: inout GraphicsContext, rect: CGRect, fill: Color, stroke: Color, width: CGFloat) {
    let p = Path(ellipseIn: rect)
    ctx.fill(p, with: .color(fill))
    ctx.stroke(p, with: .color(stroke), lineWidth: width)
}

private func drawZ(ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
    let t = Text("Z")
        .font(.system(size: size, weight: .heavy, design: .serif))
        .foregroundColor(color)
    ctx.draw(t, at: p, anchor: .center)
}

// MARK: - 兴奋装饰：闪光（身上）

/// 4 个十字形闪光包围火柴人。三角波 0→1→0 驱动 size/alpha，错相 0.4s。
private func drawExcitedSparkles(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 1.6
    let positions: [CGPoint] = [
        CGPoint(x: 55,  y: 72),    // 左上（头顶左上）
        CGPoint(x: 188, y: 58),    // 右上（头顶右上）
        CGPoint(x: 215, y: 175),   // 右中（手臂外）
        CGPoint(x: 35,  y: 205)    // 左中（手臂外）
    ]
    for i in 0..<positions.count {
        let p = positions[i]
        let phase = ((t + Double(i) * 0.4).truncatingRemainder(dividingBy: period)) / period
        // 三角波：0→1→0 over [0, 1)
        let wave = CGFloat(1.0 - abs(phase * 2.0 - 1.0))
        let size: CGFloat = 2.5 + 3.5 * wave   // 2.5..6
        let alpha: CGFloat = 0.45 + 0.55 * wave
        // 十字（竖 + 横）+ 中心小亮点
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: p.x, y: p.y - size),
                   to: CGPoint(x: p.x, y: p.y + size),
                   color: color.opacity(alpha), width: 1.3)
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: p.x - size, y: p.y),
                   to: CGPoint(x: p.x + size, y: p.y),
                   color: color.opacity(alpha), width: 1.3)
        drawDot(ctx: &ctx, at: p, r: 1.2, color: color.opacity(alpha), filled: true)
    }
}

// MARK: - 兴奋装饰：♪ 音符（附近）

/// 单个 ♪ 音符从右中飘到右上方，4s 一周期，含淡入/淡出 + 横向 sin 摇摆。
private func drawExcitedNote(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 4.0
    let p = t.truncatingRemainder(dividingBy: period) / period
    let alpha: CGFloat
    if p < 0.12 { alpha = p / 0.12 }
    else if p > 0.88 { alpha = (1 - p) / 0.12 }
    else { alpha = 1.0 }
    let prog = CGFloat(p)
    let wobble = CGFloat(sin(t * 1.8) * 3) * prog
    let xStart: CGFloat = 195, xEnd: CGFloat = 218
    let yStart: CGFloat = 130, yEnd: CGFloat = 30
    let x = xStart + (xEnd - xStart) * prog + wobble
    let y = yStart + (yEnd - yStart) * prog
    drawNote(ctx: &ctx, at: CGPoint(x: x, y: y), size: 18, color: color.opacity(alpha))
}

private func drawNote(ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
    let t = Text("♪")
        .font(.system(size: size, weight: .bold, design: .serif))
        .foregroundColor(color)
    ctx.draw(t, at: p, anchor: .center)
}
