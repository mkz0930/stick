#!/bin/bash
# Final verify: user 指定的 input="下午很困" + v4 prompt 跑 10 次
# 确认 prompt 仍然稳定, 无 action suggestion
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

# mock user profile + AI reply (典型场景)
USER_INPUT="下午很困"
USER_PROFILE="28岁男程序员, 长期久坐电脑前, 偶尔失眠, 腰颈经常酸, 每天喝2-3杯咖啡"
AI_REPLY="困倦与生理节律、血糖、室内 CO₂ 浓度相关,下午 2-4 点是自然能量低谷。建议起身活动 5 分钟、到窗边晒太阳、深呼吸 3 次。"

# === v4 prompt (从 ChatOverlay.swift 提取, 内容同 commit 05e7dec) ===
PROMPT=$(cat <<'PROMPT_EOF'
你是健康助手的「用户下一步输入预测器」。

【任务】
根据用户最近输入、用户画像、上一轮 AI 回复，预测用户**接下来会主动打字输入什么**内容（不是 AI 给建议，是 user 自己的好奇心驱动）。

【判断依据】
用户画像：
USER_PROFILE_PLACEHOLDER
AI 最新回复：
AI_REPLY_PLACEHOLDER
用户最近一条输入: USER_INPUT_PLACEHOLDER

【预测原则】
1. **问句为主**：用户主动打字时倾向问"为什么" / "怎么办" / "有什么" / "怎么" — 探索性、好奇驱动，不是结论性陈述
2. **不指挥用户**：不要输出"试试 X"、"喝杯 X"、"做 X" 这种 action suggestion；不要给"你应该..."
3. **从用户画像出发**：用户画像里关心的方向优先（如画像说失眠则深挖失眠相关；不是泛泛的健康话题）
4. **贴近 AI 给的内容**：基于 AI 提到的具体点追问（不是泛泛的相关话题）
5. **多样性原则**：3 条推荐必须**覆盖不同角度**（例: 1 条问机制/原因、1 条问具体操作/数字、1 条问风险/副作用/替代方案）。**禁止 3 条都"X 怎么 Y 才有效"这种同构模板**

【输出格式】
- 输出 3 条，每条独占一行
- 单条 ≤ 18 字
- **必须是问句**（带"吗"、"怎么"、"为什么"、"什么"等疑问词）
- 模拟 user 会打的字（口语化，像聊天输入）

【风格示例】（好 — 探索性 + 多样）
- 为什么咖啡喝多了下午反而更困（机制/为什么）
- 盐 5g 大概是多少（具体数字）
- 低血糖会有哪些身体信号（症状/识别）
- 耳石症和体位性低血压怎么区分（鉴别诊断）
- 咖啡因代谢要多久不影响睡眠（代谢时长）
- 枕头高度和颈椎的关系是什么（原理/因果）
- 长期吃止痛药会有副作用吗（风险/副作用）
- 有没有不吃药缓解头痛的方法（替代方案）

【风格示例】（❌ 不好 — 陈述/指挥/泛泛/同构）
- 站起来走一走（指挥）
- 试试喝杯咖啡（指挥）
- 午餐后血糖怎么测（太泛，没贴近用户）
- 深蹲做多少个合适（指挥/结论）
- 保持规律作息（空泛建议）
- 注意补充水分（空泛建议）
- X 怎么测（空泛操作疑问，无机制）
- X 怎么治（空泛操作疑问，无机制）
- ❌ 3 条都"X 怎么 Y 才有效"（同构模板 — 严禁）

硬性规则：
1. **必须问句**（陈述句会被过滤掉）
2. **3 条必须角度不同**：禁止 3 条都用"X 怎么 Y"结构；至少 1 条问"为什么"，至少 1 条问具体数字/时长
3. 严禁"试试"、"起身"、"喝杯"、"做一组"、"不妨"、"建议"等动作或建议词
4. 不要序号、注释、说明文字
5. 不输出抽象话题标签（如"健康"、"睡眠"单独出现）
6. 单条 ≤ 18 字
PROMPT_EOF
)

OUT_FILE="${1:-/tmp/suggest-final.log}"
> "$OUT_FILE"

echo "=== Final verify: input='$USER_INPUT' × 10 runs (v4 prompt) ===" | tee -a "$OUT_FILE"
echo "user profile: $USER_PROFILE" | tee -a "$OUT_FILE"
echo "AI reply: $AI_REPLY" | tee -a "$OUT_FILE"
echo "" | tee -a "$OUT_FILE"

python3 <<PYEOF | tee -a "$OUT_FILE"
import json
import subprocess
import time

api = "$API"
key = "$KEY"
model = "$MODEL"
prompt_template = '''$PROMPT'''
user_input = '''$USER_INPUT'''
user_profile = '''$USER_PROFILE'''
ai_reply = '''$AI_REPLY'''
out_file = "$OUT_FILE"

prompt = (prompt_template
    .replace("USER_PROFILE_PLACEHOLDER", user_profile)
    .replace("AI_REPLY_PLACEHOLDER", ai_reply)
    .replace("USER_INPUT_PLACEHOLDER", user_input))

results = []
for i in range(10):
    body = json.dumps({
        "model": model,
        "stream": False,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 200,
        "temperature": 0.75
    })
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", api,
         "-H", f"Authorization: Bearer {key}",
         "-H", "Content-Type: application/json",
         "-d", body],
        capture_output=True, text=True, timeout=30
    )
    try:
        data = json.loads(result.stdout)
        content = data["choices"][0]["message"]["content"]
    except Exception as e:
        content = f"PARSE_ERROR: {result.stdout[:200]}"
    results.append(content)
    print(f"  Run {i+1}: {content}", flush=True)
    time.sleep(0.5)

# 检测
print("", flush=True)
print("=== 检测结果 ===", flush=True)

# 1. 问句率
q_count = sum(1 for r in results if any(k in r for k in ["吗", "怎么", "为什么", "什么", "哪些", "多少", "多久", "？", "?"]))
print(f"问句率: {q_count}/10", flush=True)

# 2. action suggestion
action = sum(1 for r in results if any(r.startswith(k) for k in ["试试", "起来", "起身", "喝", "做", "走", "跑", "晒", "深呼吸", "按摩", "拉伸", "建议", "不妨", "立即", "赶紧", "立刻", "马上"]))
print(f"action suggestion: {action}/10 (期望 0)", flush=True)

# 3. 多样性（同 run 3 条结构雷同检测）
import re
same_structure_runs = 0
for r in results:
    lines = [l.strip() for l in r.split('\n') if l.strip()]
    if len(lines) >= 3 and all('怎么' in l for l in lines):
        same_structure_runs += 1
print(f"3 条都'怎么'结构雷同: {same_structure_runs}/10 (期望 0)", flush=True)

# 4. 跟画像贴合
keywords_profile = ['咖啡', '失眠', '腰', '颈', '程序员', '久坐', '电脑']
match_count = sum(1 for r in results if any(k in r for k in keywords_profile))
print(f"包含画像关键词 (咖啡/失眠/腰颈/久坐/电脑): {match_count}/10", flush=True)

print("", flush=True)
print("=== 总结 ===", flush=True)
all_clean = (action == 0 and same_structure_runs == 0 and q_count == 10)
if all_clean:
    print("✓ 10/10 全 clean: 问句率 100%, 无 action suggestion, 无同构模板", flush=True)
    print("→ v4 prompt 稳定, 不需要再改", flush=True)
else:
    print(f"⚠️ 有问题: action={action}, 同构={same_structure_runs}, 问句={q_count}", flush=True)
PYEOF
