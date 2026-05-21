# Changelog

All notable changes to this project will be documented in this file.

## [4.3.0] - 2026-05-21
### Changed
- **scan_issues.sh v6.4.0**: 重大逻辑重构
  - **禁止自动认领**: 不再自动认领任务，只在被 @ 时响应
  - **skill/all 新语义**: 所有非 commander agent 发送 `[slug]/analyzed` 格式分析
  - **评论格式**: 使用 `[agent/slug]/analyzed` 替代旧 ACK 格式
  - **skill/all 跳过 commander**: commander 负责协调，不参与具体执行分析
- **inbox_processor.sh v6.4.0**: 版本同步
- **agents.json**: 修复 `role` 字段映射 (xiaoxi→commander, answer→collector, taizi→executor)

### Fixed
- **Issue #70 重复触发**: 根因是 Answer cron 从未添加 + 旧逻辑自动认领

### Architecture
- **Source of Truth**: SKILL.md + roles/*/SOUL.md
- **Behavior**: @mention = 直接响应, skill/all = 全员分析（除 commander）

## [4.2.0] - 2026-05-21
### Added
- **sync_personality.sh v2.0**: Personality 同步脚本增强
  - 从 `roles/*/SOUL.md` 提取 `soul` (agent-specific identity)
  - 从 `skills/*/SKILL.md` 提取 `trait/summary/keywords` (role-based)
  - 自动映射: `xiaoxi→commander`, `answer→collector`, `taizi→executor`
- **agents.json**: 新增 `personality` 字段，包含 `trait`, `summary`, `keywords`, `soul`

### Changed
- **agents.json 字段规范**: `agents_prompt` 字段保持不变（用于运行时 prompt）
- **Dashboard SOUL.md 展示**: 支持 `agent.personality.soul` 和 `agent.soul` 两种路径

### Source of Truth
- **SKILL.md**: `trait`, `summary`, `keywords` (role-based, shared across agents with same role)
- **roles/*/SOUL.md**: `soul` (agent-specific identity)

## [4.1.1] - 2026-05-21
### Fixed
- **generate_cron.js**: 修复两个问题
  - 路径硬编码 `~/multi-agent-tasks` → 使用 `init_env.sh` 自动检测
  - `--to "@slugbot"` → `--to "@tgUsername"` (从 agents.json 读取)
- **docs/AGENT_GUIDE_PROMPT.md**: 更新 cron 示例
- **ARCHITECTURE.md**: 更新 cron 示例

### generate_cron.js 输出示例
```bash
# Answer (openclaw)
openclaw cron add --name "Answer" --session isolated --message "source $MAT_ROOT/scripts/init_env.sh openclaw && cd $MAT_ROOT..." --announce --to "@Anwsermebot"

# 太子 (hermes)
hermes cron add --command "source $MAT_ROOT/scripts/init_env.sh hermes && cd $MAT_ROOT..."
```

## [4.1.0] - 2026-05-21
### Added
- **init_env.sh**: 跨平台路径自动检测与初始化脚本
  - 自动检测框架 (openclaw/hermes)
  - 自动检测操作系统 (Linux/macOS/Windows)
  - 不存在时自动 clone
  - 存在时自动 git pull
- **Pipeline QA Gate**: task/qa-pending → task/qa-pass 质量门禁
- **Retry Mechanism**: 最多 3 次重试，超限自动 escalation
- **Status Report Template**: 标准化报告格式 (Phase/Progress/Evidence/Next)
- **Pipeline Phases**: pm → dev → qa → integration 四阶段协调
- **Evidence-based**: QA 检查清单，回复必须包含证据

### Changed
- **README.md**: 更新为使用 init_env.sh 的方式
- **scan_issues.sh v2.0**: 增加质量门禁、重试机制、状态报告、Pipeline 协调

### 路径规范
| 框架 | Linux/macOS | Windows |
|------|-------------|---------|
| OpenClaw | `~/.openclaw/workspace/multi-agent-tasks` | `%USERPROFILE%/.openclaw/workspace/multi-agent-tasks` |
| Hermes | `~/.hermes/skills/multi-agent-tasks` | `%USERPROFILE%/.hermes/skills/multi-agent-tasks` |

## [4.0.0] - 2026-05-21
### Added
- **agency-agents 标准文件结构**: SOUL.md + IDENTITY.md + SKILL.md 三文件分离
  - `SOUL.md`: 性格定义、沟通风格、学习记忆（基于 agency-agents SOUL.md 格式）
  - `IDENTITY.md`: 简短身份描述（一句话）
  - `SKILL.md`: 完整技能定义（v4.0.0）
- **load_identity.sh v2.0.0**: 支持读取 SOUL.md 和 IDENTITY.md
- **Dashboard SOUL/IDENTITY 展示**: agents API 加载并展示 SOUL.md 和 IDENTITY.md

### Changed
- **SKILL.md v4.0.0**: 添加 `## 📚 相关文件` 章节，引用 SOUL.md 和 IDENTITY.md
- **agents.json**: 无需内嵌完整性格定义，统一从 SOUL.md 读取
- **README.md**: 更新架构表，添加 agency-agents 文件结构说明

### Files Created
```
skills/task-hub-commander/SOUL.md
skills/task-hub-commander/IDENTITY.md
skills/task-hub-collector/SOUL.md
skills/task-hub-collector/IDENTITY.md
skills/task-hub-executor/SOUL.md
skills/task-hub-executor/IDENTITY.md
```

## [3.10.0] - 2026-05-21
### Added
- **inbox_processor.sh v3.6.0**: 基于 agency-agents 最佳实践重构

### 模块化架构
- `init_state()`: 初始化状态文件
- `retry()`: 重试装饰器 (指数退避)
- `gh_api()`: GitHub API 调用封装 (带重试)
- `build_*_response()`: 回复模板函数
- `has_real_reply()`: 实质性回复检查
- `process_discussions()`: Discussion 处理
- `process_issues()`: Issue 处理
- `main()`: 主流程

### 新增功能
- 状态追踪 (`state.json`)
- 活动日志 (`activity.log`)
- 统计指标 (`replies`/`errors`)
- 指数退避重试 (2s, 4s, 8s)
- GitHub API 限流处理
- 幂等性保证

### Changed
- inbox_processor.sh v3.5.0 (233行) → v3.6.0 (455行)

## [3.9.0] - 2026-05-21
### Added
- **agency-agents 最佳实践**: 基于 144+ agents 项目优化 SKILL.md
- **Core Mission 章节**: 核心使命定义
- **Success Metrics**: 成功标准量化指标
- **Processes 流程**: Phase 1-4 详细执行流程
- **Deliverables 模板**: 任务完成报告、进度报告、战报模板
- **Error Handling 章节**: 错误处理策略
- **Status Reporting 模板**: 状态报告模板
- **禁止行为 (🚫)**: 明确禁止的行为

### Changed
- **SKILL.md v3.5.0**: 三个角色全部增强
  - task-hub-executor: 4435 bytes
  - task-hub-collector: 4205 bytes
  - task-hub-creator: 4547 bytes

### New
- **docs/review_and_optimization_CN.md**: agency-agents 对比分析文档

## [3.8.0] - 2026-05-21
### Added
- **sync_personality.sh**: 自动化同步脚本，从 SKILL.md 读取 personality 到 agents.json
  - Source of Truth: SKILL.md 的 `## 🎭 性格定义` 章节
  - 提取 `trait`、`summary`、`keywords`
  - 用法: `./scripts/sync_personality.sh [--dry-run]`

### Changed
- **agents.json 更新**: 重新从 SKILL.md 同步 personality 数据

## [3.7.0] - 2026-05-21
### Added
- **skill/role 广播支持**: inbox_processor.sh v3.5.0 支持 skill/executor、skill/collector 等角色专属广播
- **严格回复格式校验**: `[skill/slug]/analyzed` 格式，使用 `grep -E` 正则匹配
- **三种回复类型**:
  - `broadcast`: skill/all 广播回复
  - `direct`: @agent/xxx 直接艾特回复
  - `role_task`: skill/role 角色专属任务回复

### Changed
- **inbox_processor.sh v3.4.0 → v3.5.0**: 174行 → 233行，新增 skill/role 检测和严格回复校验
- **回复格式升级**: 不再接受纯 ACK，必须是 `[skill/slug]/analyzed` 格式

### Fixed
- **回复判定逻辑**: `HAS_REAL_REPLY` 改用 `grep -E '\[skill/[a-z-]+\]/analyzed'` 严格校验

## [3.6.0] - 2026-05-21
### Added
- **Personality 性格系统**: SKILL.md 定义角色性格，agents.json 同步
  - `personality.trait`: 角色类型（指挥官/执行者/汇总者）
  - `personality.summary`: 性格描述
  - `personality.keywords`: 关键词标签
- **agents_prompt 字段**: agents.json 中定义每个 agent 的 LLM prompt
- **执行链/汇报链**: 明确指挥官→执行者→汇总者的执行汇报关系
- **艾特回复时效机制**:
  - @agent/xxx 被点名: 3分钟内必须实质性回复
  - skill/all 广播: 5分钟内必须实质性回复
  - 专属任务领取: 30分钟内必须开始执行

### Changed
- **LLM-Driven Inbox (v3.4.0)**: 去掉 ACK 层，直接 LLM 分析 + 实质性回复
- **skill/all 强制实质性回复**: 所有 agent 必须回复，禁止纯 ACK
- **Dashboard agents tab**: 全新卡片式布局，展示 personality 和 agents_prompt

### Fixed
- **inbox_processor.sh v3.3.1 → v3.4.0**: 174行，LLM-Driven 架构

## [3.5.0] - 2026-05-21
### Added
- **scripts/ 目录**: 所有脚本从 dashboard/public/ 移到 scripts/
  - `scripts/inbox_processor.sh` - 主入口
  - `scripts/load_identity.sh` - 从 agents.json 读取身份
  - `scripts/modules/` - 功能模块（quiet_period, git_sync, heartbeat, scan_discussions, scan_issues, daily_report, update_activity）
- **load_identity.sh**: 根据 agent_slug 从 agents.json 自动读取 Agent 完整身份信息

### Changed
- **移除皇帝-将军-兵团称呼**: 全部改用正常名称（小溪、Answer、太子）
- **cron 参数简化**: 只需传 `token` + `agent_slug`，身份自动从 agents.json 读取
- **Cron 框架隔离**: OpenClaw 和 Hermes 各跑各的 cron，物理隔离避免冲突
- **ARCHITECTURE.md v1.3**: 移除皇帝-将军-兵团描述，更新为小溪-Answer-太子架构
- **README.md**: 重写，更新架构说明和目录结构
- **docs/AGENT_GUIDE_PROMPT.md v2.1**: 更新 cron 部署，框架隔离说明
- **docs/collector_CN.md**: 更新为正常名称，简化内容
- **docs/executor_CN.md**: 更新为正常名称，简化内容
- **docs/role_definition_guide_CN.md**: 更新为正常名称，简化内容

### Fixed
- **scan_discussions 重复消息**: HAS_REAL_REPLY 逻辑改为 grep [PROPOSAL]，不再误判 ACK
- **scan_issues [@@agent/xxx] 格式**: 改用 `<agent/xxx>` 格式，避免 GitHub 解析成双@
- **agents.json label 字段**: 修复 role(executor) vs label(skill/taizi) 不一致问题
- **webhook route.ts action scope**: 修复 TypeScript scope 错误，action 移到 if 块外面

## [3.4.0] - 2026-05-20
### Added
- **模块化重构**: inbox_processor.sh 拆分为独立模块
  - `modules/quiet_period.sh` - 安静期控制（30分钟无活动才扫描）
  - `modules/git_sync.sh` - Git同步
  - `modules/heartbeat.sh` - 心跳注册到 Dashboard
  - `modules/scan_discussions.sh` - Discussion 扫描
  - `modules/scan_issues.sh` - Issue 扫描
  - `modules/daily_report.sh` - 日报生成（9:00/18:00）
  - `modules/update_activity.sh` - 状态更新
- **小溪-Answer-太子架构确立**: 明确三层汇报体系
- **ARCHITECTURE.md v1.1**: 架构设计文档

### Changed
- **太子的 Discussion 规则**: 发有意义的内容，不发无意义的 ACK
- **Role 标签明确**: Answer 用 `skill/answer`，太子用 `skill/taizi`

### Fixed
- **重复发送消息 Bug**: 修复 `[@@agent/taizi]` 刷屏问题
- **Force Push 权限**: main 分支保护，禁止 force push，需要 PR review

## [3.3.1] - 2026-05-06
### Fixed
- **Virtual Mention Recognition**: Fixed an issue where agents with Chinese names (e.g., 小溪) wouldn't respond to English slug mentions (`@agent/xiaoxi`).
- **Title-Aware Scanning**: Agents now scan Discussion titles for mentions, not just the body and comments.
- **Slug-Based Routing**: Standardized on lowercase English slugs for virtual mentions across Telegram and GitHub.
- **Fulfillment Debt Logic**: Improved the "Debt" detection to ensure agents follow up on `[ACK]` with actual `[PROPOSAL]` content.

## [3.3.0] - 2026-05-04
### Added
- **Virtual Identity Routing**: Map Telegram bot mentions (e.g., `@Anwsermebot`) to internal GitHub mentions (`@agent/answer`).
- **Fulfillment Protocol**: Automated `[ACK]` mechanism that creates a "contractual debt" for the agent to provide a substantive response in the next cycle.
- **Concurrency Locking**: Added `flock` to `inbox_processor.sh` to prevent overlapping scans.
- **Heartbeat System**: Real-time "Online" status displayed on the Dashboard.

## [3.2.0] - 2026-05-03
### Added
- **Native GitHub Discussions**: Switched from Issues-only communication to threaded Discussions via GraphQL.
- **GraphQL Integration**: Bypassed GitHub CLI version limitations by using direct GraphQL API for Discussions.

## [3.1.0] - 2026-05-02
### Added
- **Dashboard v3.0**: GitHub OAuth, encrypted secrets, and multi-language support (CN/EN).
- **Telegram Webhook Automation**: Bridge GitHub events directly to Telegram groups.

## [3.0.0] - 2026-05-01
### Added
- **Initial Multi-Agent Architecture**: Support for Answer, 太子, and 小溪 sharing a single GitHub account.
- **Inbox Processor**: Baseline shell script for agents to poll GitHub state.