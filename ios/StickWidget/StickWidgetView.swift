import SwiftUI
import WidgetKit

// MARK: - Entry

struct StickEntry: TimelineEntry {
    let date: Date
    let state: SharedStickState
}

// MARK: - Provider

struct StickProvider: TimelineProvider {
    func placeholder(in context: Context) -> StickEntry {
        StickEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StickEntry) -> Void) {
        completion(StickEntry(date: Date(), state: SharedStateStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StickEntry>) -> Void) {
        let now = Date()
        let entry = StickEntry(date: now, state: SharedStateStore.read())
        let next = now.addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget View (2x2 systemSmall)
// 由 widget target 和主 app 共享，widget target 用 @main 装载，主 app 直接渲染预览。

struct StickWidgetView: View {
    let entry: StickEntry
    private var s: SharedStickState { entry.state }
    private var stateRaw: String { s.stateRaw }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(s.englishName)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Theme.navy)
                Spacer(minLength: 0)
            }

            MiniFigure(stateRaw: stateRaw, accent: accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 50)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(s.actionPhrase)
                    .font(.system(size: 14, weight: .black, design: .serif))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                    Text("\(s.heartRate)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.navy)
                }
                Text("·")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Theme.mist)
                Text(s.mood)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundColor(Theme.slate)
                    .lineLimit(1)
                Spacer(minLength: 0)
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
}

// MARK: - 迷你火柴人

struct MiniFigure: View {
    let stateRaw: String
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            let stroke = Theme.navy
            let w: CGFloat = 1.6
            let midX = size.width / 2

            switch stateRaw {
            case "walk":
                ctx.fill(
                    Path(ellipseIn: CGRect(x: midX - 6, y: 2, width: 12, height: 12)),
                    with: .color(stroke)
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 14))
                        p.addLine(to: CGPoint(x: midX, y: 32))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 20))
                        p.addLine(to: CGPoint(x: midX + 10, y: 26))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 20))
                        p.addLine(to: CGPoint(x: midX - 10, y: 28))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 32))
                        p.addLine(to: CGPoint(x: midX + 8, y: 44))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 32))
                        p.addLine(to: CGPoint(x: midX - 6, y: 44))
                    },
                    with: .color(stroke), lineWidth: w
                )
            case "sit":
                ctx.fill(
                    Path(ellipseIn: CGRect(x: midX - 6, y: 2, width: 12, height: 12)),
                    with: .color(stroke)
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX, y: 14))
                        p.addLine(to: CGPoint(x: midX + 4, y: 32))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX + 4, y: 22))
                        p.addLine(to: CGPoint(x: midX + 16, y: 30))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX + 4, y: 32))
                        p.addLine(to: CGPoint(x: midX + 22, y: 32))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX + 22, y: 32))
                        p.addLine(to: CGPoint(x: midX + 22, y: 44))
                    },
                    with: .color(stroke), lineWidth: w
                )
            case "sleep":
                ctx.fill(
                    Path(ellipseIn: CGRect(x: midX - 14, y: 16, width: 12, height: 12)),
                    with: .color(stroke)
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX - 2, y: 22))
                        p.addLine(to: CGPoint(x: midX + 22, y: 24))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX + 22, y: 24))
                        p.addLine(to: CGPoint(x: midX + 28, y: 30))
                    },
                    with: .color(stroke), lineWidth: w
                )
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: midX - 2, y: 22))
                        p.addLine(to: CGPoint(x: midX - 10, y: 18))
                    },
                    with: .color(stroke), lineWidth: w
                )
            default:
                break
            }
        }
    }
}
