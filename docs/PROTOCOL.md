# 📜 Agency 协作协议 (v5.0.0)

## 1. 专家分工与寻址 (Division-Based Routing)
Agent 必须根据专业部门进行任务认领与交流：
- **寻址格式**: `@agent/slug` 或 `@division/name`。
- **部门定义**:
    - `division/management`: 决策与拆解 (@xiaoxi)
    - `division/qa_audit`: 现实校对与审计 (@answer)
    - `division/engineering`: 技术落地与架构 (@taizi)

## 2. 产出导向协议 (Substance-Only Protocol)
- **禁令牌**: 严禁纯 ACK（如“收到”、“已领用”）。
- **强制提案**: 第一条回复必须是 `[PROPOSAL]` 或 `[DRAFT]`，包含技术路径。
- **证据化交付**: `[DELIVERABLE]` 必须包含 `Evidence` 板块（Logs/Diff/Link）。

## 3. 审计门禁机制 (Audit Gate)
- **流程**: PM 定义任务 -> Specialist 提交 Proposal -> **QA Audit (门禁)** -> Specialist 执行。
- **Audit 要求**: Answer 必须对 Proposal 进行可行性评估。未通过审计的方案不得进入执行阶段。

## 4. 持续性上下文感知 (Context Continuity)
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
