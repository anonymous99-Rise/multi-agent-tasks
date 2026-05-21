# Changelog

All notable changes to this project will be documented in this file.

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
- **quiet hours 实现**: inbox_processor.sh 入口统一检查，凌晨 1:00-8:30 静默跳过
- **null guards**: 所有 `grep -c` / `wc -l` 添加 `|| echo "0"` 兜底

## [6.5.0] - 2026-05-22
### Added
- **Framework badge**: Agent 卡片展示框架标识（Hermes 🟣 / OpenClaw 🟠）
- **Skill 溯源**: Agent 卡片展示 skill 路径（如 `skills/task-hub-executor/SKILL.md`）
- **Dashboard 同步按钮**: Agents Tab 新增「从 SKILL.md 同步」按钮

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
