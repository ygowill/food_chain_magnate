# Sushi（模块7：寿司）

## 已实现

- 产品：`sushi`（tag: `food` + `no_marketing`）
- 晚餐规则：仅对“带花园的房屋”，优先尝试用 `sushi` 完全替代全部需求（每个需求标记对应 1 个寿司）
- 额外奢侈品经理：启用本模块时，供应池额外 +1 张 `luxury_manager`（多模块同时使用时仍只加一次）
- 员工：`sushi_cook`（pool fixed=12，salary=true）→ `sushi_chef`（unique=true，生产同披萨主厨）

## 待补齐

- 端到端用例：生产→晚餐替代（当前已有规则与 unit test 覆盖，但尚未覆盖“通过实际 produce_food 行为生产寿司”）
