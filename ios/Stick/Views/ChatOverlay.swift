import SwiftUI

/// Chat 底栏（v2）：直接叠在主页底部，跟主界面无缝融合。
/// - 默认高度 ≈ 220pt（header 32pt + 消息列表 + inputBar 44pt）
/// - 消息多时 list 可滚；inputBar 永远贴底
/// - 关闭按钮在右上；点 chat 之外的区域（需要点 homeBody）目前是 noop，可以由外层处理
struct ChatOverlay: View {
    let state: StickState
    let initialText: String
    var onClose: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @ObservedObject private var history = ChatHistoryStore.shared

    private let suggestedQuestions: [String] = [
        "我刚坐了一上午，怎么办？",
        "眼睛干涩怎么缓解？",
        "午饭后困得不行，有什么办法？",
        "睡前总刷手机，怎么改？",
    ]

    var body: some View {
        // 用 GeometryReader 读父高度, 展开时撑满 90%+
        GeometryReader { geo in
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
            .background(
                // 只圆顶部两角，底部贴边 (展开后全圆)
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 14,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 14
                    ),
                    style: .continuous
                )
                .fill(Theme.card)
            )
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
            .shadow(color: .black.opacity(0.10), radius: 0, y: 0)
            .padding(.horizontal, 12)         // 水平留白
            .padding(.top, 8)                  // 顶部留白（让 card 浮起来）
            .frame(height: geo.size.height * 0.95, alignment: .bottom)
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
                input = initialText
                if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    send()
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
                history.replaceAll(with: newHistory)
            }
        }   // GeometryReader
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
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
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
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

        messages.append(ChatMessage(role: .user, content: text))
        input = ""
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
        return """
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
