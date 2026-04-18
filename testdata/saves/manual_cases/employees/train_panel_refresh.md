# employee/train_panel_refresh - 培训面板刷新（双 trainer）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/train_panel_refresh.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 Train 面板在执行一次培训后，会立刻刷新可继续培训的员工列表，并且刚被培训过的员工不会在同回合再次出现在来源列表中。

## 情景设计

- 玩家 0 有 2 张 trainer，第一次培训后 Train 子阶段仍会停留在当前面板，便于观察可用员工列表是否即时刷新。
- 待命区同时放入 marketing_trainee 与 management_trainee；推荐先培训前者，这样刷新后应只剩 management_trainee 可继续培训。
- training 成功后，新得到的 campaign_manager 本回合不应立刻再次作为培训来源出现，否则就会错误允许同一员工继续被重复培训。

## 复核步骤

1. 载入后应处于 Working/Train，且玩家 0 在岗包含 trainer x2；reserve_employees 至少包含 marketing_trainee 与 management_trainee。
2. 先打开培训面板，确认可选来源列表里有 marketing_trainee 与 management_trainee。
3. 执行一次培训：将 marketing_trainee 培训为 campaign_manager。
4. 不要切换面板，直接观察当前培训面板中的可选来源列表。

## 预期结果

- 培训后仍停留在 Working/Train，因为还有 1 次培训额度且 management_trainee 仍可培训。
- 面板应立即移除 marketing_trainee，不需要手动关闭重开。
- 新得到的 campaign_manager 不应在本回合立刻出现在来源列表里，因此不能继续把同一名员工再培训到 brand_manager。
- 此时可继续培训的来源应只剩 management_trainee。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `marketing_trainee`
	- `to_employee`: `campaign_manager`

## 关联单元测试

- `core/tests/train_state_access_test.gd`
- `ui/scenes/tests/working_panels_visible_sync_test.gd`
