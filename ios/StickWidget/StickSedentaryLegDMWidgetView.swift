import SwiftUI
import WidgetKit

// MARK: - 2x2 久坐点击钩子 Widget · "腿给你发了一条私信"
//
// 设计来源: widget-designs/sedentary-click-hooks-stickman.html (Card 1)
// 蓝渐变 + 火柴人 + 信封 + "新"角标 + 大钩子文案
// 正面是 teaser · 点开 app 看 "想你了，走两步见我。"

// MARK: - Entry

struct StickSedentaryLegDMEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct LegDMProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickSedentaryLegDMEntry {
        StickSedentaryLegDMEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (StickSedentaryLegDMEntry) -> Void) {
        completion(StickSedentaryLegDMEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickSedentaryLegDMEntry>) -> Void) {
        let now = Date()
        let entry = StickSedentaryLegDMEntry(date: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Theme

private enum LegDMTheme {
    static let ink     = Color(red: 0.082, green: 0.114, blue: 0.157)  // #151d28
    static let blueTop = Color(red: 0.682, green: 0.894, blue: 1.000)  // #aee4ff
    static let blueBot = Color(red: 0.365, green: 0.588, blue: 1.000)  // #5d96ff
    static let skin    = Color(red: 1.000, green: 0.957, blue: 0.843)  // #fff4d7
    static let white   = Color.white
    static let pink    = Color(red: 1.000, green: 0.361, blue: 0.604)  // #ff5c9a
}

// MARK: - Widget View

struct StickSedentaryLegDMWidgetView: View {
    let entry: StickSedentaryLegDMEntry

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // 4pt 黑色描边
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(LegDMTheme.ink, lineWidth: 3.5)
                VStack(alignment: .leading, spacing: 4) {
                    topRow(t: t)
                    LegDMStage(t: t)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                    hookBox
                }
                .padding(7)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [LegDMTheme.blueTop, LegDMTheme.blueBot],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: top: 身体私信 ......... [1]

    private func topRow(t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            HStack {
                Text("身体私信")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(LegDMTheme.ink)
                Spacer()
            }
            HStack {
                Spacer()
                Text("1")
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundColor(LegDMTheme.ink)
                    .frame(width: 22, height: 17)
                    .background(LegDMTheme.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(LegDMTheme.ink, lineWidth: 2.2))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            }
            // 右上角 "新" bubble（HTML 1)
            Text("新")
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .foregroundColor(LegDMTheme.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(LegDMTheme.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LegDMTheme.ink, lineWidth: 1.6))
                .offset(x: 28, y: -2)
        }
        .frame(height: 20)
    }

    // MARK: hook box: 腿给你发了 / 一条私信

    private var hookBox: some View {
        HStack {
            VStack(alignment: .leading, spacing: -1) {
                Text("腿给你发了")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(LegDMTheme.ink)
                Text("一条私信")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(LegDMTheme.pink)
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(LegDMTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(LegDMTheme.ink, lineWidth: 3))
        .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 4)
    }
}

// MARK: - Stage · 火柴人 + 信封 + 飞心

struct LegDMStage: View {
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / 120
            let ox = (size.width - 120 * scale) / 2
            let oy = (size.height - 120 * scale) / 2
            let p: (CGFloat, CGFloat) -> CGPoint = { x, y in
                CGPoint(x: ox + x * scale, y: oy + y * scale)
            }
            let s: (CGFloat) -> CGFloat = { v in v * scale }

            let ink = LegDMTheme.ink
            let skin = LegDMTheme.skin
            let white = LegDMTheme.white
            let pink = LegDMTheme.pink

            // ---- 信封 (top-right) ----
            let envRect = CGRect(
                x: ox + 69 * scale,
                y: oy + 24 * scale,
                width: 32 * scale,
                height: 24 * scale
            )
            ctx.fill(Path(roundedRect: envRect, cornerRadius: s(5)), with: .color(white))
            ctx.stroke(
                Path(roundedRect: envRect, cornerRadius: s(5)),
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2.5), lineJoin: .round)
            )
            // 信封 V flap
            var flap = Path()
            flap.move(to: p(71, 28))
            flap.addLine(to: p(85, 41))
            flap.addLine(to: p(99, 28))
            ctx.stroke(
                flap,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(1.8), lineJoin: .round)
            )

            // ---- 火柴人身体主线 ----
            var body = Path()
            body.move(to: p(50, 53))
            body.addLine(to: p(50, 77))
            ctx.stroke(
                body,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 右臂（向上伸够信封） ----
            var armR = Path()
            armR.move(to: p(50, 63))
            armR.addLine(to: p(69, 48))
            ctx.stroke(
                armR,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 左臂（向下） ----
            var armL = Path()
            armL.move(to: p(50, 63))
            armL.addLine(to: p(32, 75))
            ctx.stroke(
                armL,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 双腿 ----
            var legL = Path()
            legL.move(to: p(50, 77))
            legL.addLine(to: p(34, 105))
            ctx.stroke(
                legL,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )
            var legR = Path()
            legR.move(to: p(51, 77))
            legR.addLine(to: p(73, 103))
            ctx.stroke(
                legR,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 头 ----
            let headR = s(17)
            let headPt = p(49, 36)
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: headPt.x - headR, y: headPt.y - headR,
                    width: headR * 2, height: headR * 2
                )),
                with: .color(skin)
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: headPt.x - headR, y: headPt.y - headR,
                    width: headR * 2, height: headR * 2
                )),
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineJoin: .round)
            )

            // ---- 眼睛 ----
            let eyeR = s(2.5)
            let eyeL = p(43, 34)
            let eyeR2 = p(55, 34)
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: eyeL.x - eyeR, y: eyeL.y - eyeR,
                    width: eyeR * 2, height: eyeR * 2
                )),
                with: .color(ink)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: eyeR2.x - eyeR, y: eyeR2.y - eyeR,
                    width: eyeR * 2, height: eyeR * 2
                )),
                with: .color(ink)
            )

            // ---- 微笑（嘴） ----
            var smile = Path()
            smile.move(to: p(43, 46))
            smile.addQuadCurve(to: p(56, 46), control: p(49, 52))
            ctx.stroke(
                smile,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2), lineCap: .round)
            )

            // ---- 飞心（脉冲） ----
            let heartAlpha = 0.55 + 0.45 * sin(t * 3.2)
            // main heart
            let hx = p(105, 22)
            let hSize = s(6)
            let heart = Path { pth in
                pth.move(to: CGPoint(x: hx.x, y: hx.y + hSize * 0.4))
                pth.addQuadCurve(
                    to: CGPoint(x: hx.x - hSize, y: hx.y - hSize * 0.1),
                    control: CGPoint(x: hx.x - hSize * 1.2, y: hx.y + hSize * 0.4)
                )
                pth.addQuadCurve(
                    to: CGPoint(x: hx.x, y: hx.y - hSize * 0.8),
                    control: CGPoint(x: hx.x - hSize * 0.5, y: hx.y - hSize * 1.2)
                )
                pth.addQuadCurve(
                    to: CGPoint(x: hx.x + hSize, y: hx.y - hSize * 0.1),
                    control: CGPoint(x: hx.x + hSize * 0.5, y: hx.y - hSize * 1.2)
                )
                pth.addQuadCurve(
                    to: CGPoint(x: hx.x, y: hx.y + hSize * 0.4),
                    control: CGPoint(x: hx.x + hSize * 1.2, y: hx.y + hSize * 0.4)
                )
            }
            ctx.fill(heart, with: .color(pink.opacity(heartAlpha)))
            ctx.stroke(
                heart,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2), lineJoin: .round)
            )
        }
    }
}
