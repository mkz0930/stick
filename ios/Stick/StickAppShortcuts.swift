import AppIntents

/// 把 OpenChatIntent 暴露给系统（Shortcuts / Spotlight / Siri）。
/// AppShortcutsProvider 不用手动引用，运行时系统会从 bundle 里扫描。
struct StickAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenChatIntent(),
            phrases: [
                "用 \(.applicationName) 打开聊天",
                "\(.applicationName) 打开对话",
            ],
            shortTitle: "打开聊天",
            systemImageName: "message.fill"
        )
    }
}
