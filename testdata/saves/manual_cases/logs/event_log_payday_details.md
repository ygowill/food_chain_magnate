# logs/event_log_payday_details - 日志回放验证（Payday 发薪明细）

## 存档

- JSON: `res://testdata/saves/manual_cases/logs/event_log_payday_details.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 用于手工复核 Payday 日志细节：单独的解雇日志、逐员工发薪/免薪、招聘折扣来源、里程碑薪资修正。

## 情景设计

- 玩家1：hr_director（在岗）+ campaign_manager（忙碌营销）+ burger_cook（待命，已在 Payday 解雇）。
- 玩家1持有里程碑 first_train（总薪资 -$15）与 first_billboard（营销员工免薪）。
- 当前停在 Payday，玩家1为当前玩家；日志历史里已经包含一条解雇日志。
- 进入后依次让玩家1、玩家2点击「确认结束」，当轮 Payday 完成时会新增每位玩家的发薪总结，并展示逐员工发薪/免薪/减免来源。

## 复核步骤

1. 载入后打开日志视图。
2. 先确认已经存在一条「解雇 ...」日志。
3. 依次点击「确认结束」直到离开发薪日（当前存档需要玩家1、玩家2各确认一次）。
4. 确认出现每位玩家的 Payday 总结日志。
5. 确认日志文本中包含逐员工明细、免薪原因、招聘折扣来源、里程碑薪资修正。

## 预期结果

- 解雇日志与最终发薪日志分开显示。
- 玩家1的发薪日志应包含 hr_director 在岗发薪、campaign_manager 忙碌营销免薪，以及 first_train / first_billboard 带来的减免信息。

## 关联单元测试

- `core/tests/payday_salary_test.gd`
- `core/tests/payday_report_event_test.gd`
- `core/tests/fire_action_test.gd`
