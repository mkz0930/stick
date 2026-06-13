import AppIntents

/// widget 点击触发的 AppIntent：把 seed 写到 App Group shared state，
/// 主 app 启动 / 进入前台时读出 → 打开 chat 并预填。
///
/// 这个 intent **不弹系统对话框**（iOS 对自定义 URL scheme 才会弹）。
/// `Button(intent:)` 是 widget 点击的 iOS 17+ 推荐方案。
struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 Stick 对话"
    static var description = IntentDescription("用预填问题直接打开 Stick 聊天")

    @Parameter(title: "预填问题")
    var seed: String

    init() {
        self.seed = ""
    }

    init(seed: String) {
        self.seed = seed
    }

    /// true → perform() 跑完会顺带把主 app 拉到前台
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedStateStore.writePendingChatSeed(seed)
        return .result()
    }
}
