---
id: GOV-003
doc_kind: governance
status: active
created: 2026-07-11
updated: 2026-07-11
owners: [engineering-governance, engineering-productivity]
review_after: 2026-08-11
---

# 项目 Skills 注册表

本页是仓库内 Skill 版本、Owner、生命周期状态和复核日期的唯一人工真相源。Skill 的触发描述与执行步骤分别以其 `SKILL.md` 为准；[`skill-index.json`](../_generated/skill-index.json)是脚本生成的访问层，不能手工维护状态。

## 当前 Skills

| Skill | Version | Status | Owner | Invocation | 职责边界 |
|---|---|---|---|---|---|
| [`fcm-deliver-feature`](../../.agents/skills/fcm-deliver-feature/SKILL.md) | 0.1.0 | experimental | product-owner, engineering | implicit / `$fcm-deliver-feature` | 从意图、Requirement、设计到实现、验证的新 Feature 交付；不替代独立验收 |
| [`fcm-safe-refactor`](../../.agents/skills/fcm-safe-refactor/SKILL.md) | 0.1.0 | experimental | core-architecture, engineering | implicit / `$fcm-safe-refactor` | 以显式行为不变量和基线证物驱动安全重构；不增加产品行为 |
| [`fcm-quality-gate`](../../.agents/skills/fcm-quality-gate/SKILL.md) | 0.1.0 | experimental | quality-engineering | implicit / `$fcm-quality-gate` | 只读判定是否可进入 Review；不顺手修复或自我放行 |
| [`fcm-sync-docs`](../../.agents/skills/fcm-sync-docs/SKILL.md) | 0.1.0 | experimental | engineering-governance | implicit / `$fcm-sync-docs` | 同步唯一真相源、关系和生成索引；不创建业务意图 |
| [`fcm-validate-acceptance`](../../.agents/skills/fcm-validate-acceptance/SKILL.md) | 0.1.0 | experimental | quality-engineering, product-owner | manual / `$fcm-validate-acceptance` | 冷启动独立验收并产出正式 verdict；不由实现者自我批准 |

## 推荐编排

### 新 Feature

`fcm-deliver-feature → fcm-sync-docs → fcm-quality-gate → independent review → fcm-validate-acceptance`

若实现需要大规模行为保持型整理，在 Feature 的新行为 AC 与重构不变量分离后插入 `fcm-safe-refactor`。

### 重构

`fcm-safe-refactor → fcm-sync-docs → fcm-quality-gate`

涉及用户路径、平台、性能或兼容性人工判断时，再由独立执行者运行 `fcm-validate-acceptance`。

## 生命周期与晋升

状态使用：`candidate → draft → experimental → active → deprecated → retired`。

从 experimental 晋升 active 前，每个 Skill 至少需要：

- 三个真实任务记录，且能与无 Skill 基线比较；
- 正负触发、执行和 Safety Eval 全部通过；
- 无严重误触发、Gate 漏检或越权执行；
- 固定 Output Contract 与 Stop/Ask 条件已被实际使用；
- Owner 完成一次冷启动复核并更新 Version / review_after。

目录、触发描述、UI metadata、引用或 Eval 发生实质变化时提升语义版本并运行：

```bash
python3 tools/skills_governance.py --self-test
python3 tools/skills_governance.py --write-index
python3 tools/skills_governance.py
```

模型、Codex 或项目治理规范升级时重跑全部 Eval。退役 Skill 必须先从 `AGENTS.md` 和编排文档移除触发入口，再保留归档理由；不能静默删除仍被引用的 Skill。
