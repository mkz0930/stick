//
//  PersonalView.swift
//  个人面板 (浅色) — 跟主页一致的极浅色主题
//
//  新增：数据能力矩阵 (设备划分)
//  - 已连接的设备亮，对应 metric 解锁
//  - 未连接的设备灰，旁边提示"连接 XX 解锁 N 项"
//  - 点击设备行可切换 connected / disconnected（模拟连接）
//

import SwiftUI

struct PersonalView: View {
    var onClose: () -> Void
    @Binding var openSpecialists: Bool
    @Binding var openDataRecord: Bool
    @Binding var openWidgetPreview: Bool
    @Binding var deviceSet: Set<DeviceID>
    @ObservedObject var healthAuth: HealthAuthService
    @ObservedObject var chatHistory: ChatHistoryStore
    /// 点击历史消息 → 打开 chat 并滚动到该消息位置
    var onHistoryTap: ((UUID) -> Void)? = nil

    @State private var showSpecialists: Bool = false
    @State private var showDataRecord: Bool = false
    @State private var showWidgetPreview: Bool = false
    @State private var devicesExpanded: Bool = false   // 设备列表展开/收起（默认收起，只显示 1 个）
    @State private var chatHistoryExpanded: Bool = false   // 对话记录展开/收起（默认收起，只显示 2 条）
    @State private var suggestionsExpanded: Bool = false  // 健康建议展开/收起（默认收起，只显示 2 个）

    private let menus: [MenuItem] = [
        MenuItem(icon: "clock.arrow.circlepath", title: "数据记录"),
        MenuItem(icon: "person.2",  title: "专科专家"),
        MenuItem(icon: "macwindow",  title: "Widget 预览"),
    ]

    // 已配置的设备 (iPhone 看 HealthKit 授权; 其他看 toggle 连上)
    private var allDevices: [Device] {
        DeviceID.allCases.map { id in
            // iPhone 判授权: 至少一个 native metric 成功 query 出数据 → 已授权
            let isAuthorized: Bool = {
                if id != .iPhone { return true }
                return MetricID.allCases.contains { m in
                    if m.dataSource != .iPhoneNative && m.dataSource != .iPhoneManual { return false }
                    let s = healthAuth.statuses[m] ?? .unknown
                    return s == .hasData || s == .noData
                }
            }()
            return Device(
                id: id.rawValue,
                icon: id.icon,
                name: id.displayName,
                isConnected: deviceSet.contains(id),
                isAuthorized: isAuthorized,
                color: id.color
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topUserBar
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    devicesSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    VStack(spacing: 0) {
                        ForEach(menus) { item in
                            Button {
                                switch item.title {
                                case "专科专家":
                                    withAnimation(.easeInOut(duration: 0.25)) { showSpecialists = true }
                                case "数据记录":
                                    withAnimation(.easeInOut(duration: 0.25)) { showDataRecord = true }
                                case "Widget 预览":
                                    withAnimation(.easeInOut(duration: 0.25)) { showWidgetPreview = true }
                                default: break
                                }
                            } label: {
                                MenuRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    Rectangle()
                        .fill(Theme.borderSoft)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    chatHistorySection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // 分隔
                    Rectangle()
                        .fill(Theme.borderSoft)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    taskSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showSpecialists) {
            SpecialistsView(onClose: { showSpecialists = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDataRecord) {
            DataRecordView(onClose: { showDataRecord = false }, deviceSet: deviceSet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showWidgetPreview) {
            WidgetGalleryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .onChange(of: openSpecialists) { _, newValue in
            if newValue { showSpecialists = true; openSpecialists = false }
        }
        .onChange(of: openDataRecord) { _, newValue in
            if newValue { showDataRecord = true; openDataRecord = false }
        }
        .onChange(of: openWidgetPreview) { _, newValue in
            if newValue { showWidgetPreview = true; openWidgetPreview = false }
        }
    }

    // MARK: - 顶部用户栏

    private var topUserBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
                Text("X")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(StickState.walk.accent)
            }
            .frame(width: 48, height: 48)

            Text("xxx")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.navy)

            Spacer()

            // 六边形 (设置)
            Button {} label: {
                Image(systemName: "hexagon")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(Theme.navy)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }

            // 三横线 (关闭)
            Button(action: onClose) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.navy)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    // MARK: - 智能设备

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 + 副操作
            HStack {
                Text("连接智能设备")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.slate)
                Spacer()
                Text("\(deviceSet.count) / \(DeviceID.allCases.count) 在线")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundColor(Theme.slate)
            }

            VStack(spacing: 0) {
                // 默认只显示 1 个（iPhone），展开后看全部
                let visibleDevices = devicesExpanded ? allDevices : Array(allDevices.prefix(1))
                ForEach(Array(visibleDevices.enumerated()), id: \.offset) { idx, dev in
                    DeviceRow(
                        device: dev,
                        capabilities: dev.idEnum.capabilities,
                        healthStatuses: healthAuth.statuses,
                        deviceSet: deviceSet
                    ) {
                        // iPhone + 未授权 → 真实授权 + 注入 demo 数据 + 抓取 + 刷新
                        if dev.idEnum == .iPhone && !dev.isAuthorized {
                            Task {
                                await HealthKitService.shared.requestAuthorization()
                                HealthKitService.shared.startAutoCapture(interval: 60)
                                // 模拟器上没数据时, 自动注入过去 7 天样本 (用户首次 demo 体验)
                                await HealthKitDemoData.shared.injectIfNeeded()
                                healthAuth.refresh()
                                // 1.5s 后再 refresh 一次 (HKHealthStore.save 写入完成需要时间)
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                healthAuth.refresh()
                            }
                        } else {
                            toggleDevice(dev.idEnum)
                        }
                    }
                    if idx < visibleDevices.count - 1 {
                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.leading, 54)
                    }
                }

                // 折叠/展开按钮（设备 > 1 时显示）
                if allDevices.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            devicesExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(devicesExpanded ? "收起" : "展开 \(allDevices.count - 1) 个")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: devicesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(StickState.walk.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 切换设备连接状态 (iPhone 永远在)
    private func toggleDevice(_ id: DeviceID) {
        if id == .iPhone { return }   // iPhone 不可断开
        withAnimation(.easeInOut(duration: 0.25)) {
            if deviceSet.contains(id) {
                deviceSet.remove(id)
            } else {
                deviceSet.insert(id)
            }
        }
    }

    // MARK: - 导出对话

    /// 导出对话为 .txt 文件，触发 iOS share sheet（保存到 Files / AirDrop / 复制）
    private func exportChat() {
        let text = formatChatAsText()
        let url = saveTextToTempFile(text)
        shareItems = [url]
        showShareSheet = true
    }

    /// 格式化为可读文本（按时间顺序）
    private func formatChatAsText() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("═══ Stick 对话记录 ═══")
        lines.append("导出时间：\(df.string(from: Date()))")
        lines.append("消息总数：\(chatHistory.messages.count)")
        lines.append("")

        // 按时间正序（从早到晚）
        let ordered = chatHistory.messages.sorted { $0.timestamp < $1.timestamp }
        for (i, msg) in ordered.enumerated() {
            let role = msg.role == "user" ? "👤 我" : "🤖 AI"
            let time = df.string(from: msg.timestamp)
            lines.append("[\(i + 1)] \(role)  \(time)")
            lines.append("    \(msg.content)")
            lines.append("")
        }

        lines.append("─── Stick · 关心你的腰 ───")
        return lines.joined(separator: "\n")
    }

    /// 写到 /tmp/stick-chat-时间戳.txt
    private func saveTextToTempFile(_ text: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "stick-chat-\(df.string(from: Date())).txt"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 对话记录

    /// 最近 N 条 user 提问（按时间倒序）— 全部
    private var recentUserPrompts: [PersistedChatMessage] {
        Array(
            chatHistory.messages
                .filter { $0.role == "user" }
                .sorted { $0.timestamp > $1.timestamp }
        )
    }

    /// 默认只显示前 2 条
    private var visibleUserPrompts: [PersistedChatMessage] {
        chatHistoryExpanded ? recentUserPrompts : Array(recentUserPrompts.prefix(2))
    }

    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    private var chatHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("对话记录")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.slate)
                Spacer()
                if !chatHistory.messages.isEmpty {
                    Text("\(chatHistory.messages.filter { $0.role == "user" }.count) 条")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundColor(Theme.slate)
                }
                // 保存按钮
                Button {
                    exportChat()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .heavy))
                        Text("保存")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(StickState.walk.accent)
                }
                .padding(.leading, 6)
                .disabled(recentUserPrompts.isEmpty)
                .opacity(recentUserPrompts.isEmpty ? 0.4 : 1)
                // 查看全部
                Button {} label: {
                    Text("查看全部")
                        .font(.system(size: 12))
                        .foregroundColor(StickState.walk.accent)
                }
                .padding(.leading, 6)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                if recentUserPrompts.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(Theme.mist)
                        Text("还没有对话记录")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.slate)
                        Spacer()
                    }
                    .frame(minHeight: 40)
                } else {
                    ForEach(Array(visibleUserPrompts.enumerated()), id: \.offset) { idx, msg in
                        Button {
                            onHistoryTap?(msg.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(StickState.walk.accent)
                                    .frame(width: 18)
                                    .padding(.top, 2)
                                Text(msg.content)
                                    .font(.system(size: 13, weight: .regular, design: .serif))
                                    .foregroundColor(Theme.navy)
                                    .lineLimit(2)
                                    .lineSpacing(1.5)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if idx < visibleUserPrompts.count - 1 {
                            Rectangle()
                                .fill(Theme.borderSoft)
                                .frame(height: 0.5)
                                .padding(.leading, 28)
                        }
                    }

                    // 折叠/展开按钮（总条数 > 2 时显示）
                    if recentUserPrompts.count > 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                chatHistoryExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(chatHistoryExpanded
                                     ? "收起"
                                     : "展开 \(recentUserPrompts.count - 2) 条")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: chatHistoryExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(StickState.walk.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 健康建议

    private let suggestions: [Suggestion] = [
        Suggestion(icon: "figure.walk",     color: Color(red: 0.30, green: 0.85, blue: 0.50), title: "起身活动",   desc: "已连续坐 2 小时, 建议站起走动 5 分钟"),
        Suggestion(icon: "drop.fill",       color: Color(red: 0.40, green: 0.65, blue: 0.95), title: "补充水分",   desc: "今日饮水量不足 1L, 目标 2L"),
        Suggestion(icon: "moon.zzz.fill",   color: Color(red: 0.55, green: 0.50, blue: 0.85), title: "早睡",       desc: "最佳入睡时间为 22:30"),
    ]

    /// 默认只显示前 2 个建议
    private var visibleSuggestions: [Suggestion] {
        suggestionsExpanded ? suggestions : Array(suggestions.prefix(2))
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("健康建议")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.slate)
                Spacer()
                Button {} label: {
                    Text("编辑")
                        .font(.system(size: 14))
                        .foregroundColor(StickState.walk.accent)
                }
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(visibleSuggestions.enumerated()), id: \.offset) { idx, s in
                    SuggestionRow(suggestion: s)
                    if idx < visibleSuggestions.count - 1 {
                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.leading, 50)
                    }
                }

                // 折叠/展开按钮（总条数 > 2 时显示）
                if suggestions.count > 2 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            suggestionsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(suggestionsExpanded
                                 ? "收起"
                                 : "展开 \(suggestions.count - 2) 个")
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: suggestionsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(StickState.walk.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 新建
            Button {} label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Theme.slate)
                    Text("新建任务")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.slate)
                }
            }
            .padding(.top, 18)
        }
    }
}

// MARK: - 菜单行

struct MenuItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
}

struct MenuRow: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 16) {
            // 图标 — 32x32 圆角矩形 + 15pt medium icon（浅绿底 + walk 绿 icon）
            // 32-15=17pt 总 padding（每边 ~8.5pt），icon 不贴边
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.86, green: 0.95, blue: 0.88))
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(StickState.walk.accent)
            }
            .frame(width: 32, height: 32)

            // 标题 — 跟对话记录行同款：13pt regular serif navy
            // （跟 1级 section 标题 14pt slate 区分 — section 是背景层，
            //  menu/action 行是内容层，统一 serif 字体家族）
            Text(item.title)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(Theme.navy)
                .lineLimit(1)

            Spacer()

            // chevron — 9pt bold mist（右侧动作指示）
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.mist)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }
}

// MARK: - 智能设备

struct Device: Identifiable {
    let id: String
    let icon: String
    let name: String
    /// 外设 (Watch/护腰/鞋): 是否 toggle 连上
    let isConnected: Bool
    /// iPhone: 是否已授权 HealthKit (任一 native metric 成功 query → 已授权)
    let isAuthorized: Bool
    let color: Color

    var idEnum: DeviceID {
        DeviceID(rawValue: name) ?? .iPhone
    }
}

struct DeviceRow: View {
    let device: Device
    /// 这个设备能提供哪些 metric (放小字在设备下方)
    let capabilities: [MetricID]
    /// 每个 metric 的真实 HealthKit 状态
    let healthStatuses: [MetricID: MetricDataStatus]
    /// 整体设备集合 (用来判断 watch-required / peripheral-required)
    let deviceSet: Set<DeviceID>
    let onTap: () -> Void

    /// iPhone 标"已授权" / "点击授权"; 其他设备标"已连接/未连接"
    private var statusText: String {
        if device.idEnum == .iPhone {
            return device.isAuthorized ? "已授权" : "点击授权"
        }
        return device.isConnected ? "已连接" : "未连接"
    }

    /// 决定整行亮/灰 + 状态色 dot
    private var isActive: Bool {
        device.idEnum == .iPhone ? device.isAuthorized : device.isConnected
    }

    /// iPhone 未授权时整行可点 (触发 HealthKit 授权弹窗)
    private var isIPhoneAwaitingAuth: Bool {
        device.idEnum == .iPhone && !device.isAuthorized
    }

    /// 该 metric 在当前 UI 下的呈现 (亮/灰)
    private func availability(of metric: MetricID) -> MetricAvailability {
        let status = healthStatuses[metric] ?? .unknown
        return DeviceCapabilities.effective(metric, status: status, deviceSet: deviceSet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    // 图标
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(device.color.opacity(isActive ? 0.14 : 0.05))
                        Image(systemName: device.icon)
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(isActive ? device.color : Theme.mist)
                    }
                    .frame(width: 32, height: 32)

                    // 名称
                    Text(device.name)
                        .font(.system(size: 16))
                        .foregroundColor(isActive ? Theme.navy : Theme.mist)

                    Spacer()

                    // 状态指示 (iPhone 显已授权/点击授权, 其他显已连接/未连接)
                    HStack(spacing: 6) {
                        if isIPhoneAwaitingAuth {
                            // 点击授权 — 用 chevron + 高亮文本，提示可点
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(StickState.walk.accent)
                        } else {
                            Circle()
                                .fill(isActive ? device.color : Theme.mist)
                                .frame(width: 6, height: 6)
                        }
                        Text(statusText)
                            .font(.system(size: 12, weight: isIPhoneAwaitingAuth ? .semibold : .regular))
                            .foregroundColor(isIPhoneAwaitingAuth
                                             ? StickState.walk.accent
                                             : (isActive ? Theme.slate : Theme.mist))
                    }
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // iPhone 已授权时不可点 (永远在); 未授权时可点 → 触发 HealthKit 授权
            .disabled(device.idEnum == .iPhone && device.isAuthorized)

            // 设备下方小字: 该设备能提供的数据项 (亮/灰)
            // 4 列网格 — 7 个 tag 自动排成 2 行 (4+3), 1 个 tag 占 1 行
            if !capabilities.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    // 缩进跟图标对齐 (16 + 32 = 48)
                    Spacer().frame(width: 48)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4),
                        alignment: .leading,
                        spacing: 3
                    ) {
                        ForEach(capabilities) { m in
                            CapabilityTag(metric: m, availability: availability(of: m))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            } else {
                Spacer().frame(height: 4)
            }
        }
    }
}

// MARK: - 设备下方的能力 tag (小字)

/// tag 单行: 小点 + 名字; 灰色字体 (不论锁/不锁)
private struct CapabilityTag: View {
    let metric: MetricID
    let availability: MetricAvailability

    private var isOn: Bool { availability.kind == .available }

    var body: some View {
        HStack(spacing: 3) {
            // 小点 (小圆点, 不用 SF Symbol)
            Circle()
                .fill(isOn ? metric.required.first?.color ?? Theme.slate : Theme.mist.opacity(0.5))
                .frame(width: 4, height: 4)
            Text(metric.rawValue)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.mist)   // 灰色字体
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PersonalView(
        onClose: {},
        openSpecialists: .constant(false),
        openDataRecord: .constant(false),
        openWidgetPreview: .constant(false),
        deviceSet: .constant([.iPhone]),
        healthAuth: HealthAuthService.shared,
        chatHistory: ChatHistoryStore.shared
    )
}

// MARK: - 专科专家列表

struct Specialist: Identifiable {
    let id = UUID()
    let name: String        // 姓氏
    let title: String       // 职称
    let dept: String        // 科室
    let hospital: String    // 医院
    let avatarColor: Color  // 头像背景色
    let avatarChar: String  // 头像文字
}

struct SpecialistsView: View {
    var onClose: () -> Void

    // 各专科名医 (假数据)
    private let specialists: [Specialist] = [
        Specialist(name: "李",  title: "主任医师",  dept: "心血管内科",   hospital: "北京协和医院",   avatarColor: Color(red: 0.30, green: 0.55, blue: 0.85), avatarChar: "李"),
        Specialist(name: "王",  title: "副主任医师", dept: "神经内科",     hospital: "北京天坛医院",   avatarColor: Color(red: 0.85, green: 0.45, blue: 0.55), avatarChar: "王"),
        Specialist(name: "张",  title: "主任医师",  dept: "骨科",         hospital: "北京积水潭医院", avatarColor: Color(red: 0.45, green: 0.65, blue: 0.50), avatarChar: "张"),
        Specialist(name: "陈",  title: "副主任医师", dept: "消化内科",     hospital: "上海瑞金医院",   avatarColor: Color(red: 0.85, green: 0.65, blue: 0.30), avatarChar: "陈"),
        Specialist(name: "刘",  title: "主任医师",  dept: "呼吸内科",     hospital: "广州呼吸健康研究院", avatarColor: Color(red: 0.60, green: 0.45, blue: 0.75), avatarChar: "刘"),
        Specialist(name: "赵",  title: "主任医师",  dept: "内分泌科",     hospital: "北京 301 医院",   avatarColor: Color(red: 0.40, green: 0.65, blue: 0.70), avatarChar: "赵"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(specialists) { s in
                            SpecialistRow(specialist: s)
                            Rectangle()
                                .fill(Theme.borderSoft)
                                .frame(height: 0.5)
                                .padding(.leading, 76)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("专科专家")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.navy)
                Text("\(specialists.count) 位名医 · 点击查看详情")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
            }
        }
    }
}

struct SpecialistRow: View {
    let specialist: Specialist

    var body: some View {
        Button {} label: {
            HStack(spacing: 16) {
                // 头像 (圆形 + 姓氏 + 彩色背景)
                ZStack {
                    Circle().fill(specialist.avatarColor)
                    Text(specialist.avatarChar)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 52, height: 52)

                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(specialist.name + "医生")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.navy)
                        Text("·")
                            .foregroundColor(Theme.mist)
                        Text(specialist.title)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.slate)
                    }
                    Text(specialist.dept)
                        .font(.system(size: 14))
                        .foregroundColor(StickState.walk.accent)
                    Text(specialist.hospital)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.slate)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.mist)
            }
            .frame(minHeight: 72)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 健康建议

struct Suggestion: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let desc: String
}

struct SuggestionRow: View {
    let suggestion: Suggestion

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                // 图标 (圆角方块 + 彩色淡底) — 缩小 38→32
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(suggestion.color.opacity(0.12))
                    Image(systemName: suggestion.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(suggestion.color)
                }
                .frame(width: 32, height: 32)

                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Text(suggestion.desc)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.slate)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(minHeight: 40)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
