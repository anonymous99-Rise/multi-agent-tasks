# Multi-Agent Agency (v6.2.0)

基于 GitHub Issues, Discussions 和 Pull Requests 的专家代理事务所 (AI Agency)。

## 🚀 核心特性 (v6.2.x)

- **Sentient Reasoning (有感知的推理)**: 
    - 移除所有脚本自动回复模板。
    - 脚本仅作为“信息喂养员”，输出 `🚨 ACTION_REQUIRED` 信号。
    - Agent 必须通过自己的 LLM 进行实质性分析并手动调用工具回复。
- **Concurrency & Sync Fix**: 
    - 引入 `git pull --rebase` 和随机退避机制，彻底解决多智能体并行 Push 时的冲突问题。
- **Memory Compaction (记忆压缩)**: 
    - 自动监测记忆膨胀，提示 Agent 进行里程碑式总结，保持上下文高效。
- **Full Platform PR Audit**: 
    - 深度集成 PR 状态追踪，Answer 能根据 CI 运行结果自动触发审计流程。
- **Soul Awakening & Scaffolding**: 
    - 实现从 Dashboard 到 Repo 的一键初始化与灵魂生成。


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
