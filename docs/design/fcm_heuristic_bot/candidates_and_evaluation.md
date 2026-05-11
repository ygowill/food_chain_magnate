# 启发式人机对手：候选生成与评价函数

本文聚焦候选生成规则、各阶段动作候选和评价函数设计。

## 9. 候选生成

### 9.1 通用规则

候选生成器输出 `MacroAction`：

```gdscript
{
	"id": "human_readable_id",
	"commands": [Command],
	"prior_score": 0.0,
	"tags": [],
	"debug": {},
}
```

首版每个 `MacroAction` 通常只含一个命令。公司结构是例外：一个结构候选应展开为多条 internal 编辑命令，再以 `submit_restructuring` 结束，不能绕过命令系统直接写真实状态。

所有候选必须：

- 数量有限。
- 有 deterministic 排序。
- validate 后再进入搜索。
- 记录丢弃原因，便于调试。

### 9.2 储备卡选择

当前 action：

```gdscript
Command.create("select_reserve_card", player_id, {"selected_index": i})
```

启发式：

- 优先选择能延长 bank clock 且不破坏早期现金节奏的卡。
- 严格隐藏信息下，只能看自己的 reserve cards。
- 若有 `can_peek_all_reserve_cards`，ObservationAdapter 可提供对手选择信息。

### 9.3 初始餐厅放置

当前 action：

```gdscript
Command.create("place_restaurant", player_id, {
	"position": Vector2i(x, y),
	"rotation": rotation,
})
```

候选评分：

- 附近早号房价值。
- 未来 billboard/mailbox/radio 位置。
- 饮料路线起点价值。
- 距离对手优势。
- 后续扩张空间。
- 入口 tile 冲突风险。

保留未来 pass 接口：

```gdscript
{
	"type": "initial_restaurant_pass",
	"enabled": false,
}
```

在当前引擎未支持初始餐厅 pass 前，该候选必须禁用。

### 9.4 公司结构

当前 `submit_restructuring` 不从 command params 接收结构，而是读取：

`player.company_structure.structure`

因此 AI 真实执行时应生成如下命令序列：

1. 用 `restructure_employee` 把不需要上班的员工移到待命。
2. 用 `set_company_structure_direct` 设置 CEO 直属槽。
3. 用 `set_company_structure_report` 设置经理下属。
4. 用 `submit_restructuring` 提交。

这些编辑 action 是 internal action，但仍是正式命令。AI 只允许在自己的 Restructuring 决策中使用它们。

结构格式：

```gdscript
{
	"ceo_slots": 3,
	"structure": [
		{"employee_id": "trainer", "reports": ["management_trainee"]},
		{"employee_id": "", "reports": []},
		{"employee_id": "pricing_manager", "reports": []},
	]
}
```

提交时当前实现会 normalize/prune：

- CEO 自动纠正回在岗。
- 未知员工移除。
- 数量不足的重复员工移除。
- 经理不能作为下属。
- 超过 manager capacity 的下属移除。
- 未放入结构的员工进入 reserve。

Bot 不能依赖“非法结构会原样失败”。候选生成必须先用当前公司结构规则预校验，避免被 prune 后行为和评分不一致。

当前结构评价已经把泛员工本体分单独降权，避免 `recruiting_girl` 这类边际直改长期压过 `submit_restructuring`；但像 `kitchen_trainee`、`pricing_manager` 这类能打开食品供给、价格恢复或 waitress 路线的结构动作，仍然保留完整的路线增益分。

### 9.5 Order of Business

当前选择顺序由 `WorkingFlow.start_order_of_business()` 计算：

- 空位多的玩家先选。
- 空位相同按上一轮 turn order 打破平局。
- `first_airplane` 的 `turnorder_empty_slots` 会增加空位计数。

选择命令：

```gdscript
Command.create("choose_turn_order", player_id, {"position": slot})
```

评分：

- 本轮关键稀缺动作是否要抢先。
- Dinnertime 平局是否需要更早 turn order。
- 是否需要靠后观察对手。
- 是否要避免先服务高需求导致库存被过早消耗。

### 9.6 Working 子阶段

Recruit：

- `recruit` 候选来自员工池、现金、当前结构需求、里程碑竞速。
- 第三次 recruit 触发 `first_hire_3` 的逻辑应通过真实事件系统判断。

Train：

- `train` 只能沿员工定义 `train_to` 路径。
- coach/guru 多步、培训锁、`multi_trainer_on_one`、`train_from_active_same_color` 都由当前 executor 管。
- 候选生成只生成少量目标路径，并依赖 validate 筛选。

Marketing：

- `initiate_marketing` 必须满足 board spec、range、位置合法性。
- 首版只支持 base marketing。
- 广告评分要考虑未来数轮收益和是否帮对手。

GetFood：

- `produce_food` 根据员工定义生产。
- kitchen trainee 等需要 `food_type` 的员工要生成多个候选。

GetDrinks：

- Errand Boy 按当前已对齐的规则处理。
- route-based 员工由 `DrinkRouteAnalyzer` 生成 topK 合法路线。

PlaceHouses：

- `place_house` 使用当前房屋供应号。
- 当前新房 action 放的是 `house_with_garden`，即新房自带花园。
- `add_garden` 与 `place_house` 共享房屋/花园放置计数，需要通过 action count 校验。

PlaceRestaurants：

- `local_manager` 放置 `opening_soon` 餐厅，Cleanup 才正式开业。
- `regional_manager` 可立即放/移餐厅。
- `place_restaurant` 与 `move_restaurant` 共享使用次数。

### 9.7 Payday 与裁员

薪资结算入口是 `modules/base_rules/rules/phase/payday_settlement.gd`。Bot 不应使用简化公式。

当前薪资因素：

- `state.rules["salary_cost"]`
- `salary_cost_override`
- `EmployeeRules.count_paid_employees(player)`
- 招聘经理/HR 未使用招聘折扣。
- `salary_total_delta` 里程碑。
- 可选 `salary_pay_with_tokens`
- 可选 `salary_allow_unpaid`

裁员 action：

```gdscript
Command.create("fire", player_id, {
	"employee_id": employee_id,
	"location": "active",
	"staff_id": staff_id,
})
```

Bot 裁员策略：

- 优先保留能产生本轮或下轮现金的员工。
- 忙碌市场人员通常不能裁，除非满足当前 executor 的特殊条件。
- 现金危机时用 fork engine 验证裁员序列能通过 Payday。

### 9.8 Cleanup

Cleanup 相关真实逻辑：

- `choose_fridge_keep`
- `CleanupSettlement.apply_opening_soon_restaurants`
- `CleanupSettlement.apply_cleanup_milestones`

Bot 需要处理：

- 冰箱容量来自 `gain_fridge` 里程碑。
- `keep` 字典总数不得超过容量。
- 同回合获得的里程碑在 Cleanup 从 `milestone_pool` 移除。
- `expires_at` 里程碑会在 Cleanup 清理。
- `opening_soon_restaurants` 在 Cleanup 正式写入 `state.map.restaurants`。


## 10. 评价函数

首版 `Evaluator` 采用线性特征即可：

```text
score =
  cash_value
  + expected_dinner_income
  + inventory_value
  + employee_value
  + milestone_value
  + map_position_value
  + marketing_pipeline_value
  + turn_order_value
  - salary_risk
  - bank_clock_risk
  - hidden_info_risk
```

特征必须从 `ObservationState` 与 simulation result 提取，不得越过隐藏信息边界读取真实对手结构/储备卡。

关键 feature：

- 当前现金与预计发薪后现金。
- 下一次 Dinnertime 可服务房屋数。
- 能否抢到关键里程碑。
- 是否有足够厨师/采购/市场/培训链条。
- 广告是否主要给自己创造需求。
- 对手在 belief 样本下可反抢的概率。
- bank 离破产还有多少现金。
