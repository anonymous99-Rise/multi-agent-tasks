#!/bin/bash
# load_identity.sh - 从 agents.json 读取 Agent 身份
# v2.0.0 - 支持 SOUL.md 和 IDENTITY.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_JSON="$ROOT_DIR/agents.json"
TARGET_SLUG="${1:-taizi}"  # 默认 taizi，可通过参数指定

if [ ! -f "$AGENTS_JSON" ]; then
  echo "Error: agents.json not found at $AGENTS_JSON"
  echo "请先配置 agents.json"
  exit 1
fi

# 根据 slug 查找对应的 Agent
AGENT_INFO=$(cat "$AGENTS_JSON" | jq -r --arg slug "$TARGET_SLUG" \
  '.agents[] | select(.slug == $slug)')

if [ -z "$AGENT_INFO" ] || [ "$AGENT_INFO" = "null" ]; then
  echo "Error: No agent found with slug '$TARGET_SLUG'"
  echo "Available agents:"
  cat "$AGENTS_JSON" | jq -r '.agents[].slug'
  exit 1
fi

export AGENT_NAME=$(echo "$AGENT_INFO" | jq -r '.name')
export AGENT_SLUG=$(echo "$AGENT_INFO" | jq -r '.slug')
export MY_ROLE_LABEL=$(echo "$AGENT_INFO" | jq -r '.label')
export IDENTITY_LABEL=$(echo "$AGENT_INFO" | jq -r '.label')
export VIRTUAL_MENTION="@agent/${AGENT_SLUG}"
export FRAMEWORK=$(echo "$AGENT_INFO" | jq -r '.framework')
export AGENT_ROLE=$(echo "$AGENT_INFO" | jq -r '.role')  # commander/collector/executor

# 读取 SOUL.md 和 IDENTITY.md
SKILL_DIR="$ROOT_DIR/skills/task-hub-${AGENT_ROLE}"
export SOUL_PATH="$SKILL_DIR/SOUL.md"
export IDENTITY_PATH="$SKILL_DIR/IDENTITY.md"
export SOUL_CONTENT=""
export IDENTITY_CONTENT=""

if [ -f "$SOUL_PATH" ]; then
  export SOUL_CONTENT=$(cat "$SOUL_PATH")
fi

if [ -f "$IDENTITY_PATH" ]; then
  export IDENTITY_CONTENT=$(cat "$IDENTITY_PATH")
fi

# 读取 agents_prompt
export AGENTS_PROMPT=$(echo "$AGENT_INFO" | jq -r '.agents_prompt // empty')

# 读取 personality
export PERSONALITY_TRAIT=$(echo "$AGENT_INFO" | jq -r '.personality.trait // empty')
export PERSONALITY_SUMMARY=$(echo "$AGENT_INFO" | jq -r '.personality.summary // empty')

echo "Agent identity loaded:"
echo "  Name: $AGENT_NAME"
echo "  Slug: $AGENT_SLUG"
echo "  Role: $MY_ROLE_LABEL"
echo "  Framework: $FRAMEWORK"
[ -n "$PERSONALITY_TRAIT" ] && echo "  Trait: $PERSONALITY_TRAIT"
[ -n "$SOUL_CONTENT" ] && echo "  SOUL.md: Loaded (${#SOUL_CONTENT} chars)"
[ -n "$IDENTITY_CONTENT" ] && echo "  IDENTITY.md: Loaded"
