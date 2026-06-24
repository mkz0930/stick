import SwiftUI

// MARK: - Message Area View

struct MessageAreaView: View {
    let historyMessages: [PersistedChatMessage]
    let messages: [ChatMessage]
    let isStreaming: Bool
    let suggestedQuestions: [String]
    let state: StickState
    @Binding var scrollToBottom: Bool
    @Binding var pendingScrollId: UUID?
    let scrollToStreamingTrigger: Int
    let searchStatus: String?
    let onSend: (String) -> Void
    let onSendDirect: (String) -> Void
    let onHistorySectionTap: () -> Void
    let onMessageSelected: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                // 1) 对话记录 (从 ChatHistoryStore 拉最近 3 条 user 问题) — 一直显示在顶部
                if !historyMessages.isEmpty {
                    HistorySectionView(
                        historyMessages: historyMessages,
                        accent: state.accent,
                        onHeaderTap: onHistorySectionTap,
                        onMessageSelected: onMessageSelected
                    )
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
                                        onSend(q)
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
                                    MessageRow(message: msg, state: state, isStreaming: isStreaming) { suggestion in
                                        onSendDirect(suggestion)
                                    }
                                        .id(msg.id)
                                }
                                if isStreaming {
                                    HStack(spacing: 5) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(state.accent)
                                        Text(searchStatus ?? "正在生成建议…")
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
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: isStreaming) { oldStreaming, streaming in
                            // 流式输出结束后（streaming 从 true→false），自动滚到底部显示最新回复
                            if !streaming, let last = messages.last {
                                self.scrollToBottom = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    self.pendingScrollId = last.id
                                }
                            }
                        }
                        .onChange(of: messages.last?.id) { oldId, newId in
                            // 新消息追加时（流式首 chunk + 非流式新消息）→ 滚到底部
                            guard self.isStreaming, let last = messages.last else { return }
                            let anchor: UnitPoint = .bottom
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    msgProxy.scrollTo(last.id, anchor: anchor)
                                }
                            }
                        }
                        .onChange(of: pendingScrollId) { oldId, newId in
                            guard let id = newId else { return }
                            let anchor: UnitPoint = self.scrollToBottom ? .bottom : .top
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    msgProxy.scrollTo(id, anchor: anchor)
                                }
                            }
                            self.pendingScrollId = nil
                        }
                        .onChange(of: scrollToStreamingTrigger) { _, _ in
                            // 始终滚到「正在加载」指示器，让动效可见
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    msgProxy.scrollTo("streaming", anchor: .bottom)
                                }
                            }
                        }
                        .onTapGesture {
                            // 点击消息区 → 滚到底部 + 收键盘
                            if let last = messages.last {
                                self.scrollToBottom = true
                                self.pendingScrollId = last.id
                            }
                            // UIKit 兜底
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    let state: StickState
    /// AI 正在流失输出 → 个性化分析段默认折叠
    var isStreaming: Bool = false
    var onSuggestionTap: ((String) -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:
            HStack(alignment: .bottom) {
                Spacer(minLength: 32)
                VStack(alignment: .trailing, spacing: 6) {
                    if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .cornerRadius(8)
                    }
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
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 7) {
                // 一个大泡泡
                VStack(alignment: .leading, spacing: 8) {
                    AssistantText(text: message.content, accent: state.accent, searchResults: message.searchResults, isStreaming: isStreaming)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.bubbleBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.bubbleBorder, lineWidth: 0.8)
                )
                .shadow(color: Theme.bubbleShadow.opacity(0.15), radius: 6, x: 0, y: 3)

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

                // 联网搜索引用（紧凑型横滑 chip 列表）
                if !message.searchResults.isEmpty {
                    searchResultsBar(message.searchResults, accent: state.accent)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// 联网搜索来源 chip 列表（横滑 + 角标编号 [n]）
    @ViewBuilder
    private func searchResultsBar(_ refs: [SearchResult], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.slate)
                Text("参考来源")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.slate)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(refs) { ref in
                        if let url = URL(string: ref.url) {
                            ReferenceChip(ref: ref, accent: accent, url: url)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Reference Chip

/// 单个参考来源 chip（按钮 + openURL）
private struct ReferenceChip: View {
    let ref: SearchResult
    let accent: Color
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 4) {
                Text("[\(ref.index)]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                Text(ref.siteName ?? ref.title ?? ref.url)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.navy)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Assistant Text

private struct AssistantText: View {
    let text: String
    let accent: Color
    /// 联网搜索结果，用于把文本里的 [n] 角标渲染成可点击链接
    let searchResults: [SearchResult]
    /// AI 正在流失输出 → 个性化分析段默认折叠
    var isStreaming: Bool = false

    @State private var analysisExpanded: Bool = false

    init(text: String, accent: Color, searchResults: [SearchResult] = [], isStreaming: Bool = false) {
        self.text = text
        self.accent = accent
        self.searchResults = searchResults
        self.isStreaming = isStreaming
    }

    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 【个性化分析】段的行索引范围（含标题行，到下一个【xxx】段前一行；不存在返回 nil）
    private var analysisRange: ClosedRange<Int>? {
        guard let start = lines.firstIndex(where: { sectionTitle($0) == "个性化分析" }) else { return nil }
        var end = lines.count - 1
        for i in (start + 1)..<lines.count {
            if sectionTitle(lines[i]) != nil {
                end = i - 1
                break
            }
        }
        guard end >= start else { return nil }
        return start...end
    }

    /// 解析行内 [n] 角标 + **xxx** 加粗段 → AttributedString 拼接后返回 Text
    /// - 行内 `**xxx**` 段：剥掉首尾 `**`，用 baseFont.bold() 渲染
    /// - 行内 `[n]` 角标：只在 searchResults 非空时识别（避免 [1] 被误当 link）
    /// - 当 [n] 落在 **xxx** 内部时，外层 ** 优先，避免双重处理
    private func renderInlineText(_ raw: String, baseFont: Font, baseColor: Color) -> Text {
        let refs: [SearchResult]? = searchResults.isEmpty ? nil : searchResults
        return renderInlineTextWithBold(raw, baseFont: baseFont, baseColor: baseColor, refs: refs)
    }

    /// 内部实现：bold 段 + bracket 角标合并处理
    private func renderInlineTextWithBold(
        _ raw: String,
        baseFont: Font,
        baseColor: Color,
        refs: [SearchResult]?
    ) -> Text {
        let nsText = raw as NSString
        let length = nsText.length
        if length == 0 {
            return Text(raw).font(baseFont).foregroundColor(baseColor)
        }

        // 收集所有 match 位置（bold 优先，bracket 在 bold 内部时跳过）
        struct Hit {
            let start: Int
            let end: Int
            let kind: Kind
            let captured: String
        }
        enum Kind { case bold, bracket }
        var hits: [Hit] = []

        // 行内 **xxx** 加粗段（非贪婪，1-200 字符非星号非换行）
        guard let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^*\\n]{1,200}?)\\*\\*") else {
            return Text(raw).font(baseFont).foregroundColor(baseColor)
        }
        for m in boldRegex.matches(in: raw, range: NSRange(location: 0, length: length)) {
            let inner = nsText.substring(with: m.range(at: 1))
            hits.append(Hit(
                start: m.range.location,
                end: m.range.location + m.range.length,
                kind: .bold,
                captured: inner
            ))
        }

        // [n] 角标（[1] / (2) 都行），只在有 refs 时识别
        if let refs = refs, !refs.isEmpty,
           let bracketRegex = try? NSRegularExpression(pattern: "[\\[\\(](\\d+)[\\]\\)]") {
            for m in bracketRegex.matches(in: raw, range: NSRange(location: 0, length: length)) {
                let mStart = m.range.location
                let mEnd = mStart + m.range.length
                // 跳过已被 bold 段覆盖的位置
                if hits.contains(where: { $0.start <= mStart && mEnd <= $0.end }) {
                    continue
                }
                let tokenStr = nsText.substring(with: m.range)
                hits.append(Hit(
                    start: mStart,
                    end: mEnd,
                    kind: .bracket,
                    captured: tokenStr
                ))
            }
        }

        if hits.isEmpty {
            return Text(raw).font(baseFont).foregroundColor(baseColor)
        }

        // 按 start 排序
        hits.sort { $0.start < $1.start }

        // 拼接 AttributedString
        var result = AttributedString()
        var cursor = 0
        for hit in hits {
            // 拼接 hit 之前的普通文本
            if hit.start > cursor {
                let plainRange = NSRange(location: cursor, length: hit.start - cursor)
                var plain = AttributedString(nsText.substring(with: plainRange))
                plain.font = baseFont
                plain.foregroundColor = baseColor
                result += plain
            }
            switch hit.kind {
            case .bold:
                var bold = AttributedString(hit.captured)
                bold.font = baseFont.weight(.bold)
                bold.foregroundColor = baseColor
                result += bold
            case .bracket:
                // 提取数字，找 ref
                let digits = hit.captured.filter { $0.isNumber }
                if let idx = Int(digits), let ref = refs?.first(where: { $0.index == idx }) {
                    var linkAttr = AttributedString(hit.captured)
                    linkAttr.font = .system(size: 12, weight: .bold, design: .monospaced)
                    linkAttr.foregroundColor = accent
                    linkAttr.underlineStyle = .single
                    if let url = URL(string: ref.url) {
                        linkAttr.link = url
                    }
                    result += linkAttr
                } else {
                    var plain = AttributedString(hit.captured)
                    plain.font = baseFont
                    plain.foregroundColor = baseColor
                    result += plain
                }
            }
            cursor = hit.end
        }
        // 结尾剩余
        if cursor < length {
            let tailRange = NSRange(location: cursor, length: length - cursor)
            var plain = AttributedString(nsText.substring(with: tailRange))
            plain.font = baseFont
            plain.foregroundColor = baseColor
            result += plain
        }
        return Text(result)
    }

    /// 把含 [n] 角标的字符串用 SwiftUI Text（含 link tap）渲染
    private func renderRichText(_ raw: String, font: Font, color: Color) -> Text {
        return renderInlineText(raw, baseFont: font, baseColor: color)
    }

    @ViewBuilder
    private func parseLine(_ line: String) -> some View {
        // 【段落标题】- 加粗加大、accent 色，作为分段标题
        if let title = sectionTitle(line) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(accent)
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
        }
        // 警告段落：温暖琥珀色高亮
        else if line.contains("警告") || line.hasPrefix("⚠") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.warnIcon)
                renderRichText(line, font: .system(size: 14, weight: .medium), color: Theme.warnText)
            }
        }
        // 粗体标题行 **xxx**
        else if line.hasPrefix("**") && line.hasSuffix("**") && line.count > 4 {
            let inner = String(line.dropFirst(2).dropLast(2))
            Text(inner)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.navy)
        }
        // bullet 行 - xxx 或 * xxx
        else if let body = bulletBody(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("·")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(accent)
                renderRichText(body, font: .system(size: 15, weight: .regular), color: Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 编号行 1. xxx 或 1) xxx
        else if let (num, body) = numberedBody(line) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(num).")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
                renderRichText(body, font: .system(size: 15, weight: .regular), color: Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 普通行（含可能的 [n] 角标）
        else {
            renderRichText(line, font: .system(size: 15, weight: .regular), color: Theme.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletBody(_ line: String) -> String? {
        for prefix in ["- ", "• ", "· ", "* "] {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private func numberedBody(_ line: String) -> (String, String)? {
        guard let numberedPattern = try? NSRegularExpression(pattern: "^([0-9]+)[.)、\\s]+(.+)$") else { return nil }
        guard let match = numberedPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        guard let numRange = Range(match.range(at: 1), in: line),
              let bodyRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[numRange]), String(line[bodyRange]))
    }

    /// 提取 【xxx】 段落标题；无则返回 nil
    private func sectionTitle(_ line: String) -> String? {
        // 必须整行就是 【xxx】 形式（允许空白）
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("【"), trimmed.hasSuffix("】"), trimmed.count > 4 else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
        // 排除内容里夹带的【】（不是整行只有【】）
        guard !inner.contains("【"), !inner.contains("】") else { return nil }
        return inner
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let range = analysisRange {
                // 标题前的内容（如有）
                ForEach(Array(0..<range.lowerBound), id: \.self) { i in
                    renderLine(i)
                }
                // 个性化分析段：可折叠
                analysisSection(range: range)
                // 段之后的剩余行
                ForEach(Array((range.upperBound + 1)..<lines.count), id: \.self) { i in
                    renderLine(i)
                }
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.isEmpty {
                        Color.clear.frame(height: 4)
                    } else {
                        parseLine(line)
                    }
                }
            }
        }
        .task {
            analysisExpanded = !isStreaming
        }
        .onChange(of: isStreaming) { oldStreaming, nowStreaming in
            analysisExpanded = !nowStreaming
        }
    }

    /// 渲染指定索引的单行（空行给间距）
    @ViewBuilder
    private func renderLine(_ i: Int) -> some View {
        let line = lines[i]
        if line.isEmpty {
            Color.clear.frame(height: 4)
        } else {
            parseLine(line)
        }
    }

    /// 个性化分析段：标题可点击切换折叠/展开
    private func analysisSection(range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // 标题行（点击切换）
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    analysisExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 3, height: 14)
                    Text(sectionTitle(lines[range.lowerBound]) ?? lines[range.lowerBound])
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(accent)
                    Spacer(minLength: 4)
                    Image(systemName: analysisExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent.opacity(0.7))
                    Text(analysisExpanded ? "收起" : "展开")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(accent.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.bottom, 2)

            // 内容
            if analysisExpanded {
                ForEach(Array((range.lowerBound + 1)...range.upperBound), id: \.self) { i in
                    renderLine(i)
                }
            } else if isStreaming {
                Text("AI 正在分析…")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.slate)
                    .padding(.leading, 9)
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
