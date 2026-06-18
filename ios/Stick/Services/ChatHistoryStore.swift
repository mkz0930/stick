//
//  ChatHistoryStore.swift
//  持久化 chat messages 到 UserDefaults — ChatOverlay 关闭时存, 启动时读
//
//  简化模型: 最多保留 50 条最近消息
//

import Foundation

/// 一条持久化的 chat 消息 (UserDefaults JSON)
struct PersistedChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: String         // "user" / "assistant"
    let content: String
    let timestamp: Date
    let tags: [String]       // 本次消息提取的标签（user 消息才有）
    let suggestions: [String] // 推荐主题（assistant 消息才有）

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(), tags: [String] = [], suggestions: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tags = tags
        self.suggestions = suggestions
    }
}

@MainActor
@Observable
final class ChatHistoryStore {
    static let shared = ChatHistoryStore()

    private let key = "stick.chat.history.v1"
    private let maxMessages = 200
    private let pageSize = 10

    /// 全量历史（持久化，懒加载）
    private(set) var allMessages: [PersistedChatMessage] = []

    /// 当前展示的消息（分页加载）
    private(set) var loadedMessages: [PersistedChatMessage] = []

    /// 是否还有更早的消息可加载
    var hasMore: Bool { loadedCount < allMessages.count }

    /// 当前已加载的条数
    var loadedCount: Int { loadedMessages.count }

    init() {
        load()
    }

    /// 初始加载最近 pageSize 条
    func loadInitial() {
        loadedMessages = Array(allMessages.suffix(pageSize))
    }

    /// 加载更早的消息（追加 N 条）
    func loadMore() {
        guard hasMore else { return }
        let start = max(0, allMessages.count - loadedCount - pageSize)
        let end = allMessages.count - loadedCount
        let earlier = Array(allMessages[start..<end])
        loadedMessages.insert(contentsOf: earlier, at: 0)
    }

    // MARK: - 增删改

    func append(_ msg: PersistedChatMessage) {
        allMessages.append(msg)
        if allMessages.count > maxMessages {
            allMessages.removeFirst(allMessages.count - maxMessages)
        }
        // 新消息追加到展示列表
        loadedMessages.append(msg)
        if loadedMessages.count > maxMessages {
            loadedMessages.removeFirst(loadedMessages.count - maxMessages)
        }
        save()
    }

    func clear() {
        allMessages = []
        loadedMessages = []
        save()
    }

    /// 用新消息列表整体替换 (用于 ChatOverlay.onDisappear 写回)
    func replaceAll(with newMessages: [PersistedChatMessage]) {
        allMessages = Array(newMessages.suffix(maxMessages))
        // 保持 loadedMessages 同步截断
        loadedMessages = Array(allMessages.suffix(loadedCount))
        save()
    }

    // MARK: - 持久化

    private func save() {
        do {
            let data = try JSONEncoder().encode(allMessages)
            UserDefaults.standard.set(data, forKey: key)
            print("[ChatHistoryStore] save(): \(allMessages.count) msgs")
        } catch {
            print("[ChatHistoryStore] save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            allMessages = try JSONDecoder().decode([PersistedChatMessage].self, from: data)
            print("[ChatHistoryStore] load(): \(allMessages.count) msgs loaded")
        } catch {
            print("[ChatHistoryStore] load failed: \(error)")
        }
    }
}
