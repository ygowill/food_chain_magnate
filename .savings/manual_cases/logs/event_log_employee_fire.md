# logs/event_log_employee_fire - 日志回放验证（Payday 解雇）

## 存档

- JSON: `res://.savings/manual_cases/logs/event_log_employee_fire.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 用于手工复核解雇日志：EMPLOYEE_FIRED。

## 复核步骤

1. 载入后打开日志视图。
2. 确认存在「解雇 ...（待命）」日志。

## 预期结果

- 解雇日志包含 employee_id/location 等 details 字段。

## 关联单元测试

- `core/tests/fire_action_test.gd`
