import SwiftUI
import WidgetKit

// MARK: - 2x2 运动后冰水告警 Widget
//
// 5 步因果链:
//   冰水杯 → 血管 → 收缩 → 心律失常 → 可能晕厥
//
// 设计来源: widget-designs/post-workout-cold-water-hybrids.html (HYBRID γ)

// MARK: - Entry

struct StickPostWorkoutEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct PostWorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickPostWorkoutEntry {
        StickPostWorkoutEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (StickPostWorkoutEntry) -> Void) {
        completion(StickPostWorkoutEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickPostWorkoutEntry>) -> Void) {
        let now = Date()
        let entry = StickPostWorkoutEntry(date: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Theme

private enum PWTheme {
    static let navy   = Color(red: 0.10,  green: 0.15,  blue: 0.25)
    static let red    = Color(red: 0.753, green: 0.224, blue: 0.169)  // #C0392B
    static let cream  = Color(red: 1.000, green: 0.914, blue: 0.796)  // #FFE9CB
    static let ice    = Color(red: 0.655, green: 0.863, blue: 0.933)  // #A7DCEE
    static let slate  = Color(red: 0.353, green: 0.388, blue: 0.471)  // #5A6378
    static let bgTop  = Color(red: 0.957, green: 0.965, blue: 0.949)  // #F4F6F2
    static let bgBot  = Color(red: 0.863, green: 0.890, blue: 0.863)  // #DCE3DC
    static let paper  = Color(red: 0.984, green: 0.980, blue: 0.965)
}

// MARK: - Widget View

struct StickPostWorkoutWidgetView: View {
    let entry: StickPostWorkoutEntry

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 3) {
                topRow(t: t)

                CausalChain(t: t)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                titleRow
                subRow

                Spacer(minLength: 2)

                Rectangle()
                    .fill(PWTheme.navy.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.bottom, 3)

                footerRow
            }
            .padding(10)
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [PWTheme.bgTop, PWTheme.bgBot],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: top row: [01] EXERCISE · [⚠ RISK]

    private func topRow(t: Double) -> some View {
        HStack(spacing: 4) {
            Text("01")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(PWTheme.paper)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(PWTheme.navy)
                .cornerRadius(3)
            Text("WORKOUT END")
                .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundColor(PWTheme.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 2.5) {
                let pulse = 0.6 + 0.4 * sin(t * 3.5)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(PWTheme.paper.opacity(pulse))
                Text("RISK ↑")
                    .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                    .tracking(0.3)
                    .foregroundColor(PWTheme.paper)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(PWTheme.red)
            .cornerRadius(3)
        }
    }

    // MARK: title: 冰水 → 晕厥

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("冰水")
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundColor(PWTheme.navy)
            Text("→")
                .font(.system(size: 15, weight: .heavy, design: .serif))
                .foregroundColor(PWTheme.red)
                .baselineOffset(1)
            Text("晕厥")
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundColor(PWTheme.navy)
        }
    }

    // MARK: sub: 阈值 · 心率回 <100 再喝

    private var subRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("阈值 · 心率回")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(PWTheme.slate)
            Text("<100")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(PWTheme.red)
            Text("再喝")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(PWTheme.slate)
        }
    }

    // MARK: footer: [TIP] 常温水 · 小口慢饮

    private var footerRow: some View {
        HStack(spacing: 4) {
            Text("TIP")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(PWTheme.paper)
                .padding(.horizontal, 3.5)
                .padding(.vertical, 1)
                .background(PWTheme.navy)
                .cornerRadius(2)
            Text("常温水 · 小口慢饮")
                .font(.system(size: 9, weight: .semibold, design: .serif))
                .italic()
                .foregroundColor(PWTheme.navy)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 5 步因果链

struct CausalChain: View {
    let t: Double

    var body: some View {
        VStack(spacing: 2) {
            // Icons + arrows (Canvas)
            ChainIcons(t: t)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            // Labels evenly distributed
            HStack(spacing: 0) {
                chainLabel("冰水")
                chainLabel("血管")
                chainLabel("收缩")
                chainLabel("心律", color: PWTheme.red)
                chainLabel("晕厥", color: PWTheme.red)
            }
        }
    }

    private func chainLabel(_ text: String, color: Color = PWTheme.navy) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy, design: .monospaced))
            .tracking(0.3)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Canvas: 5 icons + 4 arrows

struct ChainIcons: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let panelW = size.width / 5
            let cy = size.height / 2

            // Centers
            let centers: [CGFloat] = (0..<5).map { panelW * (CGFloat($0) + 0.5) }

            // Arrows under icons
            for i in 0..<4 {
                let arrowX = panelW * CGFloat(i + 1)
                drawArrow(ctx: &ctx, midX: arrowX, midY: cy)
            }

            // Icons
            drawIceCup(ctx: &ctx, cx: centers[0], cy: cy)
            drawVessel(ctx: &ctx, cx: centers[1], cy: cy)
            drawConstrict(ctx: &ctx, cx: centers[2], cy: cy)
            drawArrhythmia(ctx: &ctx, cx: centers[3], cy: cy)
            drawFainting(ctx: &ctx, cx: centers[4], cy: cy, t: t)
        }
    }

    // MARK: arrow

    private func drawArrow(ctx: inout GraphicsContext, midX: CGFloat, midY: CGFloat) {
        let len: CGFloat = 5
        let shaft = Path { p in
            p.move(to: CGPoint(x: midX - len, y: midY))
            p.addLine(to: CGPoint(x: midX + len, y: midY))
        }
        ctx.stroke(shaft, with: .color(PWTheme.slate.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        let head = Path { p in
            p.move(to: CGPoint(x: midX + len - 2.2, y: midY - 2.2))
            p.addLine(to: CGPoint(x: midX + len, y: midY))
            p.addLine(to: CGPoint(x: midX + len - 2.2, y: midY + 2.2))
        }
        ctx.stroke(head, with: .color(PWTheme.slate.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
    }

    // MARK: P1 — 冰水杯

    private func drawIceCup(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let topW: CGFloat = 14
        let botW: CGFloat = 12
        let h: CGFloat = 22
        let topY = cy - h / 2 + 1
        let botY = cy + h / 2 + 1

        // glass
        let glass = Path { p in
            p.move(to: CGPoint(x: cx - topW / 2, y: topY))
            p.addLine(to: CGPoint(x: cx + topW / 2, y: topY))
            p.addLine(to: CGPoint(x: cx + botW / 2, y: botY))
            p.addLine(to: CGPoint(x: cx - botW / 2, y: botY))
            p.closeSubpath()
        }
        ctx.fill(glass, with: .color(.white.opacity(0.88)))
        ctx.stroke(glass, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))

        // water surface ellipse on top
        let waterRect = CGRect(x: cx - topW / 2, y: topY - 1.2, width: topW, height: 2.4)
        ctx.fill(Path(ellipseIn: waterRect), with: .color(PWTheme.ice))
        ctx.stroke(Path(ellipseIn: waterRect), with: .color(PWTheme.navy), lineWidth: 0.8)

        // 3 ice cubes
        let cubes: [(CGFloat, CGFloat, CGFloat)] = [
            (cx - 4, topY + 2, 5),
            (cx + 1, topY + 6, 4.5),
            (cx - 2, topY + 11, 4)
        ]
        for (cubeX, cubeY, sz) in cubes {
            let r = CGRect(x: cubeX, y: cubeY, width: sz, height: sz)
            ctx.fill(Path(roundedRect: r, cornerRadius: 0.6), with: .color(.white))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 0.6), with: .color(PWTheme.navy), lineWidth: 0.7)
        }
    }

    // MARK: P2 — 血管 (normal)

    private func drawVessel(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let w: CGFloat = 24
        let h: CGFloat = 11
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let path = Path(roundedRect: rect, cornerRadius: 2.5)
        ctx.fill(path, with: .color(PWTheme.cream))
        ctx.stroke(path, with: .color(PWTheme.navy), lineWidth: 0.9)
        // 4 red cells flowing
        for ox in [CGFloat(-8.5), CGFloat(-3), CGFloat(2.5), CGFloat(8)] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx + ox - 2, y: cy - 1.5, width: 4, height: 3)),
                with: .color(PWTheme.red.opacity(0.88))
            )
        }
    }

    // MARK: P3 — 收缩 (constricted)

    private func drawConstrict(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let w: CGFloat = 24
        let h: CGFloat = 11
        let neckH: CGFloat = 4
        let neckW: CGFloat = 4

        let pinched = Path { p in
            // Top edge
            p.move(to: CGPoint(x: cx - w / 2 + 1.5, y: cy - h / 2))
            p.addLine(to: CGPoint(x: cx - neckW / 2, y: cy - h / 2))
            p.addLine(to: CGPoint(x: cx - neckW / 2, y: cy - neckH / 2))
            p.addLine(to: CGPoint(x: cx + neckW / 2, y: cy - neckH / 2))
            p.addLine(to: CGPoint(x: cx + neckW / 2, y: cy - h / 2))
            p.addLine(to: CGPoint(x: cx + w / 2 - 1.5, y: cy - h / 2))
            // Right rounded end
            p.addQuadCurve(to: CGPoint(x: cx + w / 2, y: cy - h / 2 + 1.5),
                           control: CGPoint(x: cx + w / 2, y: cy - h / 2))
            p.addLine(to: CGPoint(x: cx + w / 2, y: cy + h / 2 - 1.5))
            p.addQuadCurve(to: CGPoint(x: cx + w / 2 - 1.5, y: cy + h / 2),
                           control: CGPoint(x: cx + w / 2, y: cy + h / 2))
            // Bottom edge
            p.addLine(to: CGPoint(x: cx + neckW / 2, y: cy + h / 2))
            p.addLine(to: CGPoint(x: cx + neckW / 2, y: cy + neckH / 2))
            p.addLine(to: CGPoint(x: cx - neckW / 2, y: cy + neckH / 2))
            p.addLine(to: CGPoint(x: cx - neckW / 2, y: cy + h / 2))
            p.addLine(to: CGPoint(x: cx - w / 2 + 1.5, y: cy + h / 2))
            // Left rounded end
            p.addQuadCurve(to: CGPoint(x: cx - w / 2, y: cy + h / 2 - 1.5),
                           control: CGPoint(x: cx - w / 2, y: cy + h / 2))
            p.addLine(to: CGPoint(x: cx - w / 2, y: cy - h / 2 + 1.5))
            p.addQuadCurve(to: CGPoint(x: cx - w / 2 + 1.5, y: cy - h / 2),
                           control: CGPoint(x: cx - w / 2, y: cy - h / 2))
            p.closeSubpath()
        }
        ctx.fill(pinched, with: .color(PWTheme.cream))
        ctx.stroke(pinched, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 0.9, lineJoin: .round))

        // Crammed cells on left
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - 10, y: cy - 1.5, width: 3.2, height: 2.5)),
            with: .color(PWTheme.red)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - 7, y: cy - 3.5, width: 3.0, height: 2.5)),
            with: .color(PWTheme.red)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - 7, y: cy + 1, width: 3.0, height: 2.5)),
            with: .color(PWTheme.red)
        )
        // Sparse cell after pinch
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx + 7, y: cy - 1.2, width: 3.2, height: 2.5)),
            with: .color(PWTheme.red.opacity(0.4))
        )

        // Squeeze arrows (top + bottom)
        let topArrow = Path { p in
            p.move(to: CGPoint(x: cx, y: cy - h / 2 - 4))
            p.addLine(to: CGPoint(x: cx, y: cy - h / 2 - 0.4))
        }
        ctx.stroke(topArrow, with: .color(PWTheme.red),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        let topHead = Path { p in
            p.move(to: CGPoint(x: cx - 1.5, y: cy - h / 2 - 1.6))
            p.addLine(to: CGPoint(x: cx, y: cy - h / 2 - 0.4))
            p.addLine(to: CGPoint(x: cx + 1.5, y: cy - h / 2 - 1.6))
        }
        ctx.stroke(topHead, with: .color(PWTheme.red),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
        let botArrow = Path { p in
            p.move(to: CGPoint(x: cx, y: cy + h / 2 + 4))
            p.addLine(to: CGPoint(x: cx, y: cy + h / 2 + 0.4))
        }
        ctx.stroke(botArrow, with: .color(PWTheme.red),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        let botHead = Path { p in
            p.move(to: CGPoint(x: cx - 1.5, y: cy + h / 2 + 1.6))
            p.addLine(to: CGPoint(x: cx, y: cy + h / 2 + 0.4))
            p.addLine(to: CGPoint(x: cx + 1.5, y: cy + h / 2 + 1.6))
        }
        ctx.stroke(botHead, with: .color(PWTheme.red),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
    }

    // MARK: P4 — 心律失常 (arrhythmic ECG)

    private func drawArrhythmia(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat) {
        let w: CGFloat = 24
        let h: CGFloat = 14
        let leftX = cx - w / 2

        // Baseline left + small P-QRS
        let baseLeft = Path { p in
            p.move(to: CGPoint(x: leftX, y: cy))
            p.addLine(to: CGPoint(x: leftX + 4, y: cy))
            p.addLine(to: CGPoint(x: leftX + 5.5, y: cy - 2))
            p.addLine(to: CGPoint(x: leftX + 7, y: cy + 1))
            p.addLine(to: CGPoint(x: leftX + 8, y: cy))
        }
        ctx.stroke(baseLeft, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))

        // Arrhythmic burst (red)
        let burst = Path { p in
            p.move(to: CGPoint(x: leftX + 8, y: cy))
            p.addLine(to: CGPoint(x: leftX + 9, y: cy))
            p.addLine(to: CGPoint(x: leftX + 10, y: cy - h / 2 + 1))
            p.addLine(to: CGPoint(x: leftX + 12, y: cy + h / 2 - 1))
            p.addLine(to: CGPoint(x: leftX + 13, y: cy - 3))
            p.addLine(to: CGPoint(x: leftX + 15, y: cy + 4))
            p.addLine(to: CGPoint(x: leftX + 16, y: cy - 2))
            p.addLine(to: CGPoint(x: leftX + 17, y: cy + 1))
            p.addLine(to: CGPoint(x: leftX + 18, y: cy))
        }
        ctx.stroke(burst, with: .color(PWTheme.red),
                   style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))

        // Baseline right
        let baseRight = Path { p in
            p.move(to: CGPoint(x: leftX + 18, y: cy))
            p.addLine(to: CGPoint(x: cx + w / 2, y: cy))
        }
        ctx.stroke(baseRight, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        // Mini heart icon top-left
        let hx = leftX
        let hy = cy - h / 2 - 4
        let heart = Path { p in
            p.move(to: CGPoint(x: hx + 2.5, y: hy + 3))
            p.addQuadCurve(to: CGPoint(x: hx - 0.5, y: hy - 0.5),
                           control: CGPoint(x: hx - 1, y: hy + 1.5))
            p.addQuadCurve(to: CGPoint(x: hx + 2.5, y: hy - 1),
                           control: CGPoint(x: hx + 1, y: hy - 2.5))
            p.addQuadCurve(to: CGPoint(x: hx + 5.5, y: hy - 0.5),
                           control: CGPoint(x: hx + 4, y: hy - 2.5))
            p.addQuadCurve(to: CGPoint(x: hx + 2.5, y: hy + 3),
                           control: CGPoint(x: hx + 6, y: hy + 1.5))
            p.closeSubpath()
        }
        ctx.fill(heart, with: .color(PWTheme.red))
    }

    // MARK: P5 — 可能晕厥 (figure collapsing)

    private func drawFainting(ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, t: Double) {
        let headR: CGFloat = 3.8
        let headX = cx - 5
        let headY = cy - 7

        // Head (filled circle)
        ctx.fill(
            Path(ellipseIn: CGRect(x: headX - headR, y: headY - headR,
                                    width: headR * 2, height: headR * 2)),
            with: .color(PWTheme.navy)
        )

        // Body curving down-right
        let body = Path { p in
            p.move(to: CGPoint(x: headX + 1, y: headY + headR + 0.5))
            p.addQuadCurve(to: CGPoint(x: cx + 4, y: cy + 4),
                           control: CGPoint(x: cx, y: cy))
        }
        ctx.stroke(body, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // Left arm flailing
        let armL = Path { p in
            p.move(to: CGPoint(x: headX - 0.5, y: cy - 2.5))
            p.addLine(to: CGPoint(x: headX - 6, y: cy - 1))
        }
        ctx.stroke(armL, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 1.0, lineCap: .round))

        // Right arm reaching
        let armR = Path { p in
            p.move(to: CGPoint(x: headX + 2, y: cy - 1))
            p.addLine(to: CGPoint(x: cx + 6, y: cy - 3))
        }
        ctx.stroke(armR, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 1.0, lineCap: .round))

        // Legs collapsing
        let legL = Path { p in
            p.move(to: CGPoint(x: cx + 4, y: cy + 4))
            p.addLine(to: CGPoint(x: cx + 1, y: cy + 10))
        }
        ctx.stroke(legL, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        let legR = Path { p in
            p.move(to: CGPoint(x: cx + 4, y: cy + 4))
            p.addLine(to: CGPoint(x: cx + 7, y: cy + 10))
        }
        ctx.stroke(legR, with: .color(PWTheme.navy),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        // Dizzy stars (pulsing)
        let pulse = 0.55 + 0.45 * sin(t * 4)
        ctx.draw(
            Text("✦")
                .font(.system(size: 6.5, weight: .black, design: .serif))
                .foregroundColor(PWTheme.red.opacity(pulse)),
            at: CGPoint(x: headX - 6, y: headY - 2), anchor: .center
        )
        ctx.draw(
            Text("✦")
                .font(.system(size: 5, weight: .black, design: .serif))
                .foregroundColor(PWTheme.red.opacity(0.7 * pulse)),
            at: CGPoint(x: headX + 6, y: headY - 4), anchor: .center
        )

        // subtle ground line
        let ground = Path { p in
            p.move(to: CGPoint(x: cx - 8, y: cy + 11.5))
            p.addLine(to: CGPoint(x: cx + 9, y: cy + 11.5))
        }
        ctx.stroke(ground, with: .color(PWTheme.navy.opacity(0.3)),
                   style: StrokeStyle(lineWidth: 0.7, dash: [1.5, 1.2]))
    }
}
