# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 项目概述

火柴人（Stick）—— iOS app，4 个姿态状态：**走 / 坐 / 站 / 睡**。深色主题，UI 布局参考 WorkBuddy（顶栏 + 主舞台 + 时间线 + 3 功能卡 + 底部输入栏），火柴人视觉风格参考 ATLAS 项目的 v2/v3/v6（侧视、线框、关节圆点、胸前虚线、道具提示）。

**状态来源不是手选，而是 24h 时刻表自动查表。** 用户可以在时间线上拖动 thumb 来预览任意时刻的状态。

工程有两部分：
- `ios/` —— SwiftUI iOS app（**主项目**，可在 Xcode 直接打开运行）
- `mock/index.html` —— 早期 HTML 静态原型（15 状态版本，已不再维护，仅作历史参考）

---

## 运行 iOS app

```bash
# 推荐：直接打开 Xcode
open ios/Stick.xcodeproj

# 或命令行 build
cd ios
xcodebuild -project Stick.xcodeproj -scheme Stick \
  -destination 'generic/platform=iOS Simulator' build

# 装到模拟器
SIM=$(xcrun simctl list devices available | grep "iPhone 17 " | head -1 | awk -F'[()]' '{print $2}')
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Stick.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.stick.app.van
```

要求 Xcode 15+（实测 Xcode 26.5，iOS 17+ deployment target）。注意 bundle ID 是 `com.stick.app.van`，不是 `com.stick.app`。

---

## iOS 架构

```
ios/Stick/
├── StickApp.swift                   @main 入口，强制 dark scheme
├── ContentView.swift                主舞台 + 布局；@State 持有 now / scrubMinute
├── Models/
│   └── StickState.swift             enum: walk / sit / stand + 24h daySchedule + current(at:)
├── Views/                           SwiftUI 视图
├── Services/                        @MainActor ObservableObject 业务服务
└── Tool/                            工具类、扩展

ios/SharedKit/                       被主 app 和 StickWidget 两个 target 共享编译
├── SharedState.swift                Theme 色板 + SharedStickState + SharedStateStore
└── OpenChatIntent.swift             AppIntent

ios/StickWidget/                     Widget extension
├── StickWidget.swift                Widget bundle 入口
└── StickRiskAlertWidgetView.swift   2×2 久坐血小板风险 widget
```

### 关键设计选择

- **`StickState`** 是状态中枢。文案 / 数据 / accent 颜色全部从 enum 派生；新增状态只需加 case + 派生 + `daySchedule` 一行。
- **`StickState.daySchedule`** 是 24h 时刻表。8 个时段覆盖全天（00:00-07:00 睡 / 07-08:30 走 / 08:30-12 坐 / 12-13:30 走 / 13:30-18 坐 / 18-19 走 / 19-22 站 / 22-24 睡）。`current(at:)` 给定时间查 state，`currentSegment(at:)` 给定时间查 segment（UI 用来显示当前时段范围）。
- **`ContentView`** 持有 `now: Date` 和 `scrubMinute: Int?`。`displayMinute = scrubMinute ?? minutesOfDay(now)`，`displayState = currentSegment(...).state`。所有子视图（StickFigure / Timeline / FeatureRow）都消费 `displayState`。
- **`TimelineView`** 是核心交互：
  - 24h 横条：4 状态色段（绿/橙/蓝/紫）+ 1.5pt 间隙 + 圆角
  - 白色 thumb，整条 `DragGesture(minimumDistance: 0)` 监听，5 分钟 snap
  - `scrubMinute != 当前分钟` 时显示 "SCRUBBING" 提示 + 时段信息 + "回到现在" 按钮
- **状态色** — 走=绿 / 坐=橙 / 站=蓝 / 睡=紫；线条=off-white (`#E6EBF2`)。状态色渗透到关节点、状态徽章、thumb 边框、feature 卡、accent 字、背景柔光。
- **动效**：
  - thumb 拖动：`interactiveSpring(response: 0.18, dampingFraction: 0.85)` 跟手
  - 状态切换：`.animation(.easeInOut(0.45), value: state)` 让 stick figure / 背景柔光平滑过渡
  - 时间数字：`.contentTransition(.numericText())` 翻牌效果
  - "回到现在" 按钮：`withAnimation(.spring(response: 0.4, dampingFraction: 0.72))` 回弹

### Widget 扩展

- **App ↔ Widget 通信**：通过 App Group (`group.com.example.stick`) 的 UserDefaults 共享状态。Widget 写入，App 启动时读取。
- **Widget 点击**：使用 `Button(intent: OpenRiskAlertIntent(...))` 触发 AppIntent，不弹 "在 Stick 中打开?" 系统确认框。
- **Timeline 更新**：每 5 分钟刷新一次。

---

## 开发规范（强制）

### Swift 语言约束

- Swift 5.9+，iOS 15+ deployment target
- 禁止混用 Objective-C，新增功能纯 Swift 实现
- 异步逻辑统一 `async/await`，杜绝回调嵌套
- 可选类型：优先 `guard let` / `if let` 解包，**禁止强制解包 `!`**
- 数组、字典取值先判空，防止越界崩溃
- 所有耗时操作（网络、文件、解析）放异步线程，UI 刷新必须切回主线程

### 命名规范

| 类型 | 规则 | 示例 |
|---|---|---|
| 类 / 结构体 / 枚举 / 协议 | 大驼峰 PascalCase | `StickState`, `RiskAlertProvider` |
| 变量 / 常量 / 函数 | 小驼峰 camelCase | `pendingChatSeed`, `drainPendingRiskAlert()` |
| 布尔值 | `is`/`has`/`should`/`can` 开头 | `isLoading`, `hasUnreadMessage` |
| 文件名 | 与核心类名完全一致 | `StickState.swift` |

### 代码格式

- **缩进：4 空格**，不用 Tab
- 每行不超过 120 字符，超长参数换行对齐
- 逻辑块之间空一行，函数之间空一行
- 所有控制流（`if`/`for`/`guard`/`switch`）必须带完整大括号，**禁止单行省略**
- 废弃代码直接删除，不做注释保留

### 注释规范

- 所有自定义类型、函数、协议、枚举必须添加文档注释（`///`）
- 复杂逻辑、特殊兼容、埋点、权限判断必须单行注释说明
- 注释只解释「为什么」，不重复代码字面含义
- 禁止无用注释、冗余代码、空行堆砌

### 架构与分层（MVVM）

```
Model      —— 数据模型、结构体、枚举，纯数据层，无 UI 逻辑
ViewModel  —— 业务逻辑、状态管理、接口请求组装，无视图依赖
View      —— 页面、自定义控件、UI 组件，只负责渲染与用户交互回调
Network   —— 网络封装、请求配置、响应解析
Tool      —— 工具类、扩展、权限、缓存
Resource  —— 图片、颜色、字体、多语言、静态配置
```

**强制约束：**
- View 不直接调用网络接口，数据请求交由 ViewModel 处理
- ViewModel 不持有 UI 控件，不依赖 View 生命周期
- 页面状态统一由 ViewModel 发布（`@Published` / `StateObject`），视图单向绑定
- 通用组件全局复用，**禁止每个页面重复写同款 UI、工具方法**

### Widget 与主 App 共享代码

- SharedKit 被两个 target 同时编译，Intent 文件在两边的 import 路径相同
- `SharedStateStore`：App Group UserDefaults 读写
- Widget 中的 AppIntent `perform()` 只在 widget 进程运行，不能直接操作主 app UI

---

## UI/UX 设计规范（强制）

### 基础规则

| 项目 | 规范 |
|---|---|
| 圆角 | 按钮、卡片、输入框统一 **8px**；大卡片、弹窗、底部弹出层 **16px**；禁止混用 |
| 阴影 | 轻质感：opacity **0.08～0.12**，blur **6～10**；禁止浓阴影、彩色阴影 |
| 间距 | **8px 栅格系统**（4/8/16/24/32px）；页面左右安全边距 **16px**；禁止 5px、7px 等不规则间距 |
| 触控热区 | **最小 44×44px**，禁止 40px 以下点击区域 |

### 字体规范

| 层级 | 字号 / 字重 |
|---|---|
| 大标题 | 20px / Semibold |
| 页面标题 | 18px / Semibold |
| 正文内容 | 16px / Regular |
| 辅助文字 | 14px / Regular |
| 备注/标签/提示 | 最小 **14px**，**禁止 12px 及以下** |

- 采用动态字体 + 系统原生字体，支持系统字体大小调节
- **禁止随意自定义字体大小、字重**
- 字重仅标题加粗，**正文全部常规字重**，界面轻量化

### 色彩规范

所有颜色放入 `SharedKit/SharedState.swift` 的 `Theme` 枚举或 `Color` 资源文件，禁止硬编码。

| 类型 | 说明 |
|---|---|
| 主色 | 品牌主色（低饱和高级色），用于按钮、选中态、重点高亮 |
| 辅助色 | 成功绿、警告黄、错误红，仅用于状态提示 |
| 文字色 | 一级黑、二级灰、三级浅灰，**不使用纯黑 `#000`** |
| 背景色 | 页面底色、卡片底色，**深浅模式自动切换** |
| 分割色 | 极浅灰分割线，弱化边界 |

禁止：高饱和刺眼颜色、多色堆砌；界面以「留白+层次」为主。

### 控件规范

**按钮：**
- 主按钮：主色背景、白色文字、8px 圆角、固定高度 **44px**
- 次按钮：白色背景、主色边框、主色文字、高度 **44px**
- 文字按钮：无背景无边框、主色文字、**点击热区扩至 44×44px**
- 所有按钮添加点击缩放动效（`scaleEffect`），时长 **0.2～0.3s ease-in-out**

**输入框：**
- 圆角、浅灰边框、聚焦主色高亮
- 高度不低于 **44px**，文字最小 **14px**
- 清空、密码显隐等操作按钮扩边适配 **44px** 点击热区

**列表 & 卡片：**
- cell 高度自适应，**最小行高不低于 52px**
- 卡片底色纯色 + 轻阴影，与背景区分层级，留白充足
- 列表分割线统一缩进，弱化分割感

### 动画规范

- 所有转场、弹窗、按钮点击动画：**0.2～0.3s ease-in-out**
- 禁止过快、闪烁、卡顿动画，禁止花哨无意义动效
- 可点击元素必须有反馈（缩放、变色、高亮），**无静默点击**

### 适配规范

- 全站使用**自适应布局 + 安全区域**，禁止固定坐标、固定宽高硬编码
- 适配 iPhone 全尺寸、折叠屏、横竖屏切换
- 顶部导航、底部 TabBar 统一依托系统安全区域，无遮挡、无溢出
- 文字、图片、控件跟随屏幕比例自适应，小屏不挤压、大屏不空旷

---

## 改动注意事项

- **坐标系**：火柴人坐标全部在 240×320 空间内。**不要**改 viewBox，改坐标即可。
- **添加新状态**：(1) `StickState` 加 case + 派生属性 (2) `daySchedule` 加 segment (3) `StickFigureView` 加 `drawXxx` 函数 (4) `drawScene` switch 加 case 画场景 (5) `drawFigure` 路由加 case
- **时刻表修改**：在 `StickState.daySchedule` 直接改分钟数即可。所有 1440 分钟必须覆盖到，否则 `current()` 会 fall back 到 `.stand`。
- **颜色派生**：`bg` / `accent` 颜色直接用 `state.accent` 派生，**不要**在调用方硬编码
- **pbxproj**：手写版，新增/重命名 .swift 需同步改 `PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase` 四处（**没有** xcodegen/tuist 依赖）。Widget target 的文件 ID 固定 24 字符（如 `B40000000000000000000012`）。
- **Preview Assets 路径含空格**会有 asset reader warning，不影响 build

---

## 后续方向

- 替换 `Date()` 为真实时间 + 后端 sensor
- thumb 拖动时让 stick figure 关节参数化（smooth pose 插值而非瞬时切换）
- 详情页：点底部功能卡 / 火柴人 → push sheet
- 1024×1024 AppIcon（现为占位）
- 横屏适配
