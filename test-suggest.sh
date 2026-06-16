#!/bin/bash
# 测试 suggest prompt: 用 curl 调 LLM, 模拟 ChatOverlay.fetchSuggestions 流程
# 10 次跑同一 prompt (input="下午很困" + mock AI reply), 记录输出 + 检测"行动建议"
set -e

API="https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
KEY="sk-0a4953d1dd0b40238be4cc7d8ba656dc"
MODEL="qwen-plus"

USER_INPUT="下午很困"
AI_REPLY="下午困倦可能与午餐后血糖波动、室内二氧化碳浓度升高、缺乏运动有关。建议起身活动 10 分钟、到窗边晒太阳 5 分钟、深呼吸 3 次。如果长期如此，可能提示睡眠质量不足。"

# === 当前 ChatOverlay fetchSuggestions 用的 prompt (line 996-1026) ===
read -r -d '' PROMPT <<'EOF' || true
你是健康助手的「下一步意图预测器」。基于用户的最近输入和 AI 的最新回复，预测用户接下来**最可能输入**或**想继续探索**的 2-3 条话题。

【判断依据】
用户最近一条输入：下午很困
AI 最新回复：
下午困倦可能与午餐后血糖波动、室内二氧化碳浓度升高、缺乏运动有关。建议起身活动 10 分钟、到窗边晒太阳 5 分钟、深呼吸 3 次。如果长期如此，可能提示睡眠质量不足。

【预测方向】（三类话题混合输出 2-3 条）或者其他方向也可以
1. **追问细节**：用户想继续追问 AI 提到的某个点（贴合 AI 给的具体内容）
2. **立刻执行**：用户想马上执行的动作解析（贴合 AI 给的实操建议）
3. **继续探索**：用户想继续探索的相关方向（结合用户画像和上下文，可以稍微发散到相邻话题）

【输出格式】
- 直接写出用户会打的字，模拟用户口吻
- 单条 ≤ 18 字
- 严禁问号、严禁"试试"、"了解下"、"如何"开头的疑问句
- 必须是用户**会输入**的具体短句，不是抽象话题标签
- 三类话题可以混合，不强制每类都出现，也可以是相关的话题，必须用户关心的

【风格示例】
- 膝盖有点酸是要补钙吗
- 跑步和快走哪个更适合我
- 肩颈酸可以做什么运动

硬性规则：
1. 只输出 2-3 条，每条独占一行
2. 严禁"建议"、"试试建议"等含"建议"的词
3. 严禁"某动作"、"某个"、"具体"等泛化占位词
4. 不带序号、注释、说明文字
EOF

OUT_FILE="${1:-/tmp/suggest-round0.log}"
> "$OUT_FILE"

echo "=== Round 0: baseline ===" | tee -a "$OUT_FILE"
echo "input: $USER_INPUT" | tee -a "$OUT_FILE"
echo "API: $MODEL @ $API" | tee -a "$OUT_FILE"
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
echo "=== 行动建议检测 (含"试试/起来/喝/走/动"等动词) ===" | tee -a "$OUT_FILE"
grep -iE "试试|起来|起身|喝|走一走|动一下|动一动|晒太阳|深呼吸|建议|尝试|不妨" "$OUT_FILE" | tee -a "$OUT_FILE" || echo "(none)" | tee -a "$OUT_FILE"
