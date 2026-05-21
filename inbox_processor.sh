#!/bin/bash

# Multi-Agent Inbox Processor (v6.3.1)
# Agency v6.3.1: Incremental Scan + Mailbox Purge + Capability Gates

set -e

TOKEN=$1
MY_ROLE_LABEL=$2
AGENT_NAME=$3
AGENT_SLUG=$4

DASHBOARD_URL="https://multi-agent-task-dashboard.vercel.app"

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

# =============================================
# 能力加载 (Capability Loading)
# =============================================
get_config_value() {
  local key=$1
  jq -r ".agents[] | select(.slug == \"$AGENT_SLUG\") | .$key" agents.json 2>/dev/null || echo "null"
}

CAPABILITIES=$(get_config_value "capabilities")
ARCHETYPE=$(get_config_value "archetype")

has_capability() {
  local cap=$1
  echo "$CAPABILITIES" | jq -e ". | contains([\"$cap\"])" >/dev/null 2>&1
}

# =============================================
# 工具函数
# =============================================
STATE_DIR="/tmp/agent_state_${AGENT_SLUG}"
LOG_FILE="${STATE_DIR}/activity.log"
LAST_SCAN_FILE="${STATE_DIR}/last_scan.at"
mkdir -p "$STATE_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" | tee -a "$LOG_FILE"
}

pull_with_healing() {
  git pull --rebase -X theirs origin main || {
    log "WARN" "Conflict detected, forcing remote state"
    git rebase --abort || true
    git fetch origin main
    git reset --hard origin main
  }
}

init_role_if_missing() {
  local role_dir="roles/$AGENT_SLUG"
  if [ ! -d "$role_dir" ]; then
    log "INFO" "Soul Awakening: Initializing $AGENT_NAME as archetype '$ARCHETYPE'..."
    mkdir -p "$role_dir/diary"
    local template_dir="roles/templates/$ARCHETYPE"
    [ ! -d "$template_dir" ] && template_dir="roles/templates/engineering"
    
    cp "$template_dir/SOUL.md" "$role_dir/SOUL.md"
    cp "$template_dir/AGENTS.md" "$role_dir/AGENTS.md"
    cp "roles/templates/IDENTITY.md" "$role_dir/IDENTITY.md"
    
    sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g" "$role_dir/SOUL.md"
    sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g" "$role_dir/IDENTITY.md"
    
    sleep $((RANDOM % 10))
    git add "$role_dir"
    pull_with_healing
    git commit -m "chore: soul awakening for $AGENT_NAME ($AGENT_SLUG)"
    git push origin main
  fi
}

write_mailbox() {
  local task_id=$1
  local type=$2
  local reason=$3
  local context=$4
  local inbox_file="roles/$AGENT_SLUG/inbox.json"
  
  local entry=$(jq -n \
    --arg id "$task_id" \
    --arg type "$type" \
    --arg reason "$reason" \
    --arg context "$context" \
    --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id: $id, type: $type, reason: $reason, context: $context, timestamp: $time}')
    
  if [ ! -f "$inbox_file" ]; then
    echo "{\"pending_tasks\": []}" > "$inbox_file"
  fi
  
  local new_inbox=$(jq ".pending_tasks = ([.pending_tasks[] | select(.id != \"$task_id\")] + [$entry])" "$inbox_file")
  echo "$new_inbox" > "$inbox_file"
}

cleanup_mailbox() {
  local inbox_file="roles/$AGENT_SLUG/inbox.json"
  [ ! -f "$inbox_file" ] && return
  
  log "INFO" "Purging closed tasks from mailbox..."
  local closed_ids=$(gh issue list --state closed --limit 50 --json number -q '.[].number')
  local merged_prs=$(gh pr list --state merged --limit 50 --json number -q '.[].number')
  local all_done="$closed_ids $merged_prs"
  
  local new_inbox=$(jq --arg done "$all_done" '.pending_tasks = [.pending_tasks[] | select(.id as $id | ($done | contains($id) | not))]' "$inbox_file")
  echo "$new_inbox" > "$inbox_file"
}

# =============================================
# 核心扫描逻辑 (Capability Gates)
# =============================================
is_last_speaker() {
  [[ "$1" == *"$AGENT_SLUG"* ]] && return 0
  return 1
}

has_real_reply() {
  echo "$1" | grep -Ei "(\[$AGENT_NAME\]|@agent/$AGENT_SLUG|@$AGENT_SLUG)" | \
    grep -vE "收到任务|已领用|ACK" | grep -q .
}

process_item() {
  local type=$1 
  local id=$2
  local title=$3
  local body=$4
  local last_author=$5
  local all_text=$6
  local comments=$7

  # 1. 最后发言人保护
  if is_last_speaker "$last_author"; then
    local tagged=$(echo "$all_text" | grep -i "$VIRTUAL_MENTION" | wc -l)
    [ "$tagged" -eq "0" ] && return
  fi

  # 2. 能力门禁逻辑
  local trigger_reason=""

  # A. 管理权 (CAN_CLOSE / CAN_STRATEGIZE)
  if has_capability "CAN_CLOSE"; then
     if echo "$comments" | grep -q "VERIFIED"; then
       trigger_reason="auto_close_ready"
     fi
  fi
  if has_capability "CAN_STRATEGIZE" && [ -z "$trigger_reason" ]; then
     if [[ "$all_text" == *"[TASK]"* ]] && ! echo "$comments" | grep -q "PROPOSAL"; then
       trigger_reason="strategy_needed"
     fi
  fi

  # B. 审计权 (CAN_AUDIT)
  if has_capability "CAN_AUDIT" && [ -z "$trigger_reason" ]; then
     if echo "$comments" | grep -q "PROPOSAL" && ! echo "$comments" | grep -q "AUDIT"; then
       trigger_reason="audit_required"
     fi
  fi

  # C. 执行权 (CAN_EXECUTE)
  if has_capability "CAN_EXECUTE" && [ -z "$trigger_reason" ]; then
     if echo "$comments" | grep -q "APPROVED" && ! echo "$comments" | grep -q "DELIVERABLE"; then
       trigger_reason="execution_ready"
     fi
  fi

  # D. 兜底触发 (Direct Mentions)
  if [ -z "$trigger_reason" ]; then
     local is_tagged=$(echo "$all_text" | grep -Ei "($VIRTUAL_MENTION|$AGENT_ALL_MENTION|$SKILL_ALL_LABEL)" | wc -l)
     [ "$is_tagged" -gt "0" ] && trigger_reason="direct_mention"
  fi

  if [ -n "$trigger_reason" ]; then
     has_real_reply "$comments" && return
     echo "🚨 ACTION_REQUIRED: $type #$id ($trigger_reason)"
     write_mailbox "$id" "$type" "$trigger_reason" "Context: $(echo "$comments" | tail -n 5)"
  fi
}

# =============================================
# 运行环境
# =============================================
export GITHUB_TOKEN="$TOKEN"
REPO_FULL=$(gh repo view --json nameWithOwner --jq ".nameWithOwner")
OWNER=$(echo "$REPO_FULL" | cut -d'/' -f1)
REPO_NAME=$(echo "$REPO_FULL" | cut -d'/' -f2)

init_role_if_missing

# 增量扫描时间窗口 (默认 10 分钟内有更新的)
SINCE_TIME=$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
[ -f "$LAST_SCAN_FILE" ] && SINCE_TIME=$(cat "$LAST_SCAN_FILE")

echo "🕵️ [$AGENT_NAME] Incremental Scan (since $SINCE_TIME)..."

# Discussion Loop
gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -f query='query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){discussions(first:10,states:OPEN){nodes{number,title,body,comments(last:20){nodes{author{login},body}}}}}}' --jq ".data.repository.discussions.nodes[]" | jq -c "." | while read -r d; do
  process_item "discussion" "$(echo $d | jq -r .number)" "$(echo $d | jq -r .title)" "$(echo $d | jq -r .body)" "$(echo $d | jq -r .comments.nodes[-1].author.login)" "$(echo $d | jq -r '.title, .body, .comments.nodes[].body')" "$(echo $d | jq -r '.comments.nodes[].body')"
done

# Issue/PR Loop (Incremental)
gh issue list --state open --updated "$SINCE_TIME" --json number,title,body,labels --limit 20 | jq -c ".[]" | while read -r i; do
  details=$(gh issue view "$(echo $i | jq -r .number)" --json comments,author)
  process_item "issue" "$(echo $i | jq -r .number)" "$(echo $i | jq -r .title)" "$(echo $i | jq -r .body)" "$(echo $details | jq -r .comments[-1].author.login)" "$(echo $i | jq -r .title, .body; echo $details | jq -r .comments[].body)" "$(echo $details | jq -r .comments[].body)"
done

cleanup_mailbox
date -u +%Y-%m-%dT%H:%M:%SZ > "$LAST_SCAN_FILE"

# Final Push
local_dir="roles/$AGENT_SLUG"
if [ -d "$local_dir" ] && git status --porcelain "$local_dir" | grep -q .; then
  sleep $((RANDOM % 15))
  git add "$local_dir"
  pull_with_healing
  git commit -m "chore: update memory/mailbox for $AGENT_NAME"
  git push origin main
fi

echo "✅ [$AGENT_NAME] Scan complete."
