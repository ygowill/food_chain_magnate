# Hard Choices（模块16）

## 规则要点

- 该模块是对“基础里程碑集合”的变体规则（必须与 `base_milestones` 一起使用）。
- 在回合结束的 Cleanup 阶段：
  - 第 2 回合结束：若仍未被获取，则移除 `first_burger_marketed` / `first_pizza_marketed` / `first_drink_marketed` / `first_train`。
  - 第 3 回合结束：若仍未被获取，则移除 `first_hire_3`。

## 技术实现

- 通过 `RulesetRegistrarV2.register_milestone_patch()` 将对应里程碑的 `expires_at` 设置为 2/3。

