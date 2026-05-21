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

  # ========== 三层查重 ==========
  # 1. 实质性回复（[@agent/xxx] 格式）— agent 的正式分析，永久有效
  # 2. ACK 通知（@agent/xxx 收到）— 一次性确认，发送后不再重复
  # 3. QA PASS 标记 — 证明任务已通过质量验证

  HAS_REAL_REPLY=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and (.body | contains(\"[@${AGENT_SLUG}]\")))] | length" 2>/dev/null)

  HAS_ACK=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and .body | contains(\"收到\") and (.body | not(contains(\"[@${AGENT_SLUG}]\"))))] | length" 2>/dev/null)

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

  # ========== 决策逻辑 ==========

  # 场景1：QA PASS → 跳过（任务已完成）
  if [ "$HAS_QA_PASS" -gt "0" ]; then
    echo "  → QA PASS，跳过"

  # 场景2：有实质性回复 → 检查是否需要 QA 验证
  elif [ "$HAS_REAL_REPLY" -gt "0" ]; then
    echo "  → 有实质性回复，检查 QA 状态"

    # 如果有 skill/all 且 agent 是 collector，应该进行审计
    if [ "$HAS_SKILL_ALL" -gt 0 ] && [ "$IS_COMMANDER" -eq 0 ]; then
      if [ "$HAS_PHASE_QA" -eq "0" ]; then
        gh issue edit $I_NUM --add-label "phase/qa" 2>/dev/null
        gh issue comment $I_NUM --body "[${AGENT_SLUG}]/analyzed

[@${AGENT_SLUG}] 已分析，等待质量验证。

**Skill/All 分析报告：**
\`\`\`
## [ANALYSIS]
**Agent:** @${AGENT_SLUG}
**Type:** skill/all 响应
**Phase:** QA

### 分析内容
[根据角色提供分析]
- Trait: ${MY_ROLE_LABEL}
- 分析要点: [角色相关的内容]

### Evidence
[证据：链接、截图、代码片段]

### Next
[下一步建议]
\`\`\`
" 2>/dev/null
      fi
    fi

  # 场景3：触发 + 没回复 → 发送分析（不是认领！）
  elif [ "$SHOULD_PROCESS" -gt "0" ] && [ "$HAS_REAL_REPLY" -eq "0" ]; then
    echo "  → 触发，发送分析（不认领）"

    # 构建 skill/all 或 @ 触发的前缀
    if [ "$HAS_SKILL_ALL" -gt 0 ]; then
      COMMENT_PREFIX="[${AGENT_SLUG}]/analyzed"
      SKILL_CONTEXT="**类型:** skill/all 全员分析"
    else
      COMMENT_PREFIX="[@${AGENT_SLUG}]"
      SKILL_CONTEXT="**类型:** @ 触发响应"
    fi

    gh issue comment $I_NUM --body "${COMMENT_PREFIX}

${SKILL_CONTEXT}
**Agent:** @${AGENT_SLUG}
**Trait:** ${MY_ROLE_LABEL}

**状态报告：**
\`\`\`
## [STATUS REPORT]
**Phase:** PM → Dev → QA → Integration
**Task:** ${I_TITLE}
**Progress:** 0%
**Status:** IN_PROGRESS
**Attempts:** ${ATTEMPT_COUNT}/${MAX_RETRIES}

### 当前阶段
[具体在做什么]

### Evidence
[证据：链接、截图、代码片段]

### Next
[下一步]
\`\`\`

> ⚠️ **注意**: 不要自动认领任务！只有在被明确 @ 时才响应。
" 2>/dev/null

  # 场景4：触发 + 有回复 + 检查重试
  elif [ "$SHOULD_PROCESS" -gt "0" ] && [ "$HAS_REAL_REPLY" -gt "0" ]; then
    echo "  → 已有回复，检查 retry 状态"

    # 如果 attempts 超过上限，发送 escalation 报告
    if [ "$ATTEMPT_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "  → 达到重试上限，发送 escalation"
      gh issue edit $I_NUM --add-label "task/escalated" --remove-label "task/processing" 2>/dev/null
      gh issue comment $I_NUM --body "[${AGENT_SLUG}]/escalation

::escalation::
[@${AGENT_SLUG}] 任务已达到最大重试次数（${MAX_RETRIES}），需要人工介入。

**Escalation 报告：**
\`\`\`
## [ESCALATION]
**Issue:** #${I_NUM}
**Agent:** @${AGENT_SLUG}
**Attempts:** ${ATTEMPT_COUNT}/${MAX_RETRIES}
**Problem:** [描述问题]
**Last Attempt:** [上次尝试的结果]
**Required:** [需要什么帮助]
\`\`\`
" 2>/dev/null
    else
      echo "  → 重试次数未超限，跳过"
    fi

  # 场景5：没触发 → 跳过
  else
    echo "  → 没被艾特且无 skill/all，跳过"
  fi
done

echo "Issue scan complete."
