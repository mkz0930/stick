#!/bin/bash
# Round 4: edge case - 极短 AI reply / 极长 AI reply / action 满载
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

read -r -d '' PROMPT_HEAD <<'EOF' || true
你是健康助手的「下一步意图预测器」。基于用户的最近输入和 AI 的最新回复，预测用户接下来**最可能继续打字问**的 2-3 条话题。

【判断依据】
用户最近一条输入：{USER_INPUT}
AI 最新回复：
{AI_REPLY}

【预测方向】（两类话题混合输出 2-3 条）
1. **追问细节**：用户想继续追问 AI 提到的某个具体点（贴合 AI 提到的内容）
2. **继续探索**：用户想继续探索的相关方向（结合用户画像和上下文，可以稍微发散到相邻话题）

【不要做】
- **不要给"行动建议"**！用户不缺行动建议，AI 上一条已经给了。**不要输出"试试 X"、"喝杯 X"、"起身 X"、"做 X 分钟"这种用户会去执行的动作**
- 不要输出抽象话题标签（如"健康"、"睡眠"），要具体
- 不要问号结尾的疑问句（用陈述句口吻）

【输出格式】
- 直接写出用户会继续打的字，模拟用户口吻
- 单条 ≤ 18 字
- 必须是用户**会主动输入**的具体短句

【风格示例】（好）
- 午餐后血糖怎么测
- 晒太阳要避开紫外线吗
- 咖啡喝多了会怎样

【风格示例】（❌ 不好 — 这种是 action suggestion, 严禁）
- 站起来走一走
- 试试喝杯咖啡
- 做一组深蹲

硬性规则：
1. 只输出 2-3 条，每条独占一行
2. 严禁"试试"、"建议"、"起身"、"喝杯"、"做一组"、"不妨"等动作或建议词
3. 严禁问号开头（但陈述句末尾可有"吗"表示询问口吻，如"怎么测"、"会怎样"）
4. 不带序号、注释、说明文字
EOF

declare -a TESTS=(
  "下午很困|你可能需要休息。|4"                           # Round 4a: 极短 reply (1 句)
  "下午很困|困倦是一种常见的生理反应, 通常与生理节律、血糖波动、缺乏运动、室内空气质量、压力水平等多个因素相关。从生理节律角度看, 人体在下午 2-4 点之间会有一个自然的能量低谷, 这是由生物钟控制的皮质醇水平下降导致的。从血糖角度, 午餐后 1-2 小时血糖会显著上升, 然后快速下降, 这种波动会导致困倦。从运动角度, 长期久坐导致血液循环减慢, 大脑供血不足。从空气质量看, 室内 CO₂ 浓度过高会让人昏昏欲睡。从压力看, 慢性压力会持续消耗能量, 让你感到疲惫。建议你: 1) 午餐少吃精制碳水 2) 每小时起身活动 5 分钟 3) 下午 3 点做 10 分钟深呼吸 4) 喝一杯绿茶而不是咖啡 5) 调整室内通风。|3"  # Round 4b: 极长 reply (3 段多行动建议)
  "下午很困|起身走一走。喝杯咖啡。做一组深蹲。深呼吸。晒太阳。这些都做一下就好。|3"  # Round 4c: 满屏祈使句
)

OUT_FILE="${1:-/tmp/suggest-round4.log}"
> "$OUT_FILE"

echo "=== Round 4: edge case 测试 ===" | tee -a "$OUT_FILE"

run_count=0
for entry in "${TESTS[@]}"; do
  IFS='|' read -r user_input ai_reply n_runs <<< "$entry"
  echo "" | tee -a "$OUT_FILE"
  echo "--- input='$user_input' (reply length: ${#ai_reply} 字符, 跑 $n_runs 次) ---" | tee -a "$OUT_FILE"
  echo "reply: $ai_reply" | head -2 | tee -a "$OUT_FILE"
  prompt=$(echo "$PROMPT_HEAD" | sed "s/{USER_INPUT}/$user_input/g; s/{AI_REPLY}/$ai_reply/g")
  for i in $(seq 1 $n_runs); do
    run_count=$((run_count + 1))
    body=$(cat <<EOJSON
{
  "model": "$MODEL",
  "stream": false,
  "messages": [
    {"role": "user", "content": $(echo "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}
  ],
  "max_tokens": 200,
  "temperature": 0.75
}
EOJSON
)
    resp=$(curl -s -X POST "$API" \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d "$body" 2>&1)
    content=$(echo "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d['choices'][0]['message']['content'])
except: print('PARSE_ERROR: '+sys.stdin.read()[:200])
")
    echo "  Run $run_count: $content" | tee -a "$OUT_FILE"
    sleep 0.5
  done
done

echo "" | tee -a "$OUT_FILE"
echo "=== 严格 action suggestion 检测 ===" | tee -a "$OUT_FILE"
grep -E "^(试试|起来|起身|喝|做|走|跑|晒|深呼吸|按摩|拉伸|建议|不妨)" "$OUT_FILE" | tee -a "$OUT_FILE" || echo "(none - 全部 clean)" | tee -a "$OUT_FILE"
