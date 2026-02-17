# milestone/first_pay_20_salaries - 首个支付$20+薪水（first_pay_20_salaries）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_pay_20_salaries.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证离开 Payday 时若实际支付 paid>=20，会触发 first_pay_20_salaries（multi_trainer_on_one=true）。

## 复核步骤

1. 载入后应处于 Payday 阶段（玩家 0 已准备 4 名需薪员工与足够现金）。
2. 点击「推进阶段」离开 Payday（会自动计算薪资并继续推进）。

## 预期结果

- 玩家 0 获得里程碑 first_pay_20_salaries（player.milestones）。
- 玩家 0 multi_trainer_on_one == true。
- state.round_state.payday.details[0].paid >= 20。

## 关联单元测试

- `core/tests/milestone_system_test.gd`
- `core/tests/payday_salary_test.gd`
