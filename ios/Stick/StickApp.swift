import SwiftUI

@main
struct StickApp: App {
    @State private var pendingChatSeed: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(pendingChatSeed: $pendingChatSeed)
                .onOpenURL { url in
                    handleWidgetURL(url)
                }
                // AppIntent 路径：widget 上的 OpenChatIntent 写 shared state，
                // 切回前台时读出来打开 chat
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { drainPendingChatSeed() }
                }
                .onAppear { drainPendingChatSeed() }
        }
    }

    /// AppIntent 路径：widget 上的 OpenChatIntent 写 shared state，
    /// 切回前台时读出来打开 chat（不弹系统对话框）
    private func drainPendingChatSeed() {
        guard let seed = SharedStateStore.readAndClearPendingChatSeed() else { return }
        DispatchQueue.main.async {
            self.pendingChatSeed = seed
        }
    }

    /// 解析 widget 点击传来的 URL。
    /// URL 格式：stick://chat?seed=久坐风险提醒
    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == "stick", let host = url.host else { return }

        if host == "chat" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let seed = comps?.queryItems?.first(where: { $0.name == "seed" })?.value ?? ""
            DispatchQueue.main.async {
                self.pendingChatSeed = seed
            }
        }
    }
}
