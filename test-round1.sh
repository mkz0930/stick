#!/bin/bash
# Round 1: 删"立刻执行"方向, 强化"用户会问"角度
# 测试用更"action-heavy"的 AI reply 逼出 action suggestion
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

USER_INPUT="下午很困"
# Round 1: 更"action-heavy" 的 AI reply, 逼 LLM 倾向输出 action suggestion
AI_REPLY="困了马上喝一杯美式咖啡，起身到窗边晒 5 分钟太阳，做 20 个深蹲。如果还困就再喝一杯浓茶，每天必须 11 点前睡觉。每周跑步 3 次每次 5 公里。"

# === Round 1 prompt: 删"立刻执行"方向, 加 explicit "不是行动建议" ===
read -r -d '' PROMPT <<'EOF' || true
你是健康助手的「下一步意图预测器」。基于用户的最近输入和 AI 的最新回复，预测用户接下来**最可能继续打字问**的 2-3 条话题。

【判断依据】
用户最近一条输入：下午很困
AI 最新回复：
困了马上喝一杯美式咖啡，起身到窗边晒 5 分钟太阳，做 20 个深蹲。如果还困就再喝一杯浓茶，每天必须 11 点前睡觉。每周跑步 3 次每次 5 公里。

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

【风格示例】（❌ 不好）
- 站起来走一走
- 试试喝杯咖啡
- 做一组深蹲

硬性规则：
1. 只输出 2-3 条，每条独占一行
2. 严禁"试试"、"建议"、"起身"、"喝杯"、"做一组"、"不妨"等动作或建议词
3. 严禁问号开头（但陈述句末尾可有"吗"表示询问口吻，如"怎么测"、"会怎样"）
4. 不带序号、注释、说明文字
EOF

OUT_FILE="${1:-/tmp/suggest-round1.log}"
> "$OUT_FILE"

echo "=== Round 1: 删'立刻执行'方向 + 强化'不是行动建议' ===" | tee -a "$OUT_FILE"
echo "input: $USER_INPUT" | tee -a "$OUT_FILE"
echo "AI reply (action-heavy): $AI_REPLY" | tee -a "$OUT_FILE"
echo "" | tee -a "$OUT_FILE"

for i in $(seq 1 10); do
  body=$(cat <<EOJSON
{
  "model": "$MODEL",
  "stream": false,
  "messages": [
    {"role": "user", "content": $(echo "$PROMPT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}
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
  echo "--- Run $i ---" | tee -a "$OUT_FILE"
  echo "$content" | tee -a "$OUT_FILE"
  echo "" | tee -a "$OUT_FILE"
  sleep 0.5
done

echo "" | tee -a "$OUT_FILE"
echo "=== 行动建议检测 (含试试/起来/喝/走/动/起身/晒/深呼吸/做一组/跑步) ===" | tee -a "$OUT_FILE"
grep -iE "试试|起来|起身|晒太阳|做.*个|喝.*杯|走.*步|跑步|深呼吸|跑.*公里|动作|建议|尝试|不妨" "$OUT_FILE" | tee -a "$OUT_FILE" || echo "(none - 全部 clean)" | tee -a "$OUT_FILE"
