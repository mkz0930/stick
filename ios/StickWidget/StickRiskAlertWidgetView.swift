import SwiftUI
import WidgetKit

// MARK: - 2x2 久坐血小板风险 Widget
// 血管横截面 + 血小板随时间累积 → 血栓风险
// 风格参考 design-demos 的 widget-platelet-v3.html（暖色卡 + 粗线条手绘感）

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
            // 标题行
            HStack(spacing: 0) {
                Text("久坐")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                Spacer(minLength: 0)
                Text("血小板累积")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // 血管图
            VesselCanvas(duration: entry.sitDurationMinutes)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(red: 1.0, green: 0.97, blue: 0.91) // #FFF7E8
        )
    }
}

// MARK: - 血管 Canvas

private struct VesselCanvas: View {
    let duration: Int  // 久坐分钟数

    var body: some View {
        Canvas { ctx, size in
            let sc = min(size.width, size.height) / 240

            let dark = Color(red: 0.10, green: 0.10, blue: 0.12)
            let vesselFill = Color(red: 1.0, green: 0.89, blue: 0.82)
            let vesselInner = Color(red: 1.0, green: 0.80, blue: 0.66)
            let plateletRed = Color(red: 1.0, green: 0.30, blue: 0.18)
            let clotRed = Color(red: 0.79, green: 0.16, blue: 0.0)

            func sx(_ x: CGFloat) -> CGFloat { x * sc }
            func sy(_ y: CGFloat) -> CGFloat { y * sc }
            let sw: (CGFloat) -> CGFloat = { $0 * sc }

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
            ctx.stroke(outer, with: .color(dark), lineWidth: sw(3))

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

                let label = Text(m.label)
                    .font(.system(size: 9 * sc, weight: m.isWarn ? .heavy : .bold, design: .monospaced))
                    .foregroundColor(m.isWarn ? plateletRed : dark.opacity(m.isWarn ? 0.8 : 0.5))
                ctx.draw(label, at: CGPoint(x: x, y: sy(48)), anchor: .center)

                if m.x == 55 {
                    let normalLabel = Text("正常")
                        .font(.system(size: 7 * sc, weight: .bold, design: .monospaced))
                        .foregroundColor(dark.opacity(0.4))
                    ctx.draw(normalLabel, at: CGPoint(x: x, y: sy(165)), anchor: .center)
                }
            }

            // ── 根据 duration 决定画多少血小板 ──
            let steps: Int
            if duration >= 120 { steps = 4 }
            else if duration >= 90 { steps = 3 }
            else if duration >= 60 { steps = 2 }
            else if duration >= 30 { steps = 1 }
            else { steps = 0 }

            if steps >= 1 {
                // 0' 位置: 1 颗
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(53), y: sy(100)), r: sw(5), color: plateletRed, scale: sc)
            }
            if steps >= 2 {
                // 30' 位置: 3 颗
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(115), y: sy(93)), r: sw(4.5), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(127), y: sy(105)), r: sw(4), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(103), y: sy(103)), r: sw(3.5), color: plateletRed, scale: sc)
            }
            if steps >= 3 {
                // 60' 位置: 6 颗
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(175), y: sy(90)), r: sw(4), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(187), y: sy(100)), r: sw(4.5), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(180), y: sy(110)), r: sw(4), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(167), y: sy(100)), r: sw(3.5), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(195), y: sy(95)), r: sw(3.5), color: plateletRed, scale: sc)
                drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(165), y: sy(110)), r: sw(3), color: plateletRed, scale: sc)
            }
            if steps >= 4 {
                // 90' 位置: ~9 颗
                let pos90: [(CGFloat, CGFloat)] = [
                    (235, 88), (247, 96), (230, 98), (252, 106),
                    (240, 105), (225, 105), (256, 98), (234, 110), (249, 90),
                ]
                for (px, py) in pos90 {
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(3 + CGFloat.random(in: 0...1)), color: plateletRed, scale: sc)
                }
                // 120' 位置: 血栓（砖红）
                let clot: [(CGFloat, CGFloat)] = [
                    (278, 85), (285, 93), (280, 100), (286, 105),
                    (278, 110), (288, 110), (290, 100), (284, 89), (292, 108), (295, 96),
                ]
                for (px, py) in clot {
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(3 + CGFloat.random(in: 0...1)), color: clotRed, scale: sc)
                }

                // ── 血栓! 红色爆炸标 ──
                let badgeCenter = CGPoint(x: sx(285), y: sy(100))
                let badgeR = sw(22)
                let badge = Path(ellipseIn: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR,
                                                    width: badgeR * 2, height: badgeR * 2))
                ctx.fill(badge, with: .color(plateletRed))
                ctx.stroke(badge, with: .color(dark), lineWidth: sw(3))
                let badgeText = Text("血栓!")
                    .font(.system(size: 13 * sc, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                ctx.draw(badgeText, at: CGPoint(x: badgeCenter.x, y: badgeCenter.y + sw(1)), anchor: .center)
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
