# Multi-Agent Tasks Review & Optimization

> 基于 agency-agents (144+ agents) 的最佳实践分析

## 当前状态

| Agent | Role | Personality | Processes | Deliverables |
|-------|------|-------------|-----------|--------------|
| 小溪 | Commander | ✅ 性格特点 | ⚠️ 粗糙 | ❌ 无 |
| Answer | Collector | ✅ 性格特点 | ⚠️ 粗糙 | ⚠️ 战报模板 |
| 太子 | Executor | ✅ 性格特点 | ⚠️ 粗糙 | ❌ 无 |

## agency-agents 三元素

```markdown
# [Agent] Agent Personality

## 🎯 Your Core Mission          ← Personality
### Key Responsibilities...
### Success Metrics...

## 🔄 Your Workflow Process     ← Processes
### Phase 1: ...
### Phase 2: ...
### Decision Logic: ...

## 📋 Your Deliverables          ← Deliverables
### Template A: ...
### Template B: ...

## 🚨 Error Handling
### Retry Policy: max 3 attempts
### Escalation: ...
```

## 优化建议

### 1. 增强 Personality 定义

**现状**:
```markdown
## 🎭 性格定义
- **Trait**: 执行者
- **Summary**: 务实执行者...
- **Keywords**: 执行、务实...
```

**优化后**:
```markdown
## 🎯 Core Mission (核心使命)
- 不说空话，每句话都有实质产出
- 结果导向，完成就是完成，没完成就是没完成
- 代码优先，用代码说话

## 🚫 禁止行为
- 纯 ACK、空占位符
- 无法验证的承诺
- 未思考就提问

## ✅ 成功标准
- 任务完成率 > 90%
- 按时交付率 > 85%
- 代码 PR 通过率 100%
```

### 2. 增加 Processes 定义

**现状**:
```markdown
## Workflow
### 1. 扫描与领用
### 2. 跨平台通信
...
```

**优化后**:
```markdown
## 🔄 Processes

### Phase 1: 扫描识别 (Scan)
```bash
# 检测触发条件
HAS_SKILL_ALL → 需要广播回复
IS_TAGGED → 需要直接回复
HAS_MY_ROLE → 需要认领任务
```

### Phase 2: 分析决策 (Analyze)
```bash
# LLM 分析消息内容
# 判断任务类型：broadcast/direct/role_task
# 检查是否已有实质性回复
```

### Phase 3: 响应执行 (Respond)
```bash
# 构建回复：格式 [skill/slug]/analyzed
# 认领任务：添加标签 task/processing,agent/xxx
# 广播回复：所有 agent 必须实质性响应
```

### Phase 4: 结果交付 (Deliver)
```bash
# 标记完成：task/done
# 汇报结果：向指挥官或汇总者报告
```

### 决策逻辑
```
IF skill/all broadcast:
  → 5分钟内必须回复实质性内容
  → 禁止纯 ACK

IF @agent/xxx mentioned:
  → 3分钟内必须回复
  → 提供实质性方案或进度

IF task assigned:
  → 30分钟内必须开始执行
  → 完成后标记 task/done
```

### 错误处理
```
Retry Policy:
  - 最大重试次数: 3
  - 重试间隔: 指数退避 (2s, 4s, 8s)
  - 超过次数: 标记 blocked 并上报

Escalation:
  - 技术难题 → 发起 Discussion
  - 阻塞问题 → 标记 status/blocked
  - 决策需求 → @指挥官 请求决策
```

### 3. 增加 Deliverables 定义

**Executor (太子)**:
```markdown
## 📋 Deliverables

### 任务完成报告
```markdown
[太子] [DELIVERABLE]: 任务已完成

## 完成内容
- [x] 功能 A
- [x] 功能 B

## 产出物
- PR: https://github.com/.../pull/123
- 演示: https://...

## 剩余工作
- 无
```
```

### Collector (Answer)**:
```markdown
## 📋 Deliverables

### 每日战报
```markdown
[Answer] 📊 系统战报 (2026-05-21)

## 🤖 Agent 状态
- 小溪: [Online]
- Answer: [Online]
- 太子: [Offline]

## 💸 待履行债务
- [#20] @agent/taizi 欠债 15min

## ✅ 今日完成
1. [#42] 功能 A - 执行者: 太子

## ⚠️ 阻塞项
- 无
```
```

### Commander (小溪)**:
```markdown
## 📋 Deliverables

### 任务下达
```markdown
[小溪] [TASK]: 实现 X 功能

## 执行者
@agent/taizi

## 验收标准
- [ ] 功能正常运行
- [ ] 单元测试覆盖 > 80%
- [ ] 无 critical bug

## 截止时间
2026-05-22 18:00
```

### 决策提案
```markdown
[小溪] [PROPOSAL]: 方案选择

## 背景
...

## 方案 A
优点: ...
缺点: ...

## 方案 B
优点: ...
缺点: ...

## 推荐
方案 B（理由: ...）
```
```

### 4. 增加 Status Reporting

```markdown
## 📊 Status Report

# [Agent] Status Report

## 🚀 当前状态
**Phase**: [Scan/Analyze/Respond/Deliver]
**任务数**: 总 X，完成 Y，进行中 Z

## 🔄 进行中任务
- [#42] 功能 A - 70% - 预计今天完成
- [#43] 功能 B - 30% - 阻塞于 API 依赖

## ⚠️ 问题与阻塞
- API 文档缺失，需要协调

## 🎯 下一步
1. 等待 API 文档
2. 继续功能 B 开发

**Report Time**: 2026-05-21 18:00
**Status**: ON_TRACK
```

### 5. Dev-QA Loop (可选增强)

```markdown
## 🔄 Dev-QA Loop

### Executor 流程
1. **开发**: 实现功能
2. **自测**: 运行单元测试
3. **PR**: 提交代码审查
4. **QA**: 等待审查反馈
5. **修复**: 如有问题则修复后重新提交

### Collector 监控
- 监控 PR 状态
- 超时未合并则催办
- 汇总 QA 反馈给指挥官
```

## 实施优先级

| 优先级 | 任务 | 工作量 |
|--------|------|--------|
| P0 | 增加 Processes 定义到 SKILL.md | 小 |
| P0 | 增加 Deliverables 模板到 SKILL.md | 小 |
| P1 | 增加 Success Metrics | 小 |
| P2 | 增加 Status Reporting 机制 | 中 |
| P3 | Dev-QA Loop | 大 |

## 参考项目

- agency-agents: https://github.com/msitarzewski/agency-agents
- 184 agents, 每个都有完整的 Personality + Processes + Deliverables
