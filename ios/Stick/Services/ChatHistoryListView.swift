//
//  ChatHistoryListView.swift
//  对话记录列表 — 可展开
//
//  设计:
//   - 折叠态: Header (点击展开) + 最多 3 条最近 user 问题 (chip 横向)
//   - 展开态: Header (点击折叠) + 全部消息按时间倒序, user/assistant 气泡
//   - 点击 chip / 气泡 → onSelect(seed) → 打开 ChatOverlay
//

import SwiftUI

// MARK: - 本地调色板（不属于 Theme，4 档年龄色 + AI 紫）
private extension Color {
    /// 今天 (蓝)
    static let age0 = Color(red: 0.40, green: 0.65, blue: 0.95)
    /// 昨天 (灰)
    static let age1 = Color(red: 0.50, green: 0.50, blue: 0.55)
    /// 本周 (浅)
    static let age2 = Color(red: 0.75, green: 0.75, blue: 0.78)
    /// 更早 (极浅)
    static let age3 = Color(red: 0.85, green: 0.85, blue: 0.88)
    /// AI 气泡紫
    static let aiBubblePurple = Color(red: 0.55, green: 0.40, blue: 0.95)
}

struct ChatHistoryListView: View {
    let messages: [PersistedChatMessage]
    var initialExpanded: Bool = false
    let onSelect: (String) -> Void
    var onSave: (() -> Void)? = nil

    @State private var isExpanded: Bool = false

    init(messages: [PersistedChatMessage],
         initialExpanded: Bool = false,
         onSelect: @escaping (String) -> Void,
         onSave: (() -> Void)? = nil) {
        self.messages = messages
        self.initialExpanded = initialExpanded
        self.onSelect = onSelect
        self.onSave = onSave
        self._isExpanded = State(initialValue: initialExpanded)
    }

    /// 折叠态：最近 N 条 user 问题
    private var recentUserPrompts: [PersistedChatMessage] {
        Array(
            messages.filter { $0.role == "user" }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3)
        )
    }

    /// 展开态：全部消息按时间倒序，最多 80 条
    private var allMessagesReversed: [PersistedChatMessage] {
        Array(
            messages.sorted { $0.timestamp > $1.timestamp }
                .prefix(80)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (可点击)
            ChatHistoryHeader(
                messageCount: messages.count,
                isExpanded: $isExpanded,
                onSave: onSave
            )
            .padding(.bottom, isExpanded ? 6 : 8)

            if isExpanded {
                ChatHistoryExpandedList(
                    messages: allMessagesReversed,
                    onSelect: onSelect
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                    removal: .opacity
                ))
            } else {
                ChatHistoryCollapsedChips(
                    recentUserPrompts: recentUserPrompts,
                    previewText: previewText,
                    ageColor: ageColor,
                    onSelect: onSelect
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bgBottom.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border.opacity(0.4), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
    }

    // MARK: - 折叠 chip 内容（共用）

    @ViewBuilder
    private func chipContent(msg: PersistedChatMessage, isExpanded: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ageColor(msg.timestamp))
                .frame(width: 5, height: 5)
            Text(previewText(msg.content))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Theme.navy)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Theme.mist)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func previewText(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 16 { return trimmed }
        return String(trimmed.prefix(16)) + "..."
    }

    private func ageColor(_ t: Date) -> Color {
        let days = -Int(t.timeIntervalSinceNow / 86400)
        if days <= 0 { return Color.age0 }
        if days <= 1 { return Color.age1 }
        if days <= 6 { return Color.age2 }
        return Color.age3
    }

    private func timeString(_ t: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: t)
    }
}

// MARK: - 头部

private struct ChatHistoryHeader: View {
    let messageCount: Int
    @Binding var isExpanded: Bool
    var onSave: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            // 左侧 (可点击展开)
            Button {
                if messageCount > 0 { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Text("对话记录")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    if messageCount > 0 {
                        Text("(\(messageCount))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.slate.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if messageCount > 0 {
                // 保存按钮
                if let onSave = onSave {
                    Button(action: onSave) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 9, weight: .heavy))
                            Text("保存")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(StickState.walk.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                // 展开/收起
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(isExpanded ? "收起" : "全部 \(messageCount) 条")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(StickState.walk.accent)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(StickState.walk.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 折叠态：3 条横向 chip

private struct ChatHistoryCollapsedChips: View {
    let recentUserPrompts: [PersistedChatMessage]
    var previewText: (String) -> String
    var ageColor: (Date) -> Color
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(recentUserPrompts) { msg in
                    Button {
                        onSelect(msg.content)
                    } label: {
                        chipContent(msg: msg)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func chipContent(msg: PersistedChatMessage) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ageColor(msg.timestamp))
                .frame(width: 5, height: 5)
            Text(previewText(msg.content))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Theme.navy)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Theme.mist)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - 展开态：全部消息垂直列表

private struct ChatHistoryExpandedList: View {
    let messages: [PersistedChatMessage]
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(messages) { msg in
                    ExpandBubble(msg: msg) {
                        onSelect(msg.content)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 340)   // 限制高度避免把主页撑太长
    }
}

// MARK: - 展开态单条气泡

private struct ExpandBubble: View {
    let msg: PersistedChatMessage
    let onTap: () -> Void

    private var isUser: Bool { msg.role == "user" }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 6) {
                // 角色小标
                Text(isUser ? "我" : "AI")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(isUser
                            ? StickState.walk.accent
                            : Color.aiBubblePurple)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.content)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Theme.navy)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(timeString(msg.timestamp))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.mist)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Theme.mist)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ t: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: t)
    }
}
