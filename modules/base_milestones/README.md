# base_milestones

基础里程碑模块（Base game milestones）。

## 内容

- `content/milestones/*.json`

## 依赖

- `base_rules`（提供部分里程碑 `effect_ids` 所需的 effect handlers）
- `base_employees`（部分里程碑触发器会引用员工 id，例如 `UseEmployee/waitress`）

