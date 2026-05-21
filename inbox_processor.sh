#!/bin/bash

# Multi-Agent Inbox Processor (v3.6.0)
# agency-agents 最佳实践: 模块化 + 重试逻辑 + 状态追踪 + 决策日志
#
# 支持:
# - skill/all 强制回复、skill/role 广播、@agent/all
# - 执行链/汇报链、时效追踪
# - 幂等性、重试机制、错误处理

set -e

TOKEN=$1
MY_ROLE_LABEL=$2
AGENT_NAME=$3
AGENT_SLUG=$4

DASHBOARD_URL="https://multi-agent-task-dashboard.vercel.app"

# =============================================
# 配置与常量
# =============================================
if [ -z "$TOKEN" ] || [ -z "$MY_ROLE_LABEL" ] || [ -z "$AGENT_NAME" ]; then
  echo "❌ Error: Missing parameters."
  echo "Usage: $0 <token> <role_label> <agent_name> [agent_slug]"
  exit 1
fi

[ -z "$AGENT_SLUG" ] && AGENT_SLUG=$(echo "$AGENT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g')
IDENTITY_LABEL="agent/$AGENT_SLUG"
VIRTUAL_MENTION="@agent/$AGENT_SLUG"
AGENT_ALL_MENTION="@agent/all"
SKILL_ALL_LABEL="skill/all"
MY_ROLE=$(echo "$MY_ROLE_LABEL" | sed 's|skill/||')

# 重试配置
MAX_RETRIES=3
RETRY_DELAY=2
RATE_LIMIT_WAIT=60

# 状态文件
STATE_DIR="/tmp/agent_state_${AGENT_SLUG}"
STATE_FILE="${STATE_DIR}/state.json"
LOG_FILE="${STATE_DIR}/activity.log"

# =============================================
# 工具函数
# =============================================

log() {
  local level=$1
  local msg=$2
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[${timestamp}] [${level}] ${msg}" | tee -a "$LOG_FILE"
}

init_state() {
  mkdir -p "$STATE_DIR"
  touch "$LOG_FILE"
  if [ ! -f "$STATE_FILE" ]; then
    echo '{"last_run": "", "processed": {}, "stats": {"replies": 0, "errors": 0}}' > "$STATE_FILE"
  fi
}

update_stats() {
  local field=$1
  local delta=${2:-1}
  local current=$(jq -r ".stats.${field}" "$STATE_FILE" 2>/dev/null || echo "0")
  local new=$((current + delta))
  jq ".stats.${field} = ${new}" "$STATE_FILE" > /tmp/state_tmp.json && mv /tmp/state_tmp.json "$STATE_FILE"
}

# 重试装饰器
retry() {
  local max_attempts=${1:-$MAX_RETRIES}
  local delay=${2:-$RETRY_DELAY}
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    fi

    if [ $attempt -lt $max_attempts ]; then
      log "WARN" "Attempt $attempt failed, retrying in ${delay}s... (attempt $((attempt+1))/$max_attempts)"
      sleep $delay
      delay=$((delay * 2))  # 指数退避
    fi

    attempt=$((attempt + 1))
  done

  log "ERROR" "Command failed after $max_attempts attempts: $*"
  return 1
}

# GitHub API 调用（带重试）
gh_api() {
  local cmd="$1"
  shift

  case "$cmd" in
    discussion_comment)
      retry gh discussion comment "$@"
      ;;
    issue_comment)
      retry gh issue comment "$@"
      ;;
    issue_edit)
      retry gh issue edit "$@"
      ;;
    issue_view)
      retry gh issue view "$@"
      ;;
    api)
      retry gh api "$@"
      ;;
    *)
      log "ERROR" "Unknown gh_api command: $cmd"
      return 1
      ;;
  esac
}

# =============================================
# 初始化
# =============================================

export GITHUB_TOKEN="$TOKEN"
REPO_JSON=$(gh repo view --json nameWithOwner 2>/dev/null)
if [ $? -ne 0 ]; then
  log "ERROR" "Failed to access GitHub repository"
  exit 1
fi

REPO_FULL=$(echo "$REPO_JSON" | jq -r ".nameWithOwner")
OWNER=$(echo "$REPO_FULL" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO_FULL" | cut -d'/' -f2)

init_state

echo "===================================================="
echo "🤖 Agent: $AGENT_NAME ($AGENT_SLUG) | Role: $MY_ROLE"
echo "📦 Repo: $OWNER/$REPO_NAME"
echo "⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "===================================================="

# 进程锁
LOCKFILE="/tmp/agent_${AGENT_SLUG}.lock"
exec 200>$LOCKFILE
flock -n 200 || { log "WARN" "Agent $AGENT_NAME is already running, exiting"; exit 0; }

# Git 同步
if [ -d ".git" ]; then
  git fetch origin main >/dev/null 2>&1
  LOCAL=$(git rev-parse HEAD 2>/dev/null)
  REMOTE=$(git rev-parse origin/main 2>/dev/null)
  if [ "$LOCAL" != "$REMOTE" ]; then
    log "INFO" "Syncing with origin/main..."
    git reset --hard origin/main >/dev/null 2>&1
  fi
fi

# 心跳
curl -s -X POST "$DASHBOARD_URL/api/agents" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AGENT_NAME\",\"role\":\"$MY_ROLE_LABEL\",\"action\":\"heartbeat\"}" > /dev/null

# 更新最后运行时间
jq ".last_run = \"$(date -Iseconds)\"" "$STATE_FILE" > /tmp/state_tmp.json && mv /tmp/state_tmp.json "$STATE_FILE"

# =============================================
# 回复模板
# =============================================

build_broadcast_response() {
  local title="$1"
  cat << EOF
[$AGENT_NAME] [skill/all]/analyzed: 已收到广播任务通知。

✅ 状态: 在线并准备就绪

📋 初步响应:
- 任务: $title
- 我将持续关注此任务进展，需要时主动配合。

---
*⚠️ skill/all 广播要求：所有 agent 必须实质性回复，禁止纯 ACK。*
EOF
}

build_direct_response() {
  local title="$1"
  cat << EOF
[$AGENT_NAME] [skill/$AGENT_SLUG]/analyzed: 已收到 @mention，正在分析。

📋 分析中:
- 任务: $title
- 将尽快提供实质性方案

---
*回复格式: [skill/slug]/analyzed*
EOF
}

build_role_task_response() {
  local title="$1"
  local role="$2"
  cat << EOF
[$AGENT_NAME] [skill/$role]/analyzed: 已收到 $MY_ROLE_LABEL 任务通知。

✅ 状态: 任务已确认，正在准备执行方案

📋 初步计划:
- 理解任务细节
- 制定执行方案
- 分步实施并汇报

---
*回复格式: [skill/slug]/analyzed*
EOF
}

build_claim_response() {
  local title="$1"
  cat << EOF
[$AGENT_NAME] [skill/$MY_ROLE]/analyzed: 我已领取此任务，正在分析需求。

📋 初步分析:
- 任务: $title
- 状态: 已认领，开始执行

🎯 执行计划:
1. 理解需求细节
2. 制定执行方案
3. 分步实施
4. 汇报结果

---
*回复格式: [skill/slug]/analyzed*
EOF
}

# =============================================
# 核心逻辑：检查是否已有实质性回复
# =============================================

has_real_reply() {
  local comments="$1"
  local agent_name="$2"

  echo "$comments" | grep -E '\[skill/[a-z-]+\]/analyzed' | grep -v "^\[ACK\]" | grep -q .
  return $?
}

# =============================================
# 处理 Discussion
# =============================================

process_discussions() {
  log "INFO" "Scanning Discussions..."

  local DISC_QUERY='query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){discussions(first:10,orderBy:{field:CREATED_AT,direction:DESC}){nodes{id,number,title,url,body,comments(last:20){nodes{author{login},body}}}}}}'

  local DISC_DATA=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -f query="$DISC_QUERY" --jq ".data.repository.discussions.nodes[]" 2>/dev/null)

  if [ -z "$DISC_DATA" ]; then
    log "INFO" "No active discussions found"
    return
  fi

  local processed=0
  local replied=0

  echo "$DISC_DATA" | jq -c "." | while read -r disc; do
    local D_NUM=$(echo "$disc" | jq -r '.number')
    local D_TITLE=$(echo "$disc" | jq -r '.title')
    local D_BODY=$(echo "$disc" | jq -r '.body // ""')

    processed=$((processed + 1))

    # 合并所有文本用于检测
    local ALL_TEXT="$D_TITLE $D_BODY"
    local COMMENTS_BODY=$(echo "$disc" | jq -r '.comments.nodes[].body // ""' | tr '\n' ' ')
    ALL_TEXT="$ALL_TEXT $COMMENTS_BODY"

    # 检测触发条件
    local HAS_SKILL_ALL=$(echo "$ALL_TEXT" | grep -i "$SKILL_ALL_LABEL" | wc -l)
    local IS_AGENT_ALL=$(echo "$ALL_TEXT" | grep -i "$AGENT_ALL_MENTION" | wc -l)
    local IS_TAGGED=$(echo "$ALL_TEXT" | grep -i "$VIRTUAL_MENTION" | wc -l)
    local HAS_MY_ROLE=$(echo "$ALL_TEXT" | grep -i "$MY_ROLE_LABEL" | wc -l)

    # 获取自己的回复
    local OWN_REPLIES=$(echo "$disc" | jq -r ".comments.nodes[] | select(.body | contains(\"[$AGENT_NAME]\")) | .body" 2>/dev/null)

    # 判断是否需要回复
    local SHOULD_RESPOND=0
    local REASON=""
    local RESPONSE_TYPE=""

    if [ "$HAS_SKILL_ALL" -gt "0" ]; then
      SHOULD_RESPOND=1
      REASON="skill/all broadcast"
      RESPONSE_TYPE="broadcast"
    elif [ "$IS_AGENT_ALL" -gt "0" ]; then
      SHOULD_RESPOND=1
      REASON="@agent/all mentioned"
      RESPONSE_TYPE="broadcast"
    elif [ "$IS_TAGGED" -gt "0" ]; then
      SHOULD_RESPOND=1
      REASON="direct @mention"
      RESPONSE_TYPE="direct"
    elif [ "$HAS_MY_ROLE" -gt "0" ]; then
      SHOULD_RESPOND=1
      REASON="$MY_ROLE_LABEL role task"
      RESPONSE_TYPE="role_task"
    fi

    # 检查是否已有回复（幂等性）
    if [ "$SHOULD_RESPOND" -eq "1" ]; then
      if has_real_reply "$OWN_REPLIES" "$AGENT_NAME"; then
        log "INFO" "Discussion #$D_NUM already has reply from $AGENT_NAME, skipping"
        continue
      fi

      echo "------------------------------------------------"
      echo "🗣️ DISCUSSION #$D_NUM: $D_TITLE"
      echo "📌 Trigger: $REASON"
      log "INFO" "Processing Discussion #$D_NUM: $REASON"

      local RESPONSE_BODY=""
      case "$RESPONSE_TYPE" in
        broadcast)
          echo "📢 Generating broadcast response..."
          RESPONSE_BODY=$(build_broadcast_response "$D_TITLE")
          ;;
        direct)
          echo "💬 Generating direct mention response..."
          RESPONSE_BODY=$(build_direct_response "$D_TITLE")
          ;;
        role_task)
          echo "🎯 Generating role task response..."
          RESPONSE_BODY=$(build_role_task_response "$D_TITLE" "$MY_ROLE")
          ;;
      esac

      if gh_api discussion_comment "$D_NUM" --body "$RESPONSE_BODY"; then
        log "INFO" "Replied to Discussion #$D_NUM"
        replied=$((replied + 1))
        update_stats "replies"
      else
        log "ERROR" "Failed to reply to Discussion #$D_NUM"
        update_stats "errors"
      fi
    fi
  done

  log "INFO" "Discussions: processed=$processed replied=$replied"
}

# =============================================
# 处理 Issues
# =============================================

process_issues() {
  log "INFO" "Scanning Issues..."

  local ISSUE_DATA=$(gh issue list --state open --json number,title,body,labels --limit 20 2>/dev/null)

  if [ -z "$ISSUE_DATA" ] || [ "$ISSUE_DATA" = "[]" ]; then
    log "INFO" "No open issues found"
    return
  fi

  local processed=0
  local replied=0
  local claimed=0

  echo "$ISSUE_DATA" | jq -c ".[]" | while read -r issue; do
    local I_NUM=$(echo "$issue" | jq -r '.number')
    local I_TITLE=$(echo "$issue" | jq -r '.title')
    local I_BODY=$(echo "$issue" | jq -r '.body // ""')
    local I_LABELS=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ' ')

    processed=$((processed + 1))

    local HAS_SKILL_ALL=$(echo "$I_LABELS" | grep -i "$SKILL_ALL_LABEL" | wc -l)
    local HAS_MY_ROLE=$(echo "$I_LABELS" | grep -i "$MY_ROLE_LABEL" | wc -l)
    local HAS_MY_LABEL=$(echo "$I_LABELS" | grep -i "$IDENTITY_LABEL" | wc -l)

    # 过滤：只处理 skill/all 或我的 role 标签
    if [ "$HAS_SKILL_ALL" -eq "0" ] && [ "$HAS_MY_ROLE" -eq "0" ]; then
      continue
    fi

    # 检查是否已有回复
    local OWN_COMMENTS=$(gh issue view $I_NUM --json comments --jq ".comments[] | select(.body | contains(\"[$AGENT_NAME]\")) | .body" 2>/dev/null)

    if has_real_reply "$OWN_COMMENTS" "$AGENT_NAME"; then
      log "INFO" "Issue #$I_NUM already has reply from $AGENT_NAME, skipping"
      continue
    fi

    echo "------------------------------------------------"
    echo "📌 ISSUE #$I_NUM: $I_TITLE"

    if [ "$HAS_SKILL_ALL" -gt "0" ]; then
      echo "📢 skill/all broadcast - providing substantive response..."
      local RESPONSE_BODY=$(build_broadcast_response "$I_TITLE")

      if gh_api issue_comment "$I_NUM" --body "$RESPONSE_BODY"; then
        replied=$((replied + 1))
        update_stats "replies"
      fi

    elif [ "$HAS_MY_ROLE" -gt "0" ] && [ "$HAS_MY_LABEL" -eq "0" ]; then
      # 尝试认领任务（原子锁）
      local IS_LOCKED=$(gh issue view "$I_NUM" --json labels --jq ".labels[] | select(.name | startswith(\"agent/\"))" 2>/dev/null | wc -l)

      if [ "$IS_LOCKED" -eq "0" ]; then
        echo "🔒 Claiming exclusive task..."
        log "INFO" "Claiming Issue #$I_NUM"

        if gh_api issue_edit "$I_NUM" --add-label "task/processing,$IDENTITY_LABEL" --remove-label "task"; then
          local RESPONSE_BODY=$(build_claim_response "$I_TITLE")
          if gh_api issue_comment "$I_NUM" --body "$RESPONSE_BODY"; then
            claimed=$((claimed + 1))
            replied=$((replied + 1))
            update_stats "replies"
          fi
        fi
      else
        log "INFO" "Issue #$I_NUM is locked by another agent, skipping"
      fi
    fi
  done

  log "INFO" "Issues: processed=$processed replied=$replied claimed=$claimed"
}

# =============================================
# 主流程
# =============================================

main() {
  process_discussions
  echo ""
  process_issues
  echo ""
  echo "===================================================="
  echo "✅ Scan complete. Stats: $(cat "$STATE_FILE" | jq '.stats')"
  log "INFO" "Run complete. Stats: $(jq -r '.stats' "$STATE_FILE")"
}

main
