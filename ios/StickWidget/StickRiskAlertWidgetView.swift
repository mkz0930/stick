import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 2x2 久坐血小板风险 Widget
// 血管横截面 + 血小板随时间累积 → 血栓风险
// 风格参考 widget-platelet-v3.html

struct StickRiskAlertEntry: TimelineEntry {
    let date: Date
    let sitDurationMinutes: Int
    let heartRate: Int
}

struct RiskAlertProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickRiskAlertEntry {
        StickRiskAlertEntry(date: Date(), sitDurationMinutes: 90, heartRate: 75)
    }
    func getSnapshot(in context: Context, completion: @escaping (StickRiskAlertEntry) -> Void) {
        completion(StickRiskAlertEntry(date: Date(), sitDurationMinutes: 90, heartRate: 75))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickRiskAlertEntry>) -> Void) {
        let now = Date()
        let entry = StickRiskAlertEntry(date: now, sitDurationMinutes: 90, heartRate: 75)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

// MARK: - AppIntent：点击 widget 弹久坐风险告警 sheet
// 走 App Intents 路径不弹 "在 'Stick' 中打开?" 系统确认框

struct OpenRiskAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "打开久坐风险告警"
    static var description = IntentDescription("直接弹出久坐风险告警 sheet")

    @Parameter(title: "久坐分钟")
    var sitDurationMinutes: Int

    @Parameter(title: "心率")
    var heartRate: Int

    init() {
        self.sitDurationMinutes = 0
        self.heartRate = 0
    }

    init(sitDurationMinutes: Int, heartRate: Int) {
        self.sitDurationMinutes = sitDurationMinutes
        self.heartRate = heartRate
    }

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // 写 chat seed 格式 → 主 app 走 drainPendingChatSeed → openChat → ChatOverlay
        // riskSeed 格式 "久坐风险提醒:XX分钟" 触发 ChatOverlay.generateRiskAnalysis（AI 自动回答）
        SharedStateStore.writePendingChatSeed("久坐风险提醒:\(sitDurationMinutes)分钟")
        return .result()
    }
}

// MARK: - AppIntent：点击 widget 聊天入口 → 打开风险科普对话
// 写 seed 到 SharedState，主 app 读取后打开 ChatOverlay，走专属风险科普 prompt

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "打开健康助手"
    static var description = IntentDescription("打开聊天，触发健康风险科普流程")

    @Parameter(title: "Seed")
    var seed: String

    init() {
        self.seed = ""
    }

    init(seed: String) {
        self.seed = seed
    }

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedStateStore.writePendingChatSeed(seed)
        return .result()
    }
}

// MARK: - View

struct StickRiskAlertWidgetView: View {
    let entry: StickRiskAlertEntry

    var body: some View {
        // 按 widget-platelet-v3.html 设计：标题 + 血管图上下布局
        Button(intent: OpenChatIntent(seed: "久坐风险提醒:\(entry.sitDurationMinutes)分钟")) {
            VStack(spacing: 14) {
                // 标题区
                Text("久坐")
                    .font(.system(size: 56, weight: .black))
                    .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .tracking(-2)  // letter-spacing: -2px

                // 血管图：宽度撑满，高度按 2:1 比例自动计算（匹配 HTML vessel-svg: width:100%; height:auto）
                VesselCanvas(duration: entry.sitDurationMinutes)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2/1, contentMode: .fit)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 1.0, green: 0.97, blue: 0.91))
    }
}

// MARK: - 血管 Canvas
// SVG viewBox 320×160，跟 HTML widget-platelet-v3.html 完全一致

private struct VesselCanvas: View {
    let duration: Int  // 久坐分钟数

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let SVG_W: CGFloat = 320
                let SVG_H: CGFloat = 160

                // 等比缩放：SVG 坐标 → canvas 像素
                let scaleX = size.width / SVG_W
                let scaleY = size.height / SVG_H
                let scale  = min(scaleX, scaleY)  // 保证不变形，y 方向可能有边距

                func sx(_ x: CGFloat) -> CGFloat { x * scale }
                func sy(_ y: CGFloat) -> CGFloat { y * scale }
                let sw: (CGFloat) -> CGFloat = { $0 * scale }

                let dark         = Color(red: 0.10, green: 0.10, blue: 0.12)
                let vesselFill   = Color(red: 1.0,  green: 0.89, blue: 0.82)  // #FFE4D0
                let vesselInner  = Color(red: 1.0,  green: 0.80, blue: 0.66)  // #FFCBA8
                let plateletRed  = Color(red: 1.0,  green: 0.30, blue: 0.18)  // #FF4D2E
                let clotRed      = Color(red: 0.79, green: 0.16, blue: 0.0)   // #C92A00

                // ── 血管外壁 ──
                let outer = Path { p in
                    p.move(to: CGPoint(x: sx(20), y: sy(100)))
                    p.addLine(to: CGPoint(x: sx(20), y: sy(70)))
                    p.addQuadCurve(to: CGPoint(x: sx(35), y: sy(55)),
                                   control: CGPoint(x: sx(20),  y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(285), y: sy(55)))
                    p.addQuadCurve(to: CGPoint(x: sx(300), y: sy(70)),
                                   control: CGPoint(x: sx(300), y: sy(55)))
                    p.addLine(to: CGPoint(x: sx(300), y: sy(130)))
                    p.addQuadCurve(to: CGPoint(x: sx(285), y: sy(145)),
                                   control: CGPoint(x: sx(300), y: sy(145)))
                    p.addLine(to: CGPoint(x: sx(35), y: sy(145)))
                    p.addQuadCurve(to: CGPoint(x: sx(20), y: sy(130)),
                                   control: CGPoint(x: sx(20),  y: sy(145)))
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

                // ── 时间刻度线 + 标签 ──
                let markers: [(x: CGFloat, label: String, isWarn: Bool)] = [
                    (55,  "0'",   false),
                    (115, "30'",  false),
                    (175, "60'",  false),
                    (235, "90'",  false),
                    (280, "120'", true),
                ]
                for m in markers {
                    let x = sx(m.x)
                    let color = m.isWarn ? plateletRed : dark.opacity(0.3)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: sy(55)))
                    line.addLine(to: CGPoint(x: x, y: sy(145)))
                    ctx.stroke(line, with: .color(color),
                               style: StrokeStyle(lineWidth: m.isWarn ? sw(1.5) : sw(1),
                                                   dash: [sw(2), sw(3)]))

                    // 标签在血管上方 (SVG y=48)
                    let label = Text(m.label)
                        .font(.system(size: 11 * scaleX, weight: m.isWarn ? .heavy : .bold,
                                     design: .monospaced))
                        .foregroundColor(m.isWarn ? plateletRed : dark.opacity(0.6))
                    ctx.draw(label, at: CGPoint(x: x, y: sy(48)), anchor: .center)

                    // "正常" 在血管下方 (SVG y=158)
                    if m.x == 55 {
                        let normalLabel = Text("正常")
                            .font(.system(size: 9 * scaleX, weight: .bold, design: .monospaced))
                            .foregroundColor(dark.opacity(0.5))
                        ctx.draw(normalLabel, at: CGPoint(x: x, y: sy(158)), anchor: .center)
                    }
                }

                // ── 根据 duration 显示血小板 ──
                let steps: Int
                if duration >= 120 { steps = 4 }
                else if duration >= 90  { steps = 3 }
                else if duration >= 60  { steps = 2 }
                else if duration >= 30  { steps = 1 }
                else                   { steps = 0 }

                if steps >= 1 {
                    // 0' — 1 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(53),  y: sy(100)), r: sw(6),   color: plateletRed, scale: scaleX)
                }
                if steps >= 2 {
                    // 30' — 3 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(115), y: sy(93)),  r: sw(5.5), color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(127), y: sy(105)), r: sw(5),   color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(103), y: sy(103)), r: sw(4.5), color: plateletRed, scale: scaleX)
                }
                if steps >= 3 {
                    // 60' — 6 颗
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(175), y: sy(90)),  r: sw(5),   color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(187), y: sy(100)), r: sw(5.5), color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(180), y: sy(110)), r: sw(5),   color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(167), y: sy(100)), r: sw(4),   color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(195), y: sy(95)),  r: sw(4),   color: plateletRed, scale: scaleX)
                    drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(165), y: sy(110)), r: sw(3.5), color: plateletRed, scale: scaleX)
                }
                if steps >= 4 {
                    // 90' — 10 颗 (完整)
                    let pos90: [(CGFloat, CGFloat)] = [
                        (235, 88), (247, 96), (230, 98), (252, 106),
                        (240, 105), (225, 105), (256, 98), (234, 110), (249, 90), (243, 98),
                    ]
                    let radii90: [CGFloat] = [5, 5, 5, 5, 4.5, 3.5, 3.5, 3, 3, 4]
                    for (i, (px, py)) in pos90.enumerated() {
                        drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(radii90[i]), color: plateletRed, scale: scaleX)
                    }

                    // 120' — 血栓 10 颗
                    let clot: [(CGFloat, CGFloat)] = [
                        (278, 85), (285, 93), (280, 100), (286, 105),
                        (278, 110), (288, 110), (290, 100), (284, 89), (292, 108), (295, 96),
                    ]
                    let radiiClot: [CGFloat] = [4.5, 4.5, 5, 4.5, 4.5, 3.5, 3, 3, 2.5, 2.5]
                    for (i, (px, py)) in clot.enumerated() {
                        drawPlatelet(ctx: &ctx, at: CGPoint(x: sx(px), y: sy(py)), r: sw(radiiClot[i]), color: clotRed, scale: scaleX)
                    }

                    // ── 血栓! 爆炸标 ──
                    let badgeCenter = CGPoint(x: sx(285), y: sy(100))
                    let badgeR = sw(26)
                    let badge = Path(ellipseIn: CGRect(
                        x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR,
                        width: badgeR * 2, height: badgeR * 2))
                    ctx.fill(badge, with: .color(plateletRed))
                    ctx.stroke(badge, with: .color(dark), lineWidth: sw(3.5))
                    let badgeText = Text("血栓!")
                        .font(.system(size: 16 * scaleX, weight: .heavy, design: .rounded))
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

// MARK: - Preview

struct StickRiskAlertWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        StickRiskAlertWidgetView(entry: StickRiskAlertEntry(date: .now, sitDurationMinutes: 90, heartRate: 75))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
