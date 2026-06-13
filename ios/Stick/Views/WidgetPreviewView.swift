import SwiftUI

/// Widget 预览页：在主 app 内展示小部件 + 中型部件的样子，引导用户去主屏添加。
/// 渲染用真实 SwiftUI view（跟 widget target 里用同一份 view），所以预览就是真实呈现。
struct WidgetPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 说明
                    header
                    // 2x2 小部件
                    sectionHeader("SMALL · 2×2", subtitle: "主屏小方块")
                    widgetFrame {
                        WidgetPreviewSmall()
                    }
                    // 4x2 中型部件
                    sectionHeader("MEDIUM · 4×2", subtitle: "主屏宽矩形")
                    widgetFrame {
                        WidgetPreviewMedium()
                    }
                    // 添加引导
                    addInstruction
                }
                .padding(20)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("Widget 预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WIDGET 预览")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.slate)
            Text("在主屏长按空白处 → "+" → 搜 Stick → 选尺寸")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundColor(Theme.navy)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Theme.slate)
            Text(subtitle)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundColor(Theme.mist)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 模拟主屏 widget 容器：圆角 + 微阴影（让 widget 看着像贴在主屏上）
    private func widgetFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
            )
    }

    private var addInstruction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添加步骤")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(Theme.slate)
            VStack(alignment: .leading, spacing: 6) {
                instructionRow(num: "1", text: "返回主屏，长按空白处或图标")
                instructionRow(num: "2", text: "点击左上角 \"+\" 进入小组件库")
                instructionRow(num: "3", text: "搜索 \"Stick\" 找到本 app")
                instructionRow(num: "4", text: "选 SMALL 或 MEDIUM 拖到主屏")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.card)
            )
        }
    }

    private func instructionRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.slate)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundColor(Theme.navy)
        }
    }
}

// MARK: - Widget 预览容器（用 SharedStickState placeholder 渲染）

/// 2×2 小部件预览（简化版 — 主 app 拿不到 widget target 的 StickEntry，
/// 这里用 SharedStickState.placeholder 内联画一个样子相似的小部件）
private struct WidgetPreviewSmall: View {
    var body: some View {
        WidgetPreviewShape(state: .placeholder, size: .small)
    }
}

/// 4×2 中型部件预览（同上，简化版中型）
private struct WidgetPreviewMedium: View {
    var body: some View {
        WidgetPreviewShape(state: .placeholder, size: .medium)
    }
}

/// 通用 widget 预览形状（按尺寸切换 small / medium 两套布局）
private struct WidgetPreviewShape: View {
    let state: SharedStickState
    let size: WidgetSize

    enum WidgetSize { case small, medium }

    var body: some View {
        switch size {
        case .small:  smallBody
        case .medium: mediumBody
        }
    }

    // 2×2 小部件：状态色点 + 英文名 + 动作短语
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Circle()
                    .fill(stateAccent)
                    .frame(width: 6, height: 6)
                Text(state.englishName)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(Theme.navy)
            }
            Text(state.actionPhrase)
                .font(.system(size: 13, weight: .heavy, design: .serif))
                .foregroundColor(Theme.navy)
                .lineLimit(1)
            Text("\(state.heartRate) bpm")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(Theme.slate)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgTop)
    }

    // 4×2 中型部件：左半（状态 + 动作 + 心率），右半（mood）
    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(stateAccent)
                        .frame(width: 6, height: 6)
                    Text(state.englishName)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(Theme.navy)
                }
                Text(state.actionPhrase)
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(red: 0.86, green: 0.21, blue: 0.27))
                    Text("\(state.heartRate) bpm")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(Theme.navy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(state.mood)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
                Text("\(state.durationMinutes) min")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgTop)
    }

    private var stateAccent: Color {
        switch state.stateRaw {
        case "sit":   return Color(red: 0.92, green: 0.34, blue: 0.05)
        case "sleep": return Color(red: 0.39, green: 0.40, blue: 0.95)
        default:      return Color(red: 0.02, green: 0.59, blue: 0.41)
        }
    }
}
