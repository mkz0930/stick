#!/bin/bash
# Round 2: 用最强 action 诱导 AI reply 测 prompt 是否真的抗 action suggestion
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

USER_INPUT="下午很困"
# Round 2: 最"action 诱导" AI reply (用"建议你"句式)
AI_REPLY="建议你马上喝一杯浓缩咖啡。建议你起身去窗边站 5 分钟。建议你做 10 个深蹲。如果你照做下午就不困了。试一下这些方法吧。"

# === Round 2 prompt: 同 Round 1 (不再改, 测稳定性) ===
read -r -d '' PROMPT <<'EOF' || true
你是健康助手的「下一步意图预测器」。基于用户的最近输入和 AI 的最新回复，预测用户接下来**最可能继续打字问**的 2-3 条话题。

【判断依据】
用户最近一条输入：下午很困
AI 最新回复：
建议你马上喝一杯浓缩咖啡。建议你起身去窗边站 5 分钟。建议你做 10 个深蹲。如果你照做下午就不困了。试一下这些方法吧。

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

OUT_FILE="${1:-/tmp/suggest-round2.log}"
> "$OUT_FILE"

echo "=== Round 2: 最强 action 诱导 AI reply ===" | tee -a "$OUT_FILE"
echo "input: $USER_INPUT" | tee -a "$OUT_FILE"
echo "AI reply (最强 action 诱导): $AI_REPLY" | tee -a "$OUT_FILE"
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
echo "=== 严格 action suggestion 检测 (整句以动词开头的祈使句) ===" | tee -a "$OUT_FILE"
# 检测以"试试/起来/起身/喝/做/走/跑"等动词开头的句
grep -E "^(试试|起来|起身|喝|做|走|跑|跑一|晒|深呼吸|按摩|拉伸|试试看|建议)" "$OUT_FILE" | tee -a "$OUT_FILE" || echo "(none - 全部 clean)" | tee -a "$OUT_FILE"
