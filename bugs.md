# bugs.md — 踩坑记录
## 已确认方案

| 日期 | 摘要 | 根因 | 修复 |
|---|---|---|---|
| 2026-06-17 | StickFigureView `drawSleep` / `drawWalk` 脚部坐标超出 240×320 | drawSleep: knee.x=240 导致 foot 右侧最远 x=256 超 16px；drawWalk 左脚 y=322 超 2px | knee.x→232，foot 右侧收窄到 x=240；左脚 ankle.y→318，foot 起点 y→318，合入 main |
| 2026-06-17 | `computeDaySchedule` 凌晨 00:00-07:00 被误判为 .sit 而非 .sleep | gap 检测逻辑跨午夜计算错误（minute - lastActiveMinute 在午夜边界产生负数） | 增加独立夜间小时判断（h >= 22 \|\| h < 7），合入 `1f5b0d2` |
| 2026-06-17 | drawScene ground=322 超出 240×320 坐标系 | 硬编码坐标值不符注释约定 | 统一改为 ground=320，合入 `b6379ec` |
| 2026-06-17 | Widget 背景色硬编码暖白色 | 未使用 Theme 变量 | 改用 `Theme.darkPanel`（navy)，合入 `2b40acf` |

## 失败方案

## 已知风险
