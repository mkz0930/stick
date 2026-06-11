import SwiftUI
import WidgetKit

// MARK: - Medium Widget View（4×2，心情 + 状态告警）
// 与主 app 共享：stateRaw / mood / heartRate / durationMinutes。

struct StickMediumWidgetView: View {
    let entry: StickEntry
    private var s: SharedStickState { entry.state }
    private var stateRaw: String { s.stateRaw }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左半：状态 + 动作 + 心率
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    Text(s.englishName)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Theme.navy)
                }

                Text(s.actionPhrase)
                    .font(.system(size: 16, weight: .black, design: .serif))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // 迷你火柴人（紧凑）
                MiniFigure(stateRaw: stateRaw, accent: accentColor)
                    .frame(width: 70, height: 70)

                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                    Text("\(s.heartRate)")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.navy)
                    Text("bpm")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(Theme.slate)
                }
            }
            .frame(maxWidth: 100, alignment: .leading)

            // 分割
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 0.5)

            // 右半：心情趋势 + 告警
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 9))
                        .foregroundColor(accentColor)
                    Text("心情")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(Theme.slate)
                    Spacer(minLength: 0)
                    Text(s.mood)
                        .font(.system(size: 12, weight: .heavy, design: .serif))
                        .foregroundColor(Theme.navy)
                }

                // 心情折线图（按 stateRaw 合成 8 个数据点）
                MoodSparkline(values: moodHistory(), accent: accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)

                // 状态告警 / 状态良好
                AlertLine(stateRaw: stateRaw, durationMinutes: s.durationMinutes, accent: accentColor)
            }
        }
        .padding(10)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var accentColor: Color {
        switch stateRaw {
        case "sit":   return Color(red: 0.92, green: 0.34, blue: 0.05)
        case "sleep": return Color(red: 0.39, green: 0.40, blue: 0.95)
        default:      return Color(red: 0.02, green: 0.59, blue: 0.41)
        }
    }

    /// 按 stateRaw 合成 8 个心情数值（0-1，0.5 中性）
    private func moodHistory() -> [Double] {
        var rng = SeededRandom(seed: stateRaw.hashValue)
        var base: Double = 0.7  // walk 默认开心
        var drift: Double = 0.04
        switch stateRaw {
        case "walk":  base = 0.72; drift = 0.05
        case "sit":   base = 0.45; drift = -0.06
        case "sleep": base = 0.80; drift = 0.01
        default:      base = 0.6
        }
        return (0..<8).map { i in
            let v = base + Double(i) * drift + (rng.next() - 0.5) * 0.15
            return max(0.1, min(0.95, v))
        }
    }
}

// MARK: - 心情折线图

private struct MoodSparkline: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let midY = size.height * 0.5
            let amp = size.height * 0.4
            let stepX = size.width / CGFloat(values.count - 1)

            // 渐变填充区
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = midY - CGFloat(v - 0.5) * 2 * amp
                fillPath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()
            ctx.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [accent.opacity(0.28), accent.opacity(0.02)]),
                    startPoint: .init(x: 0, y: 0),
                    endPoint: .init(x: 0, y: size.height)
                )
            )

            // 折线
            var linePath = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = midY - CGFloat(v - 0.5) * 2 * amp
                if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
                else { linePath.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(linePath, with: .color(accent), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            // 末点
            if let last = values.last {
                let x = size.width
                let y = midY - CGFloat(last - 0.5) * 2 * amp
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                    with: .color(accent)
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                    with: .color(Theme.card)
                )
            }
        }
    }
}

// MARK: - 告警 / 状态行

private struct AlertLine: View {
    let stateRaw: String
    let durationMinutes: Int
    let accent: Color

    private var line: (icon: String, text: String, color: Color)? {
        switch stateRaw {
        case "sit":
            if durationMinutes >= 30 {
                return ("exclamationmark.triangle.fill", "久坐 \(durationMinutes) 分 · 建议起身", Color(red: 0.92, green: 0.34, blue: 0.05))
            }
            return nil
        case "walk":
            return nil
        case "sleep":
            if durationMinutes < 6 * 60 {
                return ("moon.zzz.fill", "入睡 \(durationMinutes) 分 · 浅睡", Color(red: 0.39, green: 0.40, blue: 0.95))
            }
            return ("checkmark.circle.fill", "深睡中 · 状态平稳", Color(red: 0.02, green: 0.59, blue: 0.41))
        default:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            if let l = line {
                Image(systemName: l.icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(l.color)
                Text(l.text)
                    .font(.system(size: 10, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(accent)
                Text("状态平稳 · 继续")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .foregroundColor(Theme.slate)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke((line?.color ?? Theme.border), lineWidth: 0.5)
        )
    }
}

// MARK: - 简易稳定随机（按 seed 可复现）

struct MiniFigure: View {
    let stateRaw: String
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            let midX = size.width / 2
            let stroke = Color.white.opacity(0.9)
            let w: CGFloat = 2
            let headR: CGFloat = min(size.width, size.height) * 0.12
            let headY = size.height * 0.25
            ctx.stroke(Path(ellipseIn: CGRect(x: midX - headR, y: headY - headR, width: headR * 2, height: headR * 2)),
                       with: .color(stroke), lineWidth: w)
            let bodyTop = CGPoint(x: midX, y: headY + headR)
            let bodyBot = CGPoint(x: midX, y: headY + headR + size.height * 0.35)
            var p = Path(); p.move(to: bodyTop); p.addLine(to: bodyBot)
            ctx.stroke(p, with: .color(stroke), lineWidth: w)
            var a = Path()
            a.move(to: CGPoint(x: midX - headR * 1.5, y: bodyTop.y + size.height * 0.1))
            a.addLine(to: CGPoint(x: midX + headR * 1.5, y: bodyTop.y + size.height * 0.1))
            ctx.stroke(a, with: .color(stroke), lineWidth: w)
            var l = Path(); var r = Path()
            switch stateRaw {
            case "walk":
                l.move(to: bodyBot); l.addLine(to: CGPoint(x: midX - size.width * 0.12, y: bodyBot.y + size.height * 0.25))
                r.move(to: bodyBot); r.addLine(to: CGPoint(x: midX + size.width * 0.12, y: bodyBot.y + size.height * 0.25))
            case "sit":
                l.move(to: bodyBot); l.addLine(to: CGPoint(x: midX - size.width * 0.18, y: bodyBot.y + size.height * 0.18))
                r.move(to: bodyBot); r.addLine(to: CGPoint(x: midX, y: bodyBot.y + size.height * 0.25))
            case "sleep":
                l.move(to: bodyBot); l.addLine(to: CGPoint(x: midX - size.width * 0.15, y: bodyBot.y + size.height * 0.25))
                r.move(to: bodyBot); r.addLine(to: CGPoint(x: midX + size.width * 0.15, y: bodyBot.y + size.height * 0.25))
            default:
                l.move(to: bodyBot); l.addLine(to: CGPoint(x: midX - size.width * 0.10, y: bodyBot.y + size.height * 0.30))
                r.move(to: bodyBot); r.addLine(to: CGPoint(x: midX + size.width * 0.10, y: bodyBot.y + size.height * 0.30))
            }
            ctx.stroke(l, with: .color(stroke), lineWidth: w)
            ctx.stroke(r, with: .color(stroke), lineWidth: w)
        }
    }
}

private struct SeededRandom {
    var state: UInt64
    init(seed: Int) { self.state = UInt64(bitPattern: Int64(seed)) &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
