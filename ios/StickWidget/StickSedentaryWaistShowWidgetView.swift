import SwiftUI
import WidgetKit

// MARK: - 2x2 久坐点击钩子 Widget · "今晚腰会演哪一出"
//
// 设计来源: widget-designs/sedentary-click-hooks-stickman.html (Card 10)
// 蓝渐变 + 弯腰火柴人 + 黄色聚光打在腰上 + "小剧场"预告片钩子
// 正面是 teaser · 点开 app 看 "《明早起不来》 即将上映"

// MARK: - Entry

struct StickSedentaryWaistShowEntry: TimelineEntry {
    let date: Date
}

// MARK: - Provider

struct WaistShowProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickSedentaryWaistShowEntry {
        StickSedentaryWaistShowEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (StickSedentaryWaistShowEntry) -> Void) {
        completion(StickSedentaryWaistShowEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickSedentaryWaistShowEntry>) -> Void) {
        let now = Date()
        let entry = StickSedentaryWaistShowEntry(date: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Theme

private enum WaistShowTheme {
    static let ink     = Color(red: 0.082, green: 0.114, blue: 0.157)  // #151d28
    static let blueTop = Color(red: 0.682, green: 0.894, blue: 1.000)  // #aee4ff
    static let blueBot = Color(red: 0.365, green: 0.588, blue: 1.000)  // #5d96ff
    static let skin    = Color(red: 1.000, green: 0.957, blue: 0.843)  // #fff4d7
    static let white   = Color.white
    static let yellow  = Color(red: 1.000, green: 0.847, blue: 0.310)  // #ffd84f 聚光
    static let red     = Color(red: 0.86, green: 0.21, blue: 0.27)
}

// MARK: - Widget View

struct StickSedentaryWaistShowWidgetView: View {
    let entry: StickSedentaryWaistShowEntry

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // 4pt 黑色描边
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(WaistShowTheme.ink, lineWidth: 3.5)
                VStack(alignment: .leading, spacing: 4) {
                    topRow(t: t)
                    WaistShowStage(t: t)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                    hookBox
                }
                .padding(7)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [WaistShowTheme.blueTop, WaistShowTheme.blueBot],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: top: 小剧场 ......... [新]  [腰]

    private func topRow(t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            HStack {
                Text("小剧场")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(WaistShowTheme.ink)
                Spacer()
            }
            HStack {
                Spacer()
                Text("新")
                    .font(.system(size: 7.5, weight: .black, design: .rounded))
                    .foregroundColor(WaistShowTheme.ink)
                    .frame(width: 20, height: 17)
                    .background(WaistShowTheme.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(WaistShowTheme.ink, lineWidth: 2.2))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 2)
            }
            // 右上角 "腰" bubble（HTML card 10)
            Text("腰")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundColor(WaistShowTheme.ink)
                .frame(width: 22, height: 17)
                .background(WaistShowTheme.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(WaistShowTheme.ink, lineWidth: 1.6))
                .offset(x: 26, y: 0)
        }
        .frame(height: 20)
    }

    // MARK: hook box: 今晚腰会演 / 哪一出？

    private var hookBox: some View {
        HStack {
            VStack(alignment: .leading, spacing: -1) {
                Text("今晚腰会演")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(WaistShowTheme.ink)
                HStack(spacing: 3) {
                    Text("哪一出")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(WaistShowTheme.ink)
                    Text("？")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(WaistShowTheme.red)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(WaistShowTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(WaistShowTheme.ink, lineWidth: 3))
        .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 4)
    }
}

// MARK: - Stage · 弯腰火柴人 + 黄色腰聚光 + 飞手

struct WaistShowStage: View {
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

            let ink = WaistShowTheme.ink
            let skin = WaistShowTheme.skin
            let yellow = WaistShowTheme.yellow

            // ---- 身体（弯曲线：56 49 Q63 65 74 79） ----
            var body = Path()
            body.move(to: p(56, 49))
            body.addQuadCurve(to: p(74, 79), control: p(63, 65))
            ctx.stroke(
                body,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 左臂（68 64 L 48 76） ----
            var armL = Path()
            armL.move(to: p(68, 64))
            armL.addLine(to: p(48, 76))
            ctx.stroke(
                armL,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 右臂（74 78 L 91 70） ----
            var armR = Path()
            armR.move(to: p(74, 78))
            armR.addLine(to: p(91, 70))
            ctx.stroke(
                armR,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 双腿（弯腰后的站姿） ----
            var legL = Path()
            legL.move(to: p(75, 79))
            legL.addLine(to: p(63, 109))
            ctx.stroke(
                legL,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )
            var legR = Path()
            legR.move(to: p(76, 79))
            legR.addLine(to: p(94, 107))
            ctx.stroke(
                legR,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(3.2), lineCap: .round, lineJoin: .round)
            )

            // ---- 头（微低） ----
            let headR = s(16)
            let headPt = p(55, 32)
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

            // ---- 困倦眼（X X 简化成两小斜线） ----
            var eyeL = Path()
            eyeL.move(to: p(48, 31))
            eyeL.addLine(to: p(53, 35))
            ctx.stroke(
                eyeL,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2), lineCap: .round)
            )
            var eyeR = Path()
            eyeR.move(to: p(65, 31))
            eyeR.addLine(to: p(61, 35))
            ctx.stroke(
                eyeR,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2), lineCap: .round)
            )
            // 嘴（小曲线 - 不情愿）
            var mouth = Path()
            mouth.move(to: p(50, 44))
            mouth.addQuadCurve(to: p(63, 44), control: p(56, 40))
            ctx.stroke(
                mouth,
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2), lineCap: .round)
            )

            // ---- 黄色腰聚光（在身体弯折处）· 脉冲 ----
            let pulse = 0.8 + 0.2 * sin(t * 2.5)
            let spotR = s(7) * pulse
            let spotPt = p(74, 67)
            // 外层辐射环
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: spotPt.x - spotR * 1.5, y: spotPt.y - spotR * 1.5,
                    width: spotR * 3, height: spotR * 3
                )),
                with: .color(yellow.opacity(0.25))
            )
            // 内层实心
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: spotPt.x - spotR, y: spotPt.y - spotR,
                    width: spotR * 2, height: spotR * 2
                )),
                with: .color(yellow)
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: spotPt.x - spotR, y: spotPt.y - spotR,
                    width: spotR * 2, height: spotR * 2
                )),
                with: .color(ink),
                style: StrokeStyle(lineWidth: s(2.5))
            )

            // ---- 飞出的"X"标（痛点） ----
            let xPulse = 0.5 + 0.5 * sin(t * 4)
            ctx.draw(
                Text("×")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(WaistShowTheme.red.opacity(xPulse)),
                at: p(108, 38), anchor: .center
            )
            ctx.draw(
                Text("!")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(WaistShowTheme.red.opacity(xPulse * 0.8)),
                at: p(8, 50), anchor: .center
            )
        }
    }
}
