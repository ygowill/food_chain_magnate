# 动作面板重构：确认结束替代跳过 + 自动推进阶段（计划）

## 背景与目标

当前 UI 中存在两个问题：

1. 动作面板提供了手动 `推进阶段(advance_phase)`，玩家可以绕过“应当自动推进”的流程。
2. `跳过(skip)` 语义更像“确认结束”，但目前没有做到“所有玩家确认结束后自动推进”。

本重构目标：

- UI 不再提供手动 `推进阶段` 按钮入口。
- 将 `跳过(skip)` 在 UI 上改为“确认结束”，并作为玩家“我已完成本阶段/子阶段”的显式确认。
- 当所有玩家都确认结束后，系统自动推进到下一子阶段/阶段。

## 约定/默认决策（如需调整请直接指出）

- 保持动作 `action_id` 不变：继续使用 `skip` 作为“确认结束”，不新增 `confirm_end` 动作。
- 结算类阶段（`Dinnertime/Marketing/Cleanup`）默认仍需要所有玩家逐一“确认结束”后才进入下一阶段（便于阅读结算结果）。
- `OrderOfBusiness`：最后一位玩家选完顺序后立即自动进入 `Working`，不需要额外确认。
- 保留 `Game.gd` 侧“玩家动作成功后自动 `end_turn`”的现有行为（避免牵连太多 UI 流程）。

## 非目标

- 不在本次重构中改变各阶段的规则内容（仅调整推进/确认机制）。
- 不实现新的 UI 视觉设计（只做必要的文案/可用性调整与状态同步）。

## 执行计划（每完成一项会更新本文件）

### 1) UI：隐藏手动推进阶段入口

- [x] ActionPanel：隐藏 `advance_phase`（不删除执行器，只移除 UI 入口）
- [x] ActionPanel：将 `skip` 显示名/描述改为“确认结束”
- [x] ActionPanel fallback：去掉 fallback 中的 `advance_phase`

### 2) Core：确认结束状态与轮转规则

- [x] `skip_action`：在所有阶段都写入 `round_state.sub_phase_passed[player_id]=true`
- [x] `end_turn_action`：轮转时跳过已确认结束的玩家（避免确认后仍反复轮到）
- [x] `skip_action`：自身推进到“下一位未确认结束玩家”（与 `end_turn_action` 对齐）

### 3) Core：自动推进子阶段/阶段

- [x] PhaseManager：在所有“进入新阶段”时重置 `sub_phase_passed`（避免跨阶段残留导致误判）
- [x] `skip_action`：当所有玩家都确认结束后自动推进：
	- 有 `sub_phase`：推进到下一子阶段（最后子阶段则进入下一主阶段）
	- 无 `sub_phase`：推进到下一主阶段（`OrderOfBusiness` 例外：由选顺序动作驱动）
- [x] `choose_turn_order_action`：当 `finalized=true` 时自动进入 `Working`

### 4) UI/测试：适配与回归

- [x] UI：移除/收敛 `advance_phase` 的触发路径（仅保留 debug/内部使用）
- [x] 测试工具/用例：更新与新增测试覆盖“确认结束自动推进”路径
- [x] 运行 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 360`

## 当前进度

- 状态：已完成
- 已完成：计划落盘
- 已完成：UI 隐藏手动推进阶段入口（并将 skip 改为“确认结束”）
- 已完成：确认结束状态写入 + 轮转跳过已确认玩家
- 已完成：全员确认结束后自动推进阶段/子阶段（含 OrderOfBusiness 自动进入 Working）
- 已完成：避免软锁：Train/PlaceRestaurants 中存在阻塞条件时，相关玩家不能确认结束
- 已完成：测试适配完成，AllTests 通过
