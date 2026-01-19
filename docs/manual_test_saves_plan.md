# 手工复核用存档生成计划（员工 / 里程碑）

本文档用于评审：如何为**当前仓库内容**中的每一个员工与里程碑生成一份“测试用存档”（JSON archive），方便你在 UI 中载入并手工复核功能是否正常。测试点尽量对齐现有单元测试（`core/tests/*_test.gd`）。

---

## 1. 目标与范围

### 1.1 目标

- 为 `modules/*/content/employees/*.json` 中的**每一个员工**生成至少 1 份可载入存档。
- 为 `modules/*/content/milestones/*.json` 中的**每一个里程碑**生成至少 1 份可载入存档。
- 每份存档应满足：
	- **可手工复核**：载入后在 1～3 个明确步骤内即可触发/观察目标行为。
	- **尽量确定性**：固定 seed、固定模块计划、固定回合/阶段定位。
	- **可回归维护**：生成逻辑可脚本化，避免手工编辑 JSON。

### 1.2 非目标（第一版先不做）

- 不追求“完全覆盖所有 UI 交互细节/动画表现”。重点是规则与状态变化可复核。
- 不把这些存档作为自动化 CI 的唯一保障（但会提供加载/冒烟校验）。
- 不对未实现/定义不清的员工文本描述做“推测实现”；若行为在代码中尚无落点，会在测试点里标注“待确认/待补齐实现”。

---

## 2. 交付物与目录约定

### 2.1 存档输出目录

建议新增目录（放在仓库内，便于分享与版本管理）：

- `/.savings/manual_cases/`
	- `/.savings/manual_cases/employees/`：员工存档
	- `/.savings/manual_cases/milestones/`：里程碑存档

说明：

- 当前项目已有 `/.savings/234.json` 可作为存档样例；主菜单“文件”页可以加载任意路径 JSON，因此放在仓库目录内可直接选取。

### 2.2 命名规范

- 员工存档：`/.savings/manual_cases/employees/<employee_id>.json`
- 里程碑存档：`/.savings/manual_cases/milestones/<milestone_id>.json`
-（可选但强烈建议）同名说明文件：`<id>.md`
	- 例如：`/.savings/manual_cases/employees/marketing_trainee.md`
	- 内容：复核步骤（Step-by-step）、预期结果、可观察字段（cash/inventory/round_state/marketing_instances 等）、关联单测。

### 2.3 生成脚本（建议）

为保证可维护与可重复生成，建议新增：

- `tools/generate_manual_test_saves.gd`
	- 通过 Godot CLI 运行：`godot --headless --path . --script res://tools/generate_manual_test_saves.gd`
	- 负责：按“场景清单”批量生成 JSON 存档到 `/.savings/manual_cases/`
- `tools/generate_manual_test_saves_manifest.gd`（或 `.json`）
	- 负责：声明每个场景的参数（模块列表/玩家数/seed/构造函数/输出文件名/说明文本）
-（可选）`tools/verify_manual_test_saves.gd`
	- 负责：逐个加载生成的存档，并做最基本的 fail-fast 校验（能 load、schema 匹配、关键字段存在、必要 registries 初始化完成等）。

---

## 3. 存档生成策略（核心思路）

### 3.1 存档格式与加载路径（现状确认）

- 存档由 `GameEngine.save_to_file(path)` 写入（见 `core/engine/game_engine.gd`、`core/engine/game_engine/archive.gd`）。
- 主菜单载入调用 `GameEngine.load_from_file(path)`（见 `ui/scenes/menus/main_menu.gd`），因此存档必须是“archive JSON”，包含：
	- `schema_version / initial_state / commands / checkpoints / rng / modules_v2_base_dir / current_index / final_hash` 等字段。

### 3.2 “场景构造”优先级

为了降低“存档数据与运行时规则不一致”的风险，构造状态建议遵循以下优先级：

1. **优先通过命令系统构造**：使用 `engine.execute_command(Command.create(...))`，让 action/validator 走同一条路径。
2. **必要时才直接改 state**：例如某些测试为了避免 UI 交互，直接注入 map/houses/marketing_instances（参考现有单测写法），但需要同步做：
	- `RoadGraphCache.invalidate_road_graph(state)`（当道路/地图结构变更影响路径计算时）
	- 补齐 `state.round_state` 必需字段（例如某些 phase 依赖）

### 3.3 通用“存档就绪态”规范（建议统一）

每个存档生成时，尽量满足：

- **玩家数**：默认 2 人局；确实需要时再用 3/4 人局（例如 Coffee route purchase 的 3 人局测试）。
- **当前行动者**：固定为玩家 0（`state.turn_order=[0,1,...]` 且 `state.current_player_index=0`）。
- **阶段/子阶段**：定位到能直接执行目标动作的阶段，例如：
	- `Working/Recruit`：测试招聘相关员工/里程碑
	- `Working/Train`：测试培训链/培训次数/在岗培训（first_lemonade_sold）
	- `Working/GetFood`：测试厨师生产
	- `Working/GetDrinks`：测试采购
	- `Working/Marketing`：测试营销发起与营销相关里程碑
	- `Working/PlaceHouses` / `Working/PlaceRestaurants`：测试建房/开店/搬店（含里程碑）
	- `Payday`、`Dinnertime`、`Cleanup`：测试结算/被动效果/触发里程碑
- **减少噪音**：除测试目标外，尽量不要额外注入复杂模块/状态。

### 3.4 生成后校验（建议至少做到）

每个存档生成后立即做一次“自举校验”，避免生成坏档：

- 新建一个 `GameEngine`，调用 `load_from_file(刚写出的文件)`，确保能成功加载。
-（可选）调用 `engine.verify_checkpoints()`。
-（可选）检查目标动作“理论可执行”（例如 action.can_initiate 为 true，或 UI 面板中应出现对应 action）。

---

## 4. 手工复核工作流（给测试人员）

### 4.1 载入方式

- 进入主菜单 → “载入游戏” → 切到 “文件” 页签 → 选择 `/.savings/manual_cases/.../*.json`。

### 4.2 推荐配合 DebugPanel

游戏内已有 DebugPanel 与若干命令（见 `core/debug/debug_commands/state_commands.gd`），用于快速观察状态：

- `state`：回合/阶段/当前玩家/银行/命令数/哈希摘要
- `players` / `player <id>`：现金、在岗员工、手牌/待命、忙碌营销员
- `marketing_list`：当前营销实例（board_number、duration、owner 等）

建议每个存档说明文件（`*.md`）都写清楚：

- 复核步骤（按键/动作）
- 复核前/后的关键字段（cash、inventory、milestones、round_state.*、marketing_instances 等）
- 若依赖 DebugPanel：明确要执行的命令与预期输出关键字

---

## 5. 员工清单与测试点（全部）

说明：

- “测试点”尽量以“可观察结果”描述；并附上对齐的单测文件，便于追根溯源。
- 若某员工当前缺少对应单测，会标注“现有单测覆盖：无/不足”，并给出建议的存档测试点（基于数据定义与规则代码）。

### 5.1 base_employees（基础员工）

#### ceo（CEO）

- 核心行为/约束：
	- 起始员工；`unique=true`；不可解雇（`can_be_fired=false`）。
	- 提供招聘次数：`recruit_capacity=1`（影响 Recruit 上限）。
	- 提供 CEO 卡槽（公司结构）。
- 存档建议定位：
	- `Working/Recruit`：验证“无招聘员时仅 1 次招聘”。
	- `Restructuring`：验证 CEO 卡槽/公司结构限制。
- 手工测试点：
	- 仅有 CEO 时：本回合只能成功执行 1 次 `recruit`，第二次应被拒绝。
	- 试图解雇 CEO：应失败/按钮不可用。
- 参考单测：
	- `core/tests/employee_action_test.gd`
	- `core/tests/company_structure_test.gd`

#### waitress（服务员）

- 核心行为/约束：
	- `mandatory=true` 但 `mandatory_action_id=""`（自动应用，无需强制动作）。
	- 结算效果：晚餐小费与平局胜负（effect_ids：`base_rules:dinnertime:tips:waitress`、`base_rules:dinnertime:tiebreaker:waitress`）。
- 存档建议定位：
	- `Dinnertime`：可立即跑一轮晚餐结算，观察 tips 与 tiebreak。
- 手工测试点：
	- 晚餐结算后：现金应包含 waitress tips（默认 `rules.waitress_tips=3`），且 UseEmployee(wai­tress) 事件应被触发（里程碑依赖点）。
	- 平局链路：在“服务员数量/或 waitress tie-break”相关场景下，胜负应符合规则。
- 参考单测：
	- `core/tests/dinnertime_settlement_test.gd`
	- `core/tests/movie_stars_v2_test.gd`（与 movie_star tie-break 关系）
	- `core/tests/effect_registry_v2_test.gd`

#### cfo（首席财务官）

- 核心行为/约束：
	- `mandatory=true` 且自动应用；`unique=true`；提供晚餐收入加成（effect_ids：`base_rules:dinnertime:income_bonus:cfo`）。
- 存档建议定位：
	- `Dinnertime`：构造“能卖出 1 个房屋”的局面，观察收入额外 +50%（取整规则见实现）。
- 手工测试点：
	- 卖出产生 base_gain 后，CFO 应让收入额外增加（默认配置 `cfo_bonus_percent=50`）。
- 参考单测：
	- `core/tests/dinnertime_settlement_test.gd`
	- `core/tests/milestone_system_test.gd`（first_have_100 的 CEO 获得 CFO 能力是另一条路径）

#### pricing_manager（定价经理）

- 核心行为/约束：
	- `mandatory=true` 且 `mandatory_action_id="set_price"`：必须执行强制动作才能离开 Working。
	- 效果：基础单价 -$1（见 set_price 动作与价格管线）。
- 存档建议定位：
	- `Working`（任意子阶段）：突出 mandatory action 面板与阻塞逻辑。
- 手工测试点：
	- 若在岗 pricing_manager：本回合必须执行 `set_price`；否则结束回合/离开 Working 应失败。
	- 执行后：`round_state.price_modifiers[player_id][pricing_manager] == -1`（或等价可视化）。
- 参考单测：
	- `core/tests/mandatory_actions_test.gd`
	- `core/tests/milestone_system_test.gd`（触发 `first_lower_prices`）

#### discount_manager（折扣经理）

- 核心行为/约束：
	- `mandatory_action_id="set_discount"`：必须执行强制动作。
	- 效果：基础单价 -$3；并可能触发里程碑 `first_discount_manager_used`（new_milestones）。
- 存档建议定位：
	- `Working`：让玩家 0 在岗 discount_manager，直接点 `set_discount`。
- 手工测试点：
	- mandatory 校验同 pricing_manager。
	- `set_discount` 后：`round_state.price_modifiers[player_id][discount_manager] == -3`。
	- 启用 `new_milestones` 时：第一次 `set_discount` 应获得里程碑并在下回合扣银行 $100。
- 参考单测：
	- `core/tests/mandatory_actions_test.gd`
	- `core/tests/new_milestones_discount_manager_bank_burn_v2_test.gd`

#### luxury_manager（奢侈品经理）

- 核心行为/约束：
	- `mandatory_action_id="set_luxury_price"`：必须执行强制动作。
	- 效果：售价 +$10（定价管线/晚餐结算相关）。
- 存档建议定位：
	- `Working`：突出 mandatory action。
	-（可选）`Dinnertime`：构造卖出房屋，验证价格提升。
- 手工测试点：
	- 执行 `set_luxury_price` 后应能观察到价格提升（cash 或价格显示）。
- 参考单测：
	- `core/tests/mandatory_actions_test.gd`
	- `core/tests/noodles_sushi_v2_test.gd`（该模块会 patch luxury_manager 供应数量）

#### recruiting_girl（人力资源专员）

- 核心行为/约束：
	- `recruit_capacity=1`；`entry_level`；提供额外 1 次招聘。
	- 与 `night_shift_managers`、`new_milestones` 有联动（倍数/里程碑）。
- 存档建议定位：
	- `Working/Recruit`：玩家 0 在岗 recruiting_girl，验证招聘上限与里程碑触发。
- 手工测试点：
	- 招聘上限：CEO(1) + recruiting_girl(1) = 2（未启用 night_shift_managers）。
	- 启用 `new_milestones`：当本回合招聘次数用到 recruiting_girl 的容量（例如招 2 人）时，应获得里程碑 `first_recruiting_girl_used` 并获得 `executive_vice_president`（且永久免薪）。
- 参考单测：
	- `core/tests/employee_action_test.gd`
	- `core/tests/new_milestones_recruiter_waitress_v2_test.gd`
	- `core/tests/night_shift_managers_v2_test.gd`

#### recruiting_manager（人力资源经理）

- 核心行为/约束：
	- `mandatory=true`（自动应用）；`recruit_capacity=2`；`salary_discount`（effect_ids：`base_rules:payday:salary_discount:recruiting_manager`）。
- 存档建议定位：
	- `Working/Recruit`：验证招聘上限提升（CEO +2）。
	- `Payday`：验证“未用完招聘次数→薪资折扣”生效。
- 手工测试点：
	- 招聘上限应为 3（CEO 1 + recruiting_manager 2）。
	- Payday：若本回合只招 1 人，则 recruiting_manager 的 2 次折扣动作应全部“未使用”，薪资应减少 $10（每次 $5）。
- 现有单测覆盖：无（建议补齐或用存档重点验证）。

#### hr_director（人力资源总监）

- 核心行为/约束：
	- `mandatory=true`（自动应用）；`unique=true`；`recruit_capacity=4`；`salary_discount`（effect_ids：`base_rules:payday:salary_discount:hr_director`）。
- 存档建议定位：
	- `Working/Recruit`：用于触发 `first_hire_3`（一回合雇佣三人）。
	- `Payday`：用于验证薪资折扣。
- 手工测试点：
	- Recruit：连续招聘 3 人后，应获得 `first_hire_3` 并得到 2 张 `management_trainee` 到 reserve。
	- Payday：验证未使用的 hr_director 招聘次数转化为薪资折扣。
- 参考单测：
	- `core/tests/milestone_system_test.gd`
	- `core/tests/payday_salary_test.gd`

#### trainer（培训讲师）

- 核心行为/约束：
	- `train_capacity=1`；`use:train`。
	- 与里程碑 `first_train`、`first_trainer_used`（new_milestones）关联。
- 存档建议定位：
	- `Working/Train`：玩家 0 在岗 trainer，待命区有可培训对象与目标。
- 手工测试点：
	- Train 子阶段：有 trainer 时应允许至少 1 次培训；无 trainer 时应不允许进入/执行 train。
	- 启用 `new_milestones`：触发 `UseEmployee/trainer` 后（通常发生在训练事件推导中），应获得 `first_trainer_used`，并允许欠薪离开 Payday。
- 参考单测：
	- `core/tests/milestone_system_test.gd`（first_train）
	- `core/tests/new_milestones_beer_trainer_payday_v2_test.gd`（first_trainer_used）

#### coach（培训指导员）

- 核心行为/约束：`train_capacity=2`。
- 存档建议定位：
	- `Working/Train`：验证可执行 2 次培训。
- 手工测试点：
	- Train 子阶段允许 2 次 train（用尽后应拒绝第 3 次）。
- 参考单测：
	- `core/tests/coffee_v2_test.gd`（使用 coach 提供 Train 容量）

#### guru（培训专家）

- 核心行为/约束：`unique=true`；`train_capacity=3`。
- 存档建议定位：
	- `Working/Train`：验证可执行 3 次培训。
- 手工测试点：
	- Train 子阶段允许 3 次 train；第 4 次应失败。
	-（可选）结合里程碑 `multi_trainer_on_one`：验证链式培训限制/放开（见 `first_pay_20_salaries` 或 `first_house_built`）。
- 现有单测覆盖：无（建议用存档重点验证）。

#### management_trainee（管理培训生）

- 核心行为/约束：`entry_level`；`manager_slots=2`；培训链到 `new_business_developer / junior_vice_president / luxury_manager`。
- 存档建议定位：
	- `Working/Train`：从 management_trainee 培训到目标岗位，验证公司结构/颜色规则等。
- 手工测试点：
	- 培训后应正确进入待命/在岗（若启用 `first_lemonade_sold` 的在岗同色培训规则，可能直接在岗）。
- 参考单测：
	- `core/tests/milestone_system_test.gd`（first_hire_3 获得 management_trainee）
	- `core/tests/new_milestones_lemonade_sold_v2_test.gd`

#### junior_vice_president（总经理助理）
#### vice_president（副总裁）
#### senior_vice_president（高级副总裁）
#### executive_vice_president（执行副总裁）

（这四类属于“纯公司结构/培训链”的 manager 卡，文本描述为空或很少，主要验证 manager_slots 与 training chain 以及 unique/one_x 供给。）

- 核心行为/约束：
	- 提供不同的 `manager_slots`，影响公司结构可容纳人数。
	- train_to 链：逐级到更高级职位、或分支到功能员工（例如 junior_vp -> discount_manager/recruiting_manager/coach）。
	- executive_vice_president：`unique=true`，大槽位（10）。
- 存档建议定位：
	- `Restructuring`：把这些 manager 放到公司结构中，验证容量与 overflow 处理。
	- `Working/Train`：验证从上一级能否训练到下一级。
- 手工测试点：
	- 放入公司结构后：空槽数变化符合 manager_slots。
	- unique：同一玩家不能同时拥有多张 unique 职位（获得/培训应被拒绝）。
- 参考单测：
	- `core/tests/company_structure_test.gd`
	- `core/tests/restructuring_overflow_penalty_test.gd`
	- `core/tests/new_milestones_recruiter_waitress_v2_test.gd`（EVP 作为里程碑奖励且免薪）

#### local_manager（区域经理）
#### regional_manager（大区经理）

- 核心行为/约束：
	- `role=new_shop`；提供 `place_restaurant`（两者）与 `move_restaurant`（regional_manager）能力。
	- 执行后本回合启用 `drive_thru_active`（Cleanup 重置）。
- 存档建议定位：
	- `Working/PlaceRestaurants`：可直接放置/移动餐厅并观察 drive_thru_active。
- 手工测试点：
	- local_manager：放置新餐厅应成功，并使 `drive_thru_active=true`。
	- regional_manager：移动餐厅应成功，并与 place_restaurant 共享次数限制。
- 参考单测：
	- `core/tests/place_restaurant_rules_test.gd`
	- `core/tests/move_restaurant_rules_test.gd`
	- `core/tests/new_milestones_new_restaurant_v2_test.gd`（触发 first_new_restaurant）

#### new_business_developer（新业务拓展经理）

- 核心行为/约束：
	- `use:place_house`、`use:add_garden` 两类动作（建房/加花园）。
- 存档建议定位：
	- `Working/PlaceHouses`：先放房屋，再加花园。
- 手工测试点：
	- place_house 可用；add_garden 需对有效 house_id 与方向生效。
- 参考单测：
	- `core/tests/place_house_rules_test.gd`
	- `core/tests/add_garden_rules_test.gd`

#### kitchen_trainee（见习厨师）

- 核心行为/约束：
	- 多选生产：需显式指定 `food_type`（burger/pizza），每次产量 1。
- 存档建议定位：
	- `Working/GetFood`：在岗 kitchen_trainee，UI 允许选择生产 burger 或 pizza。
- 手工测试点：
	- 生产 burger：库存 burger +1；生产 pizza：库存 pizza +1。
	- 同一回合次数限制：每张在岗卡每子阶段一次。
- 参考单测：
	- `core/tests/produce_food_test.gd`

#### burger_cook（汉堡厨师）/ burger_chef（汉堡主厨）
#### pizza_cook（披萨厨师）/ pizza_chef（披萨主厨）

- 核心行为/约束：
	- 固定产量生产（cook=3，chef=8）；chef 多为 unique/one_x。
- 存档建议定位：
	- `Working/GetFood`：在岗对应厨师，执行 produce_food。
- 手工测试点：
	- produce_food 后库存增加符合 amount。
	- `first_burger_produced` / `first_pizza_produced` 里程碑触发（base_milestones）。
- 参考单测：
	- `core/tests/produce_food_test.gd`
	- `core/tests/milestone_system_test.gd`（burger produced）
	- `core/tests/new_milestones_lemonade_sold_v2_test.gd`（pizza_cook->pizza_chef 训练行为）

#### errand_boy（跑腿伙计）

- 核心行为/约束：
	- 特殊采购：直接获得 1 瓶指定饮料（需要参数 drink_type）。
- 存档建议定位：
	- `Working/GetDrinks`：在岗 errand_boy，库存初始为 0，点一次采购。
- 手工测试点：
	- 选择 drink_type=soda：库存 soda +1。
	- 触发 base_milestones `first_errand_boy` 后，后续采购每源 +1（procure_plus_one）。
- 参考单测：
	- `core/tests/procure_drinks_route_rules_test.gd`

#### cart_operator（手推车操作员）/ truck_driver（货车驾驶员）/ zeppelin_pilot（飞艇驾驶员）

- 核心行为/约束：
	- 路线采购：按路线每个来源获得固定数量饮料；range 不同（road/air）。
	- UseEmployee 触发里程碑：base_milestones `first_cart_operator`（distance+1）；new_milestones `first_cart_operator_used`（每源数量提升）。
- 存档建议定位：
	- `Working/GetDrinks`：预置可用餐厅、饮料来源、以及一条“边界路线”，方便观察距离规则变化。
- 手工测试点：
	- 无里程碑时：超范围路线应被拒绝；有 `distance_plus_one` 后应允许。
	- 触发 `first_cart_operator_used` 后：每源获得数量应按 targets 变化（truck_driver 更大增量）。
- 参考单测：
	- `core/tests/procure_drinks_test.gd`
	- `core/tests/procure_drinks_route_rules_test.gd`

#### marketing_trainee（营销实习生）
#### campaign_manager（营销经理）
#### brand_manager（品牌经理）
#### brand_director（品牌总监）

- 核心行为/约束：
	- `initiate_marketing`（billboard/mailbox/airplane/radio 取决于 usage_tags 与 max_duration）。
	- 与 base_milestones/new_milestones 多里程碑强相关（first_billboard/first_radio/first_marketing_trainee_used/first_campaign_manager_used/first_brand_manager_used/first_brand_director_used/first_marketeer_used 等）。
- 存档建议定位：
	- `Working/Marketing`：地图上预留可合法放置点，且玩家 0 拥有餐厅。
- 手工测试点（按员工分）：
	- marketing_trainee：放置 billboard -> 触发 `first_billboard`（base_milestones）与 `first_marketing_trainee_used`（new_milestones，赠卡）。
	- campaign_manager：放置 mailbox -> 触发 `first_campaign_manager_used`，同回合允许额外放置第二张同类型板件（并验证 busy_marketers 释放时机）。
	- brand_manager：放置 airplane -> 触发 `first_brand_manager_used`，同回合允许设置第二种商品（A→B 顺序结算）。
	- brand_director：放置任意营销 -> 触发 `first_brand_director_used`；之后你放置的 radio 永久；且 brand_director 永久忙碌不回手。
- 参考单测：
	- `core/tests/marketing_campaigns_test.gd`（first_billboard、first_radio 等）
	- `core/tests/new_milestones_marketing_trainee_v2_test.gd`
	- `core/tests/new_milestones_campaign_manager_v2_test.gd`
	- `core/tests/new_milestones_brand_manager_v2_test.gd`
	- `core/tests/new_milestones_brand_director_v2_test.gd`
	- `core/tests/new_milestones_v2_test.gd`（first_marketeer_used effect_ids）

---

### 5.2 coffee（咖啡模块员工）

#### barista_trainee（咖啡学徒）/ barista（咖啡师）/ lead_barista（首席咖啡师）

- 核心行为/约束：
	- produce_food：分别生产 coffee 1/2/5。
	- 培训链：barista_trainee -> barista -> lead_barista。
- 存档建议定位：
	- `Working/GetFood`：验证 coffee 生产。
	- `Working/Train`：验证培训链。
- 手工测试点：
	- produce_food 后 coffee 库存增加符合定义。
	- coffee 模块的“培训触发咖啡店动作窗口”属于模块规则，可额外做回归（见单测）。
- 参考单测：
	- `core/tests/coffee_v2_test.gd`

---

### 5.3 fry_chefs（薯条厨师）

#### fry_chef（薯条厨师）

- 核心行为/约束：
	- 晚餐：每成功售卖一个“非饮品 food”的房屋，每个在岗 fry_chef +$10（按房屋计）。
	- 培训链通过 patch 注入到 burger/pizza/noodle/sushi 的 cook。
- 存档建议定位：
	- `Dinnertime`：预置 1 个 food demand 与赢家可售卖路径。
- 手工测试点：
	- 卖 food 房屋：收入额外 +10。
	- 卖 drink 房屋：不应触发 +10。
	- 培训链 patch：相关 cook 的 train_to 应包含 fry_chef（启用模块时）。
- 参考单测：
	- `core/tests/fry_chefs_v2_test.gd`

---

### 5.4 gourmet_food_critics（美食评论家）

#### gourmet_food_critic（美食评论家）

- 核心行为/约束：
	- 发起 gourmet_guide 营销：影响“有花园的房屋”；全局最多 3 个；要求边缘放置；与 rural_offramp 冲突。
	- training chain patch：marketing_trainee.train_to 包含 gourmet_food_critic。
- 存档建议定位：
	- `Working/Marketing`：地图内放置若干 house（含 has_garden true/false），并预置 rural_offramp（可选）。
- 手工测试点：
	- 结算范围：仅 has_garden 的房屋被加入需求。
	- 全局数量上限：第 4 次放置应被拒绝。
	- 与 offramp 同格冲突应被拒绝。
- 参考单测：
	- `core/tests/gourmet_food_critics_v2_test.gd`

---

### 5.5 kimchi（泡菜模块）

#### kimchi_master（泡菜大师）

- 核心行为/约束：
	- Cleanup：丢弃食物后生产 1 个 kimchi，并强制只保留 kimchi（模块规则）。
- 存档建议定位：
	- `Cleanup`：玩家 0 在岗 kimchi_master，库存含 burger/pizza，进入 cleanup 结算即可观察。
- 手工测试点：
	- cleanup 后 kimchi=1，burger/pizza=0；且 `round_state.kimchi.produced` 有记录。
- 参考单测：
	- `core/tests/kimchi_v2_test.gd`

---

### 5.6 lobbyists（说客模块）

#### lobbyist（提案人）

- 核心行为/约束：
	- Working 子阶段插入 Lobbyists；可放置“建设中道路/公园”。
	- 触发里程碑 `first_lobbyist_used` 后，允许立即扩边放置地图 tile（pending）。
- 存档建议定位：
	- `Working/Lobbyists`（子阶段）：玩家 0 在岗 lobbyist，地图预置可放置点与 tile_supply_remaining 非空。
- 手工测试点：
	- 放置 park 或 road 应成功，并触发 `first_lobbyist_used`。
	- 触发后：出现 extra tile pending，能执行扩边放置，且 tile_supply_remaining 消耗。
- 参考单测：
	- `core/tests/lobbyists_v2_test.gd`

---

### 5.7 mass_marketeers（大众营销员）

#### mass_marketeer（大众营销员）

- 核心行为/约束：
	- Marketing 阶段额外结算轮数：`marketing_rounds = 1 + active_count(mass_marketeer)`
- 存档建议定位：
	- `Marketing` 进入点前：玩家 0 在岗 0/1/2 张 mass_marketeer（可做 2 个存档或 1 个存档里包含 2 张）。
- 手工测试点：
	- 进入 Marketing 后，`round_state.marketing_rounds` 应等于 1 + 在岗数量。
- 参考单测：
	- `core/tests/mass_marketeers_v2_test.gd`

---

### 5.8 movie_stars（电影明星）

#### movie_star_b / movie_star_c / movie_star_d

- 核心行为/约束：
	- OrderOfBusiness：拥有在岗 movie_star 的玩家优先选顺序（B>C>D）；剩余按空槽数。
	- Dinnertime：movie_star 作为更高优先级 tiebreaker（B>C>D）。
	- waitress.train_to 被 patch：可培训成 movie_star_b/c/d；且同一玩家只能拥有一种 movie_star（互斥）。
- 存档建议定位：
	- `OrderOfBusiness`：建议用 3 人局更直观（参考单测）。
	- `Dinnertime`：构造平局链路，验证 tiebreak 分数差。
- 手工测试点：
	- OOB 选择顺序：B>C>D 优先级生效。
	- Dinnertime tiebreak：movie_star_b 的加成应最大。
	- 互斥校验：若已有 movie_star_b，再培训到 movie_star_c 应被拒绝。
- 参考单测：
	- `core/tests/movie_stars_v2_test.gd`

---

### 5.9 night_shift_managers（夜班经理）

#### night_shift_manager（夜班经理）

- 核心行为/约束：
	- 在岗 night_shift_manager：你所有“无薪员工”（salary=false）在 Working 的次数翻倍（CEO 排除）。
	- 影响招聘上限/培训上限/生产次数等（通过 working_employee_multipliers）。
- 存档建议定位：
	- `Working/Recruit`：放入 recruiting_girl（无薪）并对比有无 night_shift_manager。
- 手工测试点：
	- 招聘上限：无 night_shift -> 2；有 night_shift -> 3（CEO 不倍增）。
- 参考单测：
	- `core/tests/night_shift_managers_v2_test.gd`

---

### 5.10 noodles / sushi（面条 / 寿司模块员工）

#### noodle_cook / noodle_chef
#### sushi_cook / sushi_chef

- 核心行为/约束：
	- produce_food：面条/寿司固定产量。
	- 晚餐替代规则由模块实现：sushi（花园房屋可替代全部需求），noodles（仅当 base 不可满足时替代）。
- 存档建议定位：
	- `Working/GetFood`：验证生产。
	- `Dinnertime`：构造需求与库存，验证替代规则生效（更偏模块规则，但与这些员工直接相关）。
- 手工测试点：
	- 生产数量符合定义。
	- Dinnertime：sushi/noodles 替代逻辑与收入符合预期。
- 参考单测：
	- `core/tests/noodles_sushi_v2_test.gd`
	- `core/tests/fry_chefs_v2_test.gd`（训练链 patch：cook.train_to -> fry_chef）

---

### 5.11 rural_marketeers（乡村营销员）

#### rural_marketeer（乡村营销员）

- 核心行为/约束：
	- 放置巨型广告牌（4 槽位 N/E/S/W）：每轮 Marketing 向 rural_area 添加 2 需求（不受 cap 限制）。
	- 触发里程碑 `first_rural_marketeer_used` 后：获得 offramp 放置权（pending），并与 airplane 同边互斥。
- 存档建议定位：
	- `Working/Marketing`：玩家 0 在岗 rural_marketeer，地图包含 rural_area；并可预置边缘道路满足 offramp 放置条件。
- 手工测试点：
	- 放置巨型广告牌后：Marketing 扩展使 rural_area.demands +2。
	- 获得里程碑后：offramp pending 出现，能放置棋盘外 offramp；同边 airplane 被拒绝。
- 参考单测：
	- `core/tests/rural_marketeers_v2_test.gd`

---

## 6. 里程碑清单与测试点（全部）

说明：

- 里程碑的“触发”与“效果应用”并不总在同一代码路径：
	- 有的靠 `MilestoneEffectRegistry`（effects.type handler）
	- 有的靠 `effect_ids`（EffectRegistry 的 segment effect）
	- 有的靠模块 settlement hook（例如 `first_burger_sold`、`first_pizza_sold`）
- 因此每个里程碑存档应明确：它主要验证“触发是否正确”、还是“效果是否生效”，或两者都覆盖。

### 6.1 base_milestones（基础里程碑）

#### first_train（首个培训员工）

- 触发：`Train`
- 效果：`salary_total_delta=-15`（永久影响 Payday）
- 手工测试点：
	- 执行一次 `train` 后自动获得里程碑。
	- 后续 Payday：应在 `base_due` 基础上额外 -15（最低到 0）。
- 参考单测：`core/tests/milestone_system_test.gd`、`core/tests/payday_salary_test.gd`

#### first_lower_prices（首个降价）

- 触发：`LowerPrice`
- 效果：`base_price_delta=-1`
- 手工测试点：
	- 执行 `set_price` 后获得里程碑。
	- 后续售卖单价应整体 -1（叠加其它 price_modifiers）。
- 参考单测：`core/tests/milestone_system_test.gd`、`core/tests/milestone_effect_values_test.gd`

#### first_burger_produced（首个生产汉堡）
#### first_pizza_produced（首个生产披萨）

- 触发：`Produce`（product=burger/pizza）
- 效果：`gain_card`（burger_cook / pizza_cook）
- 手工测试点：
	- 用对应厨师生产一次后获得里程碑，并在 reserve_employees 中获得对应卡牌。
- 参考单测：`core/tests/milestone_system_test.gd`

#### first_burger_marketed / first_pizza_marketed / first_drink_marketed

- 触发：`DemandMarked`（product=burger/pizza/drink）
- 效果：`sell_bonus`（每条需求 +$5）
- 手工测试点：
	- Marketing 结算产生需求后自动获得里程碑。
	- Dinnertime 售卖这些需求时，应按需求条数额外加钱。
- 参考单测：`core/tests/milestone_system_test.gd`、`core/tests/hard_choices_v2_test.gd`、`core/tests/milestone_effect_values_test.gd`

#### first_billboard（首个放置广告牌）

- 触发：`InitiateMarketing`（type=billboard）
- 效果：
	- `marketing_no_salary`：营销员不再需要支付薪水
	- `marketing_permanent`：之后放置的营销永久（duration=-1）
- 手工测试点：
	- 用 marketing_trainee 放置 billboard 后获得里程碑。
	- 此后 campaign_manager 的薪水应被豁免；并且后续放置 mailbox 等营销应变为永久（duration=-1）。
- 参考单测：`core/tests/marketing_campaigns_test.gd`、`core/rules/employee_rules/salary.gd`、`gameplay/actions/initiate_marketing/apply.gd`

#### first_radio（首个进行电波营销）

- 触发：`InitiateMarketing`（type=radio）
- 效果：
	- `extra_marketing`（value=radio）+ `effect_ids`：`base_rules:marketing:demand_amount:first_radio`
- 手工测试点：
	- 放置 radio 后获得里程碑。
	- Marketing 结算时 radio 的 demand_amount 应被 effect_registry 修正（对齐现有测试）。
- 参考单测：`core/tests/marketing_campaigns_test.gd`

#### first_airplane（首个进行飞机营销）

- 触发：`InitiateMarketing`（type=airplane）
- 效果：`turnorder_empty_slots=2`（影响 OrderOfBusiness）
- 手工测试点：
	- 放置 airplane 后获得里程碑。
	- 下一回合 OrderOfBusiness：拥有该里程碑者应获得额外空槽加成，从而更优先选顺序。
- 现有单测覆盖：间接（`core/tests/milestone_effect_values_test.gd` 覆盖 turnorder_empty_slots 的计算逻辑）。

#### first_hire_3（首个一回合雇佣三人）

- 触发：`Recruit`（累计到 3 次时授予）
- 效果：`gain_cards`（2x management_trainee）
- 手工测试点：
	- 同回合连续 recruit 3 次后获得里程碑，且 reserve_employees 增加 2 张 management_trainee。
- 参考单测：`core/tests/milestone_system_test.gd`

#### first_pay_20_salaries（首个支付$20+薪水）

- 触发：`PaySalaries`（paid >= 20）
- 效果：`multi_trainer_on_one=true`（允许链式培训）
- 手工测试点：
	- Payday 支付金额达到/超过 20 后获得里程碑。
	- 后续 Train：允许在同一 Train 子阶段链式培训“本子阶段新获得的员工”。
- 参考单测：`core/tests/milestone_system_test.gd`

#### first_have_20 / first_have_100

- 触发：`CashReached`（>=20 / >=100）
- 效果：
	- first_have_20：`peek_reserve_cards`（player.can_peek_all_reserve_cards=true）
	- first_have_100：`ceo_get_cfo`（下一回合开始生效）+ `ban_card(cfo)`
- 手工测试点：
	- 当现金达到阈值后自动获得里程碑。
	- first_have_100：应将 CFO 标为 banned，且若玩家已有 CFO 应移除并归还供应池；并在下一回合晚餐收入计算中体现 CEO 的 CFO 加成。
- 参考单测：`core/tests/milestone_system_test.gd`

#### first_throw_away（首个丢弃食物/饮品）

- 触发：`CleanupDiscard`
- 效果：`gain_fridge=10`
- 手工测试点：
	- 第一次发生丢弃（Cleanup 把库存从 >0 减到 0）后获得里程碑。
	- 后续 Cleanup：每种产品库存应限幅到 10，而不是清空。
- 参考单测：`core/tests/cleanup_inventory_test.gd`

#### first_cart_operator（首个打出手推车操作员）

- 触发：`UseEmployee`（id=cart_operator）
- 效果：`distance_plus_one`（targets：cart_operator/truck_driver/zeppelin_pilot）
- 手工测试点：
	- 使用 cart_operator 采购一次后获得里程碑。
	- 后续采购距离上限应 +1。
- 参考单测：`core/tests/procure_drinks_route_rules_test.gd`

#### first_errand_boy（首个打出跑腿伙计）

- 触发：`UseEmployee`（id=errand_boy）
- 效果：`procure_plus_one=1`
- 手工测试点：
	- 使用 errand_boy 一次后获得里程碑。
	- 后续路线采购：每个来源的饮料数量应 +1。
- 参考单测：`core/tests/procure_drinks_route_rules_test.gd`

#### first_waitress（首个使用女服务员）

- 触发：`UseEmployee`（id=waitress）
- 效果：`waitress_tips=5`
- 手工测试点：
	- waitress 参与晚餐结算并触发 UseEmployee 后获得里程碑。
	- 后续晚餐 tips 从 3 提升到 5（对获得者）。
- 参考单测：`core/tests/dinnertime_settlement_test.gd`

---

### 6.2 ketchup_mechanism

#### ketchup_sold_your_demand（有人卖了你的需求）

- 触发：`KetchupSoldDemand`
- 效果：`ketchup_active` + `effect_ids`（距离/结算相关）
- 手工测试点：
	- 当他人售卖了“你的需求”后应获得里程碑，并使 ketchup 机制的距离/结算效果生效。
- 参考单测：`core/tests/ketchup_mechanism_v2_test.gd`

---

### 6.3 lobbyists

#### first_lobbyist_used（首个使用说客）

- 触发：`UseEmployee`（employee_id=lobbyist）
- 效果：`lobbyists_grant_extra_map_tile`（允许扩边放 tile，pending）
- 手工测试点：
	- 成功放置 park/road 后获得里程碑，并出现 extra tile pending，可立即执行扩边放 tile。
- 参考单测：`core/tests/lobbyists_v2_test.gd`

---

### 6.4 new_milestones（全新里程碑）

#### first_marketing_trainee_used

- 触发：`InitiateMarketing`（employee_type=marketing_trainee）
- 效果：`gain_cards`（kitchen_trainee + errand_boy）
- 手工测试点：
	- marketing_trainee 发起营销后获得里程碑，并在 reserve_employees 中获得两张卡。
- 参考单测：`core/tests/new_milestones_marketing_trainee_v2_test.gd`

#### first_campaign_manager_used

- 触发：`InitiateMarketing`（employee_type=campaign_manager）
- 效果：同回合允许额外放置第二张同类型板件（通过模块 action 实现）
- 手工测试点：
	- 触发里程碑后，可执行 `place_campaign_manager_second_tile`；并验证两张板件到期后才释放员工。
- 参考单测：`core/tests/new_milestones_campaign_manager_v2_test.gd`

#### first_brand_manager_used

- 触发：`InitiateMarketing`（employee_type=brand_manager 且 type=airplane）
- 效果：本回合可追加第二种商品（A→B）
- 手工测试点：
	- 触发后可执行 `set_brand_manager_airplane_second_good`；Marketing 结算后需求顺序为 A 再 B。
- 参考单测：`core/tests/new_milestones_brand_manager_v2_test.gd`

#### first_brand_director_used

- 触发：`InitiateMarketing`（employee_type=brand_director）
- 效果：之后放置的 radio 永久；brand_director 永久忙碌
- 手工测试点：
	- brand_director 放置 radio 后 duration=-1；结算后不释放；mailbox 到期也不释放。
- 参考单测：`core/tests/new_milestones_brand_director_v2_test.gd`

#### first_recruiting_girl_used

- 触发：`UseEmployee`（id=recruiting_girl）
- 效果：获得 `executive_vice_president` 且其永久免薪
- 手工测试点：
	- recruiting_girl 在岗并让其容量被实际使用后触发；检查 reserve_employees 与 no_salary_employee_ids。
- 参考单测：`core/tests/new_milestones_recruiter_waitress_v2_test.gd`

#### first_trainer_used

- 触发：`UseEmployee`（id=trainer）
- 效果：获得 1 张 trainer（gain_card）并允许欠薪离开 Payday（salary_allow_unpaid）
- 手工测试点：
	- 触发后 Payday 欠薪不再阻塞离开；并验证 player.salary_allow_unpaid=true。
- 参考单测：`core/tests/new_milestones_beer_trainer_payday_v2_test.gd`

#### first_beer_sold

- 触发：`ProductSold`（beer）
- 效果：允许用 token 支付薪水（salary_pay_with_tokens）
- 手工测试点：
	- Payday 欠薪但库存有 food/drink token 时，应消耗 token 并允许离开 Payday。
- 参考单测：`core/tests/new_milestones_beer_trainer_payday_v2_test.gd`

#### first_coke_sold

- 触发：`ProductSold`（soda）
- 效果：`gain_fridge=10`（freezer）
- 手工测试点：
	- 获得后 Cleanup 对 soda 限幅到 10。
- 参考单测：`core/tests/new_milestones_coke_sold_v2_test.gd`

#### first_lemonade_sold

- 触发：`ProductSold`（lemonade）
- 效果：允许在岗同色培训（train_from_active_same_color）
- 手工测试点：
	- 在岗同色员工可直接作为 from_employee 进行培训；且“旧员工未使用→新员工可立刻在岗”。
- 参考单测：`core/tests/new_milestones_lemonade_sold_v2_test.gd`

#### first_discount_manager_used

- 触发：`UseEmployee`（id=discount_manager）
- 效果：下回合 Restructuring 结束移除银行 $100（bank_burn_on_discount_ge_3）
- 手工测试点：
	- `set_discount` 后标记 pending；下一回合离开 Restructuring 时银行减少 100。
- 参考单测：`core/tests/new_milestones_discount_manager_bank_burn_v2_test.gd`

#### first_waitress_used

- 触发：`UseEmployee`（id=waitress）
- 效果：薪水变为每人 $3（salary_cost_override=3，仅对获得者）
- 手工测试点：
	- 触发后 Payday 的 salary_cost 使用 3（对比默认 5）。
- 参考单测：`core/tests/new_milestones_recruiter_waitress_v2_test.gd`

#### first_marketeer_used

- 触发：`InitiateMarketing`（employee_is_marketeer=true）
- 效果：
	- `effect_ids`：`new_milestones:marketing:demand_cash:first_marketeer_used`（需求现金奖励）
	- `effect_ids`：`new_milestones:dinnertime:distance_delta:first_marketeer_used`（距离 -2）
- 手工测试点：
	- Marketing 结算：每新增需求 +$5（cash bonus）。
	- Dinnertime 距离：应出现 -2 距离修正（允许负数）。
- 参考单测：`core/tests/new_milestones_v2_test.gd`

#### first_new_restaurant

- 触发：`RestaurantPlaced`（phase=Working）
- 效果：noop（目前主要验证触发）
- 手工测试点：
	- 用 local_manager/place_restaurant 放置新餐厅后应获得里程碑。
- 参考单测：`core/tests/new_milestones_new_restaurant_v2_test.gd`

#### first_cart_operator_used

- 触发：`UseEmployee`（id=cart_operator）
- 效果：`drinks_per_source_delta`（不同 targets 不同增量）
- 手工测试点：
	- 触发后：cart_operator/zeppelin_pilot 每源 +2；truck_driver 每源 +4。
- 现有单测覆盖：无（建议用存档重点验证，或后续补齐单测）。

#### first_house_built

- 触发：`HouseBuilt`
- 效果：`multi_trainer_on_one=true`
- 手工测试点：
	- 成功建造房屋后获得里程碑；Train 子阶段链式培训放开。
- 现有单测覆盖：无（建议补齐或用存档重点验证）。

#### first_burger_sold / first_pizza_sold

- 触发：`ProductSold`（burger/pizza）
- 效果：noop（但 burger_sold 的 CEO 卡槽修正、pizza_sold 的 radio pending 由模块 settlement hook 实现）
- 手工测试点：
	- first_burger_sold：获得后 CEO 卡槽至少为 4（不受储备卡影响）。
	- first_pizza_sold：本回合前 3 个“买披萨”的房屋会产生“强制放置 pizza radio”的 pending actions（若有空间）。
- 参考单测：
	- `core/tests/new_milestones_burger_sold_v2_test.gd`
	-（pizza_sold）现有单测覆盖：无（建议新增或用存档重点验证）

---

### 6.5 rural_marketeers

#### first_rural_marketeer_used

- 触发：`UseEmployee`（id=rural_marketeer）
- 效果：`rural_marketeers:grant_offramp_placement`
- 手工测试点：
	- 放置巨型广告牌后应获得里程碑，并出现 offramp pending，可放置棋盘外 offramp。
- 参考单测：`core/tests/rural_marketeers_v2_test.gd`

---

## 7. 实施步骤（开发计划）

建议按“先能跑通→再补齐覆盖→最后做校验”的顺序推进。

### 阶段 A：基础设施（1～2 天）

- 新增 `tools/generate_manual_test_saves.gd`：支持批量生成并写入 `/.savings/manual_cases/`。
- 定义 manifest（`tools/generate_manual_test_saves_manifest.gd` 或 JSON）：
	- 每条记录包含：`kind(employee|milestone)`、`id`、`player_count`、`seed`、`enabled_modules`、`builder`、`expected_steps_md`。
- 先实现 3～5 个示例场景（覆盖 produce / recruit / marketing / dinnertime / payday）。
- 增加“生成后自动 load 校验”，保证不会写出坏档。

### 阶段 B：批量覆盖员工（2～4 天）

- 按模块分组逐个补齐员工场景（50 个）。
- 对“纯公司结构/纯培训链”员工，优先用 Restructuring/Train 场景覆盖。
- 对“模块规则强耦合”员工（kimchi_master、movie_star、rural_marketeer 等），直接复用对应单测的最小 map/状态构造逻辑。

### 阶段 C：批量覆盖里程碑（2～4 天）

- 为每个里程碑准备“触发型场景”：
	- 尽量通过 1 次动作触发（train/recruit/produce/initiate_marketing/set_discount 等）。
	- 对必须依赖结算日志的（ProductSold、KetchupSoldDemand 等），用 Dinnertime/Cleanup settlement 的最小场景触发。
- 对“效果在后续回合才可见”的里程碑（first_throw_away、first_have_100、first_discount_manager_used、first_burger_sold 等），存档说明文件必须写清楚“需要推进到下一回合/下阶段”。

### 阶段 D：维护性与验收（1～2 天）

- 生成 `/.savings/manual_cases/README.md`（可选）：索引全部存档、快速搜索、以及推荐的复核顺序。
- 补充一个 headless 冒烟测试：
	- 逐个加载 `/.savings/manual_cases/**/*.json`，至少保证 `load_from_file` 成功。
	-（可选）检查每个场景的“关键字段存在性”（比如期待有某员工在岗/某里程碑在 pool）。

---

## 8. 已确认的约束（按你的反馈锁定）

- 每个员工 / 里程碑：**1 个存档 + 1 个说明文件**（同名 `<id>.json` + `<id>.md`）。
- 覆盖范围：覆盖仓库中 `modules/*/content/...` 出现的**全部模块内容**（不区分“基础/扩展”）。
- 玩家数：默认 **2 人局**；仅在确实需要验证“多玩家差异/专属规则”时才使用非 2 人局。
