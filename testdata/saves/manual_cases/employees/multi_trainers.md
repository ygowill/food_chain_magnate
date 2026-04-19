# employee/multi_trainers - 多个训练员工综合测试（multi_trainers）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/multi_trainers.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 在单个存档中同时验证多个相同训练员、不同训练员、无里程碑时禁止多名训练员连续训练同一员工，以及 coach/guru 的多级培训能力。

## 情景设计

- 玩家 0 在岗同时拥有 2 名 trainer、2 名 coach、1 名 guru，用于比较同类多实例与不同训练员的剩余次数。
- 待命区放入 3 名 marketing_trainee、2 名 management_trainee、2 名 kitchen_trainee，便于连续测试不同培训链。
- 存档起点没有 multi_trainer_on_one 里程碑：先用一名 trainer 培训 marketing_trainee -> campaign_manager，再尝试换另一名 trainer 继续培训同一 staff_id 到 brand_manager，应被拒绝。
- coach 可一次将 marketing_trainee 提升两级到 brand_manager；guru 可一次将 management_trainee 提升三级到 senior_vice_president。

## 复核步骤

1. 载入后应处于 Working/Train，玩家 0 在岗包含 2 名 trainer、2 名 coach、1 名 guru。
2. 待命区应包含 3 名 marketing_trainee、2 名 management_trainee、2 名 kitchen_trainee。
3. 选择一名 trainer，将某个 marketing_trainee 培训为 campaign_manager；随后尝试选择另一名 trainer 继续将同一个 staff_id 培训为 brand_manager，应失败。
4. 选择 coach，将另一个 marketing_trainee 一次性培训为 brand_manager，应成功并消耗 2 次培训容量。
5. 选择 guru，将一个 management_trainee 一次性培训为 senior_vice_president，应成功并消耗 3 次培训容量。

## 预期结果

- 多个相同 trainer 应显示为多个可选择实例，每个实例各 1 次培训容量。
- 无 multi_trainer_on_one 时，同一名员工被某一训练员培训后，不能换另一名训练员继续训练。
- coach 单实例剩余容量为 2，可完成 2 步培训。
- guru 单实例剩余容量为 3，可完成 3 步培训。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `marketing_trainee`
	- `to_employee`: `campaign_manager`

## 关联单元测试

- `core/tests/manual_multi_trainers_save_test.gd`
- `core/tests/milestone_system/milestone_system_train_rules_test.gd`
- `core/tests/train_action_state_access_test.gd`
