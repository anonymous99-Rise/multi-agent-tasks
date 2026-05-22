#!/bin/bash
# health_check.sh - Multi-Agent 健康检测脚本 v1.0
# 用于检测三个 Agent 的存活状态

set -e

TOKEN="${GITHUB_TOKEN:-$1}"
REPO="${2:-adminlove520/multi-agent-tasks}"
STATE_DIR="/tmp/agent_health"
mkdir -p "$STATE_DIR"

# =============================================
# 配置
# =============================================
BOTS=(
  "taizi:8435768342:YinxiaBot"
  "answer:8773175290:Anwsermebot"
  "xiaoxi:caddycherrybot:caddycherrybot"
)
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"  # 默认 5 分钟
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"     # 连续失败 3 次才告警
BOT_TOKEN=""

# =============================================
# 日志
# =============================================
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [health_check] $1"
}

# =============================================
# Telegram 通知
# =============================================
send_telegram() {
  local bot_token="$1"
  local chat_id="$2"
  local message="$3"
  
  curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -d "chat_id=${chat_id}" \
    -d "text=${message}" \
    -d "parse_mode=Markdown" > /dev/null 2>&1
}

# =============================================
# 检测单个 Bot
# =============================================
check_bot() {
  local slug="$1"
  local tg_id="$2"
  local username="$3"
  
  local last_seen_file="${STATE_DIR}/${slug}.last_seen"
  local fail_count_file="${STATE_DIR}/${slug}.fail_count"
  local last_activity_file="${STATE_DIR}/${slug}.last_activity"
  
  # 检查最后活动时间（通过 GH Discussion 最近评论时间估算）
  local latest_comment_time=""
  if [ -n "$TOKEN" ]; then
    latest_comment_time=$(gh api repos/${REPO}/discussions/comments \
      --jq ".[] | select(.author.login == \"$slug\") | .createdAt" 2>/dev/null | head -1)
  fi
  
  local current_time=$(date -u +%s)
  local last_seen=0
  [ -f "$last_seen_file" ] && last_seen=$(cat "$last_seen_file")
  
  local time_diff=$((current_time - last_seen))
  
  # 判断状态
  local status="unknown"
  local should_alert=0
  
  if [ "$time_diff" -lt "$CHECK_INTERVAL" ]; then
    status="online"
    echo "0" > "$fail_count_file"
  elif [ "$time_diff" -lt $((CHECK_INTERVAL * FAIL_THRESHOLD)) ]; then
    status="warning"
  else
    status="offline"
    local fail_count=$(cat "$fail_count_file" 2>/dev/null || echo "0")
    fail_count=$((fail_count + 1))
    echo "$fail_count" > "$fail_count_file"
    
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
      should_alert=1
    fi
  fi
  
  # 更新最后活动时间
  if [ -n "$latest_comment_time" ]; then
    local gh_time=$(date -d "$latest_comment_time" -u +%s 2>/dev/null || echo "$current_time")
    echo "$gh_time" > "$last_seen_file"
  else
    echo "$current_time" > "$last_seen_file"
  fi
  
  # 记录
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${slug}: ${status} (${time_diff}s ago)" >> "$last_activity_file"
  
  return $should_alert
}

# =============================================
# 生成健康报告
# =============================================
generate_report() {
  local report_file="${STATE_DIR}/health_report.md"
  
  cat > "$report_file" << 'EOF'
# 🤖 Multi-Agent 健康检测报告

EOF
  
  for bot_config in "${BOTS[@]}"; do
    IFS=':' read -r slug tg_id username <<< "$bot_config"
    local last_seen_file="${STATE_DIR}/${slug}.last_seen"
    local fail_count_file="${STATE_DIR}/${slug}.fail_count"
    
    local current_time=$(date -u +%s)
    local last_seen=0
    [ -f "$last_seen_file" ] && last_seen=$(cat "$last_seen_file")
    local time_diff=$((current_time - last_seen))
    local fail_count=$(cat "$fail_count_file" 2>/dev/null || echo "0")
    
    local status="❓ Unknown"
    [ "$time_diff" -lt "$CHECK_INTERVAL" ] && status="✅ Online"
    [ "$time_diff" -ge "$CHECK_INTERVAL" ] && [ "$time_diff" -lt $((CHECK_INTERVAL * 2)) ] && status="⚠️ Warning"
    [ "$time_diff" -ge $((CHECK_INTERVAL * 2)) ] && status="❌ Offline"
    
    echo "| ${slug} | ${status} | ${time_diff}s ago | ${fail_count} |" >> "$report_file"
  done
  
  echo "" >> "$report_file"
  echo "*生成时间: $(date '+%Y-%m-%d %H:%M:%S') UTC*" >> "$report_file"
  
  cat "$report_file"
}

# =============================================
# 主逻辑
# =============================================
main() {
  log "开始健康检测..."
  
  local has_changes=0
  local alert_message="🚨 *Multi-Agent 健康告警*\n\n"
  local has_alert=0
  
  for bot_config in "${BOTS[@]}"; do
    IFS=':' read -r slug tg_id username <<< "$bot_config"
    
    if check_bot "$slug" "$tg_id" "$username"; then
      has_alert=1
      alert_message="${alert_message}• ${slug}: 需要关注 ❗\n"
    fi
  done
  
  # 生成报告
  generate_report
  
  # 如果有告警，发送到 Task-Control 群
  if [ "$has_alert" -eq 1 ]; then
    log "检测到异常 Bot，准备发送告警"
    # alert_message 已包含异常 Bot 信息
    echo "$alert_message"
  else
    log "所有 Bot 状态正常"
  fi
}

# =============================================
# 交互式状态查询
# =============================================
show_status() {
  generate_report
}

# =============================================
# 参数处理
# =============================================
case "${3:-check}" in
  check)
    main
    ;;
  status)
    show_status
    ;;
  reset)
    rm -f "${STATE_DIR}"/*.last_seen "${STATE_DIR}"/*.fail_count
    log "状态已重置"
    ;;
  *)
    echo "用法: $0 [github_token] [repo] [check|status|reset]"
    echo "  check  - 执行健康检测（默认）"
    echo "  status - 显示当前状态"
    echo "  reset  - 重置所有状态"
    exit 1
    ;;
esac
