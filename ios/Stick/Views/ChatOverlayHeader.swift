import SwiftUI

// MARK: - Chat Header View

struct ChatHeaderView: View {
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.navy, lineWidth: 1.6)
                    .frame(width: 20, height: 20)
                Rectangle().fill(Theme.navy).frame(width: 8, height: 1.4)
                Rectangle().fill(Theme.navy).frame(width: 1.4, height: 8)
            }

            Text("ATLAS · 健康助手")
                .font(.system(size: 15, weight: .black))
                .tracking(0.08)
                .foregroundColor(Theme.navy)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.bgTop)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
