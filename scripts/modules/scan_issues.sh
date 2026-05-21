#!/bin/bash
# scan_issues.sh - 扫描Issues
# 规则：
#   1. 被艾特 → 发送实质性回复
#   2. skill/all 标签 → 所有非 commander agent 发送分析
#   3. 永远不要自动认领！只响应被 @ 的任务
# 增强：质量门禁 + 重试机制 + 状态报告 + Evidence-based

TOKEN="$1"
OWNER="$2"
AGENT_NAME="$3"
AGENT_SLUG="$4"
MY_ROLE_LABEL="$5"
IDENTITY_LABEL="$6"
MAX_RETRIES="${7:-3}"  # 默认最多3次重试

export GITHUB_TOKEN="$TOKEN"

echo "Scanning issues..."

ISSUE_DATA=$(gh issue list --state open --json number,title,labels --limit 20 2>/dev/null)

if [ -z "$ISSUE_DATA" ] || [ "$ISSUE_DATA" = "[]" ]; then
  echo "No open issues found."
  exit 0
fi

echo "$ISSUE_DATA" | jq -c ".[]" | while read -r issue; do
  I_NUM=$(echo "$issue" | jq -r '.number')
  I_TITLE=$(echo "$issue" | jq -r '.title')
  I_LABELS=$(echo "$issue" | jq -r '.labels[].name')

  # ========== 判断是否应该处理此 issue ==========
  # 1. 被 @agent/xxx 明确艾特
  # 2. 有 skill/all 标签 AND 不是 commander（commander 负责协调，不处理具体 skill）

  ISSUE_BODY=$(gh issue view $I_NUM --json body,title --jq '[.body, .title] | join(" ")' 2>/dev/null)
  IS_TAGGED=$(echo "$ISSUE_BODY" | grep -iE "@agent/${AGENT_SLUG}|@agent/all" | wc -l)

  HAS_SKILL_ALL=$(echo "$I_LABELS" | grep -c "skill/all" || true)
  IS_COMMANDER=$(echo "$MY_ROLE_LABEL" | grep -c "commander" || true)

  # skill/all 处理：commander 不参与具体执行，只协调
  if [ "$HAS_SKILL_ALL" -gt 0 ] && [ "$IS_COMMANDER" -gt 0 ]; then
    echo "Issue #$I_NUM: $I_TITLE"
    echo "  → skill/all，但我是 commander，只协调不执行，跳过"
    continue
  fi

  # 判断是否应该处理：被 @ 或者 (skill/all 且非 commander)
  SHOULD_PROCESS=$((IS_TAGGED + (HAS_SKILL_ALL * (1 - IS_COMMANDER))))

  if [ "$SHOULD_PROCESS" -eq 0 ]; then
    continue
  fi

  # ========== 三层查重（保护 agent 免受脚本干扰）==========
  # 1. 实质性回复（[@agent/xxx] 格式）— agent 的正式分析，永久有效
  # 2. agent/ 分析回复（[xxx]/analyzed 格式）— skill/all 场景下的分析报告
  # 3. skill/all 广播回复（[xxx] [division/xxx]/xxx 格式）— agent 的实质性广播回复
  HAS_REAL_REPLY=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and (.body | contains(\"[@${AGENT_SLUG}]\") or .body | contains(\"[${AGENT_SLUG}]/analyzed\") or (.body | contains(\"[${AGENT_SLUG}]\") and .body | contains(\"/\"))))] | length" 2>/dev/null)

  HAS_QA_PASS=$(echo "$I_LABELS" | grep -c "task/qa-pass" || true)

  # ========== 重试机制：检查之前的 attempts ==========
  ATTEMPT_COUNT=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and .body | contains(\"[ATTEMPT\"))] | length" 2>/dev/null)

  # ========== Pipeline Phase 检测 ==========
  HAS_PHASE_PM=$(echo "$I_LABELS" | grep -c "phase/pm" || true)
  HAS_PHASE_DEV=$(echo "$I_LABELS" | grep -c "phase/dev" || true)
  HAS_PHASE_QA=$(echo "$I_LABELS" | grep -c "phase/qa" || true)
  HAS_PHASE_INTEGRATION=$(echo "$I_LABELS" | grep -c "phase/integration" || true)

  echo "Issue #$I_NUM: $I_TITLE"
  echo "  → tagged=${IS_TAGGED}, skill/all=${HAS_SKILL_ALL}, qa_pass=${HAS_QA_PASS}, attempt=${ATTEMPT_COUNT}"
  echo "  → phase: pm=${HAS_PHASE_PM}, dev=${HAS_PHASE_DEV}, qa=${HAS_PHASE_QA}, integration=${HAS_PHASE_INTEGRATION}"

  # ========== 核心原则：禁止脚本发送任何自动评论！==========
  # - 不发"收到"等 ACK（违反"禁止纯 ACK"原则）
  # - 不发模板占位符（agent AI 应生成真实内容）
  # - 脚本只负责检测，真实回复由 agent AI 生成
  #
  # 决策逻辑：
  # - 场景1：QA PASS → 跳过（任务已完成）
  # - 场景2：有实质性回复 → 跳过（agent AI 已处理）
  # - 场景3：触发但没回复 → 记录日志，等待 agent AI 响应（脚本不评论）
  # - 场景4：重试超限 → 可发送 escalation，但需人工确认内容
  # - 场景5：没触发 → 跳过

  # ========== 决策逻辑 ==========

  # 场景1：QA PASS → 跳过（任务已完成）
  if [ "$HAS_QA_PASS" -gt "0" ]; then
    echo "  → QA PASS，跳过"

  # 场景2：有实质性回复 → 跳过（agent AI 已处理）
  elif [ "$HAS_REAL_REPLY" -gt "0" ]; then
    echo "  → 有实质性回复，跳过（agent AI 已处理）"
    # 注意：skill/all 场景下，如果已有回复，说明其他 agent 已处理
    # 脚本不重复评论

  # 场景3：触发 + 没回复 → 记录日志，等待 agent AI 响应
  elif [ "$SHOULD_PROCESS" -gt "0" ] && [ "$HAS_REAL_REPLY" -eq "0" ]; then
    echo "  → 触发 skill/all 或 @mention，等待 agent AI 响应（脚本不自动评论）"
    # 脚本只记录日志，不发送任何评论
    # agent AI 检测到 skill/all 或被 @ 时，应该发送真实分析

  # 场景4：触发 + 有回复 + 检查重试
  elif [ "$SHOULD_PROCESS" -gt "0" ] && [ "$HAS_REAL_REPLY" -gt "0" ]; then
    echo "  → 已有回复，检查 retry 状态"

    # 如果 attempts 超过上限，标记 escalation（但不自动发评论）
    if [ "$ATTEMPT_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "  → 达到重试上限，标记 escalated"
      gh issue edit $I_NUM --add-label "task/escalated" --remove-label "task/processing" 2>/dev/null
      # 注意：escalation 评论需要人工填写内容，脚本不能生成
      echo "  → 需要人工介入填写 escalation 内容"
    else
      echo "  → 重试次数未超限，跳过"
    fi

  # 场景5：没触发 → 跳过
  else
    echo "  → 没被艾特且无 skill/all，跳过"
  fi
done

echo "Issue scan complete."
