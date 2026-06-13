import SwiftUI

/// 底部 input 区 (新设计 — 参考图):
///  - 顶部一行: 横向滚动 feature chips (AI 诊室 / 报告解读 / 拍皮肤 / 就医...)
///  - 底部一行: pill 输入条 (语音 + placeholder + +) + 独立圆形相机按钮 (右上角小星)
///
///  点击 chip / 语音 / + / 相机 → 调用 onOpenChat(seed)
///  点中间 placeholder 区域也会打开 chat (带当前 draft)
struct InputBar: View {
    let state: StickState
    @Binding var text: String
    var onOpenChat: (_ seed: String) -> Void
    /// 聊天历史最后一条用户问题 — 输入框 placeholder 显示, 提示有记录
    var lastHistoryPrompt: String? = nil

    /// 顶部 feature chips（横向滚动）
    private let features: [InputFeature] = [
        InputFeature(icon: "cross.case.fill",    title: "AI 诊室",   seed: "AI 医生问诊"),
        InputFeature(icon: "doc.text.fill",      title: "报告解读",  seed: "解读我的健康报告"),
        InputFeature(icon: "camera.viewfinder",  title: "拍皮肤",    seed: "拍照分析我的皮肤状态"),
        InputFeature(icon: "person.badge.plus",  title: "就医",      seed: "推荐合适的医院和科室"),
        InputFeature(icon: "fork.knife",         title: "饮食建议",  seed: "推荐健康饮食方案"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 顶部 feature chips (横向滚动)
            chipsRow

            // 2. 底部 input pill + 相机按钮
            HStack(spacing: 8) {
                inputPill
                cameraButton
            }
        }
    }

    // MARK: - 顶部 chips 行

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(features) { f in
                    Button {
                        onOpenChat(f.seed)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: f.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(f.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(Theme.navy)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(Color.white)
                        )
                        .overlay(
                            Capsule().stroke(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)   // 让首尾 chip 不贴边
        }
    }

    // MARK: - Pill 输入条

    private var inputPill: some View {
        HStack(spacing: 0) {
            // 左侧: 语音按钮 (圆形描边)
            Button {
                onOpenChat("")
            } label: {
                Image(systemName: "wave.3.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.navy)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(Theme.navy.opacity(0.85), lineWidth: 1.4)
                    )
            }
            .buttonStyle(.plain)

            // 中间: placeholder (点击也打开 chat)
            Text(placeholderText)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Theme.slate.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenChat(text)
                }

            // 右侧: + 按钮 (圆形描边)
            Button {
                onOpenChat("")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(Theme.navy.opacity(0.85), lineWidth: 1.4)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 56)
        .background(
            Capsule().fill(Color.white)
        )
        .overlay(
            Capsule().stroke(Theme.border, lineWidth: 0.5)
        )
    }

    // MARK: - 相机按钮 (独立圆形 + 右上角小星)

    private var cameraButton: some View {
        Button {
            onOpenChat("拍照识别")
        } label: {
            ZStack(alignment: .topTrailing) {
                // 相机主体
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Theme.navy)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(Color.white)
                    )
                    .overlay(
                        Circle().stroke(Theme.border, lineWidth: 0.5)
                    )

                // 右上角小星 (紫蓝)
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(Color(red: 0.45, green: 0.30, blue: 0.95))
                    .padding(3)
                    .background(
                        Circle().fill(Color.white)
                    )
                    .overlay(
                        Circle().stroke(Theme.border, lineWidth: 0.3)
                    )
                    .offset(x: 4, y: -2)
            }
        }
        .buttonStyle(.plain)
    }

    private var placeholderText: String {
        if !text.isEmpty { return text }
        // 有聊天历史时, 显示"上次问了: xxx" → 提示用户有记录
        if let last = lastHistoryPrompt, !last.isEmpty {
            return "上次问了: \(last.prefix(20))...   点开查看对话"
        }
        return "对话内容已开启隐私保护..."
    }
}

// MARK: - Feature chip 数据

private struct InputFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let seed: String
}
