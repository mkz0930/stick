#!/bin/bash
# v4 prompt: v3 + subagent 反馈 (多样性约束 + 防模板化反例)
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

# 3 个不同 user 画像 (同 v3)
TESTS_JSON='[
  {"profile":"28岁男程序员, 长期久坐电脑前, 偶尔失眠, 腰颈经常酸, 每天喝2-3杯咖啡","input":"下午很困","reply":"困倦与生理节律、血糖、室内 CO₂ 浓度相关,下午 2-4 点是自然能量低谷。建议起身活动 5 分钟、到窗边晒太阳、深呼吸 3 次。","runs":4},
  {"profile":"35岁女全职妈妈, 2 个孩子 (3岁/1岁), 长期睡眠不足 6 小时, 经常头痛, 体重偏重","input":"最近总是头痛","reply":"头痛可能与睡眠不足、压力、激素波动、颈椎紧张有关。建议保证 7 小时睡眠, 热敷颈后, 冥想 10 分钟, 必要时服用对乙酰氨基酚。","runs":3},
  {"profile":"50岁男高管, 血压偏高 145/90, 体重超标, 应酬多, 缺乏运动, 偶尔胸闷","input":"胸闷","reply":"胸闷可能与心绞痛、心律失常、焦虑有关。建议立即做心电图 + 心脏彩超, 控制血压 < 130/80, 每周 150 分钟有氧运动, 低盐低脂饮食, 必要时舌下含服硝酸甘油。","runs":3}
]'

# === v4 prompt: v3 + 多样性约束 + 防模板化反例 ===
PROMPT_TEMPLATE=$(cat <<'PYEOF'
你是健康助手的「用户下一步输入预测器」。

【任务】
根据用户最近输入、用户画像、上一轮 AI 回复,预测用户**接下来会主动打字输入什么**内容(不是 AI 给建议,是 user 自己的好奇心驱动)。

【用户画像】
{USER_PROFILE}

【本轮上下文】
- 用户最近一条输入: {USER_INPUT}
- AI 最新回复: {AI_REPLY}

【预测原则】
1. **问句为主**:用户主动打字时倾向问"为什么" / "怎么办" / "有什么" / "怎么" — 探索性、好奇驱动,不是结论性陈述
2. **不指挥用户**:不要输出"试试 X"、"喝杯 X"、"做 X" 这种 action suggestion;不要给"你应该..."
3. **从用户画像出发**:用户画像里关心的方向优先(如画像说失眠则深挖失眠相关;不是泛泛的健康话题)
4. **贴近 AI 给的内容**:基于 AI 提到的具体点追问(不是泛泛的相关话题)
5. **多样性原则**:3 条推荐必须**覆盖不同角度**(例: 1 条问机制/原因、1 条问具体操作/数字、1 条问风险/副作用/替代方案)。**禁止 3 条都"X 怎么 Y 才有效"这种同构模板**

【输出格式】
- 输出 3 条,每条独占一行
- 单条 ≤ 18 字
- **必须是问句**(带"吗"、"怎么"、"为什么"、"什么"等疑问词)
- 模拟 user 会打的字(口语化, 像聊天输入)

【风格示例】(好 — 探索性 + 多样)
- 为什么咖啡喝多了下午反而更困 (机制/为什么)
- 盐5g大概是多少 (具体数字)
- 低血糖会有哪些身体信号 (症状/识别)
- 耳石症和体位性低血压怎么区分 (鉴别诊断)
- 咖啡因代谢要多久不影响睡眠 (代谢时长)
- 枕头高度和颈椎的关系是什么 (原理/因果)
- 长期吃止痛药会有副作用吗 (风险/副作用)
- 有没有不吃药缓解头痛的方法 (替代方案)

【风格示例】(❌ 不好 — 陈述/指挥/泛泛/同构)
- 站起来走一走 (指挥)
- 试试喝杯咖啡 (指挥)
- 午餐后血糖怎么测 (太泛, 没贴近用户)
- 深蹲做多少个合适 (指挥/结论)
- 保持规律作息 (空泛建议)
- 注意补充水分 (空泛建议)
- X 怎么测 (空泛操作疑问,无机制)
- X 怎么治 (空泛操作疑问,无机制)
- ❌ 3 条都"X 怎么 Y 才有效" (同构模板 — 严禁)

硬性规则:
1. **必须问句**(陈述句会被过滤掉)
2. **3 条必须角度不同**:禁止 3 条都用"X 怎么 Y"结构;至少 1 条问"为什么",至少 1 条问具体数字/时长
3. 严禁"试试"、"起身"、"喝杯"、"做一组"、"不妨"、"建议"等动作或建议词
4. 不要序号、注释、说明文字
5. 不输出抽象话题标签(如"健康"、"睡眠"单独出现)
6. 单条 ≤ 18 字
PYEOF
)

OUT_FILE="${1:-/tmp/suggest-v4.log}"
> "$OUT_FILE"

echo "=== v4 prompt: v3 + 多样性约束 + 防模板化反例 ===" | tee -a "$OUT_FILE"

python3 <<PYEOF | tee -a "$OUT_FILE"
import json
import subprocess
import time

api = "$API"
key = "$KEY"
model = "$MODEL"
template = '''$PROMPT_TEMPLATE'''
tests = json.loads('''$TESTS_JSON''')
out_file = "$OUT_FILE"

run_count = 0
for idx, t in enumerate(tests):
    profile = t["profile"]
    user_input = t["input"]
    ai_reply = t["reply"]
    n_runs = t["runs"]
    print(f"\n--- input='{user_input}' (跑 {n_runs} 次) ---", flush=True)
    print(f"user profile: {profile}", flush=True)
    print(f"AI reply: {ai_reply[:80]}...", flush=True)
    prompt = template.replace("{USER_PROFILE}", profile).replace("{USER_INPUT}", user_input).replace("{AI_REPLY}", ai_reply)

    for i in range(n_runs):
        run_count += 1
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
        print(f"  Run {run_count}: {content}", flush=True)
        time.sleep(0.5)
PYEOF

echo "" | tee -a "$OUT_FILE"
echo "=== 检测 1: 全部问句 ===" | tee -a "$OUT_FILE"
total=$(grep -c "  Run " "$OUT_FILE")
qst=$(grep -E "  Run [0-9]+:.*(怎么|为什么|什么|哪些|多少|多久|吗[?？]?$|?[?？])" "$OUT_FILE" | wc -l)
echo "  问句率: $qst / $total" | tee -a "$OUT_FILE"

echo "" | tee -a "$OUT_FILE"
echo "=== 检测 2: 同 run 3 条结构是否雷同 (用首词比较) ===" | tee -a "$OUT_FILE"
python3 <<PYEOF | tee -a "$OUT_FILE"
import re

with open("$OUT_FILE") as f:
    content = f.read()

# 解析每 run 的 3 条
runs = re.findall(r"Run (\d+): (.+?)(?=\n  Run|\n\n---|\Z)", content, re.DOTALL)
# 简单按 3 条分组
groups = []
current = []
for r in runs:
    lines = [l.strip() for l in r[1].split('\n') if l.strip()]
    current.extend([(r[0], l) for l in lines])
    if len(current) >= 3:
        groups.append(current[:3])
        current = current[3:]

# 检测同 run 3 条是否有"X 怎么 Y"雷同
same_structure = 0
for g in groups:
    if len(g) != 3: continue
    first_words = [t[1].split()[0] if t[1].split() else "" for t in g]
    patterns = [t[1].split('怎么')[0] if '怎么' in t[1] else "" for t in g]
    # 如果 3 条都用"X 怎么"结构
    if all('怎么' in t[1] for t in g):
        same_structure += 1
        print(f"  Run {g[0][0]}: 3 条都用'怎么'结构 — 雷同!")
    else:
        print(f"  Run {g[0][0]}: 角度多样 (只有 {sum(1 for t in g if '怎么' in t[1])}/3 条含'怎么')")

print(f"\n  总共 {same_structure} 个 run 雷同 ({len(groups)} 个 run 总数)")
PYEOF
