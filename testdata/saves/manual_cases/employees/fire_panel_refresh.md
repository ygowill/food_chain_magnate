# employee/fire_panel_refresh - 发薪日解雇面板刷新

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/fire_panel_refresh.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证 Payday 面板在执行解雇后，会立刻刷新员工列表与薪资汇总，不再显示已解雇员工。

## 情景设计

- Payday 面板同时存在一名在岗 waitress 与一名待命 trainer，解雇后仍保留至少一个列表项，便于确认面板是即时刷新而不是整面板关闭/重开。
- waitress 需要薪水、trainer 不需要薪水，因此解雇 waitress 后，员工列表和薪资汇总都会立刻变化，适合人工复核。

## 复核步骤

1. 载入后应处于 Payday，且玩家 0 员工列表中至少有一名在岗 waitress 与一名待命 trainer。
2. 打开发薪日面板，先确认 waitress 显示为在岗员工，trainer 显示为待命员工。
3. 在面板中勾选并解雇 waitress。
4. 不要关闭面板，直接观察当前列表与汇总。

## 预期结果

- waitress 会立刻从面板列表中消失，不需要重新打开 Payday 面板。
- trainer 仍然保留在待命列表中。
- 薪资汇总会同步下降；若只剩 trainer，则应不再需要为 waitress 支付薪水。

## 推荐参数（可选）

- action_id: `fire`
- actor: `0`
- params:
	- `employee_id`: `waitress`
	- `location`: `active`

## 关联单元测试

- `core/tests/fire_action_test.gd`
- `ui/scenes/tests/working_panels_visible_sync_test.gd`
