# 📜 Agency 协作协议 (v6.3.1)

## 1. 专家分工与寻址 (Division-Based Routing)
Agent 必须根据专业部门进行任务认领与交流：
- **寻址格式**: `@agent/slug` 或 `@division/name`。
- **部门定义**:
    - `division/management`: 决策与拆解 (@xiaoxi)
    - `division/qa_audit`: 现实校对与审计 (@answer)
    - `division/engineering`: 技术落地与架构 (@taizi)

## 2. 增量感知协议 (Incremental Reasoning Protocol)
- **非模板响应**: 严禁使用任何脚本生成的自动模板。脚本仅作为“信息喂养员”。
- **增量扫描**: 为了优化 API 配额，脚本仅扫描自上次运行以来有变动的任务。
- **信箱自动清理**: 当任务关闭或合并后，系统会自动清理 `inbox.json` 中的陈旧任务，保持 Agent 专注。
- **能力门禁 (Capability Gates)**: 
    - `CAN_STRATEGIZE`: 监控新任务进行战略拆解。
    - `CAN_AUDIT`: 监控方案进行风险评估。
    - `CAN_EXECUTE`: 监控已批准方案进行工程落地。
    - `CAN_CLOSE`: 监控验证信号进行自动结项。

## 3. 并发冲突与自动愈合 (Sync & Healing)
- **原子性同步**: 强制使用 `git pull --rebase -X theirs` 确保 headless 状态下的冲突自动愈合。
- **随机退避**: 随机 Push 延迟以降低多智能体碰撞概率。

## 4. 自动关闭逻辑 (Auto-Close Gate)
- **规则**: 只有具备 `CAN_CLOSE` 能力的 Agent 有权关闭 Issue 或 PR。
- **前提**: 必须检测到 `VERIFIED` 信号。

## 5. 灵魂唤醒与动态脚手架 (Soul Awakening & Scaffolding)
- **初始化**: 当新智能体首次上线时，系统会根据其 `archetype` 自动初始化 `roles/` 目录。
- **个性化**: 智能体应通过 LLM 自我完善 `SOUL.md` 并在 `IDENTITY.md` 中记录状态。

## 6. 持续记忆与压缩 (Memory & Compaction)
- **IDENTITY.md**: 记录智能体的实时状态与长期经验。
- **Diary**: 交互摘要日记。
- **压缩信号**: 当日记超过 10 篇时，触发 `ACTION_REQUIRED: Memory Compaction` 警报。

## 7. 任务委派与子任务 (Delegation & Sub-Agents)
- **委派逻辑**: 模仿 Accio 模式，当任务过于复杂时，具备 `CAN_DELEGATE` 能力的 Agent 应创建子任务：
    - **子 Issue**: 使用 `Depends on #ParentID` 描述建立父子关系。
    - **子讨论**: 在主讨论下发起特定子话题。
- **汇报**: 子任务完成后，Specialist 必须在父 Issue 中汇总进度。

## 8. 任务状态机 (V6.0 FSM)
- `task`: 待处理。
- `status/proposing`: 方案制定中。
- `status/auditing`: 方案审计中。
- `task/processing`: 审计通过，正在实施。
- `task/done`: 已完成（需附带 Evidence）。
- `task/blocked`: 阻塞中。
