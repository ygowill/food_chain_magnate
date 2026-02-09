# The Ketchup Mechanism（番茄酱机制）

## 玩法

- 触发：当你营销产生的需求，被其他玩家的餐厅满足时，你在该晚餐阶段结束时获得里程碑 `ketchup_sold_your_demand`。
- 同一房屋若有多个玩家的营销需求，同一次售卖可使多名玩家获得该里程碑。
- 授予发生在晚餐阶段结束后，因此不会影响同一晚餐阶段内剩余房屋的结算。
- 效果：晚餐选店比较时，对拥有该里程碑的玩家按 `(unit_price + distance - 1)` 计算（等价于距离 `-1`，允许为负数，并可与 `new_milestones` 等类似距离修正叠加）。
- 仅包含饮品的订单同样适用。
- 每名玩家最多获得一次；里程碑 supply 有多份拷贝（`pool.count`），每次获得消耗 1 份，直至耗尽。

## 技术说明

- `DinnertimeSettlement` 会在 `round_state.dinnertime.sold_marketed_demand_events` 记录“他人卖出你营销需求”的事件序列（按房屋编号与需求序号确定性排序）。
- 本模块在 `Dinnertime enter` 注册一个 `SettlementRegistry` extension（priority >= 100），在 primary 晚餐结算完成后读取该事件序列，并对事件中出现的每个 `from_player` 触发里程碑事件 `KetchupSoldDemand`（去重后排序，保证确定性）。
- 距离修正通过 `EffectRegistry` 的 `:dinnertime:distance_delta:` segment 实现（`ketchup_mechanism:dinnertime:distance_delta:ketchup`），在 handler 内设置 `allow_negative=true` 并将 `ctx.distance -= 1`（对齐 `(unit_price + distance - 1)`）。
