# `staff_id`、usage track 与员工动作面板统一方案（2026-04-18）

> 状态：**部分已实施（2026-04-19）**
> 目的：统一员工运行时身份、员工使用追踪与员工驱动动作面板；本方案**不引入 `card_id`**，也**不追踪物理卡溯源**。

## 实施进展（2026-04-18）

已落地：

- `staff_id` 基础兼容层
- `fire` / `train` 动作保留并使用 `staff_id`
- `recruit` 动作支持显式 `staff_id`，并写入 `round_state.staff_usage[staff_id]["recruit"]`
- `train` 动作记录培训员 `staff_usage[trainer_staff_id]["train"]`
- `RecruitPanel` 改为“上方选招聘员工实例、下方看可招目标”
- `TrainPanel` 改为“上方选来源员工实例、下方看可达目标”
- Payday 薪资折扣已从 `staff_usage[staff_id]["recruit"]` 完全收口
- `produce_food` / `procure_drinks` 动作支持显式 `staff_id`，并写入
	- `round_state.staff_usage[staff_id]["produce_food"]`
	- `round_state.staff_usage[staff_id]["procure_drinks"]`
- `ProductionPanel` 改为优先使用 staff provider 列表：
	- 上方选具体生产/采购员工实例
	- 下方显示该实例当前可执行的生产/采购参数区
- `production_controller` 改为从 `EmployeeRules.get_food_producers_for_working` /
  `get_drinks_procurers_for_working` 读取真实实例数据，而不是本地按 `employee_type` 重建伪实例

本轮新增落地（2026-04-19）：

- 营销面板统一到 staff 驱动框架
- 房屋 / 花园面板统一到 staff 驱动框架
- 餐厅面板统一到 staff 驱动框架
- `ActionPanelContextController` 已移除 placement overlay 的旧 `employee_type`-only picker fallback
- 房屋 / 餐厅 overlay 的 staff picker 状态已收敛到公共 `StaffPickerState`
- `placement_overlays.gd` 已删除统一后不再使用的旧 helper / import

当前仍未完成：

- 将更多员工驱动面板进一步收口到相同的 provider + picker state helper（如后续需要，可继续扩展到 recruit / train / production 的内部状态层）

---

## 1. 背景

当前实现里，员工相关逻辑存在三类长期问题：

1. **员工身份粒度过粗**：多数规则和 UI 仍以 `employee_type` 为主，难以区分同类型多个员工。
2. **使用追踪分散**：生产、采购、营销、放置房屋/花园、餐厅放置/移动、招聘、培训等动作使用不同的计数字段或局部 UI 缓存，容易不一致。
3. **动作面板交互不统一**：招聘、培训等面板仍偏“动作优先”，而不是“先选员工，再看该员工当前能做什么”，容易把不同员工的能力和剩余额度混在一起。

本方案的核心目标是：

- 用 `staff_id` 统一员工运行时身份；
- 用“**员工身上的能力轨道（usage track）**”统一使用追踪；
- 用“**上方选员工、下方看该员工动作/效果**”统一动作面板；
- 保持员工池只按**剩余数量**管理，不引入 `card_id`。

---

## 2. 已确认前提（本方案的约束）

以下结论已在讨论中确认：

### 2.1 员工身份

- 需要 `staff_id`
- 不需要 `card_id`
- 员工池中不区分物理卡，只保存“某类型剩余多少张”

### 2.2 员工池

- `employee_pool_remaining[employee_type] = count`
- 不追踪“是哪一张卡被拿走/放回”
- 不要求物理卡溯源

### 2.3 培训

- 培训限制是**按回合刷新的“培训事件次数”限制**
- 默认：同一个 `staff_id` **每回合**最多被培训 1 次
- 扩展/里程碑可以提高这个上限
- 培训指导员 / 培训专家等支持“**跳级培训**”
- 跳级培训：
	- 对目标员工只算 **1 次培训事件**
	- 但按路径长度消耗培训者额度
	- 只检查**最终目标员工**是否“有货”
	- **不检查中间员工类型**是否缺货
- 若未来出现多条培训路径：
	- 选择**最短路径**
	- 若有多条同长度最短路径，再按 `train_to` 定义顺序做 tie-break

### 2.4 UI

- UI 不显示原始 `staff_id`
- 员工驱动面板应统一为：
	- 上方选择员工
	- 下方显示该员工的动作、效果、剩余次数与参数区
- 培训面板中“最终可达目标 + 消耗步数”的展示方式可复用现有 UI 思路

---

## 3. 核心设计结论

### 3.1 唯一运行时员工身份：`staff_id`

本方案中，玩家公司里的员工不再以 `employee_type` 字符串数组为核心建模，而是以 `staff_id` 为唯一运行时身份：

- `staff_id`：运行时员工实例 id
- `employee_type`：该员工当前职业/岗位
- 其它规则连续性状态（例如本回合培训事件、轨道使用情况）均围绕 `staff_id` 建模

### 3.2 员工池只按数量管理

员工池不实例化，不引入 `card_id`，只维护：

```text
employee_pool_remaining[employee_type] = count
```

因此：

- 招聘：池子数量 `-1`，创建新的 `staff_id`
- 解雇：删除 `staff_id`，池子数量 `+1`
- 培训：同一个 `staff_id` 保留，仅修改 `employee_type`，同时做源/目标类型数量变化

### 3.3 使用追踪以“员工实例 + 能力轨道”为核心

本方案不采用“匿名动作次数池”的语义。  
统一模型是：

> **某个 `staff_id` 身上的某条 `usage track`，在本回合已经消耗了多少额度**

也就是说，真正的计数对象是：

- `staff_id`
- `track_id`
- `used_units`

而不是“全局 recruit 池 / 全局 train 池 / 全局 place_house 池”。

---

## 4. Canonical 运行时状态模型

## 4.1 建议新增/收敛的核心字段

### 顶层

```text
state.next_staff_id: int
state.employee_pool_remaining: Dictionary[String, int]
```

### 玩家侧

```text
players[i].staff_registry: Dictionary[int, StaffRecord]
players[i].reserve_staff_ids: Array[int]
players[i].busy_staff_ids: Array[int]
players[i].structure / slot data: 存 staff_id，而不是 employee_type
```

> 说明：zone 信息优先由外部容器表达，不在 `StaffRecord` 内重复保存“我在哪个区”，避免双份真相。

### StaffRecord（建议）

```text
StaffRecord = {
	staff_id: int,
	employee_type: String,
	created_round: int,
}
```

> 注意：由于“培训限制”已经确认为**回合内事件限制**，因此本方案不把“终身培训次数限制”作为核心字段。  
> 如未来为了日志/分析需要记录 lifetime 指标，可作为附加统计字段，但不作为当前规则真相源。

### RoundState（建议）

```text
round_state.staff_usage: Dictionary[int, Dictionary[String, int]]
round_state.staff_train_event_counts: Dictionary[int, int]
```

语义分别是：

- `staff_usage[staff_id][track_id] = used_units`
- `staff_train_event_counts[target_staff_id] = 本回合该员工已经历的培训事件次数`

---

## 5. `staff_id` 生命周期

## 5.1 初始化

开局创建起始员工时，按稳定顺序分配 `staff_id`：

- 玩家顺序：`0..N-1`
- 同一玩家内：
	- 先按当前已有稳定容器顺序扫描
	- 再逐个分配 `staff_id`

目标是保证：

- 新局初始化稳定
- 相同种子/相同初始化流程下 staff 分配稳定
- replay 可复现

## 5.2 招聘

招聘执行时：

1. 检查 `employee_pool_remaining[target_type] > 0`
2. `employee_pool_remaining[target_type] -= 1`
3. 分配新的 `staff_id = state.next_staff_id`
4. `state.next_staff_id += 1`
5. 创建 `StaffRecord`
6. 将该 `staff_id` 放入目标 zone（通常是 reserve）

## 5.3 培训

培训执行时：

1. 保留原 `staff_id`
2. 记录 `from_type`
3. 解析 `to_type`
4. `employee_pool_remaining[from_type] += 1`
5. `employee_pool_remaining[to_type] -= 1`
6. 更新 `staff_registry[staff_id].employee_type = to_type`

即：

> 培训不会生成新的 `staff_id`，只改变该员工当前的 `employee_type`

## 5.4 解雇

解雇执行时：

1. 找到目标 `staff_id`
2. 读取其当前 `employee_type`
3. `employee_pool_remaining[current_type] += 1`
4. 从所在 zone 容器移除该 `staff_id`
5. 从 `staff_registry` 删除该员工

---

## 6. usage track 设计

## 6.1 核心语义

`track_id` 代表：

> **这张员工实例当前岗位上的某条能力槽**

它不是跨员工共享的“匿名池”，只是一个能力名字。  
真正的使用记录永远绑定在：

```text
staff_id + track_id
```

上。

## 6.2 统一存储

```text
round_state.staff_usage[staff_id][track_id] = used_units
```

例如：

```text
staff_usage[17]["recruit"] = 2
staff_usage[23]["place_house_or_garden"] = 1
staff_usage[31]["train"] = 2
```

## 6.3 容量不是硬编码计数，而是动态解析

每条轨道容量建议通过统一解析器计算：

- 基础值来自当前 `employee_type`
- 再叠加：
	- 里程碑
	- 模块效果
	- multiplier
	- 当前阶段特殊规则

统一接口建议类似：

- `get_staff_track_capacity(state, player_id, staff_id, track_id)`
- `get_staff_track_used(state, staff_id, track_id)`
- `get_staff_track_remaining(...)`
- `consume_staff_track_units(...)`

## 6.4 典型轨道示例

| 员工类型 | 轨道 | 支持动作 | 说明 |
|---|---|---|---|
| `recruiting_girl` | `recruit` | `recruit` | 容量较低 |
| `hr_manager` | `recruit` | `recruit` | 容量高；剩余能力可参与工资相关规则 |
| `hr_director` | `recruit` | `recruit` | 容量更高；规则语义独立于招聘专员 |
| `trainer` / `training_guide` / `training_expert` | `train` | `train` | 容量决定一次可跨几步 |
| `new_business_developer` | `place_house_or_garden` | `place_house` / `add_garden` | 同一员工卡共享一条放置轨道 |
| `regional_manager` | `place_or_move_restaurant` | `place_restaurant` / `move_restaurant` | 共享同一张卡上的餐厅轨道 |

> 说明：  
> `track_id` 可以在不同员工类型上同名（例如都叫 `recruit`），但使用记录仍然是按 `staff_id` 分开的，不会变成“共享次数池”。

---

## 7. 员工选择与确定性规则

## 7.1 原则

最终的员工驱动动作，应优先显式携带：

```text
staff_id
```

而不是只携带 `employee_type`。

## 7.2 自动选择最小 `staff_id` 的适用范围

只有当候选员工在当前动作语义上**等价**时，才允许 fallback 为最小 `staff_id`。

### 允许自动选择的典型情况

- 多个完全等价的 `new_business_developer`
- 多个完全等价的 waitress/fire 候选
- 只有一个合法 staff 候选

### 不应自动选择的典型情况

- `recruiting_girl`、`hr_manager`、`hr_director` 同时可用于招聘
- 不同 trainer 剩余训练额度不同
- 同类型员工在当前回合剩余能力不同

这类情况必须由 UI 显式选 staff。

## 7.3 解雇的默认规则

若解雇命令只指定类型、不指定 `staff_id`，则：

1. 先限定合法解雇候选集合
2. 在该集合中筛出对应 `employee_type`
3. 选择最小 `staff_id`

---

## 8. 培训系统（最终规则版）

## 8.1 培训限制：按“回合内培训事件次数”

目标员工的限制不是“终身只能被培训一次”，而是：

> **默认每回合同一个 `staff_id` 最多被培训 1 次**

统一存储：

```text
round_state.staff_train_event_counts[target_staff_id] = count
```

### 默认

- `allowed_train_events_per_round = 1`

### 扩展/里程碑

- 可以提高为 `2+`

校验接口建议：

- `get_allowed_train_events_per_round(state, player_id, target_staff_id)`

## 8.2 跳级培训

培训指导员 / 培训专家等员工允许一次动作直接跳到更远目标：

- 对目标员工：只算 **1 次培训事件**
- 对 trainer：按路径长度消耗相应额度

例如：

```text
management_trainee -> new_business_developer -> junior_vice_president
```

若一次直接从 `management_trainee` 到 `junior_vice_president`：

- `target_staff_id` 的培训事件计数 `+1`
- `trainer_staff_id` 的 `train` 轨道消耗 `2`

## 8.3 路径选择

当前规则中默认不会出现多条培训路径。  
若未来出现：

1. 使用**最短路径**
2. 若有多条同长度最短路径，再按 `train_to` 定义顺序做 tie-break

## 8.4 库存检查

已确认规则：

> 跳级培训只检查**最终目标员工类型**是否有货  
> 不检查中间类型是否缺货

因此：

- `steps_used` 来自完整路径长度
- 但库存校验只看 `to_type`

## 8.5 执行更新

假设：

- `trainer_staff_id = 7`
- `target_staff_id = 18`
- `from_type = management_trainee`
- `to_type = junior_vice_president`
- `steps_used = 2`

则执行：

1. `employee_pool_remaining[management_trainee] += 1`
2. `employee_pool_remaining[junior_vice_president] -= 1`
3. `staff_registry[18].employee_type = "junior_vice_president"`
4. `round_state.staff_train_event_counts[18] += 1`
5. `round_state.staff_usage[7]["train"] += 2`

## 8.6 训练命令 / 事件建议记录

为保证 replay / 日志稳定，建议显式记录：

- `trainer_staff_id`
- `target_staff_id`
- `from_type`
- `to_type`
- `path`
- `steps_used`

---

## 9. 统一动作面板方案

## 9.1 统一交互骨架

所有员工驱动的动作面板统一为：

1. **顶部：员工选择**
2. **中部：当前员工的动作/效果/剩余次数**
3. **底部：确认 / 跳过**

不再以“动作列表优先”组织员工能力。

## 9.2 统一目标

优先统一以下面板：

1. 招聘
2. 培训
3. 放置房屋 / 添加花园
4. 放置 / 移动餐厅

后续再扩展到：

- 生产
- 采购
- 营销

## 9.3 培训面板

### 顶部

显示可用 trainer staff 列表（不显示原始 `staff_id`）。

### 中部

显示当前 trainer 的：

- 剩余训练额度
- 可训练的目标员工
- 每个目标员工在当前额度内“最终可达的目标类型”
- 对应 `steps_used`

> 当前 UI 中已具备“显示被培训员工在最大允许培训次数内的培训选择”的基础思路，可优先复用，只需要把它收口到“当前选中 trainer staff”的上下文中。

## 9.4 招聘面板

### 顶部

显示可用招聘 staff（招聘专员 / HR manager / HR director 等）。

### 中部

只显示当前 staff 的：

- 招聘能力
- 剩余额度
- 可招目标
- 工资相关说明

从而避免把不同招聘员工的效果混在一起。

## 9.5 房屋 / 花园面板

### 顶部

选择 `new_business_developer` staff

### 中部

在该员工上下文中切换：

- 放置房屋
- 添加花园

两者共享同一张员工卡上的同一条轨道。

## 9.6 餐厅面板

### 顶部

选择经理 staff

### 中部

根据当前 staff 类型展示：

- 仅可放置餐厅
或
- 可放置 / 移动餐厅

---

## 10. 对自动推进的影响

自动推进不再依赖零散的 `*_counts` 或局部 UI 推断，而是统一判断：

> 当前子阶段，是否还存在任意一个 `staff_id` 的任意一条合法轨道，可驱动一个真实动作

若不存在：

- 自动推进到下一个子阶段

这能直接覆盖当前房屋/花园类问题：

- 员工已用却仍显示可用
- 已无可用员工却未自动推进

---

## 11. 迁移建议（分阶段）

## Phase 1：建立 `staff_id` 基础层

- 新增 `state.next_staff_id`
- 玩家侧新增 `staff_registry`
- 起始员工生成 `staff_id`
- 招聘创建 `staff_id`
- 解雇删除 `staff_id`

## Phase 2：先改招聘 / 培训 / 解雇

- recruit / train / fire 改为以 `staff_id` 为核心
- 培训改为：
	- 目标员工按回合内事件次数限制
	- trainer 按额度消耗
	- 跳级按最终目标库存校验

## Phase 3：引入 `staff_usage` 与轨道解析器

优先接入：

- 放置房屋 / 添加花园
- 放置 / 移动餐厅
- 招聘
- 培训

## Phase 4：统一动作面板壳层

把上面四类面板统一到：

- 上方选 staff
- 下方看动作/效果

## Phase 5：再扩展到生产 / 采购 / 营销

将所有员工驱动动作统一收口到：

- `staff_id`
- `usage track`
- `staff_selection_resolver`

---

## 12. 与旧存档 / 旧逻辑的兼容性建议

## 12.1 旧存档迁移

旧存档大概率没有 `staff_id`。迁移时可：

- 按稳定顺序扫描当前玩家已有员工
- 为现有员工生成 `staff_id`
- 当缺少 `round_state.staff_train_event_counts` 时，初始化为空

> 由于培训限制已确认为“按回合事件次数”，旧存档迁移比“终身训练历史”模型要简单很多；不需要恢复不可追溯的长期训练历史。

## 12.2 旧计数的兼容

当前已有的：

- `production_counts`
- `procurement_counts`
- `marketing_used`
- `house_placement_counts`
- 其它按 `employee_type` 粗粒度追踪的字段

建议分阶段迁移，不要一次性移除。  
短期内可保留为兼容镜像；长期统一到：

- `staff_usage`
- `staff_train_event_counts`

---

## 13. 非目标 / 明确不做

本方案明确**不做**以下事情：

- 不引入 `card_id`
- 不追踪物理卡流转历史
- 不在 UI 中显示原始 `staff_id`
- 不要求跳级培训中间类型库存合法
- 不把“跨员工共享的匿名动作池”作为核心规则模型

---

## 14. 最终结论

本方案的最终核心是：

1. **员工池只按类型记剩余数量**
2. **玩家员工统一为 `staff_id` 运行时实体**
3. **规则连续性围绕 `staff_id` 建模**
4. **员工使用统一为 `staff_id + usage track + used_units`**
5. **培训限制按“回合内培训事件次数”追踪**
6. **跳级培训算 1 次事件，但按路径长度消耗 trainer 额度**
7. **动作面板统一为“先选员工，再看该员工动作/效果”**

这是当前讨论下最贴合规则、最容易统一代码路径、也最适合渐进落地的方案。
