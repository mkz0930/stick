import SwiftUI

/// Chat 底栏（v2）：直接叠在主页底部，跟主界面无缝融合。
/// - 默认高度 ≈ 220pt（header 32pt + 消息列表 + inputBar 44pt）
/// - 消息多时 list 可滚；inputBar 永远贴底
/// - 关闭按钮在右上；点 chat 之外的区域（需要点 homeBody）目前是 noop，可以由外层处理
struct ChatOverlay: View {
    let state: StickState
    let initialText: String
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
    /// 发送消息后，滚动到这条用户消息的位置（用于发送完毕立即定位到用户问题）
    @State private var pendingScrollToUserMsgId: UUID? = nil
    /// 标记：初始加载完历史消息后，需要自动滚到底部
    @State private var needsInitialScroll: Bool = false
    @State private var keyboardVisible: Bool = false  // 键盘是否可见
    /// 上次已处理的 scrollTrigger 值（用于去重）
    @State private var lastHandledTrigger: Int = 0
    @ObservedObject private var history = ChatHistoryStore.shared
    @ObservedObject private var userProfile = UserProfileStore.shared

    private let suggestedQuestions: [String] = [
        "我刚坐了一上午，怎么办？",
        "眼睛干涩怎么缓解？",
        "午饭后困得不行，有什么办法？",
        "睡前总刷手机，怎么改？",
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
                self.needsInitialScroll = true
            }
            input = initialText
            if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                send()
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
                                    MessageRow(message: msg, state: state)
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
                        .onChange(of: needsInitialScroll) { needsScroll in
                            // 初始加载完历史消息后，等待一帧再滚动
                            guard needsScroll else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                if let last = self.messages.last {
                                    self.pendingScrollId = last.id
                                }
                                self.needsInitialScroll = false
                            }
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

            // 每 3 条用户消息总结一次用户画像
            if shouldSummarize {
                await summarizeUserProfile()
            }
        }
    }

    /// 调用 LLM 总结用户最近 3 条消息，更新用户画像
    private func summarizeUserProfile() async {
        let recentUserMessages = messages
            .filter { $0.role == .user }
            .suffix(3)
            .map(\.content)

        let oldProfile = userProfile.profile

        var prompt = "你是一个用户画像分析助手。请根据以下用户的对话历史，总结用户的画像信息。"
        prompt += "包括但不限于：用户的身体状况、健康需求、生活习惯、行为模式等。"
        prompt += "请用简洁的中文总结（50字以内）。\n\n"

        if !oldProfile.isEmpty {
            prompt += "原有的用户画像：\n\(oldProfile)\n\n"
        }

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
        return profileBlock + """
        - 当前时间: \(time) (\(period))
        - 当前姿态: \(state.actionPhrase) (\(state.englishName))
        - 用户类型: 办公室白领
        - 备注: 给出符合该时段 + 该姿态的即时可行建议
        """
    }
}

// MARK: - 消息模型

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - 单条消息

struct MessageRow: View {
    let message: ChatMessage
    let state: StickState

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
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(state.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    AssistantText(text: message.content, accent: state.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
                Spacer(minLength: 16)
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

    private func stripBullet(_ s: String) -> String? {
        for p in ["- ", "• ", "· ", "* "] where s.hasPrefix(p) {
            return String(s.dropFirst(p.count))
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else if let body = stripBullet(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(accent)
                        Text(body)
                            .font(.system(size: 16, weight: .medium))
                            .lineSpacing(4)
                            .foregroundColor(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(line)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(4)
                        .foregroundColor(Theme.navy)
                        .fixedSize(horizontal: false, vertical: true)
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
