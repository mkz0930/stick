import SwiftUI

// MARK: - History Section View

struct HistorySectionView: View {
    let historyMessages: [PersistedChatMessage]
    let accent: Color
    let onHeaderTap: () -> Void
    let onMessageSelected: (UUID) -> Void

    /// 最近 3 条 user 问题 (按时间倒序)
    private var recentUserPrompts: [PersistedChatMessage] {
        Array(
            historyMessages
                .filter { $0.role == "user" }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3)
        )
    }

    /// 对话计数: 只算 user 消息 (每条 user = 1 个对话, 不算 assistant 回复)
    private var userPromptCount: Int {
        historyMessages.filter { $0.role == "user" }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header (可点 → 弹 popover 显示完整历史)
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Text("对话记录")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.slate)
                }
                Spacer()
                Text("共 \(userPromptCount) 条")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate.opacity(0.7))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onHeaderTap()
            }

            // 横向 chip (快速定位最近 3 条 user 问题到对话位置)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentUserPrompts) { msg in
                        Button {
                            onMessageSelected(msg.id)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(historyAgeColor(msg.timestamp))
                                    .frame(width: 5, height: 5)
                                Text(historyPreview(msg.content))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.navy)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(Theme.mist)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.bgTop)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// "1小时前" / "3天前" 风格的时间文本
    private func historyTimeAgo(_ t: Date) -> String {
        let delta = -t.timeIntervalSinceNow
        if delta < 60        { return "刚刚" }
        if delta < 3600      { return "\(Int(delta/60)) 分钟前" }
        if delta < 86400     { return "\(Int(delta/3600)) 小时前" }
        if delta < 86400*7   { return "\(Int(delta/86400)) 天前" }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: t)
    }

    private func historyPreview(_ s: String) -> String {
        let trimmed = s.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 14 { return trimmed }
        return String(trimmed.prefix(14)) + "..."
    }

    /// 时间年龄颜色 (跟主页版 4 档一致: 今天 蓝 / 昨天 灰 / 本周 浅 / 更早 极浅)
    private func historyAgeColor(_ t: Date) -> Color {
        let days = -Int(t.timeIntervalSinceNow / 86400)
        if days <= 0 { return Theme.historyAge0 }
        if days <= 1 { return Theme.historyAge1 }
        if days <= 6 { return Theme.historyAge2 }
        return Theme.historyAge3
    }
}

// MARK: - History Popover Content View

struct HistoryPopoverContentView: View {
    let historyMessages: [PersistedChatMessage]
    let accent: Color
    let onMessageSelected: (UUID) -> Void
    let onDismiss: () -> Void

    /// 完整历史 (按时间倒序)
    private var allPrompts: [PersistedChatMessage] {
        historyMessages
            .filter { $0.role == "user" }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // popover 标题
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Text("历史对话 (\(allPrompts.count) 条)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Theme.navy)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().background(Theme.border.opacity(0.5))

            if allPrompts.isEmpty {
                Text("暂无历史对话")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(allPrompts) { msg in
                            HistoryRowView(
                                msg: msg,
                                accent: accent,
                                onTap: {
                                    onMessageSelected(msg.id)
                                    onDismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 280)
        .background(Theme.bgTop)
    }

    /// "1小时前" / "3天前" 风格的时间文本
    private func historyTimeAgo(_ t: Date) -> String {
        let delta = -t.timeIntervalSinceNow
        if delta < 60        { return "刚刚" }
        if delta < 3600      { return "\(Int(delta/60)) 分钟前" }
        if delta < 86400     { return "\(Int(delta/3600)) 小时前" }
        if delta < 86400*7   { return "\(Int(delta/86400)) 天前" }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: t)
    }

    /// 时间年龄颜色
    private func historyAgeColor(_ t: Date) -> Color {
        let days = -Int(t.timeIntervalSinceNow / 86400)
        if days <= 0 { return Theme.historyAge0 }
        if days <= 1 { return Theme.historyAge1 }
        if days <= 6 { return Theme.historyAge2 }
        return Theme.historyAge3
    }
}

// MARK: - History Row View

private struct HistoryRowView: View {
    let msg: PersistedChatMessage
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(historyAgeColor(msg.timestamp))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(msg.content)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.navy)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(historyTimeAgo(msg.timestamp))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.slate)
                }
                Spacer(minLength: 0)
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.border.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// "1小时前" / "3天前" 风格的时间文本
    private func historyTimeAgo(_ t: Date) -> String {
        let delta = -t.timeIntervalSinceNow
        if delta < 60        { return "刚刚" }
        if delta < 3600      { return "\(Int(delta/60)) 分钟前" }
        if delta < 86400     { return "\(Int(delta/3600)) 小时前" }
        if delta < 86400*7   { return "\(Int(delta/86400)) 天前" }
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: t)
    }

    /// 时间年龄颜色
    private func historyAgeColor(_ t: Date) -> Color {
        let days = -Int(t.timeIntervalSinceNow / 86400)
        if days <= 0 { return Theme.historyAge0 }
        if days <= 1 { return Theme.historyAge1 }
        if days <= 6 { return Theme.historyAge2 }
        return Theme.historyAge3
    }
}
