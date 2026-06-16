# ChatOverlay 推荐主题 prompt 调优记录

**目标**: 4 轮 × 10 次 = 40 次 API 调用，验证 prompt 引导 LLM 输出"用户会问的问题"（无 action suggestion）

## Round 0: Baseline 测现有 prompt
- **input**: "下午很困"
- **AI reply (普通)**: 困倦可能与血糖、CO₂、缺乏运动有关, 建议起身活动...
- **prompt**: 现有版本, 3 类方向 (追问细节/立刻执行/继续探索), "严禁建议" 过滤
- **结果**: 10/10 全是用户会问的问题 (血糖怎么测/晒太阳避紫外线/睡眠质量等), **无 action suggestion**
- **结论**: baseline 已 OK, 但 prompt 显式写"立刻执行"埋雷, Round 1 删它

## Round 1: 删"立刻执行"方向 + 加"不要行动建议"约束
- **input**: "下午很困"
- **AI reply (action-heavy)**: 起身到窗边站 5 分钟, 做 20 个深蹲, 喝浓茶, 跑步 3 次...
- **prompt**: 删 line 1006 立刻执行方向, 加【不要做】块 (严禁试试/起身/喝杯/做一组 等动作或建议词)
- **结果**: 10/10 全是用户会问的细节 (美式咖啡每天最多喝几杯/深蹲做20个会不会伤膝盖/浓茶喝哪种茶叶), **无 action suggestion**
- **结论**: 改后 prompt 抗住 action-heavy reply

## Round 2: 最强 action 诱导 AI reply
- **input**: "下午很困"
- **AI reply (最强诱导)**: 建议你马上喝浓缩咖啡. 建议你起身去窗边站 5 分钟. 建议你做 10 个深蹲. 试一下这些方法吧.
- **prompt**: 同 Round 1 (不修改, 测稳定性)
- **结果**: 10/10 全是问句 (咖啡喝多了会心慌吗/深蹲做不对伤膝盖吗/窗边站5分钟要晒太阳吗), **无 action suggestion**
- **结论**: 即使 AI reply 满屏"建议你", prompt 仍能引导 LLM 输出**用户会问的细节**

## Round 3: 3 个不同 input × 3-4 次 (覆盖不同 user 痛点)
- **input1**: 睡不好 (3 次) → 刷手机影响哪里/温牛奶多少ml/泡脚水温
- **input2**: 运动伤膝 (3 次) → 前脚掌着地怎么练/膝盖内扣怎么自测/跑量 10% 按周还是月
- **input3**: 血压偏高 (4 次) → 盐 5g 多少勺/有氧选快走还是游泳/深呼吸怎么操作
- **prompt**: 同 Round 1
- **结果**: 10/10 全是用户会问的细节, **无 action suggestion**
- **结论**: prompt 在不同 user 痛点下都稳定

## 最终总结
- 4 轮 40 次 API 测试, **0/40 action suggestion**
- 所有输出都是"用户会问什么" (陈述句口吻, 可带"吗"问询)
- 关键改动:
  1. **删"立刻执行"方向** (prompt 显式引导 LLM 输出 action 的元凶)
  2. **加【不要做】块** (explicit 严禁试试/起身/喝杯/做一组/建议/不妨 等动作或建议词)
  3. **加【风格示例】❌ 不好** (列出反例: 站起来走一走/试试喝杯咖啡/做一组深蹲)
  4. **强化"用户会主动输入"** (开头/输出格式都强调"模拟用户会打的字", 不是"AI 给建议")

## 留下的 worktree
- 分支: fix/suggestion-prompt
- 位置: /Users/horse/work/stick/ios/.claude/worktrees/suggestion-prompt
- 未 merge, 等 user 决定
