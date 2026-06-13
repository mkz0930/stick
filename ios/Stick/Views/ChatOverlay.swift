import SwiftUI
import UIKit

/// 今日健康数据统计（从 HealthStore 实时计算）
@MainActor
private struct TodayHealthStats {
    let sitMinutes: Int
    let walkMinutes: Int
    let sleepMinutes: Int
    let standMinutes: Int
    let totalSteps: Int
    let avgHeartRate: Int

    init() {
        let snapshots = HealthStore.shared.today
        var sit = 0, walk = 0, sleep = 0, stand = 0, steps = 0, hrSum = 0, hrCount = 0
        for s in snapshots {
            switch s.bodyState {
            case "sit": sit += 1
            case "walk": walk += 1
            case "sleep": sleep += 1
            case "stand": stand += 1
            default: break
            }
            steps += s.stepCount ?? 0
            if let hr = s.heartRate { hrSum += Int(hr); hrCount += 1 }
        }
        self.sitMinutes = sit
        self.walkMinutes = walk
        self.sleepMinutes = sleep
        self.standMinutes = stand
        self.totalSteps = steps
        self.avgHeartRate = hrCount > 0 ? hrSum / hrCount : 72
    }
}

/// Chat 底栏（v2）：直接叠在主页底部，跟主界面无缝融合。
/// - 默认高度 ≈ 220pt（header 32pt + 消息列表 + inputBar 44pt）
/// - 消息多时 list 可滚；inputBar 永远贴底
/// - 关闭按钮在右上；点 chat 之外的区域（需要点 homeBody）目前是 noop，可以由外层处理
struct ChatOverlay: View {
    let state: StickState
    let initialText: String
    /// 来自 widget 风险提醒的 seed（如"久坐风险提醒"），触发专属风险科普流程
    var riskSeed: String? = nil
    /// 初始从 PersonalView 点击历史记录时，滚动到这个 UUID 对应的消息位置
    var targetScrollId: UUID? = nil
    /// 滚动触发器：外部每次历史导航 +1，overlay 用 onChange 响应（不重建 overlay）
    var scrollTrigger: Int = 0
    var onClose: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @State private var showHistoryPopover: Bool = false
    @State private var pendingScrollId: UUID? = nil   // 点击历史 → 滚动定位
    @State private var scrollToBottom: Bool = false   // true=auto-scroll(anchor:.bottom) false=history导航(anchor:.top)
    @State private var keyboardVisible: Bool = false  // 键盘是否可见
    /// 上次已处理的 scrollTrigger 值（用于去重）
    @State private var lastHandledTrigger: Int = 0
    @ObservedObject private var history = ChatHistoryStore.shared
    @ObservedObject private var userProfile = UserProfileStore.shared

    private let suggestedQuestions: [String] = [
        "我刚坐了一上午",
        "眼睛干涩怎么缓解？",
        "午饭后困得不行",
        "睡前总刷手机",
    ]

    var body: some View {
        // 用 GeometryReader 读父高度, 全屏显示
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.clear
                cardContent(height: geo.size.height)
            }
        }   // GeometryReader
        // 键盘弹出/收起时自动滚到底部
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let last = messages.last {
                    self.scrollToBottom = true
                    self.pendingScrollId = last.id
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    /// 卡片本体 (全屏) — 内部 header / 消息 / input 由内层 VStack 撑开
    @ViewBuilder
    private func cardContent(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            DashedDivider()
            messageArea
            Spacer(minLength: 0)
            DashedDivider()
            inputBar
            // 底色 footer：与 card 同色，延伸到屏幕最底（覆盖 home indicator 区域）
            Theme.card
                .frame(height: 60)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.card)
        .overlay(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 14,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: 14
                ),
                style: .continuous
            )
            .stroke(Theme.border, lineWidth: 1)
        )
        .frame(height: height)
        .onAppear {
            // 从持久化 store 恢复历史 messages
            if !history.messages.isEmpty {
                messages = history.messages.map { m in
                    ChatMessage(
                        id: m.id,
                        role: m.role == "user" ? .user : .assistant,
                        content: m.content
                    )
                }
            }
            // 初始滚动（overlay 首次出现时触发）
            if let targetId = targetScrollId {
                // 有目标消息ID（从历史点击导航过来）→ 滚动到该消息
                self.scrollToBottom = false
                lastHandledTrigger = scrollTrigger
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.pendingScrollId = targetId
                }
            } else if !messages.isEmpty {
                // 无目标ID（普通打开）→ 滚到底部显示最新消息
                self.scrollToBottom = true
                // 延迟滚动：等 LazyVStack 渲染完再执行
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.pendingScrollId = self.messages.last?.id
                }
            }
            // widget 风险提醒触发：预填输入框 + 走专属风险科普流程（AI 自动回答）
            if let seed = riskSeed, !seed.isEmpty {
                input = initialText
                // 把用户消息加入对话列表（显示在 AI 回复上方）
                let userMsgId = UUID()
                messages.append(ChatMessage(id: userMsgId, role: .user, content: initialText))
                history.append(PersistedChatMessage(id: userMsgId, role: "user", content: initialText))
                _ = UserProfileStore.shared.recordUserMessage()
                self.pendingScrollId = userMsgId
                generateRiskAnalysis(seed: seed)
            } else {
                // 普通 chat seed：作为用户消息发送
                input = initialText
                if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    send()
                }
            }
            // 调试用: 启动时强制打开历史 popover
            if ProcessInfo.processInfo.environment["STICK_OPEN_HISTORY_POPOVER"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showHistoryPopover = true
                }
            }
        }
        // 历史导航时滚动（overlay 已显示，targetScrollId 变了，但 overlay 没有重建）
        .onChange(of: scrollTrigger) { _, newTrigger in
            // 防止重复触发：只有 scrollTrigger 比上次处理过的值更大时才处理
            guard newTrigger > self.lastHandledTrigger else { return }
            self.lastHandledTrigger = newTrigger
            guard let targetId = self.targetScrollId else { return }
            self.scrollToBottom = false
            // 等一帧让 LazyVStack 渲染完，再滚动
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.pendingScrollId = targetId
            }
        }
        .onDisappear {
            streamTask?.cancel()
            // 把当前 messages 写回 store
            let newHistory = messages.map { m in
                PersistedChatMessage(
                    id: m.id,
                    role: m.role == .user ? "user" : "assistant",
                    content: m.content
                )
            }
            print("[ChatOverlay] onDisappear: saving \(newHistory.count) messages, user msgs: \(newHistory.filter { $0.role == "user" }.count)")
            history.replaceAll(with: newHistory)
        }
    }

    // MARK: - Header（紧凑版）

    private var header: some View {
        HStack(spacing: 8) {
            // brand mark
            ZStack {
                Circle()
                    .stroke(Theme.navy, lineWidth: 1.6)
                    .frame(width: 20, height: 20)
                Rectangle().fill(Theme.navy).frame(width: 8, height: 1.4)
                Rectangle().fill(Theme.navy).frame(width: 1.4, height: 8)
            }

            Text("ATLAS · 健康助手")
                .font(.system(size: 15, weight: .black))
                .tracking(0.08)
                .foregroundColor(Theme.navy)

            Spacer()

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.bgTop)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 消息区（空状态 + 流式列表）

    @ViewBuilder
    private var messageArea: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                // 1) 对话记录 (从 ChatHistoryStore 拉最近 3 条 user 问题) — 一直显示在顶部
                if !history.messages.isEmpty {
                    historySection
                }

                // 2) 推荐问题 (空状态时) 或 当前对话 (有消息时)
                if messages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUGGESTED")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Theme.slate)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedQuestions, id: \.self) { q in
                                    Button {
                                        input = q
                                        send()
                                    } label: {
                                        Text(q)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Theme.navy)
                                            .lineLimit(2)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(Theme.bgTop)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(Theme.border, lineWidth: 0.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    ScrollViewReader { msgProxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(messages) { msg in
                                    MessageRow(message: msg, state: state) { suggestion in
                                        sendDirect(suggestion)
                                    }
                                        .id(msg.id)
                                }
                                if isStreaming {
                                    HStack(spacing: 5) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(state.accent)
                                        Text("正在生成建议…")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(Theme.slate)
                                    }
                                    .padding(.leading, 4)
                                    .id("streaming")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .onChange(of: isStreaming) { _, streaming in
                            // 流式输出结束后（streaming 从 true→false），自动滚到底部显示最新回复
                            if !streaming, let last = messages.last {
                                self.scrollToBottom = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    self.pendingScrollId = last.id
                                }
                            }
                        }
                        .onChange(of: messages.last?.content) { _ in
                            // 流式输出过程中，每个 chunk 到来时都实时滚到底部
                            guard self.isStreaming, let last = messages.last else { return }
                            let anchor: UnitPoint = .bottom
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    msgProxy.scrollTo(last.id, anchor: anchor)
                                }
                            }
                        }
                        .onChange(of: pendingScrollId) { newId in
                            guard let id = newId else { return }
                            let anchor: UnitPoint = self.scrollToBottom ? .bottom : .top
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    msgProxy.scrollTo(id, anchor: anchor)
                                }
                            }
                            self.pendingScrollId = nil
                        }
                        .onTapGesture {
                            // 点击消息区 → 滚到底部
                            if let last = messages.last {
                                self.scrollToBottom = true
                                self.pendingScrollId = last.id
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - 对话记录区 (在 messageArea 空状态下, 置于 SUGGESTED 之上)

    /// 最近 3 条 user 问题 (按时间倒序)
    private var recentUserPrompts: [PersistedChatMessage] {
        Array(
            history.messages
                .filter { $0.role == "user" }
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(3)
        )
    }

    /// 对话计数: 只算 user 消息 (每条 user = 1 个对话, 不算 assistant 回复)
    private var userPromptCount: Int {
        history.messages.filter { $0.role == "user" }.count
    }

    private var historySection: some View {
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
                showHistoryPopover = true
            }
            .sheet(isPresented: $showHistoryPopover) {
                historyPopoverContent
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }

            // 横向 chip (快速定位最近 3 条 user 问题到对话位置)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(recentUserPrompts) { msg in
                        Button {
                            // 滚动定位到该消息 (不重新发送)
                            self.scrollToBottom = false
                            self.pendingScrollId = msg.id
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

    /// 完整历史 popover (按时间倒序, 最多 50 条 — ChatHistoryStore 限制)
    @ViewBuilder
    private var historyPopoverContent: some View {
        let allPrompts = history.messages
            .filter { $0.role == "user" }
            .sorted { $0.timestamp > $1.timestamp }
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
                            historyRow(msg)
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

    /// popover 内单行: 完整内容 + 时间 + 恢复按钮
    private func historyRow(_ msg: PersistedChatMessage) -> some View {
        Button {
            // 滚动定位到该消息 (不重新发送)
            self.scrollToBottom = false
            self.pendingScrollId = msg.id
            showHistoryPopover = false
        } label: {
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
                    .foregroundColor(state.accent)
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

    private func historyPreview(_ s: String) -> String {
        let trimmed = s.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 14 { return trimmed }
        return String(trimmed.prefix(14)) + "..."
    }

    /// 时间年龄颜色 (跟主页版 4 档一致: 今天 蓝 / 昨天 灰 / 本周 浅 / 更早 极浅)
    private func historyAgeColor(_ t: Date) -> Color {
        let days = -Int(t.timeIntervalSinceNow / 86400)
        if days <= 0 { return Color(red: 0.40, green: 0.65, blue: 0.95) }
        if days <= 1 { return Color(red: 0.50, green: 0.50, blue: 0.55) }
        if days <= 6 { return Color(red: 0.75, green: 0.75, blue: 0.78) }
        return Color(red: 0.85, green: 0.85, blue: 0.88)
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("继续问点健康相关…", text: $input, axis: .vertical)
                    .lineLimit(1...2)
                    .tint(Theme.navy)
                    .foregroundColor(Theme.navy)
                    .accentColor(Theme.navy)
                    .font(.system(size: 16, weight: .medium))
                    .disabled(isStreaming)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.bgTop)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.border, lineWidth: 1)
            )

            Button {
                send()
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isStreaming ? Theme.mist : state.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 发送 / 取消

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsgId = UUID()
        messages.append(ChatMessage(id: userMsgId, role: .user, content: text))
        input = ""
        print("[ChatOverlay] send(): user msg added, total msgs now: \(messages.count)")

        // 立即滚动到刚发出的用户问题位置
        self.scrollToBottom = false
        self.pendingScrollId = userMsgId

        // 记录用户消息，每 3 条触发一次用户画像总结
        let shouldSummarize = UserProfileStore.shared.recordUserMessage()

        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildContext()
        streamTask = Task {
            do {
                for try await chunk in LLMService.sendMessageStream(text, context: ctx) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                        let prefix = messages[idx].content.isEmpty ? "" : messages[idx].content + "\n\n"
                        messages[idx].content = "\(prefix)⚠️ \(err)"
                    }
                }
            }
            await MainActor.run { isStreaming = false }

            // 流结束后生成追问建议
            generateSuggestions(for: assistantId)

            // 每 3 条用户消息总结一次用户画像
            if shouldSummarize {
                await summarizeUserProfile()
            }
        }
    }

    /// 直接发送文字（不经过 input 框，用于意图按钮）
    private func sendDirect(_ text: String) {
        let userMsgId = UUID()
        messages.append(ChatMessage(id: userMsgId, role: .user, content: text))

        self.scrollToBottom = false
        self.pendingScrollId = userMsgId

        let shouldSummarize = UserProfileStore.shared.recordUserMessage()
        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildContext()
        streamTask = Task {
            do {
                for try await chunk in LLMService.sendMessageStream(text, context: ctx) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                            self.messages[idx].content += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                        let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                        let prefix = self.messages[idx].content.isEmpty ? "" : self.messages[idx].content + "\n\n"
                        self.messages[idx].content = "\(prefix)⚠️ \(err)"
                    }
                }
            }
            await MainActor.run { self.isStreaming = false }

            generateSuggestions(for: assistantId)

            if shouldSummarize {
                await self.summarizeUserProfile()
            }
        }
    }

    /// 根据上一条 AI 回复生成 1-3 条追问
    private func generateSuggestions(for messageId: UUID) {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].role == .assistant,
              !messages[idx].content.isEmpty else { return }

        let responseContent = messages[idx].content

        Task {
            let suggestions = await fetchSuggestions(from: responseContent)
            await MainActor.run {
                if let i = self.messages.firstIndex(where: { $0.id == messageId }) {
                    var updated = self.messages
                    updated[i].suggestions = suggestions
                    self.messages = updated
                    // 意图出现后自动滚动到底部
                    self.scrollToBottom = true
                    self.pendingScrollId = messageId
                }
            }
        }
    }

    private func fetchSuggestions(from response: String) async -> [String] {
        let prompt = """
        基于下方AI健康助手回复内容，输出1-3条用户接下来真实想执行/深入了解的主动意图
        硬性规则：
        1. 单条文字≤20个字
        2. 严禁问号、禁止疑问句；全部使用行动句式，参考格式：了解下XX、试试XX、查看XX
        3. 仅罗列文本，不带序号、注释、说明文字
        AI健康助手回复内容：
        \(response)
        """

        do {
            let result = try await LLMService.sendMessage(prompt, context: "生成追问建议")
            let lines = result.components(separatedBy: "\n")
            var suggestions: [String] = []
            for line in lines {
                var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { continue }
                // 跳过含"追问"的标题行
                if s.contains("追问") { continue }
                // 去掉开头的编号 "1. " "1)" "1、" 等
                s = s.replacingOccurrences(of: "^[0-9]+[.)、\\s]+", with: "", options: .regularExpression)
                // 去掉结尾的问号
                s = s.replacingOccurrences(of: "[？?]+$", with: "", options: .regularExpression)
                s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty {
                    suggestions.append(s)
                }
                if suggestions.count >= 3 { break }
            }
            return suggestions
        } catch {
            return []
        }
    }

    /// 调用 LLM 总结用户最近消息，更新用户画像。新对话优先，覆盖旧画像
    private func summarizeUserProfile() async {
        let recentUserMessages = messages
            .filter { $0.role == .user }
            .suffix(10)
            .map(\.content)

        var prompt = "你是一个用户画像分析助手。请根据以下用户的对话历史，总结用户的画像信息。"
        prompt += "包括但不限于：用户的身体状况、健康需求、生活习惯、行为模式等。"
        prompt += "请用简洁的中文总结（200字以内），直接输出结论，不要解释过程。\n\n"

        prompt += "最近 \(recentUserMessages.count) 条用户消息：\n"
        for (i, msg) in recentUserMessages.enumerated() {
            prompt += "\(i + 1). \(msg)\n"
        }

        do {
            let result = try await LLMService.sendMessage(prompt, context: "用户画像总结")
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                userProfile.updateProfile(trimmed)
                userProfile.resetCounter()
            }
        } catch {
            // 静默失败，不影响主流程
            print("UserProfile summarization failed: \(error)")
        }
    }

    private func buildContext() -> String {
        let time = StickState.formatMinute(StickState.minutesOfDay(.now))
        let hour = Calendar.current.component(.hour, from: .now)
        let period: String
        switch hour {
        case 5..<11:  period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default:      period = "深夜"
        }
        let profileBlock = userProfile.profileContextBlock()

        // 最近 10 条用户问题
        let recentUserMsgs = messages
            .filter { $0.role == .user }
            .suffix(10)
            .map { "用户: \($0.content)" }
            .joined(separator: "\n")

        // 今日健康数据
        let stats = TodayHealthStats()
        let healthBlock = """
        【今日健康数据】
        - 久坐: \(stats.sitMinutes) 分钟
        - 行走: \(stats.walkMinutes) 分钟
        - 站立: \(stats.standMinutes) 分钟
        - 睡眠: \(stats.sleepMinutes) 分钟
        - 步数: \(stats.totalSteps) 步
        - 平均心率: \(stats.avgHeartRate) bpm
        """

        return profileBlock + healthBlock + """

        【用户最近问题】
        \(recentUserMsgs)

        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase) (\(state.englishName))
        - 用户类型: 职场白领
        - 备注: 给出符合该时段 + 该姿态的即时可行建议
        """
    }

    // MARK: - Widget 风险提醒专属流程

    /// 久坐时长（分钟），由 riskSeed 解析而来
    private var sedentaryMinutes: Int {
        // riskSeed 格式: "久坐风险提醒:XX分钟"
        guard let seed = riskSeed,
              seed.hasPrefix("久坐风险提醒:"),
              let minStr = seed.split(separator: ":").last,
              let min = Int(minStr) else { return 30 }
        return min
    }

    /// 构建 widget 风险提醒的 system prompt
    private func buildRiskContext(seed: String) -> String {
        let time = StickState.formatMinute(StickState.minutesOfDay(.now))
        let hour = Calendar.current.component(.hour, from: .now)
        let period: String
        switch hour {
        case 5..<11:  period = "上午"
        case 11..<14: period = "中午"
        case 14..<18: period = "下午"
        case 18..<22: period = "晚上"
        default:      period = "深夜"
        }

        if seed.hasPrefix("久坐风险提醒") {
            let mins = sedentaryMinutes
            let hours = mins / 60
            let remain = mins % 60
            let durationText = hours > 0 ? "\(hours)小时\(remain)分钟" : "\(mins)分钟"

            let stats = TodayHealthStats()
            return """
            【用户当前状态】
            - 当前时间: \(time) (\(period))
            - 当前姿态: \(state.actionPhrase)
            - 久坐时长: \(durationText)
            - 今日久坐累计: \(stats.sitMinutes) 分钟
            - 今日行走累计: \(stats.walkMinutes) 分钟
            - 今日步数: \(stats.totalSteps) 步
            - 平均心率: \(stats.avgHeartRate) bpm
            - 用户类型: 职场白领

            【本次对话目标】
            用户点击了久坐风险提醒卡片，这是一个健康科普+即时行动建议的场景。
            请严格按以下结构回复：

            1. 【风险科普】先用1-2句话解释久坐\(durationText)对身体的具体危害（要具体、可感知，不要笼统）
            2. 【当前状态分析】结合时间、姿态、今日久坐累计，简述用户此刻的身体感受
            3. 【立刻可以做的动作】给出2-4条马上就能做、没有阻力的动作，每条10字以内，格式：「动作名称 · 具体描述」

            示例：「扩胸3下 · 双手背后握拳，向后展开胸部，重复3次」

            【语气要求】
            - 温暖、口语化，像朋友提醒你动一动
            - 不要说教，不要给医疗建议
            - 总字数 ≤ 300字
            """
        }

        // 默认通用风险提醒
        return """
        【用户当前状态】
        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase)
        - 用户类型: 职场白领

        【本次对话目标】
        用户点击了健康风险提醒卡片，请给出风险科普和2-4条立刻能做的动作建议。

        1. 【风险科普】1-2句话解释当前健康风险
        2. 【立刻能做的动作】2-4条无阻力的即时行动

        语气温暖口语化，总字数 ≤ 300字
        """
    }

    /// 生成 widget 风险提醒的 AI 分析（直接输出，不作为用户消息）
    private func generateRiskAnalysis(seed: String) {
        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildRiskContext(seed: seed)
        streamTask = Task {
            do {
                for try await chunk in LLMService.sendMessageStream(seed, context: ctx) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                        messages[idx].content = "⚠️ \(err)"
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                input = ""
            }

            // 流结束后生成追问建议
            generateSuggestions(for: assistantId)
        }
    }
}

// MARK: - 消息模型

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    let id: UUID
    let role: Role
    var content: String
    var suggestions: [String] = []

    init(id: UUID = UUID(), role: Role, content: String, suggestions: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.suggestions = suggestions
    }
}

// MARK: - 单条消息

struct MessageRow: View {
    let message: ChatMessage
    let state: StickState
    var onSuggestionTap: ((String) -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 32)
                Text(message.content)
                    .font(.system(size: 16, weight: .medium))
                    .lineSpacing(4)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.navy)
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 7) {
                // 一个大泡泡
                VStack(alignment: .leading, spacing: 8) {
                    AssistantText(text: message.content, accent: state.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.97, green: 0.96, blue: 1.0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(red: 0.85, green: 0.80, blue: 0.98), lineWidth: 0.8)
                )
                .shadow(color: Color(red: 0.7, green: 0.6, blue: 1.0).opacity(0.15), radius: 6, x: 0, y: 3)

                // 追问意图按钮（竖向排列）
                if !message.suggestions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(message.suggestions, id: \.self) { suggestion in
                            Button {
                                onSuggestionTap?(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(state.accent)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(state.accent.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(state.accent, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct AssistantText: View {
    let text: String
    let accent: Color

    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseLine(_ line: String) -> some View {
        // 警告段落：温暖琥珀色高亮
        if line.contains("警告") || line.hasPrefix("⚠") {
            return AnyView(
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.88, green: 0.55, blue: 0.2))
                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.65, green: 0.4, blue: 0.1))
                }
            )
        }
        // 粗体标题行 **xxx**
        if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
            let inner = String(line.dropFirst(2).dropLast(2))
            return AnyView(
                Text(inner)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.navy)
            )
        }
        // bullet 行 - xxx 或 * xxx
        for prefix in ["- ", "• ", "· ", "* "] {
            if line.hasPrefix(prefix) {
                let body = String(line.dropFirst(prefix.count))
                return AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(accent)
                        Text(body)
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(3)
                            .foregroundColor(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                )
            }
        }
        // 编号行 1. xxx 或 1) xxx
        let numberedPattern = try! NSRegularExpression(pattern: "^([0-9]+)[.)、\\s]+(.+)$")
        if let match = numberedPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let numRange = Range(match.range(at: 1), in: line),
               let bodyRange = Range(match.range(at: 2), in: line) {
                let num = String(line[numRange])
                let body = String(line[bodyRange])
                return AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(num).")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(accent)
                        Text(body)
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(3)
                            .foregroundColor(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                )
            }
        }
        // 普通行
        return AnyView(
            Text(line)
                .font(.system(size: 15, weight: .regular))
                .lineSpacing(3)
                .foregroundColor(Theme.navy)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else {
                    parseLine(line)
                }
            }
        }
    }
}

// MARK: - 虚线分隔

struct DashedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(Theme.border,
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        .frame(height: 0.5)
    }
}
