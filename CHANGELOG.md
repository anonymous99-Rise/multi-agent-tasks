# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-05-22

## [7.0.1-b] - 2026-05-22
### Added
- **Telegram Bot-to-Bot 通信架构**：新增 `docs/BOT_TO_BOT_DESIGN.md`，详细说明三个 Agent 如何通过 Telegram 群聊和私信协作
- **健康检测脚本**：`scripts/health_check.sh` v1.0，用于检测三个 Agent 的存活状态
- **署名格式规范**：所有 Agent 的 SOUL.md 和 SKILL.md 新增 Multi-Agent 协作规范，要求 GitHub 评论使用 `**Role (Name):**` 格式署名
- **PR/Issue/Discussion 协作规范**：新增各角色在 GitHub Discussion、Issue、PR 中的使用指南
- **自主学习规范**：新增 Agent 自主进化学习指南，鼓励记录经验、分享技术发现

### Changed
- **文件清理**：`task_plan.md` 已删除，设计文档移动到 `docs/DESIGN.md`
- **README 更新**：补充 Bot-to-Bot 协作说明
- **ARCHITECTURE 更新**：补充 Telegram Bot 通信架构

### Updated SOUL.md / SKILL.md
- `roles/xiaoxi/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范
- `roles/taizi/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范
- `roles/answer/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范
- `skills/task-hub-collector/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范
- `skills/task-hub-executor/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范
- `skills/task-hub-commander/SOUL.md` — 新增署名格式 + PR/Issue/Discussion 协作规范

### Bot ID 速查
- 太子 (Hermes): `@YinxiaBot` — Telegram ID `8435768342`
- Answer (OpenClaw): `@Anwsermebot` — Telegram ID `8773175290`
- 小溪 (OpenClaw): `@caddycherrybot` — Telegram ID (待配置)

## [6.6.1] - 2026-05-22
### Fixed
- **计数变量换行符清理**: 所有 `grep -c` / `grep ... | wc -l` 输出加 `| tr -d '\n'` 防止算术表达式语法错误
  - 影响文件: scan_discussions.sh, scan_issues.sh, generate_analysis.sh
  - 根因: `grep -c` 和 `wc -l` 输出 `N\n` 格式，在 `$((IS_TAGGED + HAS_SKILL_ALL))` 中导致 `syntax error`
  - PR #87 修复了 `grep -c`，PR #88 补充了 `wc -l`
- **空扫描优化加强**: scan_discussions.sh 添加 `OPEN_COUNT` 快速检查，没有 OPEN discussions 直接跳过

### Added
- **agent/{slug} label 召唤机制**: 讨论/Issue 带 `agent/taizi` 或 `agent/answer` label 时，对应 agent 会被触发参与
  - 不再只依赖 `@agent/xxx` mention 或 `skill/all` label
  - 支持小溪发提案后打 label 召唤特定 agent 的场景

## [6.6.1] - 2026-05-22
### Fixed
- **quiet hours 改为北京时间**: `TZ=Asia/Shanghai date`，真正在北京时间 1:00-8:30 休眠
- **空扫描优化**: scan_discussions.sh 没有 OPEN discussions 时直接跳过，不空转 API
- **scan_discussions.sh 语法修复**: HAS_REAL_REPLY echo 添加 `:0` 兜底
>>>>>>> origin/main

## [6.6.0] - 2026-05-22
### Added
- **Dashboard 性格展示增强**: Agent 卡片 personality 区块全面升级
  - Trait badge 升级为渐变 + ★ 图标
  - Keywords 分级展示（前3个突出，其余用 #hashtag 格式）
  - Summary 玻璃态容器
  - 来源标注 skill 路径
- **agents_prompt 增强**: 展示完整内容 + 字数统计 + Terminal 图标
- **SOUL.md 增强**: 深紫色渐变背景 + 始终展开 + 最大高度滚动
- **Sparkles 图标**: SOUL.md 区块新增黄色闪光图标

### Changed
- **agents.json 字段规范**: `hermes_prompt` → `agents_prompt`（已完成）
- **skill/all 语义强化**: 所有 agent 必须发送实质性回复（禁止纯 ACK）
- **分析结果格式**: 统一使用 `[slug]/analyzed` 前缀格式

### Fixed
- **Null guards**: 所有 grep/wc 表达式添加 `|| echo "0"` 防止空值
- **Hermes AI filter**: 移除过度激进的 ACK 过滤，只过滤明显占位符
- **IS_TAGGED/HAS_REAL_REPLY**: 添加空值兜底

## [6.4.2] - 2026-05-22
### Fixed
- **Null guards**: 所有 grep/wc 表达式添加 `|| echo "0"` 防止 integer expression errors
- **Hermes AI filter**: 移除 `收到艾特/我来分析一下/稍后汇报` 等正常表达的过滤

## [6.4.1] - 2026-05-22
### Fixed
- **ATTEMPT_COUNT null bug**: grep -c 无匹配时返回空而非 "0"
- **ROLE_SKILL_PATHS**: commander 错误映射到 task-hub-commander → 修正为 task-hub-creator

## [6.4.0] - 2026-05-22
### Added
- **skill/all 全员评论**: 所有 agent（commander/collector/executor）都必须评论 skill/all 广播
- **Role-aware prompts**: AI 提示词包含角色上下文（commander/collector/executor 视角）
- **Framework-aware AI invoke**: scan_issues.sh 支持 openclaw/hermes 两种调用
- **AGENT_ROLE 上下文**: prompt 中使用 $AGENT_ROLE 而非 $MY_ROLE_LABEL（division/xxx）
- **Dashboard 同步能力**: Agents Tab 新增「从 SKILL.md 同步」按钮
- **Framework badge**: 每个 Agent 卡片展示框架标识（Hermes 🟣 / OpenClaw 🟠）
- **Skill 溯源**: 每个 Agent 卡片展示 skill 路径（如 `skills/task-hub-executor/SKILL.md`）

### Fixed
- **scan_discussions.sh**: 修复 hermes stdin 传递问题
- **ATTEMPT_COUNT null bug**: grep -c 无匹配时返回空而非 "0"
- **ROLE_SKILL_PATHS**: commander 错误映射到 task-hub-commander → 修正为 task-hub-creator

### Changed
- **agents.json 字段规范**: `agents_prompt` 字段保持不变（运行时 prompt）
- **Dashboard sync_personality**: 通过 GitHub API 实现（Vercel 部署可用）

## [6.3.3] - 2026-05-22
### Fixed
- **skill/all 广播**: agents 不再发送模板占位符和纯 ACK，改为生成真实分析内容
- **scan_issues.sh**: 移除模板占位符评论
- **scan_discussions.sh**: 移除 ACK 自动评论
- **HAS_REAL_REPLY 检测**: 支持新格式 `[slug]/analyzed` 和 `[slug] /`

## [6.3.2b] - 2026-05-21
### Fixed
- **scan_discussions.sh:55**: 空值比较错误 `HAS_ACK` 修复为 `${HAS_ACK:-0}`
- **daily_report.sh:61**: JSON 引号匹配问题（多余 `"`）

## [6.3.2] - 2026-05-21
### Added
- **scan_issues.sh v6.4.0**: 重大逻辑重构
  - **禁止自动认领**: 不再自动认领任务，只在被 @ 时响应
  - **skill/all 新语义**: 所有非 commander agent 发送 `[slug]/analyzed` 格式分析
  - **评论格式**: 使用 `[agent/slug]/analyzed` 替代旧 ACK 格式
  - **skill/all 跳过 commander**: commander 负责协调，不参与具体执行分析
- **agents.json**: 修复 `role` 字段映射 (xiaoxi→commander, answer→collector, taizi→executor)

### Fixed
- **Issue #70 重复触发**: 根因是 Answer cron 从未添加 + 旧逻辑自动认领

## [6.3.1] - 2026-05-21
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

## [4.2.0] - 2026-05-21
### Added
- **Multi-agent 系统**: commander/collector/executor 三角色协作
- **Hermes Agent 集成**: 支持 Hermes 框架 agent 调用

## [4.1.1] - 2026-05-21
### Fixed
- **Issue 追踪**: 修复每日报告生成逻辑

## [4.1.0] - 2026-05-21
### Added
- **skill/all 广播**: 所有 agent 接收并响应

## [4.0.0] - 2026-05-21
### Added
- **GitHub Issues 集成**: 自动扫描和处理 Issue

## [3.10.0] - 2026-05-21
### Added
- **Telegram Bot**: 实时通知能力

## [3.9.0] - 2026-05-21
### Added
- **Cron 任务调度**: 定时任务支持

## [3.8.0] - 2026-05-21
### Changed
- **代码结构重构**: 模块化拆分

## [3.7.0] - 2026-05-21
### Added
- **Dashboard UI**: Web 管理界面

## [3.6.0] - 2026-05-21
### Fixed
- **Bug 修复**: 早期版本问题

## [3.5.0] - 2026-05-21
### Added
- **通知系统**: 多渠道通知

## [3.4.0] - 2026-05-20
### Added
- **日志系统**: 完整日志记录

## [3.3.1] - 2026-05-06
### Fixed
- **补丁修复**

## [3.3.0] - 2026-05-04
### Added
- **核心功能集**

## [3.2.0] - 2026-05-03
### Added
- **初始版本功能**

## [3.1.0] - 2026-05-02
### Added
- **项目初始化**

## [3.0.0] - 2026-05-01
### Added
- **Initial release**
