#!/bin/bash
# scan_discussions.sh - 扫描讨论
# 规则：被艾特才回复（发实质性PROPOSAL），没被艾特不打扰

TOKEN="$1"
OWNER="$2"
REPO_NAME="$3"
AGENT_NAME="$4"
AGENT_SLUG="$5"
VIRTUAL_MENTION="$6"
MY_ROLE_LABEL="$7"
FRAMEWORK="$8"

export GITHUB_TOKEN="$TOKEN"

echo "Scanning discussions..."

DISC_QUERY='query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){discussions(first:10,orderBy:{field:CREATED_AT,direction:DESC}){nodes{id,number,title,body,labels(first:10){nodes{name}},comments(last:20){nodes{author{login},body}}}}}}'

DISC_DATA=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -f query="$DISC_QUERY" --jq ".data.repository.discussions.nodes[]" 2>/dev/null)

if [ -z "$DISC_DATA" ]; then
  echo "No discussions found."
  exit 0
fi

echo "$DISC_DATA" | jq -c "." | while read -r disc; do
  D_ID=$(echo "$disc" | jq -r '.id')
  D_NUM=$(echo "$disc" | jq -r '.number')
  D_TITLE=$(echo "$disc" | jq -r '.title')

  # 三层查重（保护 agent 免受脚本干扰）：
  # 1. 实质性回复（[@agent/xxx] 格式）— agent 的正式分析，永久有效
  # 2. agent/ 分析回复（[xxx]/analyzed 格式）— skill/all 场景下的分析报告
  # 3. skill/all 广播回复（[xxx] [division/xxx]/xxx 格式）— agent 的实质性广播回复
  HAS_REAL_REPLY=$(echo "$disc" | jq -r "[.comments.nodes[] | select(.body | contains(\"[@agent/${AGENT_SLUG}]\") or .body | contains(\"[${AGENT_SLUG}]/analyzed\") or (.body | contains(\"[${AGENT_SLUG}]\") and .body | contains(\"/\")))] | length" 2>/dev/null || echo "0")

  # 检查是否被艾特（标题+正文，不查评论避免自己触发自己）
  # @agent/all → 所有agent都要回，@agent/taizi → 只有我回
  IS_TAGGED=$(echo "$disc" | jq -r ".title, .body" | grep -iE "@agent/all|@agent/${AGENT_SLUG}" | wc -l)

  # skill/all label 也视为被艾特（全员广播）
  D_LABELS=$(echo "$disc" | jq -r ".labels.nodes[].name" 2>/dev/null)
  HAS_SKILL_ALL=$(echo "$D_LABELS" | grep -c "skill/all" || echo "0")

  # 触发条件：被@ 或 有 skill/all label
  SHOULD_RESPOND=$((IS_TAGGED + HAS_SKILL_ALL))

  echo "Discussion #$D_NUM: $D_TITLE"
  echo "  → tagged=${IS_TAGGED}, skill/all=${HAS_SKILL_ALL}, real_reply=${HAS_REAL_REPLY}"

  # 核心原则：禁止脚本发送任何自动评论！
  # - 不发"收到"等 ACK（违反"禁止纯 ACK"原则）
  # - 不发模板占位符（agent AI 应生成真实内容）
  # - 脚本只负责检测，真实回复由 agent AI 生成
  #
  # 场景1：有实质性回复 → 跳过（agent 已处理）
  if [ "$HAS_REAL_REPLY" -gt "0" ]; then
    echo "  → 有实质性回复，跳过（agent AI 已处理）"
  # 场景2：触发但没回复 → 根据 framework 调用 AI 生成真实内容
  elif [ "$SHOULD_RESPOND" -gt "0" ]; then
    echo "  → 触发，调用 AI 生成分析 (framework=$FRAMEWORK)..."

    # 构建 context 用于 AI
    DISC_URL="https://github.com/$OWNER/$REPO_NAME/discussions/$D_NUM"

    if [ "$FRAMEWORK" = "openclaw" ]; then
      # OpenClaw: 使用 openclaw agent --deliver
      openclaw agent \
        --agent "$AGENT_SLUG" \
        --message "你收到了一条 discussion 被 @mention 或 skill/all 广播触发的通知。

Discussion: #$D_NUM - $D_TITLE
URL: $DISC_URL

你是 $AGENT_ROLE（$AGENT_ROLE 角色）：
- commander：协调视角，发表战略/统筹建议，擅长拆解任务和协调资源
- collector：审计视角，评估风险和可行性，擅长发现问题和核对证据
- executor：执行视角，提供落地思路和技术方案，擅长代码和实现

请生成一段**真实的 [$AGENT_ROLE 视角分析]**：
- 必须包含具体观点和实质分析，不能是模板占位符
- 禁止发送\"收到艾特，我来分析一下\"这样的纯 ACK
- 格式：使用 [${AGENT_SLUG}/analyzed] 作为标题前缀
- 结合你的角色特点提供有价值的视角
- 如果没有实质性内容要说，可以跳过（不用回复）

请直接生成回复内容并通过 --deliver 发送到 GitHub。" \
        --deliver \
        --timeout 300 2>&1 || echo "  → AI 调用失败"

    elif [ "$FRAMEWORK" = "hermes" ]; then
      # Hermes: 使用 hermes chat -q 并通过 gh api 评论
      AGENT_PROMPT="你收到了一条 discussion 被 @mention 或 skill/all 广播触发的通知。

Discussion: #$D_NUM - $D_TITLE
URL: $DISC_URL

你是 $AGENT_ROLE（$AGENT_ROLE 角色）：
- commander：协调视角，发表战略/统筹建议，擅长拆解任务和协调资源
- collector：审计视角，评估风险和可行性，擅长发现问题和核对证据
- executor：执行视角，提供落地思路和技术方案，擅长代码和实现

请生成一段**真实的 [$AGENT_ROLE 视角分析]**：
- 必须包含具体观点和实质分析，不能是模板占位符
- 禁止发送\"收到艾特，我来分析一下\"这样的纯 ACK
- 格式：使用 [${AGENT_SLUG}/analyzed] 作为标题前缀
- 结合你的角色特点提供有价值的视角
- 如果没有实质性内容要说，可以跳过（不用回复）

请只生成评论内容，不要其他输出。"

      ANALYSIS=$(hermes chat -q "$AGENT_PROMPT" --provider minimax-cn 2>&1)

      # 过滤无效内容
      IS_ACK=$(echo "$ANALYSIS" | grep -iE "(收到艾特|我来分析一下|稍后汇报)" | wc -l)
      IS_PLACEHOLDER=$(echo "$ANALYSIS" | grep -iE "(\[具体在做什么\]|\[证据：)" | wc -l)

      if [ "$IS_ACK" -gt 0 ] || [ "$IS_PLACEHOLDER" -gt 0 ]; then
        echo "  → Hermes 生成内容为无效 ACK/占位符，跳过评论"
      elif [ -n "$ANALYSIS" ] && [ ${#ANALYSIS} -gt 50 ]; then
        DISCUSSION_ID=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -f query="query { repository(owner: \"$OWNER\", name: \"$REPO_NAME\") { discussion(number: $D_NUM) { id } } }" --jq ".data.repository.discussion.id" 2>/dev/null)
        printf '%s' "$ANALYSIS" | gh api graphql -f discussionId="$DISCUSSION_ID" -f body=- -f query="mutation AddDiscussionComment($input: AddDiscussionCommentInput!) { addDiscussionComment(input: $input) { comment { id } } }" 2>&1 || echo "  → 评论失败"
      else
        echo "  → Hermes 生成内容太短或为空，跳过"
      fi
    fi
  # 场景3：没触发 → 跳过
  else
    echo "  → 没被艾特且无 skill/all，跳过"
  fi
done

echo "Discussion scan complete."
