import SwiftUI

/// 底部 input card（WorkBuddy 极简风格）：
///  - 单张圆角浅色卡（米白底，24 圆角）
///  - 顶部 placeholder 文字
///  - 底部一行：+ / A Auto ⌄ / 麦克风 / 发送
///  - 任意输入交互 → 打开 ChatView
struct InputBar: View {
    let state: StickState
    @Binding var text: String
    var onOpenChat: (_ seed: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 顶部 placeholder（点击打开 chat）
            Button {
                onOpenChat(text)
            } label: {
                Text(placeholderText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Theme.slate.opacity(0.65))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 底部 row
            HStack(spacing: 6) {
                Button {
                    onOpenChat("")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Theme.navy.opacity(0.7))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                autoChip

                Spacer(minLength: 0)

                Button {
                    onOpenChat(text)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Theme.navy.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                sendButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.borderSoft, lineWidth: 0.6)
        )
        .shadow(color: Theme.navy.opacity(0.04), radius: 12, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onOpenChat(text)
        }
    }

    private var placeholderText: String {
        text.isEmpty ? "安排任务，Stick 帮你完成" : text
    }

    private var autoChip: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Theme.navy, lineWidth: 1.2)
                    .frame(width: 14, height: 14)
                Text("A")
                    .font(.system(size: 8, weight: .heavy, design: .serif))
                    .foregroundColor(Theme.navy)
            }
            Text("Auto")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Theme.navy.opacity(0.75))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.navy.opacity(0.55))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Theme.mist.opacity(0.18))
        )
    }

    private var sendButton: some View {
        Button {
            let seed = text
            text = ""
            onOpenChat(seed)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(text.isEmpty ? Theme.mist.opacity(0.55) : state.accent)
                )
        }
        .buttonStyle(.plain)
    }
}
