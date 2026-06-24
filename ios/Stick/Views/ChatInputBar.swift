import SwiftUI

// MARK: - 本地调色板（不属于 Theme，相机小星紫）
private extension Color {
    /// 相机按钮右上角小星紫
    static let cibSparklePurple = Color(red: 0.45, green: 0.30, blue: 0.95)
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Binding var input: String
    let isStreaming: Bool
    @FocusState.Binding var inputFocused: Bool
    let features: [InputFeature]
    let cameraChips: Set<String>
    let onSend: () -> Void
    let onCameraChipTap: (String) -> Void
    let onPhotoLibraryTap: () -> Void
    let onCameraTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 顶部 feature chips (横向滚动)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(features) { f in
                        Button {
                            if cameraChips.contains(f.title) {
                                // 拍食物 / 报告解读：保留当前输入 + 预填 chip 文案 + 打开相机
                                onCameraChipTap(f.seed)
                            }
                            // 其他 chip：不发不填，纯视觉提示（点击不响应）
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
                .padding(.horizontal, 2)
            }

            // 2. 底部 input pill + 相机按钮
            HStack(spacing: 8) {
                inputPill()
                CameraButtonView(
                    input: input,
                    onCameraTap: { currentInput in
                        onCameraTap(currentInput)
                    }
                )
            }
        }
        .padding(.bottom, 8)
    }

    private func inputPill() -> some View {
        HStack(spacing: 0) {
            Button {
                // TODO: 语音功能（暂时 noop）
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

            TextField("继续问点健康相关…", text: $input)
                .lineLimit(1)
                .tint(Theme.navy)
                .foregroundColor(Theme.navy)
                .font(.system(size: 15, weight: .regular))
                .disabled(isStreaming)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { onSend() }

            Button {
                onPhotoLibraryTap()
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
}

// MARK: - Camera Button View

private struct CameraButtonView: View {
    let input: String
    let onCameraTap: (String) -> Void

    var body: some View {
        Button {
            onCameraTap(input)
        } label: {
            ZStack(alignment: .topTrailing) {
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

                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(Color.cibSparklePurple)
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
}
