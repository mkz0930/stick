import SwiftUI

// MARK: - Chat History 演示
// 用假数据展示 ChatHistoryListView 的折叠/展开效果 + 保存按钮
// launch arg: -chat-history-demo

struct ChatHistoryDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startExpanded: Bool = CommandLine.arguments.contains("-expanded")
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    private var mockMessages: [PersistedChatMessage] {
        let now = Date()
        return [
            PersistedChatMessage(role: "user", content: "今天久坐多久了？",
                                 timestamp: now.addingTimeInterval(-60 * 3)),
            PersistedChatMessage(role: "assistant", content: "你今天已经连续坐了 2 小时 15 分钟，建议立刻站起来甩甩腰。",
                                 timestamp: now.addingTimeInterval(-60 * 3 + 5)),
            PersistedChatMessage(role: "user", content: "为什么坐久了会腰疼？",
                                 timestamp: now.addingTimeInterval(-3600 * 2)),
            PersistedChatMessage(role: "assistant", content: "久坐时腰椎压力比站立时大 40%，1.5 小时不动就是老腰报废的临界点。",
                                 timestamp: now.addingTimeInterval(-3600 * 2 + 8)),
            PersistedChatMessage(role: "user", content: "怎么喝水最科学？",
                                 timestamp: now.addingTimeInterval(-3600 * 24)),
            PersistedChatMessage(role: "assistant", content: "每 1 小时喝 200ml，少量多次。晨起、睡前各一杯，餐前半小时。",
                                 timestamp: now.addingTimeInterval(-3600 * 24 + 6)),
            PersistedChatMessage(role: "user", content: "颈椎前倾 30° 压力多大？",
                                 timestamp: now.addingTimeInterval(-3600 * 48)),
            PersistedChatMessage(role: "assistant", content: "相当于给脖子上挂了一个 18kg 的西瓜，颈椎间盘直接崩溃。",
                                 timestamp: now.addingTimeInterval(-3600 * 48 + 7)),
            PersistedChatMessage(role: "user", content: "运动后能喝冰水吗？",
                                 timestamp: now.addingTimeInterval(-3600 * 72)),
            PersistedChatMessage(role: "assistant", content: "不能。5 步因果链：冰水 → 血管收缩 → 心脏负担 → 心率 <100 → 晕厥。喝温水。",
                                 timestamp: now.addingTimeInterval(-3600 * 72 + 9)),
            PersistedChatMessage(role: "user", content: "今天心情不太好",
                                 timestamp: now.addingTimeInterval(-3600 * 96)),
            PersistedChatMessage(role: "assistant", content: "试着站起来走到窗边看 30 秒。久坐 → 多巴胺 ↓ → 情绪垃圾。",
                                 timestamp: now.addingTimeInterval(-3600 * 96 + 4)),
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.96, green: 0.96, blue: 0.94).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("💬 Chat History — 可展开")
                    .font(.system(size: 18, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                    .padding(.top, 60)
                    .padding(.horizontal, 20)

                Text("点 header 「全部 N 条」展开全部对话")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .padding(.horizontal, 20)

                ChatHistoryListView(
                    messages: mockMessages,
                    initialExpanded: startExpanded,
                    onSelect: { seed in
                        print("Tapped: \(seed)")
                    },
                    onSave: { exportChat() }
                )
                .padding(.horizontal, 20)

                Spacer()
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(red: 0.10, green: 0.15, blue: 0.25)))
                    .overlay(Circle().stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            }
            .padding(16)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: - 导出

    private func exportChat() {
        let text = formatChatAsText()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stick-chat-\(df.string(from: Date())).txt")
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        shareItems = [url]
        showShareSheet = true
    }

    private func formatChatAsText() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("═══ Stick 对话记录 ═══")
        lines.append("导出时间：\(df.string(from: Date()))")
        lines.append("消息总数：\(mockMessages.count)")
        lines.append("")
        let ordered = mockMessages.sorted { $0.timestamp < $1.timestamp }
        for (i, msg) in ordered.enumerated() {
            let role = msg.role == "user" ? "👤 我" : "🤖 AI"
            let time = df.string(from: msg.timestamp)
            lines.append("[\(i + 1)] \(role)  \(time)")
            lines.append("    \(msg.content)")
            lines.append("")
        }
        lines.append("─── Stick · 关心你的腰 ───")
        return lines.joined(separator: "\n")
    }
}
