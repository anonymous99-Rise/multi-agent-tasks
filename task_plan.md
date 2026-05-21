# Task Plan: Personality System + Skill/All Review

## 背景
哥哥的需求：
1. agents.json 字段 `agents_prompt` ✅ 已确认正确
2. 根据角色（commander/collector/executor）从 skill.md 读取性格
3. Dashboard 智能体身份配置增加性格展示
4. @skill/all → 所有 agent 必须实质性回复（禁止纯 ACK）
5. 用 `[skill/slug]/analyzed` 格式

## 当前状态
- ✅ agents.json 使用 `agents_prompt` 字段
- ✅ sync_personality.sh v2.0 已实现从 SKILL.md + roles/*/SOUL.md 同步
- ❌ Answer cron 未添加（OpenClaw 版本不匹配）
- ⚠️ scan_issues.sh 需要增强 skill/all 处理

## 实现计划

### Phase 1: Review & Fix scan_issues.sh (skill/all + analyzed 格式)
- [ ] 修改 scan_issues.sh: `skill/all` 标签 → 所有非 commander agent 都响应
- [ ] 修改评论格式为 `[skill/slug]/analyzed`
- [ ] 禁止纯 ACK 回复，必须包含实质性内容

### Phase 2: Dashboard Personality 展示
- [ ] 检查 dashboard 端 agent personality 展示
- [ ] 添加 personality 字段到 dashboard 配置

### Phase 3: 测试 & 验证
- [ ] 本地测试 skill/all 逻辑
- [ ] 验证 analyzed 格式
- [ ] PR 流程

### Phase 4: 文档更新
- [ ] CHANGELOG 更新
- [ ] README 更新（如果需要）
- [ ] Release v4.3.0

## 当前分支
- 工作分支: `feature/skill-all-review`

## OpenClaw cron 问题
- Answer cron 无法添加（版本不匹配 2026.5.4 vs 2026.5.18）
- 临时方案: 使用系统 crontab 或等待 OpenClaw 升级
