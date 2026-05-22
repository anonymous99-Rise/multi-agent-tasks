# Telegram Bot-to-Bot 通信架构 v1.0

> Multi-Agent Tasks v7.0.1-b 新增功能

## 概述

三个 Agent（Commander/小溪、Collector/Answer、Executor/太子）通过 Telegram 群聊和私信实现实时 Bot-to-Bot 通信，协作完成 GitHub Issues/Discussions 任务。

## 架构图

```
┌─────────────────────────────────────────────────────────┐
│                    Task-Control 群聊                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  小溪     │  │  Answer  │  │  太子     │             │
│  │ (Commander)│ │(Collector)│ │(Executor)│             │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘             │
│       │              │              │                   │
│       └──────────────┼──────────────┘                   │
│                      │                                  │
│              @mention 触发                              │
│              群聊每条消息需 @ 对方才收得到                  │
└──────────────────────┼────────────────────────────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
    ┌─────────┐  ┌─────────┐  ┌─────────┐
    │ GH API  │  │ GH API  │  │ GH API  │
    │ Discussion │  │ Issue  │  │ PR     │
    └─────────┘  └─────────┘  └─────────┘
```

## Bot ID 速查

| Bot | Username | Telegram ID |
|-----|----------|-------------|
| 太子 | @YinxiaBot | `8435768342` |
| Answer | @Anwsermebot | `8773175290` |
| 小溪 | @caddycherrybot | (待配置) |

## 通信规则

### 1. 群聊 @mention 触发

- **规则**：每条消息必须 `@mention` 对方才能触发
- **回复**：回复消息不需要再次 @，Telegram 自动建立关联通知
- **示例**：
  ```
  [太子] @Anwsermebot 请审计 Discussion #89 最新评论
  [Answer] @YinxiaBot 审计完成，方案 APPROVED ✅
  ```

### 2. 私信通信

- 用于敏感操作（如传递 GH token）
- 不经过群聊，避免暴露
- BotFather 需开启「Bot to Bot Communication」

### 3. 任务分派流程

```
小溪 → @Answer → 分配审计任务
Answer → @太子 → 分配执行任务
太子 → @Answer → 汇报完成
Answer → @小溪 → 汇报审计结果
```

## 署名格式

所有 GitHub Discussion/Issue 评论必须使用角色署名：

| 角色 | 署名格式 |
|------|----------|
| Commander (小溪) | `**Commander (小溪):** [内容]` |
| Collector (Answer) | `**Collector (Answer):** [内容]` |
| Executor (太子) | `**Executor (太子):** [内容]` |

## Telegram Bot 配置

### 白名单配置

每个 Bot 的 `.env` 或 `config.yaml` 需配置 `TELEGRAM_ALLOWED_USERS`：

```bash
# 格式：用户ID,群组ID,其他BotID
TELEGRAM_ALLOWED_USERS=5646034524,1087968824,8773175290,8435768342
```

### BotFather 设置

1. 找 BotFather 对话
2. `/mybots` → 选择 Bot → Edit Bot → Settings → Allow groups → Turn on
3. Bot Settings → Allow bot to bot communication → Turn on

### Hermes Bot 配置 (太子)

```yaml
# config.yaml
allowed_chats:
  - -1003960569663  # Task-Control 群
  chats:
    - id: -1003960569663
      username: Task-Control
```

### OpenClaw Bot 配置 (Answer)

```json
// credentials/telegram-default-allowFrom.json
{
  "allowFrom": [5646034524, 1087968824, 8435768342]
}
```

## Bot 间任务分派示例

### 场景：健康检查任务

```
[群聊]
小溪: @Answer @太子 建议在项目中增加 health_check.sh，你们怎么看？
Answer: @小溪 同意，支持这个提议。
太子: @小溪 我来负责实现。

[私信 - GH Token 传递]
小溪 → Answer (私信): GH token: ghp_xxxxx

[GitHub Discussion]
Answer: **Collector (Answer):** 审计完成，方案 APPROVED ✅
太子: **Executor (太子):** 已完成实现，curl 测试通过 ✅
小溪: **Commander (小溪):** 验收通过，合并到 main ✅
```

## 已知限制

1. **共享 GH Token**：所有 Bot 使用同一个 GH token，评论 author 统一显示为 token 所属账号
2. **署名区分**：通过评论开头的 `**Role (Name):**` 前缀区分发言者
3. **Bot 能力差异**：Answer 需要 GH token 才能发 GitHub 评论，太子已有 token
4. **小溪未接入**：@caddycherrybot 尚未接入群聊

## 配置文件路径

- **太子 (Hermes)**: `~/.hermes/config.yaml`, `~/.hermes/.env`
- **Answer (OpenClaw)**: `~/.openclaw/openclaw.json`, `~/.openclaw/credentials/telegram-*.json`
- **小溪 (OpenClaw)**: `~/.openclaw/openclaw.json`, `~/.openclaw/credentials/telegram-*.json`

---

*设计：太子 2026-05-22 v1.0*
