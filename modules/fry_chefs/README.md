# Fry Chefs（模块9：薯条主厨）

## 内容

- 员工：`fry_chef`（pool：fixed=8，salary=true）

## 规则

- 培训链：通过 employee patch，将下列员工的 `train_to` 增加 `fry_chef`：
  - `burger_cook`
  - `pizza_cook`
  - `noodle_cook`（模块6）
  - `sushi_cook`（模块7）
- 晚餐奖励：每当你成功向一个房屋售卖时，每个在岗 `fry_chef` 使该房屋结算额外 +$10（按房屋算，不按数量算；不影响 unit price 或 distance）。
