#!/bin/bash
# v3 prompt: 探索性 + 问句 + 预测 user 输入 + 基于画像
# 用 Python 替占位符避免 sed 多字节字符问题

set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

# 3 个不同 user 画像 + input 配对 (用 | 分隔, Python 处理)
TESTS_JSON='[
  {"profile":"28岁男程序员, 长期久坐电脑前, 偶尔失眠, 腰颈经常酸, 每天喝2-3杯咖啡","input":"下午很困","reply":"困倦与生理节律、血糖、室内 CO₂ 浓度相关,下午 2-4 点是自然能量低谷。建议起身活动 5 分钟、到窗边晒太阳、深呼吸 3 次。","runs":3},
  {"profile":"35岁女全职妈妈, 2 个孩子 (3岁/1岁), 长期睡眠不足 6 小时, 经常头痛, 体重偏重","input":"最近总是头痛","reply":"头痛可能与睡眠不足、压力、激素波动、颈椎紧张有关。建议保证 7 小时睡眠, 热敷颈后, 冥想 10 分钟, 必要时服用对乙酰氨基酚。","runs":3},
  {"profile":"50岁男高管, 血压偏高 145/90, 体重超标, 应酬多, 缺乏运动, 偶尔胸闷","input":"胸闷","reply":"胸闷可能与心绞痛、心律失常、焦虑有关。建议立即做心电图 + 心脏彩超, 控制血压 < 130/80, 每周 150 分钟有氧运动, 低盐低脂饮食, 必要时舌下含服硝酸甘油。","runs":4}
]'

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

【输出格式】
- 输出 2-3 条,每条独占一行
- 单条 ≤ 18 字
- **必须是问句**(带"吗"、"怎么"、"为什么"、"什么"等疑问词)
- 模拟 user 会打的字(口语化, 像聊天输入)

【风格示例】(好 — 探索性问句)
- 为什么咖啡喝多了下午反而更困
- 盐5g大概是多少
- 低血糖会有哪些表现
- 耳石症和体位性低血压怎么区分
- 咖啡因代谢要多久不影响睡眠
- 血糖低的时候身体有什么信号
- 枕头高度和颈椎的关系是什么

【风格示例】(❌ 不好 — 陈述/指挥/泛泛)
- 站起来走一走 (指挥)
- 试试喝杯咖啡 (指挥)
- 午餐后血糖怎么测 (太泛, 没贴近用户)
- 深蹲做多少个合适 (指挥/结论)
- 保持规律作息 (空泛建议)
- 注意补充水分 (空泛建议)

硬性规则:
1. **必须问句**(陈述句会被过滤掉)
2. 严禁"试试"、"起身"、"喝杯"、"做一组"、"不妨"、"建议"等动作或建议词
3. 不要序号、注释、说明文字
4. 不输出抽象话题标签(如"健康"、"睡眠"单独出现)
5. 单条 ≤ 18 字
PYEOF
)

OUT_FILE="${1:-/tmp/suggest-v3.log}"
> "$OUT_FILE"

echo "=== v3 prompt: 探索性 + 问句 + user 画像 ===" | tee -a "$OUT_FILE"

# 用 Python 跑整个测试 (避免 sed 编码问题)
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

print("", flush=True)
print("=== 检测 1: 是否为问句 ===", flush=True)
PYEOF
