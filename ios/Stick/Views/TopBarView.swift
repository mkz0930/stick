import SwiftUI

/// 极简顶栏：仅左侧一个三横线菜单按钮。中间 / 右侧不放置任何元素。
struct TopBarView: View {
    var onMenuTap: () -> Void = {}

    var body: some View {
        HStack {
            MenuButton(action: onMenuTap)
            Spacer()
        }
        .frame(height: 44)
    }
}

// MARK: - Subviews

private struct MenuButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Capsule().fill(Theme.navy).frame(width: 20, height: 1.8)
                Capsule().fill(Theme.navy).frame(width: 20, height: 1.8)
                Capsule().fill(Theme.navy).frame(width: 20, height: 1.8)
            }
            .frame(width: 40, height: 40)
            .background(
                Circle().fill(Theme.darkText.opacity(0.6))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
