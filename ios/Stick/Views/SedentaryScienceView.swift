import SwiftUI
import UserNotifications

// MARK: - 久坐科普界面
// Duolingo 风格：厚黑边 + 夸张表情 + 简单观点
// 含：5 大危险 / 5 大应对 / 一键添加久坐提醒

struct SedentaryScienceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSuccess: Bool = false
    @State private var notificationAuth: NotificationAuth = .notRequested

    private var shouldExportShot: Bool {
        CommandLine.arguments.contains("-export-shot")
    }

    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.94, blue: 0.88).ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        dangersSection
                        actionsSection
                        addReminderCard.id("bottom")
                        Spacer(minLength: 30)
                    }
                    .padding(20)
                }
                .onAppear {
                    if CommandLine.arguments.contains("-scroll-bottom") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                    if shouldExportShot {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            exportFullShot()
                        }
                    }
                }
            }

            // 关闭
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(red: 0.10, green: 0.15, blue: 0.25)))
                    .overlay(Circle().stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 3))
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3)
            }
            .padding(16)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("⚠")
                    .font(.system(size: 22))
                Text("久坐 = 慢性自杀？")
                    .font(.system(size: 24, weight: .black, design: .serif))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
            }
            Text("世界卫生组织早已把「久坐」列为十大致死致疾元凶之一。下面这些，不是吓你。")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                .lineSpacing(2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - 5 大危险

    private var dangersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("5 大危险", emoji: "☠", color: Color(red: 0.92, green: 0.22, blue: 0.15))
            VStack(spacing: 10) {
                dangerCard(
                    n: "01",
                    title: "心血管报废",
                    detail: "每坐 1 小时，血流速度慢 50%。久坐 8h ≈ 抽 1 包烟的心血管损伤。",
                    color: Color(red: 0.92, green: 0.34, blue: 0.20),
                    emoji: "❤️"
                )
                dangerCard(
                    n: "02",
                    title: "腰肌劳损",
                    detail: "腰椎压力比站立时 +40%。1.5h 不动 = 老腰报废的临界点。",
                    color: Color(red: 0.95, green: 0.50, blue: 0.05),
                    emoji: "🪑"
                )
                dangerCard(
                    n: "03",
                    title: "脑子变慢",
                    detail: "血流变慢 → 大脑供血 ↓ → 反应迟钝、记忆差、午饭后困得像熊。",
                    color: Color(red: 0.55, green: 0.40, blue: 0.95),
                    emoji: "🧠"
                )
                dangerCard(
                    n: "04",
                    title: "血栓堵血管",
                    detail: "下肢血流慢 → 血小板沉积 → 深静脉血栓。久坐 4h，肺栓塞风险 +30%。",
                    color: Color(red: 0.85, green: 0.10, blue: 0.30),
                    emoji: "🩸"
                )
                dangerCard(
                    n: "05",
                    title: "抑郁和焦虑",
                    detail: "久坐人群抑郁风险 +31%。身体不动 → 多巴胺 ↓ → 情绪垃圾桶。",
                    color: Color(red: 0.20, green: 0.50, blue: 0.85),
                    emoji: "🫥"
                )
            }
        }
    }

    private func dangerCard(n: String, title: String, detail: String, color: Color, emoji: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n)
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundColor(color)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color, lineWidth: 2.5)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(emoji).font(.system(size: 16))
                    Text(title)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                }
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5)
        )
    }

    // MARK: - 5 大应对

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("5 大应对", emoji: "✨", color: Color(red: 0.02, green: 0.59, blue: 0.41))
            VStack(spacing: 10) {
                actionCard(emoji: "⏰", text: "每 30 分钟起身", sub: "哪怕只是站起来 1 分钟，血流立刻恢复。", color: Color(red: 0.95, green: 0.50, blue: 0.05))
                actionCard(emoji: "🚶", text: "每小时走 2 分钟", sub: "去倒水、上厕所、走到窗边看 30 秒。", color: Color(red: 0.95, green: 0.65, blue: 0.05))
                actionCard(emoji: "🧍", text: "用站立式办公", sub: "每 1 小时站立 15 分钟，腰椎减负 30%。", color: Color(red: 0.55, green: 0.40, blue: 0.95))
                actionCard(emoji: "💪", text: "做 5 个深蹲", sub: "激活臀腿肌肉，把血液重新泵回心脏。", color: Color(red: 0.20, green: 0.50, blue: 0.85))
                actionCard(emoji: "💧", text: "顺便喝杯水", sub: "一举两得：补水 + 逼自己起身去厕所。", color: Color(red: 0.02, green: 0.59, blue: 0.41))
            }
        }
    }

    private func actionCard(emoji: String, text: String, sub: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color, lineWidth: 2.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text(sub)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 2.5)
        )
    }

    // MARK: - 一键添加提醒

    private var addReminderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("一键添加提醒", emoji: "🔔", color: Color(red: 0.92, green: 0.34, blue: 0.05))

            // 说明
            VStack(alignment: .leading, spacing: 6) {
                Text("每 30 分钟通知你站起来")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
                Text("从早上 9 点到晚上 9 点，每 30 分钟弹一条「起来动动」通知。")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.42, green: 0.45, blue: 0.52))
            }

            // 状态
            statusRow

            // 大按钮
            addButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.95, blue: 0.85), Color(red: 1.0, green: 0.88, blue: 0.75)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 4)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(notificationAuth.color)
                .frame(width: 10, height: 10)
            Text(notificationAuth.statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.25))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(notificationAuth.color.opacity(0.10))
        )
    }

    private var addButton: some View {
        Button {
            Task { await addReminders() }
        } label: {
            HStack {
                Image(systemName: showAddSuccess ? "checkmark.circle.fill" : "bell.badge.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text(showAddSuccess ? "已添加 24 条提醒！" : "添加 30 分钟一次提醒")
                    .font(.system(size: 16, weight: .black))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(showAddSuccess ? Color(red: 0.02, green: 0.59, blue: 0.41) : Color(red: 0.92, green: 0.34, blue: 0.05))
            )
            .foregroundColor(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.10, green: 0.15, blue: 0.25), lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(showAddSuccess)
    }

    private func sectionLabel(_ text: String, emoji: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 18))
            Text(text)
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundColor(color)
        }
    }

    // MARK: - 整页截图导出

    @MainActor
    private func exportFullShot() {
        let renderer = ImageRenderer(content:
            ZStack(alignment: .topLeading) {
                Color(red: 0.96, green: 0.94, blue: 0.88)
                VStack(alignment: .leading, spacing: 28) {
                    header
                    dangersSection
                    actionsSection
                    addReminderCard
                    Spacer().frame(height: 30)
                }
                .padding(20)
                .frame(width: 390, alignment: .leading)
            }
            .frame(width: 390, alignment: .topLeading)
        )
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            let url = URL(fileURLWithPath: "/tmp/sedentary-science.png")
            if let data = img.pngData() {
                try? data.write(to: url)
                print("=== EXPORTED: /tmp/sedentary-science.png  \(img.size) ===")
            }
        }
    }

    // MARK: - 提醒逻辑

    @MainActor
    private func addReminders() async {
        // 1. 请求通知权限
        let center = UNUserNotificationCenter.current()
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }

        notificationAuth = granted ? .granted : .denied
        if !granted {
            return
        }

        // 2. 取消旧提醒
        center.removePendingNotificationRequests(withIdentifiers:
            (0..<48).map { "stick.sit.\($0)" }
        )

        // 3. 安排 9:00-21:00 每 30 分钟一条
        let content = UNMutableNotificationContent()
        content.title = "腰罢工了"
        content.body = "起来动动 🚶"
        content.sound = .default

        var ids: [String] = []
        for i in 0..<24 {
            let triggerDate = Calendar.current.date(
                bySettingHour: 9 + i / 2,
                minute: (i % 2) * 30,
                second: 0,
                of: Date()
            ) ?? Date()
            // 跳过过去时间
            if triggerDate <= Date() { continue }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "stick.sit.\(i)"
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(req)
            ids.append(id)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showAddSuccess = true
        }
    }
}

enum NotificationAuth {
    case notRequested
    case granted
    case denied

    var color: Color {
        switch self {
        case .notRequested: return Color(red: 0.62, green: 0.65, blue: 0.72)
        case .granted:      return Color(red: 0.02, green: 0.59, blue: 0.41)
        case .denied:       return Color(red: 0.92, green: 0.20, blue: 0.20)
        }
    }

    var statusText: String {
        switch self {
        case .notRequested: return "未请求通知权限"
        case .granted:      return "✓ 通知权限已授权"
        case .denied:       return "✗ 通知权限被拒绝（去系统设置开启）"
        }
    }
}
