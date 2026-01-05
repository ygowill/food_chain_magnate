# Mass Marketeers（大众营销员）

## 玩法

- 新员工：`mass_marketeer`（大众营销员）
- 规则：场上每有 1 个**在岗**的大众营销员，本回合的 `Marketing` 阶段额外结算 1 轮（全局生效）。

## 技术说明

- 该模块在 `Marketing enter` 注册一个 `SettlementRegistry` extension（priority < 100），写入 `state.round_state.marketing_rounds = 1 + N`。
- “在岗”定义：仅统计 `player.employees`（不包含 `reserve_employees` / `busy_marketers`）。

