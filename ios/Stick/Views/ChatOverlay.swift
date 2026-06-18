import SwiftUI
import UIKit

/// 检测 AI 回复结尾是否包含问询 (e.g. "要 X 还是 Y？" / "你还有其他症状吗？")
/// 返回问询文本 (去除末尾问号和空白), 如果没有问询返回 nil
/// - Parameter aiReply: AI 完整回复
/// - Returns: 问询文本或 nil
func detectAITailQuestion(_ aiReply: String) -> String? {
    let trimmed = aiReply.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // 取最后 1-2 句 (按中文/英文句末标点分割)
    let sentenceEnders = CharacterSet(charactersIn: "。！!?\n")
    var sentences: [String] = []
    var current = ""

    for ch in trimmed {
        current.append(ch)
        if String(ch).rangeOfCharacter(from: sentenceEnders) != nil {
            let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            current = ""
        }
    }
    let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !last.isEmpty { sentences.append(last) }

    // 检查最后 1-2 句
    let lastOneOrTwo = sentences.suffix(2).joined(separator: " ")
    guard !lastOneOrTwo.isEmpty else { return nil }

    // 问询标记: 问号 / 吗 / 怎么 / 为什么 / 什么 / 哪些 / 还是 / 或者 / 要不要 / 想不想 / 想了解
    let questionMarkers = ["？", "?", "吗", "怎么", "为什么", "什么", "哪些", "还是", "或者", "要不要", "想不想", "想了解", "想试试"]
    let hasQuestion = questionMarkers.contains { lastOneOrTwo.contains($0) }

    if hasQuestion {
        // 去除末尾问号
        var q = lastOneOrTwo
        while q.hasSuffix("？") || q.hasSuffix("?") {
            q = String(q.dropLast())
        }
        return q.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
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
    /// true 时 onAppear 自动打开相册/相机选图，发送给 LLM 视觉分析（主页 + 按钮触发）
    var pendingPhotoUpload: Bool = false
    /// true 时 onAppear 自动激活相机 chip 并开相机（主页相机按钮 / 拍食物 chip 触发）
    var pendingCamera: Bool = false
    /// 非空时 onAppear 自动调 LLM 给出对应 topic 的个性化建议（如"饮食建议"）
    var pendingTopic: String? = nil
    var onClose: () -> Void

    @State var messages: [ChatMessage] = []
    @State var input: String = ""
    @State var isStreaming: Bool = false
    @State var streamTask: Task<Void, Never>?
    @State private var showHistoryPopover: Bool = false
    @State private var pendingScrollId: UUID? = nil   // 点击历史 → 滚动定位
    @State private var scrollToBottom: Bool = false   // true=auto-scroll(anchor:.bottom) false=history导航(anchor:.top)
    /// 每次变化都滚到「正在加载」指示器（id = "streaming"），让动效可见
    @State private var scrollToStreamingTrigger: Int = 0
    @State private var keyboardVisible: Bool = false  // 键盘是否可见
    /// 上次已处理的 scrollTrigger 值（用于去重）
    @State private var lastHandledTrigger: Int = 0
    @FocusState private var inputFocused: Bool
    @ObservedObject private var history = ChatHistoryStore.shared
    @ObservedObject var userProfile = UserProfileStore.shared
    @State private var showCamera: Bool = false
    @State private var showPhotoLibrary: Bool = false
    @State private var capturedImage: UIImage?
    /// 打开相机/相册前保存用户已输入的文本，选完图后拼图片一起发给 LLM
    @State private var textBeforeCamera: String = ""
    /// 联网搜索状态文本（"正在联网搜索最新信息…"），nil 表示不在搜索
    @State private var searchStatus: String? = nil

    private let suggestedQuestions: [String] = [
        "今天步数多少",
        "肩膀酸怎么缓解",
        "最近睡眠质量不好",
    ]

    var body: some View {
        // 用 GeometryReader 读父高度, 全屏显示
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                cardContent()
            }
        }   // GeometryReader
        // 整 chat 范围：simultaneousGesture 让点击穿透到子 view，
        // 同时触发收键盘
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { dismissKeyboard() }
        )
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

    /// 收起键盘的统一入口（仅在键盘可见时才生效，避免无谓的 responder chain 遍历）
    private func dismissKeyboard() {
        guard keyboardVisible else { return }
        inputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 卡片本体 (全屏) — 内部 header / 消息 / input 由内层 VStack 撑开
    @ViewBuilder
    private func cardContent() -> some View {
        VStack(spacing: 0) {
            ChatHeaderView(onClose: onClose)
            DashedDivider()
            MessageAreaView(
                historyMessages: history.loadedMessages,
                messages: messages,
                isStreaming: isStreaming,
                suggestedQuestions: suggestedQuestions,
                state: state,
                scrollToBottom: $scrollToBottom,
                pendingScrollId: $pendingScrollId,
                scrollToStreamingTrigger: scrollToStreamingTrigger,
                searchStatus: searchStatus,
                onSend: { q in
                    input = q
                    send()
                },
                onSendDirect: { suggestion in
                    sendDirect(suggestion)
                },
                onHistorySectionTap: {
                    showHistoryPopover = true
                },
                onMessageSelected: { msgId in
                    scrollToBottom = false
                    pendingScrollId = msgId
                }
            )
            Spacer(minLength: 0)
            DashedDivider()
            ChatInputBar(
                input: $input,
                isStreaming: isStreaming,
                inputFocused: $inputFocused,
                features: features,
                cameraChips: cameraChips,
                onSend: { send() },
                onCameraChipTap: { chipInput in
                    textBeforeCamera = input
                    input = chipInput
                    showCamera = true
                },
                onPhotoLibraryTap: {
                    textBeforeCamera = input
                    showPhotoLibrary = true
                },
                onCameraTap: { currentInput in
                    textBeforeCamera = currentInput
                    showCamera = true
                }
            )
        }
        .background(Theme.card)
        .sheet(isPresented: $showHistoryPopover) {
            HistoryPopoverContentView(
                historyMessages: history.loadedMessages,
                accent: state.accent,
                onMessageSelected: { msgId in
                    scrollToBottom = false
                    pendingScrollId = msgId
                },
                onDismiss: {
                    showHistoryPopover = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // 点 cardContent 任意空白处 → 收键盘（TextField / Button / 内层 ScrollView 的手势优先，会先吃掉它们的 tap）
        .onTapGesture {
            inputFocused = false
            // UIKit 兜底
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            // 检查短期标签是否过期
            UserInterestTagStore.shared.resetShortTermIfExpired()
            // 自动弹出键盘（延迟 0.1s，等 overlay 动画完成后再弹）
            // 但如果是相机/相册自动开图场景，跳过键盘弹起（避免 UI 冲突）
            let willAutoOpenImage = pendingCamera || pendingPhotoUpload
            if !willAutoOpenImage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.inputFocused = true
                }
            }
            // 主页 + 按钮触发：自动打开相册选图，发送给 LLM 视觉分析
            if pendingPhotoUpload {
                textBeforeCamera = "请分析这张图片中的健康相关内容"
                // 延迟到键盘弹出后再开 ImagePicker，避免 UI 冲突
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showPhotoLibrary = true
                }
            }
            // 主页相机按钮 / 拍食物 chip 触发：自动激活拍食物 chip 并开相机
            if pendingCamera {
                // 模拟点击"拍食物"chip：保留当前输入 + 预填 chip 文案 + 打开相机
                let photoFoodChip = features.first { $0.title == "拍食物" }
                if let chip = photoFoodChip {
                    textBeforeCamera = ""
                    input = chip.seed
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showCamera = true
                }
            }

            // 从持久化 store 恢复历史 messages
            history.loadInitial()
            if !history.loadedMessages.isEmpty {
                messages = history.loadedMessages.map { m in
                    ChatMessage(
                        id: m.id,
                        role: m.role == "user" ? .user : .assistant,
                        content: m.content,
                        suggestions: m.suggestions
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
            } else if let topic = pendingTopic, !topic.isEmpty {
                // autoTopic chip 触发：把 user msg 加入列表 + 走专属生成流程
                input = initialText
                let userMsgId = UUID()
                messages.append(ChatMessage(id: userMsgId, role: .user, content: initialText))
                history.append(PersistedChatMessage(id: userMsgId, role: "user", content: initialText))
                _ = UserProfileStore.shared.recordUserMessage()
                self.pendingScrollId = userMsgId
                if topic == "饮食建议" {
                    generateDietAdvice(seed: initialText)
                } else {
                    // 未知 topic：fallback 通用 send
                    send()
                }
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
        .onChange(of: scrollTrigger) { oldTrigger, newTrigger in
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
            // 把当前 messages 写回 store（包含推荐主题）
            let newHistory = messages.map { m in
                PersistedChatMessage(
                    id: m.id,
                    role: m.role == .user ? "user" : "assistant",
                    content: m.content,
                    suggestions: m.role == .assistant ? m.suggestions : []
                )
            }
            print("[ChatOverlay] onDisappear: saving \(newHistory.count) messages, user msgs: \(newHistory.filter { $0.role == "user" }.count)")
            history.replaceAll(with: newHistory)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(image: $capturedImage, sourceType: .camera)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoLibrary) {
            ImagePicker(image: $capturedImage, sourceType: .photoLibrary)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { oldImage, newImage in
            if let image = newImage, let data = image.jpegData(compressionQuality: 0.7) {
                // 优先用 chip 预填或用户已输入的文本，没有则用默认消息
                let currentText = input.trimmingCharacters(in: .whitespacesAndNewlines)
                let textToSend = currentText.isEmpty
                    ? (textBeforeCamera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "请分析这张图片中的健康相关内容"
                        : textBeforeCamera)
                    : currentText
                input = textToSend
                send(imageData: data)
                textBeforeCamera = ""
            }
        }
    }

    // MARK: - 输入栏数据

    private let features: [InputFeature] = [
        InputFeature(icon: "fork.knife",         title: "饮食建议",  seed: "推荐健康饮食方案"),
        InputFeature(icon: "doc.text.fill",      title: "报告解读",  seed: "解读我的健康报告"),
        InputFeature(icon: "camera.viewfinder",  title: "拍食物",    seed: "拍照分析我的饮食状态"),
        InputFeature(icon: "person.badge.plus",  title: "就医",      seed: "推荐合适的医院和科室"),
        InputFeature(icon: "cross.case.fill",    title: "AI 诊室",   seed: "AI 医生问诊"),
    ]

    /// 需要"打开相机后文字+图片一起发送"的 chip（只这两个走相机，其他都是视觉提示）
    private let cameraChips: Set<String> = ["报告解读", "拍食物"]

    // MARK: - 发送 / 取消

    private func send(imageData: Data? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsgId = UUID()
        messages.append(ChatMessage(id: userMsgId, role: .user, content: text, imageData: imageData))
        input = ""
        capturedImage = nil
        print("[ChatOverlay] send(): user msg added, total msgs now: \(messages.count)")

        self.scrollToBottom = false
        self.pendingScrollId = userMsgId

        _ = UserProfileStore.shared.recordUserMessage()

        let tags = TopicExtractor.extract(from: text)
        UserInterestTagStore.shared.record(tags: tags)
        UserInterestTagStore.shared.resetShortTermIfExpired()

        BodyMetricsStore.shared.extract(from: text)

        // 对话解析睡眠（鲁棒性）：从 user msg 提取 bedTime / wakeTime / duration
        // 写 HealthStore + 更新 UserProfile 睡眠习惯
        if let sleepInfo = SleepParser.parse(text, now: Date()) {
            if let bed = sleepInfo.bedTime, let wake = sleepInfo.wakeTime {
                HealthStore.shared.writeSleepSegment(bedTime: bed, wakeTime: wake)
            }
            UserProfileStore.shared.updateSleepHabit(from: sleepInfo)
        }

        isStreaming = true

        // 3 段式流式：本地分析 → 联网搜索 → 综合总结
        // 每段都是独立消息，收到首 chunk 后立刻显示，避免单段太长等待
        let analysisId = UUID()    // 段 1: 本地个性化分析
        let webId      = UUID()    // 段 2: 联网参考
        let synthId    = UUID()    // 段 3: 综合建议
        messages.append(ChatMessage(id: analysisId, role: .assistant, content: ""))
        messages.append(ChatMessage(id: webId,      role: .assistant, content: ""))
        messages.append(ChatMessage(id: synthId,    role: .assistant, content: ""))

        // 滚到「正在加载」指示器，让动效可见
        self.scrollToStreamingTrigger &+= 1

        let ctx = buildContext()
        streamTask = Task {
            // 段 1: 本地分析 — 1-2 句「现状/问题」（快）
            await MainActor.run {
                searchStatus = "正在分析您的健康数据…"
                self.scrollToStreamingTrigger &+= 1
            }
            let analysisOk = await streamInto(
                messageId: analysisId,
                stream: LLMService.sendMessageStream(
                    """
                    第一行输出【个性化分析】标题，第二行开始写 1-2 句「用户当下最突出的健康现状/问题」总结，60 字以内。
                    严格规则：
                    - 第一行必须是【个性化分析】（保持这个格式）
                    - 只描述现状，不给建议
                    - 不引用联网信息
                    - 不重复用户的原话
                    - 不要说"根据数据"等套话
                    - 严禁出现"设闹钟/设置提醒/定时通知/下载app/买手环/加群/挂号"——本 app 没这些功能
                    """,
                    context: ctx
                )
            )
            await MainActor.run { searchStatus = nil }
            if Task.isCancelled { return }

            // 段 2: 联网搜索 — 关键信息提炼
            if let imgData = imageData {
                await MainActor.run {
                    searchStatus = "正在分析图片…"
                    self.scrollToStreamingTrigger &+= 1
                }
                let stream2: AsyncThrowingStream<String, Error> = LLMService.sendMessageStreamWithImage(text, context: ctx, imageData: imgData)
                _ = await streamInto(messageId: webId, stream: stream2)
                await MainActor.run { searchStatus = nil }
            } else {
                await MainActor.run {
                    searchStatus = "正在联网搜索最新信息…"
                    self.scrollToStreamingTrigger &+= 1
                }
                let webResults: [SearchResult] = await streamIntoCollectingSearch(
                    messageId: webId,
                    stream: LLMService.sendMessageStreamWithSearch(
                        """
                        第一行输出【健康分析】标题，第二行开始写与用户问题相关的「健康原理/事实」2-3 条，80 字以内。
                        严格规则：
                        - 第一行必须是【健康分析】（保持这个格式）
                        - 必须是健康相关的事实/原理，不是泛泛闲聊
                        - 不要重复用户的原话
                        - 用 [n] 角标对应来源
                        """,
                        context: ctx
                    )
                )
                await MainActor.run { searchStatus = nil }
                if Task.isCancelled { return }

                // 段 3: 综合 — 只给可执行步骤，不复述前两段
                await MainActor.run {
                    searchStatus = "正在综合分析…"
                    self.scrollToStreamingTrigger &+= 1
                }
                let webSummary = webResults.prefix(5).map { "[\($0.index)] \($0.title ?? $0.url)" }.joined(separator: "\n")
                let synthPrompt = """
                你是健康助理。基于下方「本地现状」+「联网要点」回答用户。
                **根据用户问题类型采用不同输出方式**：

                【A. 操作建议型】（如"怎么办"、"怎么缓解"、"怎么改善"）
                - 标题"【立即行动】"
                - 只给 2-4 条可执行步骤，每条 30 字以内，编号 1./2./3.
                - 不超过 200 字
                - 必须立刻能执行，不要"建议咨询医生"等空话
                - 用户已看过前两段，不要重复现状/事实
                - 不要再说"根据您的..."等套话
                - 不要再次引用 [n] 角标

                【B. 科普/原理型】（如"为什么…"、"怎么回事"、"原理"、"形成原因"、"对身体的影响"）
                - 标题"【深度解析】"
                - 给完整、详细的长文解释（800-1500 字，不要限制）
                - 结构：①核心机制（为什么）②具体过程/原因（怎么发生的）③对身体的实际影响 ④与用户实际的关联
                - 用户问到的点必须讲透，不要被字数限制而省略
                - 涉及 [n] 来源时直接 inline 引用

                【硬性禁令 - 不论 A/B 都要遵守】
                - **绝对不要**让用户"设闹钟 / 设置提醒 / 定时通知"——本 app 没有这个功能
                - **不要**让用户"下载其他 app / 买手环 / 加群"
                - 所有建议必须当下就能直接做

                【本地现状】
                \(analysisOk.isEmpty ? "（暂无）" : analysisOk)

                【联网要点】
                \(webSummary.isEmpty ? "（未触发搜索）" : webSummary)

                【用户原问题】
                \(text)
                """
                _ = await streamInto(
                    messageId: synthId,
                    stream: LLMService.sendMessageStream(synthPrompt, context: ctx)
                )
                await MainActor.run { searchStatus = nil }
            }
            if Task.isCancelled { return }

            // 解析食物记录并存储；同时从所有 assistant 消息里剥掉 [FOOD] 行 + 兜底过滤禁用功能
            await MainActor.run {
                for i in messages.indices {
                    if messages[i].role == .assistant {
                        parseAndStoreFoodEntry(from: messages[i].content)
                        messages[i].content = stripFoodLine(messages[i].content)
                        messages[i].content = stripUnavailableFeatureLines(messages[i].content)
                    }
                }
            }

            await MainActor.run {
                isStreaming = false
                searchStatus = nil
            }

            LLMService.markAnalysisDone()
            // 建议话题基于最终综合建议（synthId）
            await generateSuggestions(for: synthId)
            // 更新用户画像
            await summarizeUserProfile()
        }

        inputFocused = false
        // UIKit 兜底：iOS TextField(axis: .vertical) + .focused() 偶有不响应
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 从 LLM 返回文本中解析 [FOOD] 行并存储到 FoodLogStore
    private func parseAndStoreFoodEntry(from text: String) {
        // 查找 [FOOD] 行
        guard let range = text.range(of: "\\[FOOD\\]\\s*(.+)", options: .regularExpression) else { return }
        let line = String(text[range])
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 3 else { return }
        let mealStr = parts[0].replacingOccurrences(of: "[FOOD]", with: "").trimmingCharacters(in: .whitespaces)
        let foodName = parts[1].trimmingCharacters(in: .whitespaces)
        let calStr = parts[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "kcal", with: "").trimmingCharacters(in: .whitespaces)
        let calories = Int(calStr)
        let meal: MealType
        switch mealStr {
        case "早餐": meal = .breakfast
        case "午餐": meal = .lunch
        case "晚餐": meal = .dinner
        default: meal = FoodLogStore.mealType()
        }
        FoodLogStore.shared.addEntry(meal: meal, foodName: foodName, calories: calories == 0 ? nil : calories)
    }

    /// 从 LLM 回复中剥掉 [FOOD] 行（结构化数据，不展示给用户）
    private func stripFoodLine(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\n?\\[FOOD\\][^\\n]*") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 兜底过滤：剥掉含"提醒/闹钟/定时/下载/手环/加群"的整行/整句
    /// 防止 LLM 偶尔还是瞎建议（本 app 没这些功能）
    private func stripUnavailableFeatureLines(_ text: String) -> String {
        // 触发词列表：扩展性强
        let bannedTokens = ["提醒", "闹钟", "定时", "下载", "手环", "加群", "挂号", "公众号"]
        let lines = text.components(separatedBy: "\n")
        let kept = lines.filter { line in
            // 整行含任意触发词则过滤
            !bannedTokens.contains { line.contains($0) }
        }
        return kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 流式输出辅助：把 stream 的 chunks 100ms 节流刷到指定 messageId，返回最终文本
    @discardableResult
    private func streamInto(
        messageId: UUID,
        stream: AsyncThrowingStream<String, Error>
    ) async -> String {
        let flushInterval: TimeInterval = 0.1
        var buffer = ""
        var lastFlush = Date()
        var fullText = ""

        let flushBuffer: () async -> Void = {
            guard !buffer.isEmpty else { return }
            let toFlush = buffer
            buffer = ""
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content += toFlush
                }
            }
        }

        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                buffer += chunk
                fullText += chunk
                if Date().timeIntervalSince(lastFlush) >= flushInterval {
                    await flushBuffer()
                    lastFlush = Date()
                }
            }
            await flushBuffer()
        } catch {
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                    let prefix = messages[idx].content.isEmpty ? "" : messages[idx].content + "\n\n"
                    messages[idx].content = "\(prefix)⚠️ \(err)"
                }
            }
        }
        return fullText
    }

    /// 流式输出辅助（同 streamInto + 捕获末尾的搜索引用 sentinel）
    @discardableResult
    private func streamIntoCollectingSearch(
        messageId: UUID,
        stream: AsyncThrowingStream<String, Error>
    ) async -> [SearchResult] {
        let flushInterval: TimeInterval = 0.1
        var buffer = ""
        var lastFlush = Date()
        var collected: [SearchResult] = []

        let flushBuffer: () async -> Void = {
            guard !buffer.isEmpty else { return }
            let toFlush = buffer
            buffer = ""
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[idx].content += toFlush
                }
            }
        }

        do {
            for try await chunk in stream {
                if Task.isCancelled { break }

                // 捕获末尾的搜索引用 sentinel
                if chunk.hasPrefix("__SEARCH_RESULTS__:") {
                    let json = String(chunk.dropFirst("__SEARCH_RESULTS__:".count))
                    if let data = json.data(using: .utf8),
                       let refs = try? JSONDecoder().decode([SearchResult].self, from: data) {
                        collected = refs
                        await MainActor.run {
                            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                                messages[idx].searchResults = refs
                            }
                        }
                    }
                    continue
                }

                buffer += chunk
                if Date().timeIntervalSince(lastFlush) >= flushInterval {
                    await flushBuffer()
                    lastFlush = Date()
                }
            }
            await flushBuffer()
        } catch {
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                    let err = (error as? LLMError)?.errorDescription ?? error.localizedDescription
                    let prefix = messages[idx].content.isEmpty ? "" : messages[idx].content + "\n\n"
                    messages[idx].content = "\(prefix)⚠️ \(err)"
                }
            }
        }
        return collected
    }

    /// 直接发送文字（不经过 input 框，用于意图按钮）
    private func sendDirect(_ text: String) {
        let userMsgId = UUID()
        messages.append(ChatMessage(id: userMsgId, role: .user, content: text))

        self.scrollToBottom = false
        self.pendingScrollId = userMsgId

        _ = UserProfileStore.shared.recordUserMessage()

        // 提取标签并记录
        let tags = TopicExtractor.extract(from: text)
        UserInterestTagStore.shared.record(tags: tags)
        UserInterestTagStore.shared.resetShortTermIfExpired()

        // 从用户输入中提取身体数据
        BodyMetricsStore.shared.extract(from: text)

        // 对话解析睡眠（鲁棒性）
        if let sleepInfo = SleepParser.parse(text, now: Date()) {
            if let bed = sleepInfo.bedTime, let wake = sleepInfo.wakeTime {
                HealthStore.shared.writeSleepSegment(bedTime: bed, wakeTime: wake)
            }
            UserProfileStore.shared.updateSleepHabit(from: sleepInfo)
        }

        isStreaming = true

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        let ctx = buildContext()
        streamTask = Task {
            do {
                // 100ms 节流：合并 chunks 减少 re-render
                let flushInterval: TimeInterval = 0.1
                var buffer = ""
                var lastFlush = Date()

                let flushBuffer: () async -> Void = {
                    guard !buffer.isEmpty else { return }
                    let toFlush = buffer
                    buffer = ""
                    await MainActor.run {
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                            self.messages[idx].content += toFlush
                        }
                    }
                }

                for try await chunk in LLMService.sendMessageStream(text, context: ctx) {
                    if Task.isCancelled { break }
                    buffer += chunk
                    if Date().timeIntervalSince(lastFlush) >= flushInterval {
                        await flushBuffer()
                        lastFlush = Date()
                    }
                }
                await flushBuffer()
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

            await generateSuggestions(for: assistantId)

            // 更新用户画像
            await self.summarizeUserProfile()
        }
    }

    /// 根据用户兴趣标签生成 1-3 条推荐话题
    func generateSuggestions(for messageId: UUID) async {
        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              messages[idx].role == .assistant else { return }

        let response = messages[idx].content

        // 用户上一条消息（追问的来源）
        let userLastMessage: String? = {
            if let pos = messages.firstIndex(where: { $0.id == messageId }), pos > 0 {
                let prev = messages[messages.index(messages.startIndex, offsetBy: pos - 1)]
                if prev.role == .user { return prev.content }
            }
            return nil
        }()

        let suggestions = await fetchSuggestions(
            from: response,
            userLastMessage: userLastMessage
        )

        await MainActor.run {
            guard let i = self.messages.firstIndex(where: { $0.id == messageId }) else { return }
            var updated = self.messages
            updated[i].suggestions = suggestions
            self.messages = updated
            self.scrollToBottom = true
            self.pendingScrollId = messageId
        }
    }

    private func fetchSuggestions(from response: String, userLastMessage: String?) async -> [String] {
        var userContext = ""
        if let last = userLastMessage {
            userContext += "用户最近一条输入：\(last)\n"
        }
        let profile = UserProfileStore.shared.profile
        if !profile.isEmpty {
            userContext += "用户画像：\(profile)\n"
        }

        let aiTailQuestion = detectAITailQuestion(response)
        let hasQuestion = aiTailQuestion != nil

        let prompt = """
        你是健康助手的「用户下一步话题推荐器」。

        【任务】
        根据用户最近输入、用户画像、上一轮 AI 回复、**AI 结尾是否有问询**，推荐 **3 个用户接下来会关心的、想深入了解的话题**。
        这些话题是 user 接下来想探索的方向（不是 AI 给建议，不是 user 主动打字问什么）。

        【用户画像】（长期关心方向，强信号）
        \(userContext.isEmpty ? "" : "\(userContext)")

        【本轮上下文】
        - 用户最近一条输入: \(input)
        - AI 最新回复: \(response)

        【AI 结尾问询检测】(关键: 决定推荐策略)
        - 是否有问询: \(hasQuestion ? "true" : "false")
        - 问询文本: \(aiTailQuestion ?? "（无）")

        【推荐原则】
        1. **核心：用户关心什么，他们可能想了解什么**
           - user 看到 AI 回复后，心里浮起的"我也想知道这个" / "这个跟我有关" / "我还好奇这点"的方向
           - 是 user 会**接着探索**的内容，不是空泛健康话题
        2. **不指挥用户**：不要 "试试 X"、"喝杯 X"、"做 X"、"起身 X" 这种指挥 user 执行动作的话题
        3. **【关键】从用户画像出发**：每条必须**直接关联画像**里描述的长期关心方向（职业/生活习惯/既往症状/年龄/性别）。画像里没的方向不推
        4. **贴近 AI 给的内容**：在画像驱动基础上，基于 AI 提到的具体点延伸
        5. **多样性**：3 条必须**覆盖不同角度**（机制/操作/数字/风险/替代方案/鉴别等）。禁止 3 条同构模板
        6. **【核心 - 输出形式】必须是「拓展话题」，严禁输出问句**
           - 正确：陈述/名词短语（"腰疼的具体原因有哪些"、"久坐对腰椎的影响"、"腰肌劳损如何预防"）
           - 错误：问句（"腰疼是腰椎的问题吗"、"腰疼怎么办"、"腰疼要做什么检查"）
           - 必须是**话题名称**，不是 user 主动问 AI 的问题
           - 是 user 想"接着探索的方向"，不是 user "想问什么"
        7. **【问询分支】AI 结尾有问询时 (上面 hasQuestion = true)**：
           - AI 主动抛出的问询是 user 当前最需要选择/回应的核心
           - 推荐主题应该**照搬**问询中给出的分支，让 user 可以一键选
           - 例：AI 问 "你希望了解生理机制还是缓解方法？" → 推荐按钮就是 "生理机制" / "缓解方法" (+1 条画像延伸)
           - 例：AI 问 "你想先尝试物理缓解还是直接用药？" → 推荐按钮就是 "物理缓解" / "直接用药" (+1 条画像延伸)
           - 例：AI 问 "你还有其他不适症状吗？" → 推荐按钮是 user 想补充的具体症状方向 (e.g. "心跳也很快" / "出汗多" / "持续了 3 天")
           - 这些按钮作为 user 选择项，user 选完再深入分析；不要无视问询输出泛泛话题
        8. **【无问询】hasQuestion = false 时**：按原则 1-6 处理 (画像驱动 + 内容延伸)，输出**话题拓展**而非问句

        【输出格式】
        - 输出 3 条，每条独占一行
        - 单条 ≤ 18 字
        - 口语化（像聊天输入或 topic tag）
        - 模拟 user 看到 AI 回复后，自己会想深入了解的话题

        【风格示例】(好 — 话题拓展，非问句)

        场景 A: AI 结尾问 "要药物治疗还是物理治疗？" + 程序员画像 (腰颈酸)
        - 腰肌劳损如何预防 (照搬问询分支 — 物理)
        - 止痛药副作用 (照搬问询分支 — 药物)
        - 程序员久坐腰颈酸调理 (画像延伸)

        场景 B: AI 结尾问 "还有其他症状吗？" + 妈妈画像 (头痛)
        - 心跳异常偏快 (具体症状方向)
        - 头痛持续 3 天 (症状时长)
        - 孩子发烧护理 (画像延伸)

        场景 C: AI 结尾问 "你希望了解机制还是缓解？" + 高管画像 (胸闷)
        - 胸闷的生理机制 (照搬问询分支)
        - 应急缓解方法 (照搬问询分支)
        - 应酬多时血压管理 (画像延伸)

        场景 D: AI 结尾无问询 — 话题拓展示例
        用户说"最近老是腰疼"
        - 腰疼的具体原因有哪些 (机制)
        - 久坐对腰椎的影响 (因果)
        - 腰肌劳损 vs 椎间盘突出 (鉴别)

        【风格示例】(❌ 不好)
        - 站起来走一走 (指挥)
        - 试试喝杯咖啡 (指挥)
        - ❌ 腰疼是腰椎的问题吗 (问句 — 必须改成拓展话题)
        - ❌ 腰疼怎么办 (问句)
        - ❌ 腰疼要做什么检查 (问句)
        - ❌ 午餐后血糖怎么测 (太泛，跟 user 画像无关)
        - ❌ AI 问 "X 还是 Y" 时却推跟 X Y 都无关的话题 (无视问询)
        - ❌ AI 结尾无问询时却强行照搬 (没问询就没分支可照搬)

        硬性规则：
        1. **核心：跟用户画像强关联** — 每条必须对应画像里描述的方向
        2. **不指挥 user**：严禁"试试"、"起身"、"喝杯"、"做一组"、"不妨"、"建议"等动作或建议词
        3. **多样性 + 问询分支**：3 条必须角度不同；hasQuestion=true 时至少 2 条要照搬问询中的分支
        4. 不带序号、注释、说明文字
        5. 不输出抽象话题标签（如单独"健康"、"睡眠"）
        6. 单条 ≤ 18 字
        7. **【硬性禁令 - 严禁问句】**
           - **绝对不要输出问句**（"X 怎么办"、"X 是不是 Y"、"要做什么检查"）
           - 必须是**话题拓展**（"X 的具体原因有哪些"、"X 的鉴别诊断"、"X 对 Y 的影响"）
           - 错误：腰疼是腰椎的问题吗 → 正确：腰疼的具体原因有哪些
           - 错误：腰疼怎么办 → 正确：腰疼的常见缓解方法
           - 错误：腰疼要做什么检查 → 正确：腰疼的相关检查项目
        8. **【硬性禁令 - 功能范围】**
           - 严禁出现"设闹钟 / 设置提醒 / 定时通知 / 到点叫我"——本 app 没有这个功能
           - 严禁出现"下载 XX app / 买手环 / 加群咨询"——本 app 不推荐外链/外设
           - 严禁出现"咨询医生 / 去医院挂 XX 科"等空话（除非用户主动问就医）
        """

        do {
            let result = try await LLMService.sendMessage(prompt, context: "生成下一步输入预测")
            let lines = result.components(separatedBy: "\n")
            var suggestions: [String] = []
            for line in lines {
                var s = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if s.isEmpty { continue }
                if s.contains("追问") || s.contains("建议") { continue }
                s = s.replacingOccurrences(of: "^[0-9]+[.)、\\s]+", with: "", options: .regularExpression)
                s = s.replacingOccurrences(of: "[？?]+$", with: "", options: .regularExpression)
                s = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let isQuestion = s.hasSuffix("吗") || s.hasSuffix("?") || s.hasSuffix("？")
                    || s.hasPrefix("怎么") || s.hasPrefix("为什么") || s.hasPrefix("是不是")
                    || s.contains("怎么办") || s.contains("如何做")
                if isQuestion { continue }
                if s.count >= 4 && !s.contains("某动作") && !s.contains("某个") && !s.contains("具体") && !s.contains("各种") && !s.contains("建议") {
                    suggestions.append(s)
                }
                if suggestions.count >= 3 { break }
            }
            return suggestions.isEmpty ? defaultSuggestions : suggestions
        } catch {
            return defaultSuggestions
        }
    }

    private var defaultSuggestions: [String] {
        ["肩颈酸的具体原因", "今天睡眠质量", "久坐对腰椎的影响"]
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
}

// MARK: - 消息模型

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    let id: UUID
    let role: Role
    var content: String
    var suggestions: [String] = []
    /// 用户消息可选带的图片数据
    var imageData: Data? = nil
    /// 联网搜索引用（assistant 消息可能有，文本里带 [n] 角标对应）
    var searchResults: [SearchResult] = []

    init(id: UUID = UUID(), role: Role, content: String, suggestions: [String] = [], imageData: Data? = nil, searchResults: [SearchResult] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.suggestions = suggestions
        self.imageData = imageData
        self.searchResults = searchResults
    }
}

/// Input feature chip model (used by ChatInputBar)
struct InputFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let seed: String
}
