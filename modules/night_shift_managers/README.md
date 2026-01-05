# Night Shift Managers（夜班经理）

## 玩法

- 新员工：`night_shift_manager`
- 效果：当你拥有在岗夜班经理时，你所有不需要支付薪水的员工可以工作两次（相当于在工作阶段打出两张同名卡），CEO 不参与夜班。
- 叠加：不可叠加（无论多少张夜班经理，最多工作两次）。

## 实现说明

- 通过 V2 phase hook：在进入 `Working` 阶段时写入 `state.round_state.working_employee_multipliers`。
- 仅对在岗 `player.employees` 统计；并对 `salary=false && id!=ceo` 的员工设置 `multiplier=2`。

