#!/bin/bash
# scan_issues.sh - 扫描Issues
# 规则：被艾特才回复（发实质性PROPOSAL），没被艾特不打扰
# 增强：质量门禁 + 重试机制 + 状态报告 + Pipeline协调 + Evidence-based

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

  # 过滤有 MY_ROLE_LABEL 或 skill/all 标签的 issue
  if ! echo "$I_LABELS" | grep -qE "($MY_ROLE_LABEL|skill/all)"; then
    continue
  fi

  # ========== 三层查重 ==========
  # 1. 实质性回复（[@agent/taizi]）— agent 的正式报告，永久有效
  # 2. ACK 通知（@agent/taizi 收到）— 一次性确认，发送后不再重复
  # 3. QA PASS 标记 — 证明任务已通过质量验证

  HAS_REAL_I_REPLY=$(gh issue view $I_NUM --json comments --jq \
    ".comments[] | select(.author.login == \"agent/${AGENT_SLUG}\") | .body" 2>/dev/null | wc -l)

  HAS_ACK=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and (.body | contains(\"[@${AGENT_SLUG}]\") or (.body | contains(\"@${AGENT_SLUG}\") and .body | contains(\"收到\"))))] | length")

  HAS_QA_PASS=$(echo "$I_LABELS" | grep -c "task/qa-pass" || true)

  # ========== 检查是否被艾特 ==========
  ISSUE_BODY=$(gh issue view $I_NUM --json body,title --jq '[.body, .title] | join(" ")' 2>/dev/null)
  IS_TAGGED_ISSUE=$(echo "$ISSUE_BODY" | grep -iE "@agent/all|@agent/${AGENT_SLUG}" | wc -l)

  # skill/all label 也视为被艾特（全员广播）
  HAS_SKILL_ALL=$(echo "$I_LABELS" | grep -c "skill/all" || true)

  # 触发条件：被@ 或 有 skill/all label
  SHOULD_RESPOND=$((IS_TAGGED_ISSUE + HAS_SKILL_ALL))

  # ========== 重试机制：检查之前的 attempts ==========
  # 从评论中提取 attempt 次数
  ATTEMPT_COUNT=$(gh issue view $I_NUM --json comments --jq \
    "[.comments[] | select(.author.login == \"agent/${AGENT_SLUG}\" and .body | contains(\"[ATTEMPT\"))] | length" 2>/dev/null)

  # ========== Pipeline Phase 检测 ==========
  HAS_PHASE_PM=$(echo "$I_LABELS" | grep -c "phase/pm" || true)
  HAS_PHASE_DEV=$(echo "$I_LABELS" | grep -c "phase/dev" || true)
  HAS_PHASE_QA=$(echo "$I_LABELS" | grep -c "phase/qa" || true)
  HAS_PHASE_INTEGRATION=$(echo "$I_LABELS" | grep -c "phase/integration" || true)

  echo "Issue #$I_NUM: $I_TITLE"
  echo "  → tagged=${IS_TAGGED_ISSUE}, skill/all=${HAS_SKILL_ALL}, qa_pass=${HAS_QA_PASS}, attempt=${ATTEMPT_COUNT}"
  echo "  → phase: pm=${HAS_PHASE_PM}, dev=${HAS_PHASE_DEV}, qa=${HAS_PHASE_QA}, integration=${HAS_PHASE_INTEGRATION}"

  # ========== 决策逻辑 ==========

  # 场景1：QA PASS → 跳过（任务已完成）
  if [ "$HAS_QA_PASS" -gt "0" ]; then
    echo "  → QA PASS，跳过"

  # 场景2：有实质性回复 → 检查是否需要 QA 验证
  elif [ "$HAS_REAL_I_REPLY" -gt "0" ]; then
    echo "  → 有实质性回复，检查 QA 状态"

    # 如果还没有 QA 标签，添加 QA 标签
    if [ "$HAS_PHASE_QA" -eq "0" ]; then
      gh issue edit $I_NUM --add-label "phase/qa" 2>/dev/null
      gh issue comment $I_NUM --body "::qa-require::
[@${AGENT_SLUG}] 报告已收到，等待质量验证。

**QA 检查清单：**
- [ ] 代码有实际改动吗？（不是空注释）
- [ ] 改动符合需求吗？
- [ ] 有测试或证据吗？
- [ ] 有副作用吗？

**回复格式：**
\`\`\`
[QA RESULT]
- [PASS/FAIL]: 具体说明
- Evidence: 证据链接或截图
- Next: 下一步（如果 FAIL）
\`\`\`
" 2>/dev/null
    fi

  # 场景3：触发 + 没 ACK → 发 ACK + 认领 + 初始化 Pipeline
  elif [ "$SHOULD_RESPOND" -gt "0" ] && [ "$HAS_ACK" -eq "0" ]; then
    echo "  → 触发，无 ACK，认领 + 初始化 Pipeline"

    # 添加 Pipeline phase 标签
    gh issue edit $I_NUM \
      --add-label "task/processing,$IDENTITY_LABEL,phase/pm,task/qa-pending" \
      --remove-label "task" 2>/dev/null

    gh issue comment $I_NUM --body "@${AGENT_SLUG} 收到任务，已认领。

**Pipeline 初始化：**
- Phase: PM（需求确认）
- 下一步：请 agent 确认需求理解是否正确

**状态报告模板：**
\`\`\`
## [STATUS REPORT]
**Agent:** @${AGENT_SLUG}
**Phase:** PM → Dev → QA → Integration
**Task:** [任务名称]
**Progress:** X%
**Status:** [IN_PROGRESS/BLOCKED/DONE]
**Attempts:** ${ATTEMPT_COUNT}/${MAX_RETRIES}

### 当前阶段
[具体在做什么]

### Evidence
[证据：链接、截图、代码片段]

### Next
[下一步]
\`\`\`
" 2>/dev/null

  # 场景4：触发 + 有 ACK → 检查是否超时需要 escalation
  elif [ "$SHOULD_RESPOND" -gt "0" ] && [ "$HAS_ACK" -gt "0" ]; then
    echo "  → 触发，已有 ACK，检查 retry 状态"

    # 如果 attempts 超过上限，发送 escalation 报告
    if [ "$ATTEMPT_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "  → 达到重试上限，发送 escalation"
      gh issue edit $I_NUM --add-label "task/escalated" --remove-label "task/processing" 2>/dev/null
      gh issue comment $I_NUM --body "::escalation::
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
