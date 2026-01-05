# Noodles（模块6：面条）

## 已实现

- 产品：`noodles`（tag: `food` + `no_marketing`）
- 晚餐规则：当房屋找不到任何能满足“原有需求”的餐厅时，才会尝试用 `noodles` 完全替代（每个需求标记对应 1 个面条；不能混合）
- 额外奢侈品经理：启用本模块时，供应池额外 +1 张 `luxury_manager`（多模块同时使用时仍只加一次）
- 员工：`noodles_cook`（pool fixed=12，salary=true）→ `noodles_chef`（unique=true，生产同披萨主厨）

## 待补齐

- 端到端用例：生产→晚餐替代（当前已有规则与 unit test 覆盖，但尚未覆盖“通过实际 produce_food 行为生产面条”）
