import SwiftUI
import WidgetKit

// MARK: - 2x2 久坐血小板风险 Widget
// 血管横截面 + 血小板随时间累积 → 血栓风险
// 风格参考 widget-platelet-v3.html（居中大字标题 + 暖色卡 + 粗线条手绘感）

struct StickRiskAlertEntry: TimelineEntry {
    let date: Date
    let sitDurationMinutes: Int
    let heartRate: Int
}

struct RiskAlertProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickRiskAlertEntry {
        StickRiskAlertEntry(date: Date(), sitDurationMinutes: 60, heartRate: 75)
    }
    func getSnapshot(in context: Context, completion: @escaping (StickRiskAlertEntry) -> Void) {
        completion(StickRiskAlertEntry(date: Date(), sitDurationMinutes: 60, heartRate: 75))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickRiskAlertEntry>) -> Void) {
        let now = Date()
        let entry = StickRiskAlertEntry(date: now, sitDurationMinutes: 60, heartRate: 75)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

// MARK: - View

struct StickRiskAlertWidgetView: View {
    let entry: StickRiskAlertEntry

    var body: some View {
        VStack(spacing: 0) {
            // 标题居中大字
            Text("久坐")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // 血管图（填满剩余空间）
            VesselCanvas(duration: entry.sitDurationMinutes)
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 1.0, green: 0.97, blue: 0.91)) // #FFF7E8
    }
}

// MARK: - 血管 Canvas
// viewBox 坐标系: 320×160，跟 HTML SVG 一致

private struct VesselCanvas: View {
    let duration: Int  // 久坐分钟数

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                // 坐标系跟 HTML SVG viewBox 320×160 对齐
                // x 轴: 0 → size.width
                // y 轴: 0 → size.height
                // 160/320 = 0.5，所以 y 坐标用 size.height * (svgY / 160)
                let svgH: CGFloat = 160

                func sx(_ x: CGFloat) -> CGFloat { x * size.width / 320 }
                func sy(_ y: CGFloat) -> CGFloat { y * size.height / svgH }
                let sw: (CGFloat) -> CGFloat = { $0 * size.width / 320 }

                let dark = Color(red: 0.10, green: 0.10, blue: 0.12)
                let vesselFill = Color(red: 1.0, green: 0.89, blue: 0.82)  // #FFE4D0
                let vesselInner = Color(red: 1.0, green: 0.80, blue: 0.66) // #FFCBA8
                let plateletRed = Color(red: 1.0, green: 0.30, blue: 0.18) // #FF4D2E
                let clotRed = Color(red: 0.79, green: 0.16, blue: 0.0) // #C92A00

                // ── 血管外壁 ──
                let outer = Path { p in
                    p.move(to: CGPoint(x: sx(20), y: sy(100)))
                    p.addLine(to: CGPoint(x: sx(20), y: sy(70)))
                    p.addQuadCurve(to: CGPoint(x: sx(35), y: sy(55)),
                                   control: CGPoint(x: sx(20), y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(285), y: sy(55)))
                    p.addQuadCurve(to: CGPoint(x: sx(300), y: sy(70)),
                                   control: CGPoint(x: sx(300), y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(300), y: sy(130)))
                    p.addQuadCurve(to: CGPoint(x: sx(285), y: sy(145)),
                                   control: CGPoint(x: sx(300), y: sy(145)))
                    p.addLine(to: CGPoint(x: sx(35), y: sy(145)))
                    p.addQuadCurve(to: CGPoint(x: sx(20), y: sy(130)),
                                   control: CGPoint(x: sx(20), y: sy(145)))
                    p.closeSubpath()
                }
                ctx.fill(outer, with: .color(vesselFill))
                ctx.stroke(outer, with: .color(dark), lineWidth: sw(3.5))

                // ── 血管内壁 ──
                let inner = Path { p in
                    p.move(to: CGPoint(x: sx(32), y: sy(100)))
                    p.addLine(to: CGPoint(x: sx(32), y: sy(77)))
                    p.addLine(to: CGPoint(x: sx(288), y: sy(77)))
                    p.addLine(to: CGPoint(x: sx(288), y: sy(123)))
                    p.addLine(to: CGPoint(x: sx(32), y: sy(123)))
                    p.closeSubpath()
                }
                ctx.fill(inner, with: .color(vesselInner))

                // ── 时间刻度 ──
                let markers: [(x: CGFloat, label: String, isWarn: Bool)] = [
                    (55, "0'", false),
                    (115, "30'", false),
                    (175, "60'", false),
                    (235, "90'", false),
                    (280, "120'", true),
                ]
                for m in markers {
                    let x = sx(m.x)
                    let color = m.isWarn ? plateletRed : dark.opacity(0.3)
                    let width: CGFloat = m.isWarn ? sw(1.5) : sw(1)
                    let dash: [CGFloat] = [sw(2), sw(3)]
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: sy(55)))
                    line.addLine(to: CGPoint(x: x, y: sy(145)))
                    ctx.stroke(line, with: .color(color),
                               style: StrokeStyle(lineWidth: width, dash: dash))

                    // 标签在血管上方 (y=48)
                    let label = Text(m.label)
                        .font(.system(size: 11 * size.width / 320, weight: m.isWarn ? .heavy : .bold, design: .monospaced))
                        .foregroundColor(m.isWarn ? plateletRed : dark.opacity(m.isWarn ? 0.8 : 0.6))
                    ctx.draw(label, at: CGPoint(x: x, y: sy(48)), anchor: .center)

                    // "正常" 在血管下方 (y=158)
                    if m.x == 55 {
                        let normalLabel = Text("正常")
                            .font(.system(size: 9 * size.width / 320, weight: .bold, design: .monospaced))
                            .foregroundColor(dark.opacity(0.5))
                        ctx.draw(normalLabel, at: CGPoint(x: x, y: sy(158)), anchor: .center)
                    }
                }

                // ── 根据 duration 决定画多少血小板 ──
                let steps: Int
                if duration >= 120 { steps = 4 }
                else if duration >= 90  { steps = 3 }
                else if duration >= 60  { steps = 2 }
                else if duration >= 30  { steps = 1 }
                else                   { steps = 0 }

                if steps >= 1 {
                    // 0' 位置: 1 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(53), y: sy(100)), r: sw(6), color: plateletRed, scale: size.width / 320)
                }
                if steps >= 2 {
                    // 30' 位置: 3 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(115), y: sy(93)), r: sw(5.5), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(127), y: sy(105)), r: sw(5), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(103), y: sy(103)), r: sw(4.5), color: plateletRed, scale: size.width / 320)
                }
                if steps >= 3 {
                    // 60' 位置: 6 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(175), y: sy(90)), r: sw(5), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(187), y: sy(100)), r: sw(5.5), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(180), y: sy(110)), r: sw(5), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(167), y: sy(100)), r: sw(4), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(195), y: sy(95)), r: sw(4), color: plateletRed, scale: size.width / 320)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(165), y: sy(110)), r: sw(3.5), color: plateletRed, scale: size.width / 320)
                }
                if steps >= 4 {
                    // 90' 位置: 10 颗 (完整版)
                    let pos90: [(CGFloat, CGFloat)] = [
                        (235, 88), (247, 96), (230, 98), (252, 106),
                        (240, 105), (225, 105), (256, 98), (234, 110), (249, 90), (243, 98),
                    ]
                    let radii90: [CGFloat] = [5, 5, 5, 5, 4.5, 3.5, 3.5, 3, 3, 4]
                    for (i, (px, py)) in pos90.enumerated() {
                        drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(radii90[i]), color: plateletRed, scale: size.width / 320)
                    }

                    // 120' 位置: 血栓（砖红）10 颗
                    let clot: [(CGFloat, CGFloat)] = [
                        (278, 85), (285, 93), (280, 100), (286, 105),
                        (278, 110), (288, 110), (290, 100), (284, 89), (292, 108), (295, 96),
                    ]
                    let radiiClot: [CGFloat] = [4.5, 4.5, 5, 4.5, 4.5, 3.5, 3, 3, 2.5, 2.5]
                    for (i, (px, py)) in clot.enumerated() {
                        drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(radiiClot[i]), color: clotRed, scale: size.width / 320)
                    }

                    // ── 血栓! 红色爆炸标 ──
                    let badgeCenter = CGPoint(x: sx(285), y: sy(100))
                    let badgeR = sw(26)
                    let badge = Path(ellipseIn: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR,
                                                       width: badgeR * 2, height: badgeR * 2))
                    ctx.fill(badge, with: .color(plateletRed))
                    ctx.stroke(badge, with: .color(dark), lineWidth: sw(3.5))
                    let badgeText = Text("血栓!")
                        .font(.system(size: 16 * size.width / 320, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    ctx.draw(badgeText, at: CGPoint(x: badgeCenter.x, y: badgeCenter.y + sw(2)), anchor: .center)
                }
            }
        }
    }

    private func drawPlatelet(ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color, scale: CGFloat) {
        let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(Color(red: 0.10, green: 0.10, blue: 0.12)),
                   lineWidth: max(1, 2 * scale))
    }
}
