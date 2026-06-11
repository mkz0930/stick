# Stick · iOS App

SwiftUI iOS app，4 状态（走 / 坐 / 站 / 睡）火柴人首页。深色主题，UI 风格参考 WorkBuddy，火柴人风格参考 ATLAS 项目的 v2/v3/v6（侧视、线框、关节圆点）。

## 运行

需要 Xcode 15+（实测 Xcode 26.5）。

```bash
# 打开工程
open Stick.xcodeproj

# 或命令行 build
xcodebuild -project Stick.xcodeproj -scheme Stick \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build

# 装到具体模拟器并启动
SIM=$(xcrun simctl list devices available | grep "iPhone 17 " | head -1 | awk -F'[()]' '{print $2}')
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "Stick.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" com.stick.app
```

## 工程结构

```
ios/
├── Stick.xcodeproj/         手写 pbxproj（无 xcodegen 依赖）
└── Stick/
    ├── StickApp.swift        @main 入口
    ├── ContentView.swift     主舞台 + 布局（按当前时间查表驱动状态）
    ├── Models/
    │   └── StickState.swift  walk/sit/stand enum + 24h 时刻表 daySchedule + current(at:)
    ├── Views/
    │   ├── StickFigureView.swift     Canvas 画火柴人（240×320 坐标系，等比缩放）
    │   ├── TimelineView.swift        24h 可拖动时间线
    │   ├── TopBarView.swift          顶栏（汉堡 + 标题 + LIVE 标）
    │   ├── FeatureRow.swift          底部 3 个功能卡
    │   └── InputBar.swift            底部输入栏
    ├── Assets.xcassets/      AppIcon + AccentColor 占位
    └── Preview Content/      SwiftUI Preview 资源
```

## 设计要点

### 24h 时刻表（`StickState.daySchedule`）

8 个时段覆盖一整天：

| 时间          | 状态 | 含义          | accent  |
| ------------- | ---- | ------------- | ------- |
| 00:00 – 07:00 | 睡   | 夜间 / 凌晨   | 紫      |
| 07:00 – 08:30 | 走   | 晨间通勤      | 绿      |
| 08:30 – 12:00 | 坐   | 上午工作      | 橙      |
| 12:00 – 13:30 | 走   | 午餐 + 散步   | 绿      |
| 13:30 – 18:00 | 坐   | 下午工作      | 橙      |
| 18:00 – 19:00 | 走   | 晚间通勤      | 绿      |
| 19:00 – 22:00 | 站   | 晚餐 / 休闲   | 蓝      |
| 22:00 – 24:00 | 睡   | 夜间休息      | 紫      |

### 时间线交互（`TimelineView`）

- **4 状态色段**铺成 24h 横条：走绿 / 坐橙 / 站蓝 / 睡紫，圆角 + 1.5pt 间隙
- **白色 thumb** 可拖：整个 bar 区是 `DragGesture(minimumDistance: 0)`，onChanged 实时更新 `scrubMinute`，5 分钟一档 snap
- **状态联动**：拖动时 stick figure / 状态徽章 / feature 卡 / accent 颜色全部跟着切（`.animation(.easeInOut, value: state)` + `.contentTransition(.numericText())`）
- **scrubbing 反馈**：离开当前时间后
  - header 文字 → "SCRUBBING · 拖动以查看"
  - 显示 "08:00" 等具体时间 + 当前时段 ("位于 走 时段 · 07:00–08:30")
  - 右下出现 "回到现在" 按钮，点击 `withAnimation(.spring)` 回弹到当前时间
- **自动校时**：`onReceive(Timer.publish(every: 30))` 每 30s 重新读 `Date()`

### 火柴人动作

- **走**：侧视，中步幅。右臂前摆/左臂后摆，右腿屈膝抬起/左腿后蹬 + 远景三角
- **坐**：侧视，含颌驼背 20° 前倾。双臂一前一后（键盘+下垂），右大腿水平/小腿垂直 + 椅子（含五星脚、滚轮、显示器）
- **站**：侧视，直立微前倾低头看手机。右手持手机+左手自然下垂 + 室内地砖 + 桌+杯
- **睡**：侧卧，头枕上，双臂一屈一垫，腿略屈 + 床+枕头+月光+Zzz

### 坐标系

`StickFigureView` 内部固定 240×320，调用方给 frame 时 Canvas 自动等比缩放居中。所有身体/场景坐标都在该空间内，**不要**改坐标系。

## 改动注意事项

- 加新状态：(1) `StickState` 加 case + 派生属性 (2) `daySchedule` 加 segment (3) `StickFigureView` 加 `drawXxx` + `drawScene` case (4) `drawFigure` 路由
- pbxproj 是手写版，新增/重命名 .swift 需同步改 `PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase` 四处
- Preview Assets 路径含空格 → asset reader warning，不影响 build

## 后续可做

- 替换 mock `Date()` 为真实时间
- thumb 拖动时让 stick figure 的关节参数化（smooth pose 插值而非瞬时切换）
- 详情页：点底部功能卡 / 火柴人 → push sheet
- 1024×1024 AppIcon（现为占位）
- 横屏适配
