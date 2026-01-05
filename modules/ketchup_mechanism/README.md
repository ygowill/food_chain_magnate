# The Ketchup Mechanism（番茄酱机制）

## 玩法

- 触发：当你营销产生的需求，被其他玩家的餐厅满足时，你在该晚餐阶段结束时获得里程碑 `ketchup_sold_your_demand`。
- 触发频率：整局只会发生一次（该里程碑一旦被获得，剩余拷贝在 Cleanup 阶段被移除）。
- 效果：拥有该里程碑的玩家在晚餐阶段计算 `单价 + 距离` 时，距离永久 `-1`（最小为 0）。

## 技术说明

- `DinnertimeSettlement` 会在 `round_state.dinnertime.sold_marketed_demand_events` 记录“他人卖出你营销需求”的事件序列（按房屋编号与需求序号确定性排序）。
- 本模块在 `Dinnertime enter` 注册一个 `SettlementRegistry` extension（priority >= 100），在 primary 晚餐结算完成后读取该事件序列，并触发一次里程碑事件 `KetchupSoldDemand`。
- 距离修正通过 `EffectRegistry` 的 `:dinnertime:distance_delta:` segment 实现（`ketchup_mechanism:dinnertime:distance_delta:ketchup`），并在 handler 内 clamp 到 0。

