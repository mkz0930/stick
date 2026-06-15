//
//  ChatHistoryStore.swift
//  持久化 chat messages 到 UserDefaults — ChatOverlay 关闭时存, 启动时读
//
//  简化模型: 最多保留 50 条最近消息
//

import Foundation
import SwiftUI

/// 一条持久化的 chat 消息 (UserDefaults JSON)
struct PersistedChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: String         // "user" / "assistant"
    let content: String
    let timestamp: Date
    let tags: [String]       // 本次消息提取的标签

    init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date(), tags: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tags = tags
    }
}

@MainActor
final class ChatHistoryStore: ObservableObject {
    static let shared = ChatHistoryStore()

    private let key = "stick.chat.history.v1"
    private let maxMessages = 200

    @Published private(set) var messages: [PersistedChatMessage] = []

    init() {
        load()
    }

    // MARK: - 增删改

    func append(_ msg: PersistedChatMessage) {
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
        save()
    }

    func clear() {
        messages = []
        save()
    }

    /// 用新消息列表整体替换 (用于 ChatOverlay.onDisappear 写回)
    func replaceAll(with newMessages: [PersistedChatMessage]) {
        messages = Array(newMessages.suffix(maxMessages))
        save()
    }

    // MARK: - 持久化

    private func save() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: key)
            print("[ChatHistoryStore] save(): \(messages.count) msgs, user msgs: \(messages.filter { $0.role == "user" }.count)")
        } catch {
            print("[ChatHistoryStore] save failed: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            messages = try JSONDecoder().decode([PersistedChatMessage].self, from: data)
            print("[ChatHistoryStore] load(): \(messages.count) msgs loaded, user msgs: \(messages.filter { $0.role == "user" }.count)")
        } catch {
            print("[ChatHistoryStore] load failed: \(error)")
        }
    }
}
