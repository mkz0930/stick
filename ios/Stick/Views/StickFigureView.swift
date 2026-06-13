import SwiftUI

/// 火柴人心情/姿态覆盖层。在基础状态之上叠加"有活力"等情绪效果。
///   - .normal   默认，无额外装饰
///   - .excited  兴奋（闪光 + ♪ + 更欢的颠步），用于"上午通勤 / 状态好"
///   - .calm     平稳（慢呼吸光环 + 缓升小点），用于"上午工作 / 专注"
enum StickFigureMood: Hashable {
    case normal
    case excited
    case calm
    case tired
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
    var confidence: Double = 1.0   // 0–1, 越低越虚
    var tiredness: Double = 0.0    // 0–1, 越高越累（仅 .tired 用：头部下俯 + 浮 Z + 汗滴）
    var neckWarning: Double = 0.0  // 0–1, 越高颈线越粗越红（提醒"颈椎压力过大"）

    var body: some View {
        // SwiftUI 内置 TimelineView 提供时间信号，驱动状态专属动效
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
            Canvas { context, size in
                let joint = jointColor ?? state.accent
                let accent = accentColor ?? state.accent
                let t = tl.date.timeIntervalSinceReferenceDate

                // 置信度派生：低置信度 → 线条更虚、更细
                let lineAlpha = 0.55 + 0.45 * CGFloat(confidence)  // 0.55–1.0
                let jointAlpha = 0.6 + 0.4 * CGFloat(confidence)
                let widthScale = 0.7 + 0.3 * CGFloat(confidence)    // 0.7–1.0

                // 等比缩放 + 居中到 240×320 画布
                let scale = min(size.width / 240, size.height / 320)
                let tx = (size.width - 240 * scale) / 2
                let ty = (size.height - 320 * scale) / 2

                var ctx = context
                ctx.translateBy(x: tx, y: ty)
                ctx.scaleBy(x: scale, y: scale)

                drawScene(ctx: &ctx, state: state, accent: accent, t: t, show: showScene)
                drawFigure(ctx: &ctx, state: state, mood: mood, tiredness: tiredness, neckWarning: neckWarning, stroke: lineColor, fill: fillColor, joint: joint, w: lineWidth * widthScale, t: t, lineAlpha: lineAlpha, jointAlpha: jointAlpha)
            }
            .drawingGroup()  // 离屏渲染保持线条锐利
        }
        .animation(.easeInOut(duration: 0.45), value: state)
        .animation(.easeInOut(duration: 0.6), value: confidence)
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

private func drawWalk(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double, mood: StickFigureMood = .normal, lineAlpha: CGFloat = 1.0, jointAlpha: CGFloat = 1.0) {
    let isExcited = mood == .excited

    // 步态相位：~0.7 Hz 一周期
    let phase = t * 4.5
    let armSwing: CGFloat = CGFloat(sin(phase) * (isExcited ? 0.52 : 0.30))        // 兴奋时摆臂大幅加大
    let legSwing: CGFloat = CGFloat(sin(phase + .pi) * (isExcited ? 0.38 : 0.24)) // 腿与臂反相
    let bobAmp: CGFloat = isExcited ? 4.5 : 2.0                                    // 兴奋时颠得明显更高
    let bob: CGFloat = CGFloat(abs(sin(phase * 2)) * Double(bobAmp))               // 上下颠 0~bobAmp px
    let rFootLift: CGFloat = CGFloat(max(0, sin(phase + .pi / 2)) * (isExcited ? 6 : 4))  // 兴奋时脚抬更高

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
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w, alpha: lineAlpha)
    ctx.transform = saved

    // 表情：仅在 **心情不好时**显示（mood != excited/normal 时） — 闭眼 + 愁眉 + 嘴角下垂
    // 心情好（excited/normal/calm/good）时整个脸保持空白，不画任何表情
    let showSadFace = (mood != .excited) && !isExcited
    if showSadFace {
        // 闭眼（两条向下弧线，眼角下垂带泪意）
        strokeCurve(ctx: &ctx,
                    from: CGPoint(x: 99, y: 76),
                    to:   CGPoint(x: 107, y: 78),
                    control: CGPoint(x: 103, y: 80),
                    color: stroke, width: 1.3, alpha: lineAlpha)
        // 右眼：对称
        strokeCurve(ctx: &ctx,
                    from: CGPoint(x: 117, y: 78),
                    to:   CGPoint(x: 125, y: 76),
                    control: CGPoint(x: 121, y: 80),
                    color: stroke, width: 1.3, alpha: lineAlpha)
        // 眉头：两根向中间下斜的细线（忧愁）
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: 98, y: 70),
                   to:   CGPoint(x: 105, y: 73),
                   color: stroke.opacity(0.7), width: 1.1, alpha: lineAlpha)
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: 126, y: 73),
                   to:   CGPoint(x: 119, y: 70),
                   color: stroke.opacity(0.7), width: 1.1, alpha: lineAlpha)
        // 嘴角下垂：中央到两侧向上拱（∩ 形 = 悲伤）
        strokeCurve(ctx: &ctx,
                    from: CGPoint(x: 106, y: 92),
                    to:   CGPoint(x: 118, y: 92),
                    control: CGPoint(x: 112, y: 88),
                    color: stroke, width: 1.4, alpha: lineAlpha)
    }

    // 颈椎
    strokeCurve(ctx: &ctx, from: CGPoint(x: 113, y: 105), to: CGPoint(x: 111, y: 128),
                control: CGPoint(x: 111, y: 116), color: stroke, width: w, alpha: lineAlpha)

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 111, y: 130), r: 4, color: joint, filled: true, alpha: jointAlpha)
    let shoulder: CGPoint = CGPoint(x: 111, y: 130)

    // 躯干
    strokeLine(ctx: &ctx, from: shoulder, to: CGPoint(x: 108, y: 238),
               color: stroke, width: w + 0.4, alpha: lineAlpha)
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 128, y: 238),
                control: CGPoint(x: 130, y: 180),
                color: stroke, width: 1.4, dashed: true, alpha: lineAlpha * 0.55)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 108, y: 240), r: 4, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: CGPoint(x: 95, y: 240), to: CGPoint(x: 122, y: 240),
               color: stroke, width: 1.8, alpha: lineAlpha)

    // 右臂（绕肩旋转摆动）
    let rBase = ctx.transform
    ctx.transform = rBase
        .translatedBy(x: shoulder.x, y: shoulder.y)
        .rotated(by: -armSwing)
        .translatedBy(x: -shoulder.x, y: -shoulder.y)
    let rElbow = CGPoint(x: 152, y: 170)
    let rHand  = CGPoint(x: 172, y: 218)
    strokeLine(ctx: &ctx, from: shoulder, to: rElbow, color: stroke, width: w, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rElbow, r: 3, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: rElbow, to: rHand, color: stroke, width: w, alpha: lineAlpha)
    drawEllipse(ctx: &ctx, rect: CGRect(x: rHand.x - 8, y: rHand.y - 4, width: 16, height: 8),
                fill: fill, stroke: stroke, width: 1.8, alpha: lineAlpha)
    ctx.transform = rBase

    // 左臂（反相摆动）
    let lBase = ctx.transform
    ctx.transform = lBase
        .translatedBy(x: shoulder.x, y: shoulder.y)
        .rotated(by: +armSwing)
        .translatedBy(x: -shoulder.x, y: -shoulder.y)
    let lElbow = CGPoint(x: 76, y: 168)
    let lHand  = CGPoint(x: 60, y: 205)
    strokeLine(ctx: &ctx, from: shoulder, to: lElbow, color: stroke, width: w, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: lElbow, r: 3, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: lElbow, to: lHand, color: stroke, width: w, alpha: lineAlpha)
    drawEllipse(ctx: &ctx, rect: CGRect(x: lHand.x - 7, y: lHand.y - 3, width: 14, height: 7),
                fill: fill, stroke: stroke, width: 1.8, alpha: lineAlpha)
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
    strokeLine(ctx: &ctx, from: rHipPivot, to: rKnee, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rKnee, r: 4, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: rKnee, to: rAnkle, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rAnkle, r: 3.5, color: joint, filled: true, alpha: jointAlpha)
    let rFoot = Path { p in
        p.move(to: CGPoint(x: 168, y: 312 - rFootLift))
        p.addLine(to: CGPoint(x: 198, y: 312 - rFootLift))
        p.addQuadCurve(to: CGPoint(x: 200, y: 320 - rFootLift), control: CGPoint(x: 200, y: 312 - rFootLift))
        p.addLine(to: CGPoint(x: 170, y: 320 - rFootLift))
        p.closeSubpath()
    }
    ctx.stroke(rFoot, with: .color(stroke.opacity(lineAlpha)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(rFoot, with: .color(fill.opacity(lineAlpha)))
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
    strokeLine(ctx: &ctx, from: lHipPivot, to: lKnee, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: lKnee, r: 4, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: lKnee, to: lAnkle, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: lAnkle, r: 3.5, color: joint, filled: true, alpha: jointAlpha)
    let lFoot = Path { p in
        p.move(to: CGPoint(x: 80, y: 322))
        p.addLine(to: CGPoint(x: 110, y: 322))
        p.addQuadCurve(to: CGPoint(x: 112, y: 318), control: CGPoint(x: 110, y: 322))
        p.addLine(to: CGPoint(x: 82, y: 318))
        p.closeSubpath()
    }
    ctx.stroke(lFoot, with: .color(stroke.opacity(lineAlpha)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(lFoot, with: .color(fill.opacity(lineAlpha)))
    ctx.transform = lBase2

    // 兴奋装饰：4 个十字闪光（与身体一起轻微颠簸，更贴合"身上"）
    if isExcited {
        drawExcitedSparkles(ctx: &ctx, color: joint, t: t)
    }

    // 还原整体平移
    ctx.transform = savedTop

    // 兴奋装饰：3 颗大四角星（在 bob 之外，画面上方/角落的远景"撒花"）
    if isExcited {
        drawExcitedStars(ctx: &ctx, color: joint, t: t)
    }

    // 兴奋装饰：飘动的 ♪ 音符（独立于身体颠簸，"附近"飘升）
    if isExcited {
        drawExcitedNote(ctx: &ctx, color: joint, t: t)
    }
}

// MARK: - 坐

private func drawSit(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double, mood: StickFigureMood = .normal, tiredness: Double = 0.0, neckWarning: Double = 0.0, lineAlpha: CGFloat = 1.0, jointAlpha: CGFloat = 1.0) {
    let isCalm = mood == .calm
    let isTired = mood == .tired

    // 平稳装饰（慢呼吸光环 + 缓升小点）— 在 figure 之下、scene 之上
    if isCalm {
        drawCalmAura(ctx: &ctx, color: joint, t: t)
        drawCalmDots(ctx: &ctx, color: joint, t: t)
    }

    // 疲惫装饰（浮 Z + 汗滴）— 强度随 tiredness 增长；放在 head 之后避免被遮挡
    // （稍后在函数内追加调用）

    // 头/颈参数（声明提前，后面 right arm 之后再画头，让头画在手臂之上）
    let headTiltExtra: Double = isTired ? tiredness * 10.0 : 0   // peak 时 20°+10°=30°（不夸张）
    let headShiftY: CGFloat = isTired ? CGFloat(tiredness) * 12 : 0   // 头往下沉 12px
    let headShiftX: CGFloat = isTired ? CGFloat(tiredness) * 6 : 0   // 头往屏幕方向靠 6px
    let headCenter = CGPoint(x: 108, y: 75)
    let head = CGRect(x: headCenter.x - 24, y: headCenter.y - 30, width: 48, height: 60)
    let tiltAngle = Angle.degrees(20 + headTiltExtra).radians

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 100, y: 130), r: 4, color: joint, filled: true, alpha: jointAlpha)
    let shoulder: CGPoint = CGPoint(x: 100, y: 130)

    // 躯干（靠椅背但腰部略离）
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 96, y: 222),
                control: CGPoint(x: 78, y: 175), color: stroke, width: w + 0.4, alpha: lineAlpha)
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 116, y: 222),
                control: CGPoint(x: 118, y: 175),
                color: stroke, width: 1.4, dashed: true, alpha: lineAlpha * 0.55)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 96, y: 224), r: 4, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: CGPoint(x: 84, y: 224), to: CGPoint(x: 110, y: 224),
               color: stroke, width: 1.8, alpha: lineAlpha)

    // 右臂（伸向键盘，敲击时手腕上下颤动）
    let rElbow = CGPoint(x: 140, y: 175)
    let rHand  = CGPoint(x: 175, y: 200)
    strokeLine(ctx: &ctx, from: shoulder, to: rElbow, color: stroke, width: w, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rElbow, r: 3, color: joint, filled: true, alpha: jointAlpha)
    // 敲击节奏：~3 Hz 主拍 + 快速抖动叠加；tired 时变慢（peak 时 ~40% 速度）
    let tapSpeed: Double = isTired ? 8.0 * (1.0 - tiredness * 0.6) : 8.0
    let tapPhase = t * tapSpeed
    let tapBump: CGFloat = CGFloat(max(0, sin(tapPhase)) * pow(sin(tapPhase * 0.5) * 0.5 + 0.5, 2) * 3.5)
    let rBase = ctx.transform
    ctx.transform = rBase
        .translatedBy(x: rElbow.x, y: rElbow.y)
        .rotated(by: CGFloat(sin(tapPhase) * 0.08))
        .translatedBy(x: -rElbow.x, y: -rElbow.y)
    strokeLine(ctx: &ctx, from: rElbow, to: CGPoint(x: rHand.x, y: rHand.y + tapBump), color: stroke, width: w, alpha: lineAlpha)
    drawEllipse(ctx: &ctx, rect: CGRect(x: rHand.x - 9, y: rHand.y - 3 + tapBump, width: 18, height: 7),
                fill: fill, stroke: stroke, width: 1.8, alpha: lineAlpha)
    ctx.transform = rBase

    // 左臂（垂在身侧）
    let lElbow = CGPoint(x: 92, y: 195)
    let lHand  = CGPoint(x: 90, y: 230)
    strokeLine(ctx: &ctx, from: shoulder, to: lElbow, color: stroke, width: w, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: lElbow, r: 3, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: lElbow, to: lHand, color: stroke, width: w, alpha: lineAlpha)
    drawEllipse(ctx: &ctx, rect: CGRect(x: lHand.x - 5, y: lHand.y - 3, width: 10, height: 6),
                fill: fill, stroke: stroke, width: 1.8, alpha: lineAlpha)

    // 大腿（水平）
    let rHip   = CGPoint(x: 110, y: 224)
    let rKnee  = CGPoint(x: 185, y: 222)
    strokeLine(ctx: &ctx, from: rHip, to: rKnee, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rKnee, r: 4, color: joint, filled: true, alpha: jointAlpha)

    // 小腿（垂直）
    let rAnkle = CGPoint(x: 185, y: 295)
    strokeLine(ctx: &ctx, from: rKnee, to: rAnkle, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: rAnkle, r: 3.5, color: joint, filled: true, alpha: jointAlpha)

    // 脚
    let foot = Path { p in
        p.move(to: CGPoint(x: 180, y: 297))
        p.addLine(to: CGPoint(x: 202, y: 297))
        p.addQuadCurve(to: CGPoint(x: 205, y: 305), control: CGPoint(x: 204, y: 297))
        p.addLine(to: CGPoint(x: 178, y: 305))
        p.closeSubpath()
    }
    ctx.stroke(foot, with: .color(stroke.opacity(lineAlpha)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(foot, with: .color(fill.opacity(lineAlpha)))

    // 头 + 颈椎（放在 right arm 之后，让 tired 时的头画在手臂之上，z-order 正确）
    let saved = ctx.transform
    ctx.transform = saved
        .translatedBy(x: headShiftX, y: headShiftY)
        .translatedBy(x: headCenter.x, y: headCenter.y)
        .rotated(by: tiltAngle)
        .translatedBy(x: -headCenter.x, y: -headCenter.y)
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w, alpha: lineAlpha)

    // 颈椎：画在 head 的本地坐标系里，跟头一起转。
    // 头底本地坐标：(0, 30) 相对头中心 → 屏幕 (headCenter.x, headCenter.y + 30)
    // 肩 (100, 128) 要投到头本地：先减 (headCenter + headShift)，再绕头中心逆旋 tiltAngle，再加 headCenter
    let shoulderOffsetX: CGFloat = 100 - headCenter.x - headShiftX
    let shoulderOffsetY: CGFloat = 128 - headCenter.y - headShiftY
    let cosInv = CGFloat(cos(-tiltAngle))
    let sinInv = CGFloat(sin(-tiltAngle))
    let neckShoulderLocalX = headCenter.x + shoulderOffsetX * cosInv - shoulderOffsetY * sinInv
    let neckShoulderLocalY = headCenter.y + shoulderOffsetX * sinInv + shoulderOffsetY * cosInv
    let neckTopLocal = CGPoint(x: headCenter.x, y: headCenter.y + 30)
    let neckBotLocal = CGPoint(x: neckShoulderLocalX, y: neckShoulderLocalY)
    // 控制点：起点和终点中点略偏左，让颈线有自然弧度
    let neckControlLocal = CGPoint(
        x: (neckTopLocal.x + neckBotLocal.x) / 2 - 5,
        y: (neckTopLocal.y + neckBotLocal.y) / 2
    )
    // 颈线颜色 + 宽度：tired 时颈压力大，navy → 鲜艳红，w+0.4 → w+2.8
    let neckW = CGFloat(neckWarning)
    let neckColor = Color(
        red:   0.10 + (0.93 - 0.10) * neckW,
        green: 0.15 + (0.20 - 0.15) * neckW,
        blue:  0.25 + (0.20 - 0.25) * neckW
    )
    let neckWidth = (w + 0.4) + 2.4 * neckW
    strokeCurve(ctx: &ctx, from: neckTopLocal, to: neckBotLocal,
                control: neckControlLocal, color: neckColor, width: neckWidth, alpha: lineAlpha)

    ctx.transform = saved

    // 疲惫装饰（汗滴 + 💢 烦躁爆点）— 下午工作时不再显示打呼的 Z
    if isTired {
        drawTiredSweat(ctx: &ctx, color: joint, t: t, level: tiredness)
        // 💢 跟着头走：tired 时头会下沉右移（shift 35,95），💢 同步到头左上角
        let headCenterScreenX = headCenter.x + headShiftX
        let headCenterScreenY = headCenter.y + headShiftY
        drawTiredVein(ctx: &ctx, t: t, level: tiredness,
                      headCenterX: headCenterScreenX, headCenterY: headCenterScreenY)
    }
}

// MARK: - 睡

private func drawSleep(ctx: inout GraphicsContext, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double, lineAlpha: CGFloat = 1.0, jointAlpha: CGFloat = 1.0) {
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
    drawEllipse(ctx: &ctx, rect: head, fill: fill, stroke: stroke, width: w, alpha: lineAlpha)
    // 闭眼线
    strokeLine(ctx: &ctx, from: CGPoint(x: 52, y: 192), to: CGPoint(x: 62, y: 192),
               color: stroke, width: 1.4, alpha: lineAlpha)
    // 嘴角
    strokeLine(ctx: &ctx, from: CGPoint(x: 64, y: 207), to: CGPoint(x: 70, y: 207),
               color: stroke, width: 1.2, alpha: lineAlpha * 0.6)

    // 颈
    strokeLine(ctx: &ctx, from: CGPoint(x: 72, y: 200), to: CGPoint(x: 92, y: 210),
               color: stroke, width: w, alpha: lineAlpha)

    // 肩
    drawDot(ctx: &ctx, at: CGPoint(x: 92, y: 212), r: 4, color: joint, filled: true, alpha: jointAlpha)
    let shoulder: CGPoint = CGPoint(x: 92, y: 212)

    // 躯干（水平）
    strokeLine(ctx: &ctx, from: shoulder, to: CGPoint(x: 215, y: 220),
               color: stroke, width: w + 0.4, alpha: lineAlpha)
    // 胸前轮廓
    strokeCurve(ctx: &ctx, from: shoulder, to: CGPoint(x: 215, y: 215),
                control: CGPoint(x: 150, y: 205),
                color: stroke, width: 1.4, dashed: true, alpha: lineAlpha * 0.55)

    // 髋
    drawDot(ctx: &ctx, at: CGPoint(x: 215, y: 222), r: 4, color: joint, filled: true, alpha: jointAlpha)

    // 上臂（屈，置胸前）
    let fElbow = CGPoint(x: 122, y: 232)
    let fHand  = CGPoint(x: 148, y: 230)
    strokeLine(ctx: &ctx, from: shoulder, to: fElbow, color: stroke, width: w, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: fElbow, r: 3, color: joint, filled: true, alpha: jointAlpha)
    strokeLine(ctx: &ctx, from: fElbow, to: fHand, color: stroke, width: w, alpha: lineAlpha)
    drawEllipse(ctx: &ctx, rect: CGRect(x: fHand.x - 6, y: fHand.y - 3, width: 12, height: 6),
                fill: fill, stroke: stroke, width: 1.8, alpha: lineAlpha)

    // 下臂（垫头下）
    let bElbow = CGPoint(x: 72, y: 234)
    let bHand  = CGPoint(x: 52, y: 222)
    strokeLine(ctx: &ctx, from: shoulder, to: bElbow, color: stroke, width: w * 0.85, alpha: lineAlpha * 0.7)
    strokeLine(ctx: &ctx, from: bElbow, to: bHand, color: stroke, width: w * 0.85, alpha: lineAlpha * 0.7)
    drawDot(ctx: &ctx, at: bElbow, r: 2.5, color: joint, filled: true, alpha: jointAlpha * 0.7)

    // 大腿
    let knee = CGPoint(x: 240, y: 226)
    strokeLine(ctx: &ctx, from: CGPoint(x: 215, y: 222), to: knee, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: knee, r: 4, color: joint, filled: true, alpha: jointAlpha)
    // 小腿（略屈）
    let ankle = CGPoint(x: 240, y: 248)
    strokeLine(ctx: &ctx, from: knee, to: ankle, color: stroke, width: w + 0.4, alpha: lineAlpha)
    drawDot(ctx: &ctx, at: ankle, r: 3.5, color: joint, filled: true, alpha: jointAlpha)
    // 脚
    let foot = Path { p in
        p.move(to: CGPoint(x: 232, y: 240))
        p.addLine(to: CGPoint(x: 252, y: 240))
        p.addQuadCurve(to: CGPoint(x: 256, y: 250), control: CGPoint(x: 254, y: 240))
        p.addLine(to: CGPoint(x: 234, y: 250))
        p.closeSubpath()
    }
    ctx.stroke(foot, with: .color(stroke.opacity(lineAlpha)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    ctx.fill(foot, with: .color(.black))

    // 还原
    ctx.transform = savedTop
}

// MARK: - 路由

private func drawFigure(ctx: inout GraphicsContext, state: StickState, mood: StickFigureMood, tiredness: Double, neckWarning: Double, stroke: Color, fill: Color, joint: Color, w: CGFloat, t: Double, lineAlpha: CGFloat, jointAlpha: CGFloat) {
    switch state {
    case .walk:  drawWalk(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t, mood: mood, lineAlpha: lineAlpha, jointAlpha: jointAlpha)
    case .sit:   drawSit(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t, mood: mood, tiredness: tiredness, neckWarning: neckWarning, lineAlpha: lineAlpha, jointAlpha: jointAlpha)
    case .sleep: drawSleep(ctx: &ctx, stroke: stroke, fill: fill, joint: joint, w: w, t: t, lineAlpha: lineAlpha, jointAlpha: jointAlpha)
    }
}

// MARK: - 基本图元

private func strokeLine(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                        color: Color, width: CGFloat, dashed: Bool = false, alpha: CGFloat = 1.0) {
    var p = Path()
    p.move(to: a)
    p.addLine(to: b)
    let style = StrokeStyle(lineWidth: width, lineCap: .round,
                            dash: dashed ? [3, 4] : [])
    ctx.stroke(p, with: .color(color.opacity(alpha)), style: style)
}

private func strokeCurve(ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, control: CGPoint,
                         color: Color, width: CGFloat, dashed: Bool = false, alpha: CGFloat = 1.0) {
    var p = Path()
    p.move(to: a)
    p.addQuadCurve(to: b, control: control)
    let style = StrokeStyle(lineWidth: width, lineCap: .round,
                            dash: dashed ? [3, 4] : [])
    ctx.stroke(p, with: .color(color.opacity(alpha)), style: style)
}

private func drawDot(ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color, filled: Bool = false, alpha: CGFloat = 1.0) {
    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
    let path = Path(ellipseIn: rect)
    if filled {
        ctx.fill(path, with: .color(color.opacity(alpha)))
    } else {
        ctx.stroke(path, with: .color(color.opacity(alpha)), lineWidth: 1.4)
    }
}

private func drawEllipse(ctx: inout GraphicsContext, rect: CGRect, fill: Color, stroke: Color, width: CGFloat, alpha: CGFloat = 1.0) {
    let p = Path(ellipseIn: rect)
    ctx.fill(p, with: .color(fill.opacity(alpha)))
    ctx.stroke(p, with: .color(stroke.opacity(alpha)), lineWidth: width)
}

private func drawZ(ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
    let t = Text("Z")
        .font(.system(size: size, weight: .heavy, design: .serif))
        .foregroundColor(color)
    ctx.draw(t, at: p, anchor: .center)
}

// MARK: - 兴奋装饰：闪光（身上）

/// 4 个十字形闪光包围火柴人。三角波 0→1→0 驱动 size/alpha，错相 0.4s。
/// 比 v1 大约 2× —— 夸张版。
/// 头部（耳朵位置）留给 4 角星，闪光只放在躯干两侧。
private func drawExcitedSparkles(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 1.6
    let positions: [CGPoint] = [
        CGPoint(x: 225, y: 180),   // 右上（手臂外）
        CGPoint(x: 12,  y: 175),   // 左上（躯干外）
        CGPoint(x: 230, y: 260),   // 右下（腿外）
        CGPoint(x: 8,   y: 265)    // 左下（腿外）
    ]
    for i in 0..<positions.count {
        let p = positions[i]
        let phase = ((t + Double(i) * 0.4).truncatingRemainder(dividingBy: period)) / period
        // 三角波：0→1→0 over [0, 1)
        let wave = CGFloat(1.0 - abs(phase * 2.0 - 1.0))
        let size: CGFloat = 5.0 + 7.0 * wave   // 5..12（原 2.5..6，放大约 2×）
        let alpha: CGFloat = 0.55 + 0.45 * wave
        // 十字（竖 + 横）+ 中心小亮点
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: p.x, y: p.y - size),
                   to: CGPoint(x: p.x, y: p.y + size),
                   color: color.opacity(alpha), width: 1.8)
        strokeLine(ctx: &ctx,
                   from: CGPoint(x: p.x - size, y: p.y),
                   to: CGPoint(x: p.x + size, y: p.y),
                   color: color.opacity(alpha), width: 1.8)
        drawDot(ctx: &ctx, at: p, r: 2.2, color: color.opacity(alpha), filled: true)
    }
}

// MARK: - 兴奋装饰：大四角星（远处，夸张版）

/// 3 颗四角星在画面上方/角落，旋转 + 脉冲（错相 0.5s）—— 远景"撒花"效果。
private func drawExcitedStars(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 1.4
    let stars: [(CGPoint, CGFloat, CGFloat)] = [
        // (位置, 基础尺寸, 旋转速度 rad/s)
        (CGPoint(x: 22,  y: 30),  10.0,  1.6),
        (CGPoint(x: 218, y: 22),  12.0, -1.2),
        (CGPoint(x: 115, y: 12),   8.0,  1.0),
    ]
    for i in 0..<stars.count {
        let (center, base, omega) = stars[i]
        let phase = ((t + Double(i) * 0.5).truncatingRemainder(dividingBy: period)) / period
        let wave = CGFloat(0.55 + 0.45 * abs(sin(phase * .pi)))  // 0.55..1.0
        let size = base * wave
        let alpha: CGFloat = 0.55 + 0.45 * wave
        let angle = CGFloat(t * Double(omega))
        // 旋转 + 缩放包裹
        let saved = ctx.transform
        ctx.transform = saved
            .translatedBy(x: center.x, y: center.y)
            .rotated(by: angle)
            .translatedBy(x: -center.x, y: -center.y)
        drawFourPointStar(ctx: &ctx, at: center, size: size, color: color.opacity(alpha))
        ctx.transform = saved
    }
}

/// 4 角星（菱形 × 2 交叉）—— 填充实心
private func drawFourPointStar(ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
    let k: CGFloat = 0.32  // 内缩比例（越小越尖）
    let path = Path { path in
        path.move(to: CGPoint(x: p.x,        y: p.y - size))
        path.addLine(to: CGPoint(x: p.x + size * k, y: p.y - size * k))
        path.addLine(to: CGPoint(x: p.x + size, y: p.y))
        path.addLine(to: CGPoint(x: p.x + size * k, y: p.y + size * k))
        path.addLine(to: CGPoint(x: p.x,        y: p.y + size))
        path.addLine(to: CGPoint(x: p.x - size * k, y: p.y + size * k))
        path.addLine(to: CGPoint(x: p.x - size, y: p.y))
        path.addLine(to: CGPoint(x: p.x - size * k, y: p.y - size * k))
        path.closeSubpath()
    }
    ctx.fill(path, with: .color(color))
}

// MARK: - 兴奋装饰：♪ 音符（附近，夸张版）

/// 2 个 ♪ 音符：一个大的 28px 从右中飘到右上；一个小的 18px 错相 1.5s，
/// 起始更靠左下/终点更靠左中。整体 4s 一周期，含淡入/淡出 + 横向 sin 摇摆。
private func drawExcitedNote(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 4.0

    // 大音符（主）
    drawFloatingNote(
        ctx: &ctx, color: color, t: t,
        period: period, phaseOffset: 0.0,
        start: CGPoint(x: 200, y: 135), end: CGPoint(x: 225, y: 28),
        size: 28, wobbleAmp: 4
    )
    // 小音符（次，错相 1.5s）
    drawFloatingNote(
        ctx: &ctx, color: color, t: t,
        period: period, phaseOffset: 1.5,
        start: CGPoint(x: 175, y: 158), end: CGPoint(x: 200, y: 50),
        size: 20, wobbleAmp: 3
    )
}

private func drawFloatingNote(ctx: inout GraphicsContext, color: Color, t: Double,
                              period: Double, phaseOffset: Double,
                              start: CGPoint, end: CGPoint,
                              size: CGFloat, wobbleAmp: CGFloat) {
    let p = ((t + phaseOffset).truncatingRemainder(dividingBy: period)) / period
    let alpha: CGFloat
    if p < 0.12 { alpha = p / 0.12 }
    else if p > 0.88 { alpha = (1 - p) / 0.12 }
    else { alpha = 1.0 }
    let prog = CGFloat(p)
    let wobble = CGFloat(sin(t * 1.8 + phaseOffset * 1.7) * Double(wobbleAmp)) * prog
    let x = start.x + (end.x - start.x) * prog + wobble
    let y = start.y + (end.y - start.y) * prog
    drawNote(ctx: &ctx, at: CGPoint(x: x, y: y), size: size, color: color.opacity(alpha))
}

private func drawNote(ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
    let t = Text("♪")
        .font(.system(size: size, weight: .heavy, design: .serif))
        .foregroundColor(color)
    ctx.draw(t, at: p, anchor: .center)
}

// MARK: - 平稳装饰：慢呼吸光环（上午 sit）

/// 1 个大椭圆描边环，4s 呼吸（scale 0.96↔1.04，alpha 0.15↔0.21）。
/// 紧贴 figure 周围（不覆盖椅子/床）—— 暗示"稳定/专注"。
private func drawCalmAura(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 4.0
    let p = t.truncatingRemainder(dividingBy: period) / period
    let wave = sin(p * .pi * 2)  // -1..1
    let scale = 1.0 + CGFloat(wave) * 0.04
    let alpha: CGFloat = 0.15 + CGFloat(abs(wave)) * 0.06
    // 中心 (120, 180)，覆盖 figure 主体（不含脚/椅）
    let rect = CGRect(x: 35, y: 35, width: 170, height: 290)
    let saved = ctx.transform
    ctx.transform = saved
        .translatedBy(x: 120, y: 180)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -120, y: -180)
    ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(alpha)), lineWidth: 1.4)
    ctx.transform = saved
}

// MARK: - 平稳装饰：缓升小点（上午 sit）

/// 2 个小实心圆从右中飘到右上方，3s 周期，错相 1s。
/// 比 excited 音符更慢、更小、更稳 —— 暗示"专注 / 在想"。
private func drawCalmDots(ctx: inout GraphicsContext, color: Color, t: Double) {
    let period: Double = 3.0
    let dots: [(CGPoint, CGPoint, Double)] = [
        (CGPoint(x: 200, y: 100), CGPoint(x: 215, y: 55), 0.0),
        (CGPoint(x: 218, y: 115), CGPoint(x: 232, y: 70), 1.0)
    ]
    for (start, end, offset) in dots {
        let phase = ((t + offset).truncatingRemainder(dividingBy: period)) / period
        let alpha: CGFloat
        if phase < 0.15 { alpha = phase / 0.15 * 0.7 }
        else if phase > 0.85 { alpha = (1 - phase) / 0.15 * 0.7 }
        else { alpha = 0.7 }
        let x = start.x + (end.x - start.x) * CGFloat(phase)
        let y = start.y + (end.y - start.y) * CGFloat(phase)
        drawDot(ctx: &ctx, at: CGPoint(x: x, y: y), r: 2.6, color: color.opacity(alpha), filled: true)
    }
}

// MARK: - 疲惫装饰：浮 Z（已移除 — 下午工作不再打呼的 Z）

// drawTiredZ 已删除：下午 tired-sit 不再显示打呼 Z 动效。
// 保留 drawZ 是因为 drawSleep 还在用。

// MARK: - 疲惫装饰：汗滴（下午 sit，强度 0..1）

/// 头右侧最多 2 颗泪滴/汗滴：位置微抖 + alpha 按 level 渐显 + size 微缩放。
/// 第 1 颗从 level 0.05 起；第 2 颗从 level 0.5 起，越来越"汗流浃背"。
private func drawTiredSweat(ctx: inout GraphicsContext, color: Color, t: Double, level: Double) {
    guard level > 0.05 else { return }
    let levelC = CGFloat(level)
    // 滴 1：太阳穴处，常驻
    drawOneSweat(ctx: &ctx, color: color, t: t, level: levelC, baseX: 162, baseY: 72, size: 3.5 + 2.0 * levelC, alpha: 0.6)
    // 滴 2：脸颊下方，level > 0.5 才出现
    if levelC > 0.5 {
        let sub = (levelC - 0.5) * 2  // 0..1
        drawOneSweat(ctx: &ctx, color: color, t: t, level: sub, baseX: 170, baseY: 92, size: 2.8 + 1.5 * sub, alpha: 0.55)
    }
}

private func drawOneSweat(ctx: inout GraphicsContext, color: Color, t: Double, level: CGFloat,
                          baseX: CGFloat, baseY: CGFloat, size: CGFloat, alpha: CGFloat) {
    let wobble = CGFloat(sin(t * 1.5) * 1.5)
    let drift = CGFloat(sin(t * 0.6 + Double(baseX)) * 1.0) * level
    let p = CGPoint(x: baseX + wobble, y: baseY + drift)
    // 泪滴（尖朝下，圆头朝上）
    let path = Path { path in
        path.move(to: CGPoint(x: p.x, y: p.y - size))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + size * 0.6),
                          control: CGPoint(x: p.x + size * 0.85, y: p.y - size * 0.2))
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - size),
                          control: CGPoint(x: p.x - size * 0.85, y: p.y - size * 0.2))
        path.closeSubpath()
    }
    ctx.fill(path, with: .color(color.opacity(alpha * level)))
}

// MARK: - 疲惫装饰：💢 烦躁爆点（下午 sit，强度 0..1）

/// 系统原生 💢 emoji（红/橙爆点），位置跟着头的中心走，固定在头左上角**外侧**
/// （offset -48, -40，离头远一点不贴在一起）。5Hz 脉冲让 emoji 轻微"鼓"动。
/// 用 Text 画 emoji 比自己拼 + 线条更准确（系统自带红/橙渐变 + 4 个粗臂）。
private func drawTiredVein(ctx: inout GraphicsContext, t: Double, level: Double, headCenterX: CGFloat, headCenterY: CGFloat) {
    guard level > 0.4 else { return }
    let levelC = CGFloat(level)
    // 位置：头左上角外侧 48×40（拉开距离，不跟头贴一起）
    let p = CGPoint(x: headCenterX - 48, y: headCenterY - 40)
    // 大小：14→28 随 level 增长
    let pulse = 1.0 + 0.08 * CGFloat(sin(t * 30.0))
    let size: CGFloat = (14 + 14 * levelC) * pulse
    // 系统原生 💢 emoji（自带红/橙爆点形状）
    let vein = Text("💢")
        .font(.system(size: size))
    ctx.draw(vein, at: p, anchor: .center)
}
