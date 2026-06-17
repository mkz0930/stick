# Stick 项目 Git 更新日志

按主题分组的近期 commit 历史，方便快速了解「这个项目最近在干啥」。下方有完整时间线。

---

## 主题索引

### 2026-06-17 · 闪退修复
- `2030e21` fix: prevent use-after-free in SharedStateStore.observePendingChatSeed
- `7feebe4` merge: 修复 observePendingChatSeed 重复注册导致 use-after-free 闪退

### 2026-06-16 · 晨间健康报告 + 趋势数据
**完整 feature arc**（从无到上线的多阶段合并）：
- `87f0ca1` Merge morning-report-3: UI 层（MorningReportTab / DetailView / TrendDataPage / PersonalView 入口）
- `87e2d0b` Merge morning-report-2: generator / notification / trigger
- `87e2d0b` 之前是 morning-report-1（数据模型）

**后续迭代优化**：
- `419a466` feat: 步行稳定度趋势卡片（速度归一化残差）
- `dea8c8a` feat: 步行稳定度卡片增加 14 天均值参考线
- `46de34c` feat: BodyScoreTrendChart UI 优化（折线图 + 14天参考线 + min/avg/max）
- `bd706f1` feat: add diet/food analysis to morning report
- `de01adb` feat: add 拍食物/报告解读 buttons to morning report detail
- `5458224` feat: HealthKit sleep analysis (bedtime/wake/last walk)
- `b0f1fcb` feat: add double support trend card under sedentary in TrendDataPage
- `035ec77` feat: 饮食建议 chip 一键直达个性化 LLM 建议

### 2026-06-16 · 睡眠 + 7天导出
- `d2b3cb1` Merge branch 'fix/sleep-and-7day-export'
- `9f7d081` fix(timeline): revert broken compression, fix coordinate math, add exportTodayData
- `abd5b98` fix: sleep card + add 7-day HealthKit export
- `ce35281` feat(timeline): compress sleep to fixed top band + expand active window
- `9458456` fix: 数据记录睡眠卡片回退到 HealthKit 数据源
- `58acb65` fix: 睡眠卡片第三层 fallback — body state 快照推断

### 2026-06-16 · Timeline 动画 / 性能
- `627c060` fix(timeline): cache walk visual segments to stop pulse-animation-triggered recompute
- `b861040` fix(timeline): only assign realDaySchedule when content actually changes
- `c9055c6` fix(timeline): exclude stepCount from Equatable to prevent jump on live updates
- `48164b6` fix(timeline): reduce now to per-minute granularity + Equatable to stop axis jumping
- `f6655fe` fix(timeline): apply .equatable() modifier so DayTimelineView skips body on unchanged data
- `e79da2c` fix(timeline): swipe 切状态按时间正方向跳转 thumb
- `11ae74e` fix(timeline): 淡化矩形轨道背景
- `0f12eec` feat(timeline): 步行段外发光胶囊 + 加粗实色
- `bac8a8e` feat(timeline): 步行段改为发光圆点 burst (Bold Burst design)
- `c785bfe` refine(timeline): 步行 burst 从圆点改为横向胶囊
- `dd3b08f` feat(timeline): walk capsule width + opacity driven by step count

### 2026-06-16 · HealthKit mobility 数据扩展
- `a7cf461` merge: feat(HealthKit) mobility 数据扩展 — 步速/双支撑比例/耳机暴露
- `5c16da9` feat(playback): use real HealthKit snapshots for distribution metrics
- `f8fa365` perf(healthstore): HealthStore JSON 加载改为异步

### 2026-06-16 · 启动性能优化
- `4993682` perf: 优化 app 启动性能 (HealthStore lazy + ContentView 懒加载 + 查询 stagger)
- `b770a04` perf: 启动优化 (HealthStore 异步加载 + onAppear 查询 stagger)

### 2026-06-16 · 久坐检测 / 异常提示
- `6004c2e` merge: fix(StateInference) 优化久坐检测 — 心率步数联合判断
- `baf142b` fix: 久坐检测改为累计（今日 sit snapshot 累加 ≥ 2h 才异常）
- `487be77` fix: 久坐异常阈值改为 2 小时（避免小憩误触发）
- `69236d0` fix: 删除睡眠异常 chip 和翻身指标（无真实数据源）
- `94f0946` fix: 注释掉睡眠异常检测（无真实睡眠数据时误触发）
- `0b139d9` fix: 注释掉无真实数据源的异常检测（HRV/心率/站立/锻炼/呼吸）

### 2026-06-16 · 对话 / Chat
- `2bd4dad` feat(chat): 【个性化分析】段流失时折叠，输出完自动展开
- `506547a` feat: 首页拍照/拍食物 chip 一键直达 ChatOverlay 相机
- `b582203` swap: AI 诊室 / 饮食建议 chip 顺序对调
- `b379b68` fix: 首页相机按钮走 ChatOverlay 路径
- `b82880f` fix: 唤起相机/相册时不弹键盘
- `dfb4e7d` perf(sit-timer): 解锁后久坐秒表优先刷新

### 2026-06-16 · FeatureRow 迭代
- `172e589` fix(feature-row): walk 时去掉心情指标，与压力值功能重叠
- `e90c41f` feat(feature-row): 步行时长和睡眠时长用真实数据 + 去掉 POSTURE 姿态指标
- `b05961a` fix: 恢复首页 FeatureRow + 拍食物文案 + ObserverBox 泄露

### 2026-06-16 · 睡眠提醒迭代
- `47a9519` fix: 睡眠仅 < 6h 触发严重不足提醒（移除 < 7h 偏少）
- `55a42a7` fix: 恢复 < 6h 睡眠严重不足提醒
- `20f019c` fix: 恢复睡眠偏少提醒
- `747b082` fix: 移除异常提示的睡眠兜底

### 2026-06-16 · Widget
- `6b09410` fix(widget): 修复小组件久坐始终为0分钟
- `01feb20` fix(widget): 恢复简洁版卡片（血栓沉积+血管图）

### 2026-06-16 · 同步 / SharedState
- `8e5fa1d` fix(sync): 修复异步 Task 中 SharedState 写入时机问题
- `05c7881` fix(sync): 修复久坐计时器同步问题 + 修复 extension 编译错误
- `6a6f005` fix(sync): 修复 onChange 中 SharedState 写入时机问题

### 版本号
- `7c8be99` chore: bump version to 2.0
- `5071077` chore: bump version to 1.8

---

## 完整时间线（最近）

按日期倒序，每 commit 一行：

```bash
git log --since="2026-06-10" --pretty=format:"%h %ad %s" --date=short --all | sort -k2 -r
```

### 2026-06-17
- `7feebe4` merge: 修复 observePendingChatSeed 重复注册导致 use-after-free 闪退
- `2030e21` fix: prevent use-after-free in SharedStateStore.observePendingChatSeed

### 2026-06-16（节选）
- `035ec77` feat: 饮食建议 chip 一键直达个性化 LLM 建议
- `58acb65` fix: 睡眠卡片第三层 fallback — body state 快照推断
- `d2b3cb1` Merge branch 'fix/sleep-and-7day-export'
- `9f7d081` fix(timeline): revert broken compression, fix coordinate math, add exportTodayData
- `abd5b98` fix: sleep card + add 7-day HealthKit export
- `ce35281` feat(timeline): compress sleep to fixed top band + expand active window
- `9458456` fix: 数据记录睡眠卡片回退到 HealthKit 数据源
- `2bd4dad` feat(chat): 【个性化分析】段流失时折叠，输出完自动展开
- `b82880f` fix: 唤起相机/相册时不弹键盘
- `551fd0e` feat(timeline): walk segments as proportional-height bordered boxes with step count label
- `5458224` feat: HealthKit sleep analysis (bedtime/wake/last walk)
- `7c8be99` chore: bump version to 2.0
- `172e589` fix(feature-row): walk 时去掉心情指标，与压力值功能重叠
- `5c16da9` feat(playback): use real HealthKit snapshots for distribution metrics and summary stats
- `506547a` feat: 首页拍照/拍食物 chip 一键直达 ChatOverlay 相机
- `b582203` swap: AI 诊室 / 饮食建议 chip 顺序对调 (InputBar + ChatOverlay)
- `b861040` fix(timeline): only assign realDaySchedule when content actually changes
- `b379b68` fix: 首页相机按钮走 ChatOverlay 路径
- `46de34c` feat: BodyScoreTrendChart UI 优化（折线图 + 14天参考线 + min/avg/max）
- `dea8c8a` feat: 步行稳定度卡片增加 14 天均值参考线
- `419a466` feat: 步行稳定度趋势卡片（速度归一化残差）
- `69236d0` fix: 删除睡眠异常 chip 和翻身指标
- `47a9519` fix: 睡眠仅 < 6h 触发严重不足提醒
- `55a42a7` fix: 恢复 < 6h 睡眠严重不足提醒
- `20f019c` fix: 恢复睡眠偏少提醒
- `627c060` fix(timeline): cache walk visual segments
- `94f0946` fix: 注释掉睡眠异常检测
- `e90c41f` feat(feature-row): 步行时长和睡眠时长用真实数据 + 去掉 POSTURE 姿态指标
- `f6655fe` fix(timeline): apply .equatable() modifier
- `baf142b` fix: 久坐检测改为累计
- `0b139d9` fix: 注释掉无真实数据源的异常检测
- `e79da2c` fix(timeline): swipe 切状态按时间正方向跳转 thumb
- `c9055c6` fix(timeline): exclude stepCount from Equatable
- `487be77` fix: 久坐异常阈值改为 2 小时
- `b05961a` fix: 恢复首页 FeatureRow + 拍食物文案 + ObserverBox 泄露
- `de01adb` feat: add 拍食物/报告解读 buttons to morning report detail
- `48164b6` fix(timeline): reduce now to per-minute granularity + Equatable
- `dd3b08f` feat(timeline): walk capsule width + opacity driven by step count
- `747b082` fix: 移除异常提示的睡眠兜底
- `357d33f` ui: move swipe state badge below stick figure
- `bd706f1` feat: add diet/food analysis to morning report
- `5071077` chore: bump version to 1.8
- `11ae74e` fix(timeline): 淡化矩形轨道背景
- `c785bfe` refine(timeline): 步行 burst 从圆点改为横向胶囊
- `bac8a8e` feat(timeline): 步行段改为发光圆点 burst
- `0f12eec` feat(timeline): 步行段外发光胶囊 + 加粗实色
- `b0f1fcb` feat: add double support trend card under sedentary
- `f8fa365` perf(healthstore): HealthStore JSON 加载改为异步
- `4993682` perf: 优化 app 启动性能
- `b770a04` perf: 启动优化
- `a7cf461` merge: feat(HealthKit) mobility 数据扩展
- `6004c2e` merge: fix(StateInference) 优化久坐检测
- `87f0ca1` Merge morning-report-3: UI layer
- `87e2d0b` Merge morning-report-2: generator, notification, trigger
- `6b09410` fix(widget): 修复小组件久坐始终为0分钟
- `01feb20` fix(widget): 恢复简洁版卡片
- `8e5fa1d` fix(sync): 修复异步 Task 中 SharedState 写入时机问题
- `05c7881` fix(sync): 修复久坐计时器同步问题
- `6a6f005` fix(sync): 修复 onChange 中 SharedState 写入时机问题

---

## 怎么更新这份文件

每做完一组 commit 后跑：
```bash
cd /Users/horse/work/stick
git log --since="$(grep -m1 '^###' git.md | head -1 | xargs -I{} date -v-1d +%Y-%m-%d)" \
  --pretty=format:"- `%h` %s" --date=short --all
```
把输出追加到「完整时间线」对应日期下，主题分组里也补一下。

或者直接 `git log --oneline -50` 看一遍，按需手动整理。

---

<!-- 新 commit 加在上方，主题分组里也补一笔 -->
