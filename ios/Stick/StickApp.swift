import SwiftUI

@main
struct StickApp: App {
    @State private var pendingChatSeed: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(pendingChatSeed: $pendingChatSeed)
                .onOpenURL { url in
                    StickWidgetURLRouter.route(url, setChatSeed: { pendingChatSeed = $0 })
                }
                // AppIntent 路径：widget 上的 OpenChatIntent 写 shared state，
                // 切回前台时读出来打开 chat（不弹系统对话框）
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { drainPendingChatSeed() }
                }
                .onAppear { drainPendingChatSeed() }
        }
    }

    private func drainPendingChatSeed() {
        guard let seed = SharedStateStore.readAndClearPendingChatSeed() else {
            print("[drainPendingChatSeed] no seed found in app group")
            return
        }
        print("[drainPendingChatSeed] drained seed: \(seed)")
        DispatchQueue.main.async { pendingChatSeed = seed }
    }
}
