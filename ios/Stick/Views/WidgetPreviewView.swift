import SwiftUI

/// Widget 预览：在 app 内直接渲染 2x2 systemSmall 效果，方便查看。
/// 状态：走 / 坐 / 睡（按按钮切换）。
struct WidgetPreviewView: View {
    var onClose: () -> Void

    @State private var selectedState: String = "walk"  // walk / sit / sleep

    private var state: SharedStickState {
        switch selectedState {
        case "sit":
            return SharedStickState(
                stateRaw: "sit",
                englishName: "SITTING",
                actionPhrase: "深度专注",
                heartRate: 78,
                mood: "一般",
                durationMinutes: 47,
                subLine: "久坐 47 分 · 颈椎前倾 +18°",
                updatedAt: Date()
            )
        case "sleep":
            return SharedStickState(
                stateRaw: "sleep",
                englishName: "SLEEPING",
                actionPhrase: "深度修复",
                heartRate: 56,
                mood: "良好",
                durationMinutes: 167,
                subLine: "已入睡 2 小时 47 分 · 深睡 1h32m",
                updatedAt: Date()
            )
        default:
            return SharedStickState(
                stateRaw: "walk",
                englishName: "WALKING",
                actionPhrase: "能量输出",
                heartRate: 92,
                mood: "良好",
                durationMinutes: 18,
                subLine: "步态稳定 · 心率 92 bpm",
                updatedAt: Date()
            )
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                DashedDivider()
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 22) {
                        // 真实 2x2 widget
                        StickWidgetView(entry: StickEntry(date: Date(), state: state))
                            .frame(width: 158, height: 158)
                            .scaleEffect(1.0)
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                            .padding(.top, 24)

                        // 状态切换
                        statePicker
                            .padding(.top, 18)
                            .padding(.horizontal, 20)

                        // 数据详情
                        dataDump
                            .padding(.top, 14)
                            .padding(.horizontal, 20)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            // brand mark
            ZStack {
                Circle().stroke(Theme.navy, lineWidth: 2).frame(width: 24, height: 24)
                Rectangle().fill(Theme.navy).frame(width: 10, height: 1.6)
                Rectangle().fill(Theme.navy).frame(width: 1.6, height: 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("ATLAS · WIDGET")
                    .font(.system(size: 14, weight: .black))
                    .tracking(0.1)
                    .foregroundColor(Theme.navy)
                Text("2x2 · DESKTOP PREVIEW")
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .tracking(0.2)
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var statePicker: some View {
        HStack(spacing: 6) {
            ForEach([
                ("walk",  "走 · WALK"),
                ("sit",   "坐 · SIT"),
                ("sleep", "睡 · SLEEP"),
            ], id: \.0) { (key, label) in
                Button {
                    selectedState = key
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(selectedState == key ? .white : Theme.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selectedState == key ? Theme.navy : Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dataDump: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE DATA · 当前 App Group 写入")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(Theme.slate)

            VStack(alignment: .leading, spacing: 4) {
                dataRow("stateRaw",    state.stateRaw)
                dataRow("englishName", state.englishName)
                dataRow("actionPhrase", state.actionPhrase)
                dataRow("heartRate",   "\(state.heartRate)")
                dataRow("mood",        state.mood)
                dataRow("durationMin", "\(state.durationMinutes)")
                dataRow("subLine",     state.subLine)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private func dataRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.slate)
                .frame(width: 110, alignment: .leading)
            Text(v)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.navy)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 虚线分隔

private struct DashedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(Theme.border, style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        .frame(height: 0.5)
    }
}
