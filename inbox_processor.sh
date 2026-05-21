#!/bin/bash

# Multi-Agent Inbox Processor (v6.2.0)
# Agency v6.2: Sentient Reasoning + Concurrency Fix + Memory Pruning

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

init_role_if_missing() {
  local role_dir="roles/$AGENT_SLUG"
  if [ ! -d "$role_dir" ]; then
    log "INFO" "Soul Awakening: Initializing role scaffolding for $AGENT_NAME ($AGENT_SLUG)..."
    
    # 自动识别部门 (Division)
    local division="engineering" # 默认
    if [[ "$MY_ROLE_LABEL" == *"management"* ]] || [[ "$MY_ROLE_LABEL" == *"commander"* ]]; then
      division="management"
    elif [[ "$MY_ROLE_LABEL" == *"qa_audit"* ]] || [[ "$MY_ROLE_LABEL" == *"collector"* ]] || [[ "$MY_ROLE_LABEL" == *"reality_checker"* ]]; then
      division="qa_audit"
    fi

    mkdir -p "$role_dir/diary"
    
    # 从模板拷贝
    local template_dir="roles/templates/$division"
    [ ! -d "$template_dir" ] && template_dir="roles/templates/engineering" # Fallback
    
    cp "$template_dir/SOUL.md" "$role_dir/SOUL.md"
    cp "$template_dir/AGENTS.md" "$role_dir/AGENTS.md"
    cp "roles/templates/IDENTITY.md" "$role_dir/IDENTITY.md"
    
    # 填充变量
    sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g" "$role_dir/SOUL.md"
    sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g" "$role_dir/IDENTITY.md"
    
    log "INFO" "Scaffolding complete. Committing to repository..."
    # Concurrency Fix: Pull before push
    sleep $((RANDOM % 10))
    git add "$role_dir"
    git pull --rebase origin main
    git commit -m "chore: soul awakening for $AGENT_NAME ($AGENT_SLUG)"
    git push origin main
  fi
}

log_diary() {
  local entry="$1"
  local diary_dir="roles/$AGENT_SLUG/diary"
  [ ! -d "roles/$AGENT_SLUG" ] && return # 还没初始化
  mkdir -p "$diary_dir"
  local diary_file="$diary_dir/$(date +%Y-%m-%d).md"
  if [ ! -f "$diary_file" ]; then
    echo "# Diary - $AGENT_NAME ($(date +%Y-%m-%d))" > "$diary_file"
  fi
  echo "- [$(date +%H:%M:%S)] $entry" >> "$diary_file"
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

# =============================================
# 处理 Pull Requests
# =============================================

process_prs() {
  log "INFO" "Scanning Pull Requests..."

  local PR_DATA=$(gh pr list --state open --json number,title,body,labels --limit 20 2>/dev/null)

  if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "[]" ]; then
    log "INFO" "No open PRs found"
    return
  fi

  local processed=0
  local found=0

  echo "$PR_DATA" | jq -c ".[]" | while read -r pr; do
    local P_NUM=$(echo "$pr" | jq -r '.number')
    local P_TITLE=$(echo "$pr" | jq -r '.title')
    local P_BODY=$(echo "$pr" | jq -r '.body // ""')
    local P_LABELS=$(echo "$pr" | jq -r '.labels[].name' | tr '\n' ' ')

    processed=$((processed + 1))

    # 获取 PR 详情
    local PR_DETAILS=$(gh pr view "$P_NUM" --json comments,author,statusCheckRollup 2>/dev/null)
    local LAST_COMMENT_AUTHOR=$(echo "$PR_DETAILS" | jq -r '.comments[-1].author.login // "ghost"')
    
    # 最后发言人保护
    if is_last_speaker "$LAST_COMMENT_AUTHOR"; then
       local TAGGED_IN_BODY=$(echo "$P_TITLE $P_BODY" | grep -i "$VIRTUAL_MENTION" | wc -l)
       local TAGGED_IN_LAST=$(echo "$PR_DETAILS" | jq -r '.comments[-1].body' | grep -i "$VIRTUAL_MENTION" | wc -l)
       
       if [ "$TAGGED_IN_BODY" -eq "0" ] && [ "$TAGGED_IN_LAST" -eq "0" ]; then
         continue
       fi
    fi

    # 自动关闭逻辑 (Agency Lead)
    if [ "$AGENT_SLUG" = "xiaoxi" ]; then
       local IS_VERIFIED=$(echo "$PR_DETAILS" | jq -r '.comments[].body' | grep -E "\[Answer\].*VERIFIED" | wc -l)
       if [ "$IS_VERIFIED" -gt "0" ]; then
         echo "🚨 ACTION_REQUIRED: Merge/Close PR #$P_NUM (Verified by Answer)"
         continue
       fi
    fi

    # 检测触发
    local IS_TAGGED=$(echo "$P_TITLE $P_BODY $PR_DETAILS" | grep -i "$VIRTUAL_MENTION" | wc -l)
    local IS_ROLE_TASK=$(echo "$P_LABELS" | grep -i "$MY_ROLE_LABEL" | wc -l)
    
    # Answer 特有逻辑：检查 CI 状态
    if [ "$AGENT_SLUG" = "answer" ]; then
       local CI_STATUS=$(echo "$PR_DETAILS" | jq -r '.statusCheckRollup[].status // "unknown"')
       if [ "$CI_STATUS" = "COMPLETED" ] || [ "$CI_STATUS" = "SUCCESS" ]; then
         echo "🚨 ACTION_REQUIRED: Audit PR #$P_NUM (CI Passed - Ready for Audit)"
       elif [ "$CI_STATUS" = "FAILURE" ]; then
         echo "🚨 ACTION_REQUIRED: Review PR #$P_NUM (CI Failed - Investigation Required)"
       fi
    fi

    if [ "$IS_TAGGED" -gt "0" ] || [ "$IS_ROLE_TASK" -gt "0" ]; then
       # 检查是否已实质性回复
       local OWN_COMMENTS=$(echo "$PR_DETAILS" | jq -r ".comments[] | select(.author.login | contains(\"$AGENT_SLUG\")) | .body" 2>/dev/null)
       if has_real_reply "$OWN_COMMENTS" "$AGENT_NAME"; then
         continue
       fi

       found=$((found + 1))
       echo "🚨 ACTION_REQUIRED: PR #$P_NUM: $P_TITLE"
       echo "   Type: Pull Request"
       echo "   Context: $(echo "$PR_DETAILS" | jq -r '.comments[-5:].body // ""')"
       echo "   CI Status: $(echo "$PR_DETAILS" | jq -r '.statusCheckRollup[].status // "N/A")"
       echo "   Instruction: Review and provide a substantive [PROPOSAL] or [AUDIT]."
       echo "------------------------------------------------"
    fi
  done

  log "INFO" "PRs: processed=$processed action_required=$found"
}


# 辅助函数扩展
gh_api() {
  local cmd="$1"
  shift

  case "$cmd" in
    discussion_comment) retry gh discussion comment "$@";;
    issue_comment) retry gh issue comment "$@";;
    issue_edit) retry gh issue edit "$@";;
    issue_view) retry gh issue view "$@";;
    pr_comment) retry gh pr comment "$@";;
    pr_close) retry gh pr close "$@";;
    issue_close) retry gh issue close "$@";;
    api) retry gh api "$@";;
    *) log "ERROR" "Unknown gh_api command: $cmd"; return 1;;
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
init_role_if_missing

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
# 核心逻辑：回复判定
# =============================================


is_last_speaker() {
  local last_author="$1"
  [ "$last_author" = "ghost" ] && return 1
  [[ "$last_author" == *"$AGENT_SLUG"* ]] && return 0
  return 1
}

has_real_reply() {
  local comments="$1"
  local agent_name="$2"
  local slug="$AGENT_SLUG"

  echo "$comments" | grep -Ei "(\[$agent_name\]|@agent/$slug|@$slug)" | \
    grep -vE "收到任务|已领用|已收到广播|认领任务|\[ACK\]" | grep -q .
  return $?
}

fetch_context() {
  local type="$1" # issue or discussion
  local num="$2"
  if [ "$type" = "issue" ]; then
    gh issue view "$num" --json comments --jq '.comments[-5:] | .[].body' 2>/dev/null || echo ""
  else
    # Discussion context is harder via CLI without GraphQL, 
    # but for now we'll assume the $disc object passed to the loop already has the comments.
    echo ""
  fi
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
  local found=0

  echo "$DISC_DATA" | jq -c "." | while read -r disc; do
    local D_NUM=$(echo "$disc" | jq -r '.number')
    local D_TITLE=$(echo "$disc" | jq -r '.title')
    local D_BODY=$(echo "$disc" | jq -r '.body // ""')
    local LAST_AUTHOR=$(echo "$disc" | jq -r '.comments.nodes[-1].author.login // "ghost"')

    processed=$((processed + 1))

    # 1. 最后发言人保护
    local IS_ME_TAGGED=$(echo "$D_TITLE $D_BODY" | grep -i "$VIRTUAL_MENTION" | wc -l)
    local NEW_COMMENTS_TAGGED=$(echo "$disc" | jq -r '.comments.nodes[].body' | tail -n 1 | grep -i "$VIRTUAL_MENTION" | wc -l)
    
    if is_last_speaker "$LAST_AUTHOR"; then
       if [ "$IS_ME_TAGGED" -eq "0" ] && [ "$NEW_COMMENTS_TAGGED" -eq "0" ]; then
         continue
       fi
    fi

    # 合并文本用于检测触发
    local COMMENTS_TEXT=$(echo "$disc" | jq -r '.comments.nodes[].body // ""' | tr '\n' ' ')
    local ALL_TEXT="$D_TITLE $D_BODY $COMMENTS_TEXT"

    # 检测触发条件
    local HAS_SKILL_ALL=$(echo "$ALL_TEXT" | grep -i "$SKILL_ALL_LABEL" | wc -l)
    local IS_AGENT_ALL=$(echo "$ALL_TEXT" | grep -i "$AGENT_ALL_MENTION" | wc -l)
    local IS_TAGGED=$(echo "$ALL_TEXT" | grep -i "$VIRTUAL_MENTION" | wc -l)
    local HAS_MY_ROLE=$(echo "$ALL_TEXT" | grep -i "$MY_ROLE_LABEL" | wc -l)

    if [ "$HAS_SKILL_ALL" -gt "0" ] || [ "$IS_AGENT_ALL" -gt "0" ] || [ "$IS_TAGGED" -gt "0" ] || [ "$HAS_MY_ROLE" -gt "0" ]; then
       # 检查是否已实质性回复
       local OWN_REPLIES=$(echo "$disc" | jq -r ".comments.nodes[] | select(.author.login | contains(\"$AGENT_SLUG\")) | .body" 2>/dev/null)
       if has_real_reply "$OWN_REPLIES" "$AGENT_NAME"; then
         continue
       fi

       found=$((found + 1))
       echo "🚨 ACTION_REQUIRED: Discussion #$D_NUM: $D_TITLE"
       echo "   Type: Discussion"
       echo "   Context: $(echo "$disc" | jq -r '.comments.nodes[-3:].body // ""')"
       echo "   Instruction: Please provide a substantive [PROPOSAL] or [DRAFT]."
       echo "------------------------------------------------"
    fi
  done

  log "INFO" "Discussions: processed=$processed action_required=$found"
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
  local found=0

  echo "$ISSUE_DATA" | jq -c ".[]" | while read -r issue; do
    local I_NUM=$(echo "$issue" | jq -r '.number')
    local I_TITLE=$(echo "$issue" | jq -r '.title')
    local I_BODY=$(echo "$issue" | jq -r '.body // ""')
    local I_LABELS=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ' ')

    processed=$((processed + 1))

    # 获取详情
    local ISSUE_DETAILS=$(gh issue view "$I_NUM" --json comments,author 2>/dev/null)
    local LAST_COMMENT_AUTHOR=$(echo "$ISSUE_DETAILS" | jq -r '.comments[-1].author.login // "ghost"')
    
    # 最后发言人保护
    if is_last_speaker "$LAST_COMMENT_AUTHOR"; then
       local TAGGED_IN_BODY=$(echo "$I_TITLE $I_BODY" | grep -i "$VIRTUAL_MENTION" | wc -l)
       local TAGGED_IN_LAST=$(echo "$ISSUE_DETAILS" | jq -r '.comments[-1].body' | grep -i "$VIRTUAL_MENTION" | wc -l)
       
       if [ "$TAGGED_IN_BODY" -eq "0" ] && [ "$TAGGED_IN_LAST" -eq "0" ]; then
         continue
       fi
    fi

    # 自动关闭逻辑 (Agency Lead)
    if [ "$AGENT_SLUG" = "xiaoxi" ]; then
       local IS_VERIFIED=$(echo "$ISSUE_DETAILS" | jq -r '.comments[].body' | grep -E "\[Answer\].*VERIFIED" | wc -l)
       if [ "$IS_VERIFIED" -gt "0" ]; then
         echo "🚨 ACTION_REQUIRED: Close Issue #$I_NUM (Verified by Answer)"
         continue
       fi
    fi

    # 检测触发
    local IS_TAGGED=$(echo "$I_TITLE $I_BODY $ISSUE_DETAILS" | grep -i "$VIRTUAL_MENTION" | wc -l)
    local IS_ROLE_TASK=$(echo "$I_LABELS" | grep -i "$MY_ROLE_LABEL" | wc -l)
    local IS_SKILL_ALL=$(echo "$I_LABELS" | grep -i "$SKILL_ALL_LABEL" | wc -l)

    if [ "$IS_TAGGED" -gt "0" ] || [ "$IS_ROLE_TASK" -gt "0" ] || [ "$IS_SKILL_ALL" -gt "0" ]; then
       # 检查是否已实质性回复
       local OWN_COMMENTS=$(echo "$ISSUE_DETAILS" | jq -r ".comments[] | select(.author.login | contains(\"$AGENT_SLUG\")) | .body" 2>/dev/null)
       if has_real_reply "$OWN_COMMENTS" "$AGENT_NAME"; then
         continue
       fi

       found=$((found + 1))
       echo "🚨 ACTION_REQUIRED: Issue #$I_NUM: $I_TITLE"
       echo "   Type: Issue"
       echo "   Labels: $I_LABELS"
       echo "   Context: $(echo "$ISSUE_DETAILS" | jq -r '.comments[-3:].body // ""')"
       echo "   Instruction: Analyze and provide a substantive [PROPOSAL] or [DELIVERABLE]."
       echo "------------------------------------------------"
    fi
  done

  log "INFO" "Issues: processed=$processed action_required=$found"
}


  local processed=0
  local replied=0
  local claimed=0

  echo "$ISSUE_DATA" | jq -c ".[]" | while read -r issue; do
    local I_NUM=$(echo "$issue" | jq -r '.number')
    local I_TITLE=$(echo "$issue" | jq -r '.title')
    local I_BODY=$(echo "$issue" | jq -r '.body // ""')
    local I_LABELS=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ' ')

    processed=$((processed + 1))

    # 获取 Issue 详情用于检测最后发言人
    local ISSUE_DETAILS=$(gh issue view "$I_NUM" --json comments,author 2>/dev/null)
    local LAST_COMMENT_AUTHOR=$(echo "$ISSUE_DETAILS" | jq -r '.comments[-1].author.login // "ghost"')
    
    if is_last_speaker "$LAST_COMMENT_AUTHOR"; then
       # 检查正文或最后一条评论是否又艾特了我
       local TAGGED_IN_BODY=$(echo "$I_TITLE $I_BODY" | grep -i "$VIRTUAL_MENTION" | wc -l)
       local TAGGED_IN_LAST=$(echo "$ISSUE_DETAILS" | jq -r '.comments[-1].body' | grep -i "$VIRTUAL_MENTION" | wc -l)
       
       if [ "$TAGGED_IN_BODY" -eq "0" ] && [ "$TAGGED_IN_LAST" -eq "0" ]; then
         log "INFO" "I am the last speaker in Issue #$I_NUM and no new tag, skipping to prevent loop"
         continue
       fi
    fi

    local HAS_SKILL_ALL=$(echo "$I_LABELS" | grep -i "$SKILL_ALL_LABEL" | wc -l)

    local HAS_MY_ROLE=$(echo "$I_LABELS" | grep -i "$MY_ROLE_LABEL" | wc -l)
    local HAS_MY_LABEL=$(echo "$I_LABELS" | grep -i "$IDENTITY_LABEL" | wc -l)

    # 5. 自动关闭逻辑 (v6.0 新增)
    # 只有 Agency Lead (xiaoxi) 有权在 Answer 验证后关闭任务
    if [ "$AGENT_SLUG" = "xiaoxi" ]; then
       local IS_VERIFIED=$(echo "$ISSUE_DETAILS" | jq -r '.comments[].body' | grep -E "\[Answer\].*VERIFIED" | wc -l)
       if [ "$IS_VERIFIED" -gt "0" ]; then
         echo "🏁 Task #$I_NUM is VERIFIED. Closing..."
         log "INFO" "Closing Issue #$I_NUM (Verified by Answer)"
         gh_api issue_comment "$I_NUM" --body "[小溪]: 经 @agent/answer 验证通过，现正式关闭此任务。Good job team."
         gh_api issue_close "$I_NUM"
         continue
       fi
    fi

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
      local CONTEXT=$(echo "$ISSUE_DETAILS" | jq -r '.comments[-3:].body // ""')
      local RESPONSE_BODY=$(build_broadcast_response "$I_TITLE" "$CONTEXT")

          if gh_api issue_comment "$I_NUM" --body "$RESPONSE_BODY"; then
            log "INFO" "Replied to direct mention in Issue #$I_NUM"
            log_diary "Replied to direct mention in Issue #$I_NUM"
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
        log "INFO" "Replied to Issue #$I_NUM"
        log_diary "Replied to Issue #$I_NUM ($REASON)"
        replied=$((replied + 1))
        update_stats "replies"
      else
        log "ERROR" "Failed to reply to Issue #$I_NUM"
        update_stats "errors"
      fi
    fi

    # 4. 角色专属任务锁定
    if echo "$I_LABELS" | grep -q "$MY_ROLE_LABEL"; then
       # 检查是否已锁定
       local IS_LOCKED=$(echo "$I_LABELS" | grep -E "task/processing|agent/" | wc -l)
       if [ "$IS_LOCKED" -lt "2" ]; then
         echo "🔒 Claiming private task #$I_NUM..."
         log "INFO" "Claiming Issue #$I_NUM"
         log_diary "Claimed Task #$I_NUM"
         local CLAIM_BODY=$(build_claim_response "$I_TITLE")
         gh_api issue_edit "$I_NUM" --add-label "task/processing,$IDENTITY_LABEL" --remove-label "task"
         gh_api issue_comment "$I_NUM" --body "$CLAIM_BODY"
       fi
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

final_push() {
  local role_dir="roles/$AGENT_SLUG"
  if [ -d "$role_dir" ]; then
    # 检查是否有改动
    if git status --porcelain "$role_dir" | grep -q .; then
      log "INFO" "Persisting memory and diary to repository..."
      # Concurrency Fix: Pull with rebase and random backoff
      sleep $((RANDOM % 15))
      git add "$role_dir"
      git pull --rebase origin main
      git commit -m "chore: update memory/diary for $AGENT_NAME ($(date +%Y-%m-%d))"
      git push origin main
    fi
  fi
}

check_memory_bloat() {
  local role_dir="roles/$AGENT_SLUG"
  [ ! -d "$role_dir" ] && return
  
  local diary_count=$(find "$role_dir/diary" -name "*.md" | wc -l)
  if [ "$diary_count" -gt 10 ]; then
    echo "🚨 ACTION_REQUIRED: Memory Compaction"
    echo "   Reason: You have $diary_count diary entries. Please summarize them into IDENTITY.md milestones and archive old entries."
    echo "------------------------------------------------"
  fi
}

main() {
  check_memory_bloat
  process_discussions
  echo ""
  process_issues
  echo ""
  process_prs
  echo ""
  final_push
  echo "===================================================="

  echo "✅ Scan complete. Stats: $(cat "$STATE_FILE" | jq '.stats')"
  log "INFO" "Run complete. Stats: $(jq -r '.stats' "$STATE_FILE")"
}

main
