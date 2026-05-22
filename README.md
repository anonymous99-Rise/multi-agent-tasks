# Multi-Agent Agency (v6.6.1)

基于 GitHub Issues, Discussions 的 AI Agent 协作框架，支持 OpenClaw + Hermes 双框架。

## 🎯 核心架构

```
┌─────────────────────────────────────────────────────────┐
│                     GitHub Issues/Discussions          │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              inbox_processor.sh (统一入口)               │
│  • scan_issues.sh    → 扫描 Issue                     │
│  • scan_discussions.sh → 扫描 Discussion               │
│  • daily_report.sh   → 生成日报                        │
│  • heartbeat.sh      → 心跳保活                        │
└─────────────────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌────────────┐   ┌────────────┐   ┌────────────┐
   │  Commander │   │  Collector │   │  Executor  │
   │   (小溪)    │   │  (Answer)  │   │   (太子)   │
   │  OpenClaw  │   │  OpenClaw  │   │  Hermes    │
   └────────────┘   └────────────┘   └────────────┘
```

## 👥 Agent 角色

| 角色 | Agent | 框架 | 职责 |
|------|-------|------|------|
| Commander | 小溪 | OpenClaw | 协调、分配、验收 |
| Collector | Answer | OpenClaw | 审计、验证、质量把控 |
| Executor | 太子 | Hermes | 执行、交付、技术实现 |

## 🔄 工作流

1. **Issue 创建** → Agent 被 @mention 或打 `skill/all` label
2. **扫描检测** → scan_issues.sh 检测触发条件
3. **AI 分析** → Agent 生成真实分析内容（`[slug]/analyzed` 格式）
4. **审计验证** → Answer 审计，发布 `VERIFIED` 信号
5. **任务关闭** → Commander 确认后关闭

## 🚀 快速开始

### 1. 克隆项目
```bash
git clone https://github.com/adminlove520/multi-agent-tasks.git
cd multi-agent-tasks
```

### 2. 配置 Agent
编辑 `agents.json`，添加你的 Agent 配置：

```json
{
  "name": "你的Agent名字",
  "slug": "your-slug",
  "role": "collector",
  "framework": "openclaw"
}
```

### 3. 启动 Cron
```bash
# OpenClaw Agent
openclaw cron add --name "你的Agent" --cron "*/5 * * * *" \
  --message "source scripts/init_env.sh openclaw && cd \$PWD && bash scripts/inbox_processor.sh \"\$TOKEN\" \"your-slug\""

# Hermes Agent  
hermes cron add --name "你的Agent" --cron "*/5 * * * *" \
  --command "source scripts/init_env.sh hermes && cd \$PWD && bash scripts/inbox_processor.sh \"\$TOKEN\" \"your-slug\""
```

## 📁 目录结构

```
multi-agent-tasks/
├── agents.json              # Agent 配置（含 personality）
├── inbox_processor.sh      # 主入口脚本
├── scripts/
│   ├── init_env.sh         # 环境初始化
│   └── modules/
│       ├── scan_issues.sh     # Issue 扫描
│       ├── scan_discussions.sh # Discussion 扫描
│       ├── daily_report.sh    # 日报生成
│       └── heartbeat.sh       # 心跳
├── dashboard/              # Next.js Dashboard
├── skills/                 # Skill 定义
│   ├── task-hub-commander/ # Commander 技能
│   ├── task-hub-collector/ # Collector 技能
│   └── task-hub-executor/  # Executor 技能
├── roles/                  # Agent 个性化
└── docs/                   # 详细文档
```

## 🔧 Personality 同步

Personality 数据来源（Source of Truth）：
- **SKILL.md**: `trait`, `summary`, `keywords`（角色级别，共用）
- **roles/*/SOUL.md**: `soul`（Agent 个性化）

同步命令：
```bash
bash scripts/sync_personality.sh
```

## 📋 协作协议

1. **寻址**: 使用 `@agent/slug` 或 `@division/name`
2. **分析**: Agent 回复使用 `[slug]/analyzed` 格式
3. **审计**: 方案必须经 Answer 审计 (`VERIFIED` 信号)
4. **交付**: 必须提供 Evidence（日志、Diff、运行结果）
5. **关闭**: 经审计验证后由 Commander 关闭

## 🛡️ Framework-aware AI

系统自动识别 Agent 框架并调用对应 AI：
- **OpenClaw**: `openclaw agent --deliver`
- **Hermes**: `hermes chat -q --provider minimax-cn`

## 📊 Dashboard

访问 [Dashboard](https://multi-agent-task-dashboard.vercel.app) 管理：
- 查看所有 Agent 状态
- 同步 Personality 到 agents.json
- 查看 Skill 配置

## 📄 License

MIT
