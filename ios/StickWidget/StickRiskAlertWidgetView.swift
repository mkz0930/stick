import SwiftUI
import WidgetKit

// MARK: - 2x2 风险告警 Widget（腰肌劳损 / 直不起腰 主题）
// 夸张版：久坐 → 腰椎间盘警告 → 弯腰火柴人 + 红色痛点 + 闪电
// 提示用户立刻站直 / 甩腰 / 捶后背

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

    private var riskLevel: (label: String, color: Color, emoji: String) {
        let min = entry.sitDurationMinutes
        if min >= 75 { return ("🚨 腰要断了", Color(red: 0.82, green: 0.10, blue: 0.10), "🚨") }
        if min >= 60 { return ("⚠️ 腰肌劳损", Color(red: 0.92, green: 0.22, blue: 0.15), "⚠️") }
        if min >= 45 { return ("⚠️ 腰开始抗议", Color(red: 0.96, green: 0.45, blue: 0.05), "⚠") }
        if min >= 30 { return ("⏰ 该动动了", Color(red: 0.95, green: 0.65, blue: 0.05), "⏰") }
        return ("⏰ 该动动了", Color(red: 0.95, green: 0.70, blue: 0.10), "⏰")
    }

    private var subtitle: String {
        let m = entry.sitDurationMinutes
        if m >= 75 { return "腰椎间盘在哭泣" }
        if m >= 60 { return "直不起腰 · 腰椎在报警" }
        if m >= 45 { return "腰肌开始痉挛" }
        if m >= 30 { return "血液不流通了" }
        return "坐太久了"
    }

    private var cta: String {
        let m = entry.sitDurationMinutes
        if m >= 60 { return "🚑 站起来 · 甩甩腰" }
        if m >= 45 { return "🚶 拍腰 · 伸懒腰" }
        return "🚶 动动腿"
    }

    var body: some View {
        ZStack {
            // 背景：危险时偏红，警告时偏橙
            LinearGradient(
                colors: riskGradient(),
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                // 顶 row：闪电 + 风险等级 + 久坐时间
                HStack(spacing: 3) {
                    BoltFlash(color: riskLevel.color, t: entry.date.timeIntervalSinceReferenceDate)
                        .frame(width: 11, height: 11)
                    Text(riskLevel.label)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(riskLevel.color)
                    Spacer(minLength: 0)
                    Text("坐 \(entry.sitDurationMinutes)m")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                }

                // 弯腰火柴人 + 脊椎痛点
                WidgetHunchedBackFigure(
                    t: entry.date.timeIntervalSinceReferenceDate,
                    riskColor: riskLevel.color
                )
                .frame(maxWidth: .infinity)
                .frame(height: 56)

                // 标题
                Text("腰肌劳损！")
                    .font(.system(size: 14, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.45, green: 0.10, blue: 0.10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(subtitle)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(riskLevel.color.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

                // CTA 横幅
                HStack(spacing: 4) {
                    Text(cta)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(riskLevel.color)
                )
            }
            .padding(8)
        }
    }

    private func riskGradient() -> [Color] {
        let m = entry.sitDurationMinutes
        if m >= 75 {
            return [Color(red: 1.00, green: 0.92, blue: 0.90), Color(red: 0.98, green: 0.78, blue: 0.74)]
        } else if m >= 60 {
            return [Color(red: 1.00, green: 0.94, blue: 0.90), Color(red: 0.98, green: 0.82, blue: 0.76)]
        } else if m >= 45 {
            return [Color(red: 1.00, green: 0.96, blue: 0.90), Color(red: 0.98, green: 0.86, blue: 0.80)]
        } else {
            return [Color(red: 1.00, green: 0.97, blue: 0.92), Color(red: 0.98, green: 0.93, blue: 0.88)]
        }
    }
}

// MARK: - 闪电图标（脉冲）

struct BoltFlash: View {
    let color: Color
    let t: Double
    var body: some View {
        let pulse = 0.5 + 0.5 * sin(t * 5.0)
        Image(systemName: "bolt.fill")
            .font(.system(size: 10, weight: .black))
            .foregroundColor(color.opacity(0.7 + 0.3 * pulse))
    }
}

// MARK: - 弯腰火柴人 + 脊椎痛点

struct WidgetHunchedBackFigure: View {
    let t: Double
    let riskColor: Color

    var body: some View {
        Canvas { ctx, size in
            let stroke = Color(red: 0.10, green: 0.15, blue: 0.25)
            let w: CGFloat = 1.8
            let midX = size.width / 2

            // 头（低下来）
            let headY: CGFloat = 6
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 4, y: headY, width: 9, height: 9)), with: .color(stroke))

            // 身体 - 明显前倾（弯腰）
            let neck: CGPoint = CGPoint(x: midX, y: headY + 9)
            let shoulder: CGPoint = CGPoint(x: midX - 6, y: headY + 13)
            let spine1: CGPoint = CGPoint(x: midX - 8, y: headY + 20)
            let spine2: CGPoint = CGPoint(x: midX - 7, y: headY + 27)
            let hip: CGPoint = CGPoint(x: midX - 4, y: headY + 33)

            ctx.stroke(Path { p in
                p.move(to: neck)
                p.addLine(to: shoulder)
                p.addLine(to: spine1)
                p.addLine(to: spine2)
                p.addLine(to: hip)
            }, with: .color(stroke), lineWidth: w)

            // 头 - 肩的连接
            ctx.stroke(Path { p in
                p.move(to: neck)
                p.addLine(to: CGPoint(x: midX - 2, y: headY + 13))
            }, with: .color(stroke), lineWidth: w)

            // 双手撑腰（叉腰 / 托着腰）
            ctx.stroke(Path { p in
                p.move(to: spine1)
                p.addLine(to: CGPoint(x: midX - 14, y: headY + 17))
            }, with: .color(stroke), lineWidth: w)
            ctx.stroke(Path { p in
                p.move(to: spine1)
                p.addLine(to: CGPoint(x: midX - 1, y: headY + 17))
            }, with: .color(stroke), lineWidth: w)

            // 大腿（略微下倾）
            ctx.stroke(Path { p in
                p.move(to: hip)
                p.addLine(to: CGPoint(x: midX + 6, y: headY + 36))
            }, with: .color(stroke), lineWidth: w)
            // 小腿
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 6, y: headY + 36))
                p.addLine(to: CGPoint(x: midX + 6, y: size.height))
            }, with: .color(stroke), lineWidth: w)

            // 脊椎痛点 - 红点 + 闪电
            let pulse = 0.5 + 0.5 * sin(t * 4.5)
            let painX = midX - 7
            let painY = headY + 23

            // 痛点光晕
            ctx.fill(Path(ellipseIn: CGRect(x: painX - 8, y: painY - 6, width: 16, height: 12)),
                     with: .color(riskColor.opacity(0.25 + 0.15 * pulse)))

            // 痛点中心红点
            ctx.fill(Path(ellipseIn: CGRect(x: painX - 3, y: painY - 3, width: 6, height: 6)),
                     with: .color(riskColor))

            // 痛点周围的小痛点
            for i in 0..<3 {
                let dx: CGFloat = CGFloat(i - 1) * 5
                let dy: CGFloat = CGFloat(i % 2) * 3
                ctx.fill(Path(ellipseIn: CGRect(x: painX + dx - 1.5, y: painY + dy - 1.5, width: 3, height: 3)),
                         with: .color(riskColor.opacity(0.7)))
            }

            // 闪电 / 汗滴符号
            let boltPulse = 0.5 + 0.5 * sin(t * 6.0)
            if boltPulse > 0.3 {
                let bx = painX - 16
                let by = painY - 4
                // 闪电 z 字
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: bx, y: by))
                    p.addLine(to: CGPoint(x: bx - 2, y: by + 2))
                    p.addLine(to: CGPoint(x: bx, y: by + 4))
                    p.addLine(to: CGPoint(x: bx - 2, y: by + 6))
                }, with: .color(riskColor), lineWidth: 1.2)
            }

            // 汗滴（头右上）
            let sweatPulse = 0.5 + 0.5 * sin(t * 3.0 + 1.0)
            if sweatPulse > 0.2 {
                let sx = midX + 6
                let sy = headY + 2
                ctx.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: 2.5, height: 3)),
                         with: .color(riskColor.opacity(0.8)))
            }

            // 痛苦表情点（眼睛 x 嘴）
            ctx.fill(Path(ellipseIn: CGRect(x: midX - 2.5, y: headY + 4, width: 1, height: 1)),
                     with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: midX + 0.5, y: headY + 4, width: 1, height: 1)),
                     with: .color(.white))
            // 皱眉 - 两条斜线
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX - 3, y: headY + 3))
                p.addLine(to: CGPoint(x: midX - 1, y: headY + 3.5))
            }, with: .color(.white), lineWidth: 0.5)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: midX + 1, y: headY + 3.5))
                p.addLine(to: CGPoint(x: midX + 3, y: headY + 3))
            }, with: .color(.white), lineWidth: 0.5)
        }
    }
}
