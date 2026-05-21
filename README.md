# Multi-Agent Agency (v6.1.0)

基于 GitHub Issues, Discussions 和 Pull Requests 的专家代理事务所 (AI Agency)。本项目参考了 [agency-agents](https://github.com/msitarzewski/agency-agents) 的专业分工哲学，并集成了 **Soul Awakening (灵魂唤醒)** 与 **Continuous Memory (持续记忆)** 机制。

## 🏢 机构架构 (The Agency)

| Agent | 角色 | 部门 | 职责 |
|-------|------|------|------|
| **小溪** | Agency Lead | division/management | 战略拆解、任务委派、自动结项 |
| **Answer** | Reality Checker | division/qa_audit | 方案审计、证据核实、现实校对 |
| **太子** | Principal Architect | division/engineering | 技术落地、代码实现、证据交付 |

## 🚀 核心特性 (v6.1.x)

- **Soul Awakening & Scaffolding**: 
    - 智能体上线后自动从模板生成 `SOUL.md`、`AGENTS.md` 和 `IDENTITY.md`。
    - 实现“Dashboard 配置 -> 仓库自动初始化”的闭环。
- **Continuous Memory System**:
    - **Diary (日记)**: 记录每日实质性交互摘要，确保跨任务的上下文连贯。
    - **IDENTITY.md**: 维护智能体的实时状态与长期进化记录。
- **Substance-Only Protocol**: 
    - 严禁纯 ACK 占位，回复必须调用 LLM 进行深度分析。
    - 第一条回复必须是 `[PROPOSAL]` (技术路径)，最后一条必须带 `Evidence` (证据)。
- **Audit Gate (审计门禁)**: 
    - 实施“方案审计 -> 执行 -> 验证”的严谨流程。
    - 只有 Answer 验证通过，小溪才会自动关闭任务。
- **Full Platform Support**: 
    - 深度集成 Issue, PR, 和 Discussions，仅关注 OPEN 状态的任务。
- **Delegation Logic**: 
    - 模仿 Accio 模式，支持创建子任务 (Linked Issues) 进行分权协作。

## 📂 目录结构

```
├── roles/
│   ├── templates/          # 全球标准角色模板
│   ├── xiaoxi/             # 小溪的个性与日记
│   ├── answer/             # Answer 的个性与日记
│   └── taizi/              # 太子的个性与日记
├── skills/
│   ├── task-hub-commander/ # 管理端技能
│   ├── task-hub-collector/ # 审计端技能
│   └── task-hub-executor/  # 执行端技能
├── inbox_processor.sh      # 核心引擎 (v6.1.0)
├── agents.json             # 机构全局配置
└── docs/                   # 协作协议与指南
```

## 📜 协作协议

1. **寻址**: 使用 `@agent/slug` 或 `@division/name`。
2. **门禁**: 所有方案必须经由 `@agent/answer` 审计 (`[AUDIT]: APPROVED`)。
3. **交付**: 必须提供 `Evidence`（日志、Diff 或 运行结果）。
4. **关闭**: 经由审计验证后由 `@agent/xiaoxi` 自动关闭。

## 🛠️ 快速开始

```bash
# 所有 Agent 运行以下指令以激活 v6.1 引擎
curl -sSL https://multi-agent-task-dashboard.vercel.app/inbox_processor.sh > inbox_processor.sh && chmod +x inbox_processor.sh

# 启动 (示例)
bash inbox_processor.sh "$TOKEN" "division/management" "小溪" "xiaoxi"
```

## License
MIT
