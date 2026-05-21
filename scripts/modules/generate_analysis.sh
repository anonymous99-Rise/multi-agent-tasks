#!/bin/bash

# generate_analysis.sh v1.0
# 检测到 skill/all 或 @mention 触发时，调用 OpenClaw agent 生成真实分析内容

AGENT_SLUG="$1"
TRIGGER_TYPE="$2"  # "discussion" or "issue"
TRIGGER_NUM="$3"  # discussion number or issue number
TOKEN="$4"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载 agent 身份
source "$SCRIPT_DIR/load_identity.sh" "$AGENT_SLUG"

LOCKFILE="/tmp/generate_${AGENT_SLUG}_${TRIGGER_TYPE}_${TRIGGER_NUM}.lock"
exec 200>$LOCKFILE
flock -n 200 || { echo "[generate_analysis] $AGENT_SLUG already generating for $TRIGGER_TYPE #$TRIGGER_NUM. Skipping."; exit 0; }

echo "[generate_analysis] $AGENT_SLUG generating $TRIGGER_TYPE #$TRIGGER_NUM..."

# 构建 prompt
case "$TRIGGER_TYPE" in
  discussion)
    TITLE=$(gh api graphql -f owner="adminlove520" -f repo="multi-agent-tasks" -f query="query { repository(owner: \"adminlove520\", name: \"multi-agent-tasks\") { discussion(number: $TRIGGER_NUM) { title body } } }" --jq ".data.repository.discussion" 2>/dev/null | jq -r '.title // empty')
    BODY=$(gh api graphql -f owner="adminlove520" -f repo="multi-agent-tasks" -f query="query { repository(owner: \"adminlove520\", name: \"multi-agent-tasks\") { discussion(number: $TRIGGER_NUM) { body } } }" --jq ".data.repository.discussion.body" 2>/dev/null | head -c 2000)
    PROMPT="你收到了一条讨论被 @mention 或 skill/all 广播触发的通知。

讨论标题: $TITLE
讨论内容（前2000字符）:
$BODY

请以 [$AGENT_SLUG] 的身份，生成一段**真实的分析内容**回复。
- 必须包含具体观点和分析，不能是模板占位符
- 禁止发送\"收到艾特，我来分析一下\"这样的 ACK
- 如果没有实质性内容要说，可以跳过（不用回复）
- 格式：使用 [$AGENT_SLUG/analyzed] 作为标题前缀

请直接生成回复内容，不需要额外的引导语。"
    ;;
  issue)
    ISSUE_DATA=$(gh issue view $TRIGGER_NUM --json title,body --jq '{title: .title, body: .body}' 2>/dev/null)
    TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
    BODY=$(echo "$ISSUE_DATA" | jq -r '.body // ""' | head -c 2000)
    PROMPT="你收到了一条 issue 被 skill/all 广播触发的通知。

Issue 标题: $TITLE
Issue 内容（前2000字符）:
$BODY

请以 [$AGENT_SLUG] 的身份，生成一段**真实的分析内容**回复。
- 必须包含具体观点和分析，不能是模板占位符
- 禁止发送\"收到艾特，我来分析一下\"这样的 ACK
- 如果没有实质性内容要说，可以跳过（不用回复）
- 格式：使用 [$AGENT_SLUG/analyzed] 作为标题前缀

请直接生成回复内容，不需要额外的引导语。"
    ;;
  *)
    echo "[generate_analysis] Unknown trigger type: $TRIGGER_TYPE"
    exit 1
    ;;
esac

# 调用 OpenClaw agent 生成内容
COMMENT_FILE="/tmp/analysis_${AGENT_SLUG}_${TRIGGER_TYPE}_${TRIGGER_NUM}.txt"

# 清理之前的临时文件
rm -f "$COMMENT_FILE"

# 调用 agent 获取分析内容（不自动发送，由脚本处理）
openclaw agent \
  --agent "$AGENT_SLUG" \
  --message "$PROMPT" \
  --deliver \
  --timeout 300 \
  2>&1 | tee "$COMMENT_FILE" || true

# 检查是否生成了有效内容
if [ -f "$COMMENT_FILE" ] && [ -s "$COMMENT_FILE" ]; then
  CONTENT=$(cat "$COMMENT_FILE")
  
  # 过滤掉纯 ACK 和无效内容
  IS_ACK=$(echo "$CONTENT" | grep -iE "(收到艾特|我来分析一下|稍后汇报|ACK)" | wc -l)
  IS_PLACEHOLDER=$(echo "$CONTENT" | grep -iE "(\[具体在做什么\]|\[证据：|具体时间|待确认)" | wc -l)
  
  if [ "$IS_ACK" -gt 0 ] || [ "$IS_PLACEHOLDER" -gt 0 ]; then
    echo "[generate_analysis] 生成内容为无效 ACK/占位符，跳过评论。"
    rm -f "$COMMENT_FILE"
    exit 0
  fi
  
  # 长度检查（至少要有50个字符的有效内容）
  CHAR_COUNT=$(echo "$CONTENT" | tr -d ' \n\t' | wc -c)
  if [ "$CHAR_COUNT" -lt 50 ]; then
    echo "[generate_analysis] 生成内容太短（$CHAR_COUNT chars），跳过评论。"
    rm -f "$COMMENT_FILE"
    exit 0
  fi
  
  echo "[generate_analysis] 准备评论到 $TRIGGER_TYPE #$TRIGGER_NUM..."
  
  # 发送评论
  if [ "$TRIGGER_TYPE" = "discussion" ]; then
    gh api graphql -f owner="adminlove520" -f repo="multi-agent-tasks" -f discussionNumber=$TRIGGER_NUM -f body="$CONTENT" -f query="mutation { addDiscussionComment(input: {discussionId: \"$DISCUSSION_ID\", body: \"$CONTENT\"}) { comment { id } } }" 2>&1 || \
    gh api graphql -f owner="adminlove520" -f repo="multi-agent-tasks" -f query="query { repository(owner: \"adminlove520\", name: \"multi-agent-tasks\") { discussion(number: $TRIGGER_NUM) { id } } }" --jq ".data.repository.discussion.id" 2>/dev/null | \
    while read DISCUSSION_ID; do
      gh api graphql -f discussionId="$DISCUSSION_ID" -f body="$CONTENT" -f query="mutation AddDiscussionComment($input: AddDiscussionCommentInput!) { addDiscussionComment(input: $input) { comment { id } } }" 2>&1
    done
  else
    gh issue comment $TRIGGER_NUM --body "$CONTENT" 2>&1
  fi
  
  echo "[generate_analysis] 评论成功！"
else
  echo "[generate_analysis] 未生成有效内容，跳过。"
fi

# 清理
rm -f "$COMMENT_FILE" "$LOCKFILE"

exit 0
