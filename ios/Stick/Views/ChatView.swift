import SwiftUI

/// 健康问答聊天视图（ATLAS v6 风格）：
///  - 米色背景 + 弱网格
///  - header: brand mark + 标题 + 状态 tag + 关闭
///  - user 气泡：navy 底 + 米色字，右对齐
///  - assistant 卡片：白底 + 状态色左 border，左对齐
///  - 底部 mini input bar（保留 chat 交互）
///  - 空状态：4 个建议问题 chip（一键发送）
struct ChatView: View {
    let state: StickState
    let initialText: String
    var onClose: () -> Void

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>?

    private let suggestedQuestions: [String] = [
        "我刚坐了一上午，怎么办？",
        "眼睛干涩怎么缓解？",
        "午饭后困得不行，有什么办法？",
        "睡前总刷手机，怎么改？",
    ]

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                DashedDivider()
                    .padding(.horizontal, 20)

                if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                inputBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            input = initialText
            if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                send()
            }
        }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            // 弱网格
            Canvas { ctx, size in
                let step: CGFloat = 36
                var x: CGFloat = 0
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(Theme.grid), lineWidth: 0.5)
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(Theme.grid), lineWidth: 0.5)
                    y += step
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            // brand mark
            ZStack {
                Circle()
                    .stroke(Theme.navy, lineWidth: 2)
                    .frame(width: 26, height: 26)
                Rectangle().fill(Theme.navy).frame(width: 11, height: 1.6)
                Rectangle().fill(Theme.navy).frame(width: 1.6, height: 11)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ATLAS · 健康助手")
                    .font(.system(size: 15, weight: .black))
                    .tracking(0.08)
                    .foregroundColor(Theme.navy)
                Text("OFFICE WORKER · 简单可行的小建议")
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .tracking(0.2)
                    .foregroundColor(Theme.slate)
                    .lineLimit(1)
            }

            Spacer()

            // 状态色 tag
            HStack(spacing: 4) {
                Circle().fill(state.accent).frame(width: 6, height: 6)
                Text(state.englishName)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.2)
                    .foregroundColor(state.accent)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(state.accentSoft.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(state.accent, lineWidth: 1)
            )

            // 关闭
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("— ASK · 小问答 · \(state.actionPhrase) —")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(state.accent)
                Text("问点关于你")
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .foregroundColor(Theme.navy)
                + Text("身体")
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .italic()
                    .foregroundColor(state.accent)
                + Text("的事")
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .foregroundColor(Theme.navy)

                Text("结合你当前状态，给 3-5 条立即可执行的小建议")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.slate)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SUGGESTED · 试试这些")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Theme.slate)
                    .padding(.top, 12)

                ForEach(suggestedQuestions, id: \.self) { q in
                    Button {
                        input = q
                        send()
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Text("›")
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(state.accent)
                            Text(q)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.navy)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        MessageRow(message: msg, state: state)
                            .id(msg.id)
                    }
                    if isStreaming {
                        // 占位 / 思考中
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(state.accent)
                            Text("正在生成建议…")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .tracking(0.3)
                                .foregroundColor(Theme.slate)
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
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

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("继续问点健康相关…", text: $input, axis: .vertical)
                    .lineLimit(1...3)
                    .tint(Theme.navy)
                    .foregroundColor(Theme.navy)
                    .accentColor(Theme.navy)
                    .font(.system(size: 14))
                    .disabled(isStreaming)

                if input.isEmpty && !isStreaming {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Auto")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(Theme.slate)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.card)
                    )
                }
            }
            .frame(minHeight: 38)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.border, lineWidth: 1)
            )

            Button {
                send()
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(Theme.darkText)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isStreaming ? Theme.mist : state.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
        }
    }

    // MARK: - 发送 / 取消

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // 1) append user message
        messages.append(ChatMessage(role: .user, content: text))
        input = ""
        isStreaming = true

        // 2) prepare empty assistant message that we'll stream into
        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: ""))

        // 3) start stream task
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
                        messages[idx].content = messages[idx].content.isEmpty
                            ? "⚠️ \(err)\n\n请检查网络后重试。"
                            : messages[idx].content + "\n\n⚠️ 流中断: \(err)"
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

private struct MessageRow: View {
    let message: ChatMessage
    let state: StickState

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.darkText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.navy)
                    )
            }
        case .assistant:
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(state.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(state.accent)
                        Text("ATLAS · \(state.actionPhrase)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(0.2)
                            .foregroundColor(state.accent)
                    }
                    AssistantText(text: message.content, accent: state.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.border, lineWidth: 1)
                )
                Spacer(minLength: 24)
            }
        }
    }
}

/// 轻量 markdown 渲染：识别 "- " / "• " / "· " 开头为项目符号；其他行作为正文
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.isEmpty {
                    Color.clear.frame(height: 2)
                } else if let body = stripBullet(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(accent)
                        Text(body)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(line)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Theme.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 虚线分隔

private struct DashedDivider: View {
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
