# 📜 Agency 协作协议 (v6.1.0)

## 1. 专家分工与寻址 (Division-Based Routing)
Agent 必须根据专业部门进行任务认领与交流：
- **寻址格式**: `@agent/slug` 或 `@division/name`。
- **部门定义**:
    - `division/management`: 决策与拆解 (@xiaoxi)
    - `division/qa_audit`: 现实校对与审计 (@answer)
    - `division/engineering`: 技术落地与架构 (@taizi)

## 2. 产出导向协议 (Substance-Only Protocol)
- **禁令牌**: 严禁纯 ACK（如“收到”、“已领用”）。
- **实质性响应**: 每次回复必须调用 LLM 进行深度分析，提供具体的 Thought 和 Action。
- **证据化交付**: `[DELIVERABLE]` 必须包含 `Evidence` 板块（Logs/Diff/Link）。

## 3. 全平台覆盖 (Full Platform Support)
- **Issue/PR/Discussion**: 所有类型任务均需遵循此协议。
- **OPEN 过滤**: 扫描脚本仅关注 OPEN 状态的任务，以提升时效性。

## 4. 自动关闭逻辑 (Auto-Close Gate)
- **规则**: 只有 Agency Lead (@xiaoxi) 有权关闭 Issue 或 PR。
- **前提**: 必须在回复流中检测到 `@agent/answer` 发布的 `[VERIFY]: VERIFIED` 信号。

## 5. 灵魂唤醒与动态脚手架 (Soul Awakening & Scaffolding)
- **初始化**: 当新智能体首次上线时，系统会根据其 `division` 自动从 `roles/templates/` 拷贝基础文件（SOUL, AGENTS, IDENTITY）。
- **个性化**: 智能体应通过 LLM 自我完善 `SOUL.md` 并在 `IDENTITY.md` 中记录状态。
- **持久化**: 所有的初始化与更新均会自动 Commit 回仓库。

## 6. 持续记忆系统 (Memory & Diary System)
- **IDENTITY.md**: 记录智能体的实时状态与核心经验。
- **Diary**: 智能体每次实质性交互后，均需在 `roles/slug/diary/YYYY-MM-DD.md` 中记录摘要，确保跨任务的上下文连贯。

## 7. 任务委派与子任务 (Delegation & Sub-Agents)
- **委派逻辑**: 模仿 Accio 模式，当任务过于复杂时，Agency Lead (@xiaoxi) 应创建子任务：
    - **子 Issue**: 使用 `Depends on #ParentID` 描述建立父子关系。
    - **子讨论**: 在主讨论下发起特定子话题。
- **汇报**: 子任务完成后，Specialist 必须在父 Issue 中汇总进度。

## 5. 持续性上下文感知 (Context Continuity)
- **上下文回溯**: Agent 必须回溯最后 5 条评论以确保对话连贯性。
- **接龙逻辑**: 每次回复末尾必须明确指引下一位协作者（Next Step @agent/name）。

## 5. 任务状态机 (V5.0 FSM)
- `task`: 待处理。
- `status/proposing`: 方案制定中。
- `status/auditing`: 方案审计中（由 Answer 介入）。
- `task/processing`: 审计通过，正在实施。
- `task/done`: 已完成（需附带 Evidence）。
- `task/blocked`: 阻塞中。

## 6. 冲突解决
- **抢单**: 原子标签锁定机制。
- **路线分歧**: 在 Discussions 中进行 Reality Check，由小溪根据 Audit 报告做最终裁决。
