#!/bin/bash
# v5 prompt: v4 + 强化画像驱动 (要求每条关联画像)
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

TESTS_JSON='[
  {"profile":"28岁男程序员, 长期久坐电脑前, 偶尔失眠, 腰颈经常酸, 每天喝2-3杯咖啡","input":"下午很困","reply":"困倦与生理节律、血糖、室内 CO₂ 浓度相关,下午 2-4 点是自然能量低谷。建议起身活动 5 分钟、到窗边晒太阳、深呼吸 3 次。","runs":5},
  {"profile":"35岁女全职妈妈, 2 个孩子 (3岁/1岁), 长期睡眠不足 6 小时, 经常头痛, 体重偏重","input":"最近总是头痛","reply":"头痛可能与睡眠不足、压力、激素波动、颈椎紧张有关。建议保证 7 小时睡眠, 热敷颈后, 冥想 10 分钟, 必要时服用对乙酰氨基酚。","runs":3},
  {"profile":"50岁男高管, 血压偏高 145/90, 体重超标, 应酬多, 缺乏运动, 偶尔胸闷","input":"胸闷","reply":"胸闷可能与心绞痛、心律失常、焦虑有关。建议立即做心电图 + 心脏彩超, 控制血压 < 130/80, 每周 150 分钟有氧运动, 低盐低脂饮食, 必要时舌下含服硝酸甘油。","runs":2}
]'

# === v5 prompt: v4 + 强化画像驱动 ===
PROMPT_TEMPLATE=$(cat <<'PYEOF'
你是健康助手的「用户下一步输入预测器」。

【任务】
根据用户最近输入、用户画像、上一轮 AI 回复，预测用户**接下来会主动打字输入什么**内容（不是 AI 给建议，是 user 自己的好奇心驱动）。

【用户画像】(长期关心方向, 强信号)
{USER_PROFILE}

【本轮上下文】
- 用户最近一条输入: {USER_INPUT}
- AI 最新回复: {AI_REPLY}

【预测原则】
1. **问句为主**:用户主动打字时倾向问"为什么" / "怎么办" / "有什么" / "怎么" — 探索性、好奇驱动,不是结论性陈述
2. **不指挥用户**:不要输出"试试 X"、"喝杯 X"、"做 X" 这种 action suggestion;不要给"你应该..."
3. **【关键】从用户画像出发**:每条推荐必须**直接关联用户画像**里描述的长期关心方向(职业/生活习惯/既往症状/年龄/性别)。**画像里没提到的方向不要瞎推**(例: 程序员画像不要推"孕妇注意事项")
4. **贴近 AI 给的内容**:在画像驱动的基础上,基于 AI 提到的具体点追问(不是泛泛的相关话题)
5. **多样性原则**:3 条推荐必须**覆盖不同角度**(机制/操作/数字/风险/替代方案)。禁止 3 条都"X 怎么 Y 才有效"这种同构模板

【输出格式】
- 输出 3 条,每条独占一行
- 单条 ≤ 18 字
- **必须是问句**(带"吗"、"怎么"、"为什么"、"什么"等疑问词)
- 模拟 user 会打的字(口语化, 像聊天输入)

【风格示例】(好 — 探索性 + 多样 + 强画像关联)
- 用户画像"程序员 久坐 咖啡 失眠 腰颈酸",AI 提到"生理节律"和"血糖"
  - 为什么咖啡喝多了反而困 (机制, 关联"咖啡"+AI "血糖")
  - 久坐多少分钟该起来动一次 (数字, 关联"久坐")
  - 腰颈酸和久坐是同一个原因吗 (原理, 关联"腰颈酸/久坐")
- 用户画像"妈妈 睡眠不足 头痛",AI 提到"对乙酰氨基酚"
  - 哺乳期能吃对乙酰氨基酚吗 (风险, 关联"哺乳期")
  - 长期吃止痛药会有副作用吗 (副作用, 关联"长期")
  - 孩子半夜醒导致妈妈睡不够怎么办 (替代方案, 关联"孩子/睡不够")

【风格示例】(❌ 不好 — 陈述/指挥/泛泛/同构/无画像)
- 站起来走一走 (指挥)
- 试试喝杯咖啡 (指挥)
- 午餐后血糖怎么测 (太泛, 没贴近用户画像)
- 深蹲做多少个合适 (指挥/结论)
- 保持规律作息 (空泛建议)
- 注意补充水分 (空泛建议)
- X 怎么测 (空泛操作疑问,无机制)
- X 怎么治 (空泛操作疑问,无机制)
- ❌ 3 条都"X 怎么 Y 才有效" (同构模板 — 严禁)
- ❌ 推荐跟画像无关的泛健康话题 (空泛, 浪费 user 注意力)

硬性规则:
1. **必须问句**(陈述句会被过滤掉)
2. **【关键】每条推荐必须关联用户画像**(职业/生活习惯/既往症状/年龄/性别 等);画像里没的方向禁止推
3. **3 条必须角度不同**:禁止 3 条都用"X 怎么 Y"结构;至少 1 条问"为什么",至少 1 条问具体数字/时长
4. 严禁"试试"、"起身"、"喝杯"、"做一组"、"不妨"、"建议"等动作或建议词
5. 不要序号、注释、说明文字
6. 不输出抽象话题标签(如"健康"、"睡眠"单独出现)
7. 单条 ≤ 18 字
PYEOF
)

OUT_FILE="${1:-/tmp/suggest-v5.log}"
> "$OUT_FILE"

echo "=== v5 prompt: v4 + 强化画像驱动 ===" | tee -a "$OUT_FILE"

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

all_results = {}
for t in tests:
    profile = t["profile"]
    user_input = t["input"]
    ai_reply = t["reply"]
    n_runs = t["runs"]
    print(f"\n--- input='{user_input}' × {n_runs} runs ---", flush=True)
    print(f"user profile: {profile}", flush=True)
    prompt = template.replace("{USER_PROFILE}", profile).replace("{USER_INPUT}", user_input).replace("{AI_REPLY}", ai_reply)

    runs = []
    for i in range(n_runs):
        body = json.dumps({
            "model": model, "stream": False,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 200, "temperature": 0.75
        })
        result = subprocess.run(
            ["curl", "-s", "-X", "POST", api, "-H", f"Authorization: Bearer {key}",
             "-H", "Content-Type: application/json", "-d", body],
            capture_output=True, text=True, timeout=30
        )
        try:
            content = json.loads(result.stdout)["choices"][0]["message"]["content"]
        except: content = "PARSE_ERROR"
        runs.append(content)
        print(f"  Run {i+1}: {content}", flush=True)
        time.sleep(0.5)
    all_results[user_input] = (profile, runs)

# 检测
print("\n=== 检测 ===", flush=True)
total_runs = 0
q_count = 0
action = 0
same_struct = 0
img_match = 0
img_match_per = []

for user_input, (profile, runs) in all_results.items():
    # 提取画像关键词
    keywords = []
    for kw in ["程序员", "久坐", "电脑", "腰", "颈", "咖啡", "失眠",
               "妈妈", "孩子", "哺乳", "睡不", "头痛", "体重",
               "高管", "血压", "应酬", "胸闷", "心脏", "体重"]:
        if kw in profile:
            keywords.append(kw)

    for r in runs:
        total_runs += 1
        # 1. 问句
        if any(k in r for k in ["吗", "怎么", "为什么", "什么", "哪些", "多少", "多久", "？", "?"]):
            q_count += 1
        # 2. action suggestion
        if any(r.startswith(k) for k in ["试试", "起来", "起身", "喝", "做", "走", "跑", "晒", "深呼吸", "按摩", "拉伸", "建议", "不妨", "立即", "赶紧", "立刻", "马上"]):
            action += 1
        # 3. 同构
        lines = [l for l in r.split('\n') if l.strip()]
        if len(lines) >= 3 and all('怎么' in l for l in lines):
            same_struct += 1
        # 4. 画像匹配 (3 条里至少 1 条含画像关键词)
        lines = [l.strip() for l in r.split('\n') if l.strip()]
        has_img_kw = any(any(kw in l for kw in keywords) for l in lines)
        if has_img_kw:
            img_match += 1
        img_match_per.append(f"  {user_input}: profile keywords={keywords} → match={has_img_kw}")
        # 详细: 列每条是否含画像关键词
        for l in lines:
            matched = [kw for kw in keywords if kw in l]
            print(f"    '{l[:30]}...' 含画像关键词: {matched}", flush=True)

print(f"\n=== 汇总 ===", flush=True)
print(f"问句率: {q_count}/{total_runs}", flush=True)
print(f"action suggestion: {action}/{total_runs} (期望 0)", flush=True)
print(f"同构模板: {same_struct}/{total_runs} (期望 0)", flush=True)
print(f"画像匹配 (3 条里至少 1 条含画像关键词): {img_match}/{total_runs}", flush=True)
print(f"\n详情:", flush=True)
for line in img_match_per:
    print(line, flush=True)
PYEOF
