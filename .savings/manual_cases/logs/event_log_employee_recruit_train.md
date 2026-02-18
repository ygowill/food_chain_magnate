# logs/event_log_employee_recruit_train - 日志回放验证（强制定价 + 招聘 + 培训）

## 存档

- JSON: `res://.savings/manual_cases/logs/event_log_employee_recruit_train.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 用于手工复核员工相关日志：强制定价（COMMAND_EXECUTED）、招聘（EMPLOYEE_RECRUITED）与培训（EMPLOYEE_TRAINED）。

## 复核步骤

1. 载入后打开日志视图（左侧「日志」按钮）。
2. 确认存在「设定价格（-$1）」日志。
3. 确认存在「招聘 ...（待命）」日志。
4. 确认存在「培训 ... -> ...」日志。

## 预期结果

- 日志条目可双击展开 details（含 action_id/employee ids 等）。

## 关联单元测试

- `core/tests/mandatory_actions_test.gd`
- `core/tests/recruit_on_credit_rules_test.gd`
- `core/tests/milestone_system_test.gd`
