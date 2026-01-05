# 开发状态跟踪

最后更新: 2026-01-04

---

## 里程碑进度

| 里程碑 | 状态 | 进度 | 说明 |
|--------|------|------|------|
| M0: 工程初始化与骨架 | ✅ 完成 | 100% | 主菜单→新游戏→Game 场景；日志/调试开关；GameState/Command 序列化占位 |
| M1: 核心引擎（命令/状态机/事件） | ✅ 完成 | 100% | `GameEngine.initialize()` 完成动作注册 + 数据加载 + 不变量；新增“回放确定性测试”场景 |
| M2: 地图烘焙 + 道路图 + 放置校验 | ✅ 完成 | 100% | `GameData` 由模块系统 V2 的 `ContentCatalog` 装配 `tiles/maps/pieces`；`content/maps/*.json` 作为 MapOption（主题/选项）；由 base_rules 注册的 primary map generator 按规则表生成运行期 MapDef（2P=3x3/3P=3x4/4P=4x4/5P=5x4），tile_pool 来自本局加载到的全部 tiles（不放回）并可随机旋转（确定性 RNG）；`MapBaker.bake()` 初始化地图；新增“板块编辑器/导出 JSON”；游戏场景已渲染 `state.map.cells` |
| M3: 公司/员工/库存/基础经济闭环 | ✅ 完成 | 100% | 初始公司结构（CEO）；EmployeeDef/Registry 数据驱动；薪资逻辑从 JSON 读取；新增解雇（Payday，含忙碌营销员限制）；**发薪日结算：离开 Payday 时统一结算薪水（含 recruiting_manager/hr_director 折扣与 first_train 里程碑修正，写入 round_state）**；进入 Cleanup 自动清理库存（无冰箱清空/有冰箱限幅）；重组时激活待命员工并做 CEO 卡槽裁剪；强制动作框架（定价/折扣/奢侈品）；离开 Working 阶段时阻止未完成的强制动作；生产食物动作（GetFood 子阶段）；**采购饮料动作（GetDrinks 子阶段，支持“按路线拾取/禁 U 型转弯/同来源仅一次”）**；**公司结构校验器（CEO 卡槽/唯一员工约束）**；**员工供应池守恒不变量**；补齐 `kitchen_trainee` 为 entry_level 并加入 employee_pool（用于培训链与“first_marketing_trainee_used”奖励）；新增 headless 测试 |
| M4: 营销系统 + 晚餐竞争完整规则 | 🚧 进行中 | 90% | 已实现营销生命周期（发起/结算/到期回收）；已实现晚餐结算（候选筛选/平局链路/收入/库存变化/女服务员/CFO）与基础定价管道（强制动作/里程碑/花园/奖励/下限0）；✅ 已实现银行破产（首次翻储备卡注资 + CEO 卡槽重设；第二次破产允许完成支付并在晚餐结束后终局/跳过 Payday）；✅ 已补齐营销相关里程碑效果（first_billboard：营销员免薪/后续营销永久；first_radio：radio 每房屋 2 需求；first_lower_prices/first_*_marketed/first_airplane 的数值改为以里程碑 JSON `effects.value` 为准）；✅ 营销板件按玩家数可用性数据驱动（`min_players/max_players`）；✅ MapView 已可视化房屋需求数与营销板件放置（便于调试/对齐规则）；✅ Game 场景新增“调试窗口”查看 `round_state/marketing_instances`；✅ 新增 `MarketingInitiationRegistry`（模块可在 `initiate_marketing` 完成基础放置后追加逻辑），并接入模块系统 V2（Ruleset 注册 + GameEngine 配置 + 动作调用）；✅ `MarketingSettlement` 支持营销实例声明 `products=[A,B,...]`（顺序结算）与 `no_release=true`（到期不释放营销员）；✅ 新增 `new_milestones` 模块并实现 `first_marketeer_used`（Marketing 每个需求+$5；Dinnertime 距离-2 且允许为负）、`first_new_restaurant`（首次 Working 放置新餐厅后可占用 mailbox #5-#10 放置一个永久邮箱；同街区=mailbox block；不绑定营销员）、`first_marketing_trainee_used`（获得 kitchen_trainee + errand_boy）、`first_campaign_manager_used`（获得里程碑的同回合额外放置第二张同类型板件；新增动作 `place_campaign_manager_second_tile`；营销员在两张板件都到期后返回）、`first_brand_manager_used`（同回合 airplane 追加第二种商品，动作 `set_brand_manager_airplane_second_good`）、`first_brand_director_used`（radio 永久；brand_director 忙碌到游戏结束）、`first_burger_sold`（首次卖出汉堡后 CEO 卡槽至少 4）、`first_coke_sold`（首次卖出可乐/`soda` 后获得 freezer=`gain_fridge=10`）与 `first_pizza_sold`（首次卖出披萨后：全局取前 3 个购买披萨的房屋，每次购买对应卖家必须放置 1 张 base radio#1-#3，动作 `place_pizza_radio`，持续 2 回合；未放完前阻断阶段推进）；✅ 为模块12（乡村营销员）的“大改 offramp（棋盘外放组件）”新增 `external_cells`/RoadGraph 外部格子建图与 MapCanvas 外部渲染支撑，并落盘 `modules/rural_marketeers/`（actions/validator/里程碑效果/测试）；修复 `DinnertimeSettlement` 对 `house_number` 的过严断言；并完善飞机/出口互斥映射；随后确认 `highway_offramp` 实际为 **1x2 的 piece**，撤回 tile/TileRegistry 方案并改为 `content/pieces/highway_offramp.json` + `place_highway_offramp(position=[x,y])`；进一步收紧为“连接格必须为道路且除朝外方向外还至少连接一个内部方向”，并记录 offramp 的 `owner/rotation/occupied` 供贴图与调试；✅ 为模块13（美食评论家）新增 `MarketingTypeRegistry`（模块可注册营销 type 的 range handler + 边缘放置），并落盘 `modules/gourmet_food_critics/`（gourmet_guide 17–20：每回合对所有花园房屋+1需求；全局最多 3 个；与 offramp 同格互斥）；✅ 为模块14（储备价格）新增 `BankruptcyRegistry`（模块可替换第一次破产处理），并落盘 `modules/reserve_prices/`（第一次破产固定注资 `$200×人数`，不改 CEO 卡槽；按玩家选择的储备卡类型将后续 `base_unit_price` 锁定为 5/10/20（并列按 20>5>10）；第 1 回合进入 Restructuring 时确定性发 3 张替代储备卡）；✅ 为模块16（艰难抉择）新增里程碑 patch 机制并落盘 `modules/hard_choices/`（仅在启用时将 `first_*` 起步里程碑设置为 `expires_at=2/3`，Cleanup 到期移除）；🟡 模块2（说客）：新增 `TileRegistry/PieceRegistry` 与 `state.map.tile_supply_remaining`，并提供 DinnertimeSettlement `global_effect_ids` 扩展点（可用于 roadworks/park 等全局规则）；落盘 `modules/lobbyists/`（员工/里程碑/道路 pieces/Tile Z/子阶段插入与动作）；并补齐回归覆盖 roadworks/park 的全局 effect 调用路径；✅ 为模块6/7（面条/寿司）新增 `DinnertimeDemandRegistry` 与产品 `no_marketing` 机制，并落盘模块规则 entry + 测试；✅ 新增“Cleanup 子阶段”扩展机制（模块可注入子阶段顺序与钩子；`advance_phase target=sub_phase` 与 `skip` 变为通用）；✅ 为模块4（咖啡）新增 `DinnertimeRoutePurchaseRegistry`（模块可注册“路上购买”结算）+ `RulesetV2.state_initializers`（模块可补充 state 字段），并落盘 `modules/coffee/`（咖啡店放置/移动、晚餐路上买咖啡、清理丢弃咖啡）；并收紧 `DinnertimeRoutePurchaseRegistry` 输出校验与补齐回归测试 `core/tests/dinnertime_route_purchase_registry_v2_test.gd`（`all_tests` 52/52） |
| M5: 里程碑 + 模块系统（插件化） | ✅ 完成 | 100% | 已完成里程碑数据加载/触发/回合清理 + 测试；✅ 已落盘模块系统 V2 最终方案（严格模式 + 结算全模块化 + 路线B）；✅ 已实现 V2 M1：模块包目录 + `module.json` 严格解析/加载器 + ModulePlanBuilder + headless 测试；✅ 已完成 V2 M2（employees/milestones 运行时接管）：`EmployeeRegistry/MilestoneRegistry` 由 `ContentCatalog` 装配（不再从 `data/` 懒加载），并落盘 `modules/base_employees/`、`modules/base_milestones/`；✅ 已完成 V2 M3：Pools 推导（路线B，1x=按人数决定每种卡张数，不做随机抽取）；✅ 已完成 V2 M4：SettlementRegistry + RulesetLoader（entry_script 注册）+ 缺失主结算器初始化失败（Fail Fast），并落盘 `modules/base_rules/`；✅ 已完成 V2 M5：EffectRegistry 接入结算（Dinnertime/Payday/Marketing；含 first_radio）并移除 legacy fallback（缺 SettlementRegistry/EffectRegistry/handler → init fail）；✅ 已完成 D0.5：产品模块化（`base_products`）+ `ProductRegistry` + product 引用严格校验；✅ 已移除旧模块系统 V1（`data/modules/*` + `core/modules/*`） |
| M6: 存档/复盘 + 调试工具 + 新手体验 | ⏳ 待开始 | 0% | ReplayArchive、回放定位、撤销重做、Debug Console、强制动作阻断 |
| M8: 地图视觉（图片化 + 模组资源） | ✅ 完成 | 100% | `content/visuals` + VisualCatalogLoader；MapSkin/MapSkinBuilder；MapCanvas 分层贴图渲染（道路 shape+旋转+bridge 独立 key；营销按 type + product badge；房屋需求用 product icons）；base_* 真实 PNG 已落盘（`tools/generate_module_textures.gd`）；回归通过（AllTests 37/37） |
| M7: AI 对手 | ⏳ 待开始 | 0% | DecisionPolicy、可复现决策与回放一致性 |

---

## 文件实现状态

### 自动加载 (autoload/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `globals.gd` | ✅ 完成 | 全局配置、版本号、玩家颜色 |
| `scene_manager.gd` | ✅ 完成 | 场景切换、场景栈管理 |
| `debug_flags.gd` | ✅ 完成 | 调试开关、Ctrl+Shift+D 切换 |

### 工具层 (tools/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `logger.gd` | ✅ 完成 | 日志系统、级别过滤、历史记录 |
| `check_compile.gd` | ✅ 完成 | Headless 编译/预加载扫描：快速发现脚本语法错误导致的 preload/load 失败 |

### 核心引擎 (core/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `types/result.gd` | ✅ 完成 | Result 类型、链式调用、map/and_then |
| `types/command.gd` | ✅ 完成 | 命令结构、序列化、工厂方法 |
| `state/game_state.gd` | ✅ 完成 | 游戏状态、深拷贝、哈希、地图初始化；玩家初始化时自动添加 CEO |
| `engine/game_engine.gd` | ✅ 完成 | 引擎初始化时注册 built-in actions；加载 `GameData` 并烘焙地图；支持回放/校验点/不变量/存档 |
| `events/event_bus.gd` | ✅ 完成 | 事件订阅/发射、历史记录 |
| `engine/phase_manager.gd` | ✅ 完成 | 阶段FSM、钩子系统；进入 Dinnertime 自动晚餐结算（候选筛选/平局链路/收入/库存变化/女服务员/CFO）；离开 Payday 时薪水/折扣/里程碑修正结算；进入 Marketing 自动结算营销需求/持续时间（支持多轮结算，且在 Marketing before_enter hooks 之后执行）；进入 Cleanup 的库存清理（无冰箱清空/有冰箱限幅）；重组时待命员工激活与 CEO 卡槽裁剪 |
| `actions/action_executor.gd` | ✅ 完成 | 动作执行器基类 |
| `actions/action_registry.gd` | ✅ 完成 | 注册表/校验器框架；由 `GameEngine.initialize()` 注册内置动作执行器 |
| `state/state_updater.gd` | ✅ 完成 | 状态更新辅助类 |
| `random/random_manager.gd` | ✅ 完成 | 受控随机管理器 |
| `rules/employee_rules.gd` | ✅ 完成 | 员工行动额度（招聘/培训）+ 发薪日薪水统计；通过 EmployeeRegistry 读取 JSON 定义；支持 `round_state.working_employee_multipliers` 扩展点（供模块扩展） |
| `rules/pricing_pipeline.gd` | ✅ 完成 | 定价管道（基础单价/强制动作/里程碑修正；花园倍增；营销奖励；收入下限 0） |
| `data/employee_def.gd` | ✅ 完成 | 员工定义类，解析 `modules/*/content/employees/*.json` |
| `data/employee_registry.gd` | ✅ 完成 | 员工注册表（Strict Mode）：由模块系统 V2 装配（不再从 `data/` 懒加载） |
| `data/marketing_def.gd` | ✅ 完成 | 营销板件定义（board_number/type），解析 `modules/*/content/marketing/*.json` |
| `data/marketing_registry.gd` | ✅ 完成 | 营销板件注册表（Strict Mode）：由模块系统 V2 装配（不再从 `data/` 懒加载） |
| `tests/employee_action_test.gd` | ✅ 完成 | 员工行动额度与回合切换 smoke test（纯逻辑） |
| `tests/payday_salary_test.gd` | ✅ 完成 | 发薪日薪水扣除 smoke test（纯逻辑） |
| `tests/replay_determinism_test.gd` | ✅ 完成 | 回放确定性测试（纯逻辑） |
| `tests/initial_company_test.gd` | ✅ 完成 | 初始公司结构测试（纯逻辑） |
| `tests/mandatory_actions_test.gd` | ✅ 完成 | 强制动作测试（纯逻辑） |
| `tests/produce_food_test.gd` | ✅ 完成 | 生产食物测试（纯逻辑） |
| `tests/procure_drinks_test.gd` | ✅ 完成 | 采购饮料测试（纯逻辑） |
| `tests/procure_drinks_route_rules_test.gd` | ✅ 完成 | 采购饮料路线规则测试（路线拾取/U 型/同来源一次）（纯逻辑） |
| `tests/cleanup_inventory_test.gd` | ✅ 完成 | 清理阶段库存清理规则测试（纯逻辑） |
| `tests/fire_action_test.gd` | ✅ 完成 | 解雇动作测试（Restructuring/Payday，禁止解雇 CEO）（纯逻辑） |
| `tests/company_structure_test.gd` | ✅ 完成 | 公司结构校验器测试（纯逻辑） |
| `tests/marketing_campaigns_test.gd` | ✅ 完成 | 营销发起与 Marketing 阶段需求生成/到期回收测试（纯逻辑） |
| `tests/dinnertime_settlement_test.gd` | ✅ 完成 | 晚餐结算测试（距离/库存候选过滤/平局链路；花园仅影响收入；女服务员/CFO） |
| `tests/bankruptcy_test.gd` | ✅ 完成 | 银行破产测试（首次破产注资与 CEO 卡槽重设；第二次破产终局跳过 Payday）（纯逻辑） |

### 地图系统 (core/map/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `map_utils.gd` | ✅ 完成 | 坐标变换、旋转、方向工具 |
| `tile_def.gd` | ✅ 完成 | 板块定义、道路段、印刷建筑 |
| `map_def.gd` | ✅ 完成 | 地图定义、板块布局、边缘端口 |
| `piece_def.gd` | ✅ 完成 | 建筑件定义、占地、入口 |
| `map_baker.gd` | ✅ 完成 | 板块烘焙、格子网格生成 |
| `road_graph.gd` | ✅ 完成 | 道路图、最短路径、街区划分 |
| `placement_validator.gd` | ✅ 完成 | 统一放置验证API |
| `house_number_manager.gd` | ✅ 完成 | 房屋编号分配与排序 |

### 地图编辑器（M2 交付物）

> 已新增 `ui/scenes/tools/tile_editor.tscn`：可视化编辑/校验/预览，并可一键导出（保存）到 `res://modules/base_tiles/content/tiles/*.json`。

### UI 场景 (ui/scenes/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `main_menu.tscn` | ✅ 完成 | 主菜单界面 |
| `main_menu.gd` | ✅ 完成 | 主菜单逻辑 |
| `game_setup.tscn` | ✅ 完成 | 游戏设置界面 |
| `game_setup.gd` | ✅ 完成 | 设置逻辑、玩家数、种子 |
| `game.tscn` | ✅ 完成 | 游戏主界面（占位） |
| `game.gd` | ✅ 完成 | 游戏逻辑（占位版） |
| `tile_editor.tscn` | ✅ 完成 | 板块编辑器：编辑/校验/预览/导出 JSON |
| `tile_editor.gd` | ✅ 完成 | 同上 |
| `tests/replay_test.tscn` | ✅ 完成 | 回放确定性测试场景（20+ 命令，headless 可跑） |
| `tests/replay_test.gd` | ✅ 完成 | 同上 |
| `tests/employee_test.tscn` | ✅ 完成 | 员工行动额度 smoke test（headless 可跑） |
| `tests/employee_test.gd` | ✅ 完成 | 同上 |
| `tests/payday_salary_test.tscn` | ✅ 完成 | 发薪日薪水扣除 smoke test（headless 可跑） |
| `tests/payday_salary_test.gd` | ✅ 完成 | 同上 |
| `tests/initial_company_test.tscn` | ✅ 完成 | 初始公司结构测试（headless 可跑） |
| `tests/initial_company_test.gd` | ✅ 完成 | 同上 |
| `tests/mandatory_actions_test.tscn` | ✅ 完成 | 强制动作测试（headless 可跑） |
| `tests/mandatory_actions_test.gd` | ✅ 完成 | 同上 |
| `tests/produce_food_test.tscn` | ✅ 完成 | 生产食物测试（headless 可跑） |
| `tests/produce_food_test.gd` | ✅ 完成 | 同上 |
| `tests/procure_drinks_test.tscn` | ✅ 完成 | 采购饮料测试（headless 可跑） |
| `tests/procure_drinks_test.gd` | ✅ 完成 | 同上 |
| `tests/company_structure_test.tscn` | ✅ 完成 | 公司结构测试（headless 可跑） |
| `tests/company_structure_test.gd` | ✅ 完成 | 同上 |

### 游戏规则 (gameplay/)

| 文件 | 状态 | 说明 |
|------|------|------|
| `actions/advance_phase_action.gd` | ✅ 完成 | 已注册到 `GameEngine`，可用于推进阶段/子阶段 |
| `actions/skip_action.gd` | ✅ 完成 | 已注册到 `GameEngine`，用于推进玩家回合 |
| `actions/recruit_action.gd` | ✅ 完成 | 已注册；集成公司结构校验器（唯一员工/CEO 卡槽） |
| `actions/train_action.gd` | ✅ 完成 | 已注册；待命员工→更高职位；集成公司结构校验器 |
| `actions/initiate_marketing_action.gd` | ✅ 完成 | 已注册；Working/Marketing 子阶段发起营销，创建营销实例并将营销员置为忙碌 |
| `actions/fire_action.gd` | ✅ 完成 | 已注册；Payday 解雇员工并回补员工池；忙碌营销员限制（特殊例外）；禁止解雇 `can_be_fired=false` 的员工（默认 CEO） |
| `actions/place_restaurant_action.gd` | ✅ 完成 | 已注册；Setup/Working 放置校验与落子 |
| `actions/place_house_action.gd` | ✅ 完成 | 已注册；Working 放置校验与落子 |
| `actions/set_price_action.gd` | ✅ 完成 | 已注册；强制动作，激活定价经理效果（-$1） |
| `actions/set_discount_action.gd` | ✅ 完成 | 已注册；强制动作，激活折扣经理效果（-$3） |
| `actions/set_luxury_price_action.gd` | ✅ 完成 | 已注册；强制动作，激活奢侈品经理效果（+$10） |
| `actions/produce_food_action.gd` | ✅ 完成 | 已注册；GetFood 子阶段生产食物（汉堡/披萨厨师与主厨） |
| `actions/procure_drinks_action.gd` | ✅ 完成 | 已注册；GetDrinks 子阶段采购饮料（卡车司机/飞艇驾驶员） |
| `validators/base_validator.gd` | ✅ 完成 | 校验器基类 |
| `validators/company_structure_validator.gd` | ✅ 完成 | 公司结构校验器（CEO 卡槽/唯一员工约束） |

### 数据资源 (data/)

| 目录 | 状态 | 说明 |
|------|------|------|
| `config/` | ✅ 完成 | 游戏配置文件：`data/config/game_config.json` + `core/data/game_config.gd`；`GameEngine.initialize()` 读取并生成初始状态 |

> 员工/里程碑/营销板件/板块/地图/建筑件内容已迁移到模块包：`modules/*/content/<type>/*.json`（Strict Mode）。

---

## 对照 `docs/development_plan.md`（M0–M2）差异总结

### M1（核心引擎）未完成/未接入项

- [x] 动作注册/引导：`GameEngine.initialize()` 注册 built-in actions；`ui/scenes/game/game.gd` 持有引擎并写入 `Globals.current_game_engine`。
- [x] “20+ 命令”确定性回放用例：`ui/scenes/tests/replay_test.tscn` + `core/tests/replay_determinism_test.gd`。

### M2（地图系统）未完成/未接入项

- [x] 板块编辑器（可视化编辑/校验/预览/导出 JSON）：`ui/scenes/tools/tile_editor.tscn`。
- [x] 模块内容加载（tiles/maps/pieces）+ `MapBaker.bake()` 初始化：`core/modules/v2/content_catalog_loader.gd` + `core/data/game_data.gd` + `core/engine/game_engine.gd`。
- [x] 游戏场景地图渲染接入：`ui/scenes/game/game.tscn` 使用 `MapView` 渲染 `state.map.cells`（替换占位“游戏区域（M2 实现）”）。

## M0 验收清单

- [x] 编辑器一键运行进入主菜单
- [x] 主菜单显示版本号
- [x] 新游戏 → 设置玩家数 → 进入游戏场景
- [x] GameState 可创建、序列化、反序列化
- [x] Command 可创建、序列化、反序列化
- [x] 日志系统工作正常

---

## M1 验收清单

- [x] 20+ 命令可确定性重放（见 `ui/scenes/tests/replay_test.tscn`）
- [x] 从相同初始状态 + 相同命令序列 = 相同 state_hash
- [x] 阶段推进正确（七阶段 + 工作子阶段）（实现于 `core/engine/phase_manager.gd`）
- [x] 阶段钩子按优先级执行（实现于 `core/engine/phase_manager.gd`）
- [x] 事件订阅/发射工作正常（`EventBus` 已配置为 autoload）
- [x] 校验点自动创建（每 50 命令）（`core/engine/game_engine.gd`）
- [x] 不变量检查：现金守恒、库存非负、员工供应池守恒（`core/engine/game_engine.gd`）
- [x] 测试执行规范文档（见 `docs/testing.md`）

---

## 已知问题

- ~~招聘动作当前依赖"招聘员"存在，但初始状态尚未给玩家默认员工~~ ✅ 已解决：玩家初始化时自动添加 CEO
- ~~发薪日规则为最小实现：当前默认所有员工均需要支付薪水~~ ✅ 已解决：薪资逻辑从 `modules/*/content/employees/*.json` 读取 `salary` 字段
- ⚠️ 里程碑 `effects.type` 已统一注册/严格校验（`MilestoneEffectRegistry`，缺 handler 初始化失败）；仍有少数 effect type 在 claim 时为 no-op（例如 `extra_marketing`），其行为由对应规则在结算/管道阶段读取（并非漏实现）

---

## 下一步计划

1. **继续 M4（营销系统 + 晚餐竞争完整规则）**：补齐剩余未覆盖规则点与回归用例
2. **M8 已完成（地图视觉图片化 + 模组资源）**：后续如需更精细美术，可直接替换 `modules/*/assets/map/**/*.png` 或扩展 `content/visuals`
3. **开始 M6（存档/复盘 + 调试工具 + 新手体验）**：Debug Console、回放定位、撤销重做、强制动作阻断
4. **开始 M7（AI 对手）**：DecisionPolicy、可复现决策与回放一致性

---

## 变更日志

### 2026-01-04 - M5+：动作可用性（phase/sub_phase）模块化注册

- 新增 `ActionAvailabilityRegistry`：默认从 `ActionExecutor.allowed_phases/allowed_sub_phases` 推导，但允许模块覆盖
- Ruleset 新增 `register_action_availability_override(action_id, points, priority)`；严格模式：覆盖不存在的 action_id 初始化失败
- 执行命令时先检查动作可用性（Fail Fast），并兼容旧语义：当 `state.sub_phase==""` 时忽略子阶段限制
- 修复 `modules/new_milestones/actions/place_pizza_radio_action.gd` 的 `allowed_sub_phases=[""]`（改为 `[]`）
- 新增回归：`core/tests/action_availability_override_v2_test.gd` + `modules/action_availability_override_test/`；`tools/run_headless_test.sh ... AllTests 60`（71/71）

### 2026-01-05 - 测试目录整理（modules_test + UI legacy）

- 新增 `modules_test/`：用于存放测试专用模块包（不再混入 `modules/`）
- V2 模块加载支持多根目录：`modules_v2_base_dir` 允许用 `;` 分隔多个目录（例如 `res://modules;res://modules_test`）
- 将测试专用模块包从 `modules/*` 迁移到 `modules_test/*`，并更新相关测试初始化参数
- 将 `ui/scenes/tests/` 中除 `all_tests.*` 外的旧测试场景移动到 `ui/scenes/tests/legacy/`（不作为默认 headless 入口）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（71/71）

### 2026-01-02 - M7/E4：里程碑 effects（Strict Mode）闭环

- 新增 `MilestoneEffectRegistry`：所有 `effects.type` 必须有 handler，否则 init fail
- 补齐触发点：Recruit（3次）/ PaySalaries（paid.gte）/ CashReached（$20/$100）
- `first_have_100`：CEO CFO 能力从下一回合开始生效；并对获得者 ban CFO（若已有自动移除并归还供应池）
- 扩展 `MilestoneSystemTest` 覆盖；`tools/run_headless_test.sh ... AllTests 60` 回归通过（35/35）
- 同步 `tools/check_compile.gd` 顶部运行示例：强调 `HOME=.tmp_home` 与 `--log-file`（与 `docs/testing.md` 一致），避免沙箱下 `user://` 写入导致 Godot 崩溃；回归通过（35/35）

### 2026-01-02 - M4：地图 UI 可视化（需求 / 营销）

- `ui/scenes/game/map_view.gd`：在地图格子上显示房屋需求数量、营销板件落点与关键信息（同时增强 tooltip 与颜色提示）
- `ui/scenes/game/game.tscn` / `ui/scenes/game/game.gd`：新增“调试窗口”，便于查看 `round_state/marketing_instances`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（35/35）

### 2026-01-04 - M4：New Milestones 回归与不变量修正

- 修复 Train 子阶段“链式培训”限制：默认禁止使用“本子阶段新培训得到的职位”继续培训（保留里程碑例外）；并调整 Coffee 用例避免依赖链式培训
- 银行新增 `removed_total`，现金守恒不变量升级为 `初始 + reserve_added_total - removed_total`；并修复存档加载时 `_initial_total_cash` 的基线计算（避免 double-count）
- 补齐若干 one_x 员工的 `pool` 元数据（路线B）并同步修复相关测试守恒注入（brand_director / burger_chef / pizza_chef / zeppelin_pilot / noodles_chef / sushi_chef / junior_vice_president）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：招聘/培训使用推导去硬编码

- `recruit`/`train` 动作不再硬编码 `recruiter`/`trainer`：改为按“本子阶段已用次数 vs 各招聘/培训提供者容量”推导必然使用的 employee_id，并按增量逐次触发 `UseEmployee`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：员工职责 role 字段（B）落盘

- `EmployeeDef` 新增 `role`（枚举），`get_role_color()` 改为基于 role 映射；`FIRST LEMONADE SOLD` 的“同色培训”判断改为比较 `get_role()`
- 为 `waitress` / `new_business_dev` / `cfo` 落盘 `role=special`，移除 core 中按 employee_id 写死特殊颜色的需求
- 继续迁移：为 `recruiter` / `trainer` / `recruiting_manager` / `hr_director` 落盘 `role=recruit_train`（招聘/培训职责）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：role 字段迁移完成（Strict）

- 为所有 `modules/*/content/employees/*.json` 补齐 `role`（不再依赖推导逻辑）
- 为模块系统 V2 的测试 fixtures（`core/tests/fixtures/**/content/employees/*.json`）补齐 `role`，避免 Strict Mode 下被提前拦截
- `EmployeeDef.role` 改为必填（缺失直接解析失败），并移除 `_derive_role()` fallback
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：继续清理员工硬编码（P2）

- `TrainAction` 中“价格强制动作是否已使用”的判断不再硬编码 `pricing_manager/discount_manager/luxury_manager`，改为读取 `EmployeeDef.mandatory_action_id`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：强制动作去硬编码（P2）

- `set_price/set_discount/set_luxury_price` 不再硬编码员工 id（pricing_manager/discount_manager/luxury_manager），统一通过 `EmployeeDef.mandatory_action_id == action_id` 推导提供者
- `set_discount` 的 `UseEmployee` 触发改为使用推导到的提供者 id（保持当前行为不变）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M4：P2 收尾（员工硬编码清单归零）

- 扫描 `core/` + `gameplay/`（排除 tests）后，除 D0.4 已确认保留的 `ceo`（根员工）外，不再存在基于 employee_id 的硬编码分支
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（65/65）

### 2026-01-04 - M5+：阶段顺序可由模块 override（最小实现）

- PhaseManager 新增 `phase_order`（默认仍为 core 基础阶段顺序），并允许模块通过 RulesetV2 注册 override（仅允许对基础阶段集合重排）
- `round_state.phase_order` 由初始化与阶段推进写入，`compute_timestamp/get_phase_progress` 会优先使用该顺序
- 新增测试模块 `modules/phase_order_override_test/` 与 headless 测试 `core/tests/phase_order_override_v2_test.gd` 并接入 AllTests
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（66/66）

### 2026-01-04 - M5+：Working 子阶段顺序可由模块 override（重排）

- RulesetV2 新增 `register_working_sub_phase_order_override`（与 insertions 互斥），最终由 PhaseManager 的 `set_working_sub_phase_order` 严格校验（必须包含所有基础子阶段）
- 新增测试模块 `modules/working_sub_phase_order_override_test/` 与 headless 测试 `core/tests/working_sub_phase_order_override_v2_test.gd` 并接入 AllTests
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（67/67）

### 2026-01-04 - M5+：推进规则从 PhaseManager 下沉到 base_rules hooks

- `base_rules` 注册 phase/sub_phase hooks：回合初始化/自动激活、OOB 初始化、Working 阶段状态重置、强制动作与缺货预支阻断、第二次破产后强制终局（通过 `round_state.force_next_phase`）
- PhaseManager 移除对应的硬编码分支（保留 Payday EXIT 结算调用点；结算器仍由模块注册）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（67/67）

### 2026-01-04 - M5+：Settlement 触发点映射可由模块 override

- PhaseManager 将结算调用从 `if next_phase == ...` 改为 `settlement_triggers_on_enter/on_exit` 映射驱动；模块可覆盖某阶段在 enter/exit 时要触发的 settlement points（支持顺序重排）
- `validate_required_primary_settlements()` 额外校验“必需 primary settlement 必须被映射触发”（避免 override 后主结算器永远不跑）
- RulesetV2 新增 `register_settlement_triggers_override(phase, timing, points)` 并在 apply_hooks 时应用到 PhaseManager
- 新增测试模块 `modules/settlement_trigger_override_test/` 与 headless 测试 `core/tests/settlement_trigger_override_v2_test.gd` 并接入 AllTests
- 补齐更多用例：invalid required / exit triggers / points 顺序（`modules/settlement_trigger_override_*` + `core/tests/settlement_trigger_override_extra_v2_test.gd`）
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（70/70）

### 2026-01-04 - M5+：非 Working/Cleanup 阶段子阶段框架（最小实现）

- PhaseManager 支持为任意阶段配置“按名称子阶段顺序”：`set_phase_sub_phase_order(phase, order_names)`，并允许 `advance_sub_phase` 推进（对已有 Working/Cleanup API 保持独立）
- RulesetV2 新增 `register_phase_sub_phase_order_override(phase, order_names)` 与 `register_named_sub_phase_hook(sub_phase_name, ...)`
- 新增测试模块 `modules/payday_sub_phase_test/` 与 headless 测试 `core/tests/payday_sub_phase_v2_test.gd` 并接入 AllTests
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（70/70）

### 2026-01-02 - M8：地图图片化（模块视觉目录）起步

- 新增 `core/modules/v2/visual_catalog.gd`、`core/modules/v2/visual_catalog_loader.gd`：从 `modules/*/content/visuals/*.json` 加载 VisualCatalog（UI 可选）
- 新增 `ui/visual/map_skin.gd`、`ui/visual/map_skin_builder.gd`：MapSkin（贴图缺失占位继续，Q12=C）
- 更新 `core/map/map_baker.gd` / `core/map/map_runtime.gd`：写入 `state.map.tile_placements`（后续 tile 底图/边界/调试预留）
- 更新 `ui/scenes/game/game.tscn` / `ui/scenes/game/map_view.gd` / `ui/scenes/game/map_canvas.gd`：MapView 改为 MapCanvas（Control._draw 分层渲染），并保留 hover tooltip 与选中框
- 为 `modules/base_tiles`、`modules/base_pieces`、`modules/base_products`、`modules/base_marketing` 新增 `content/visuals/*.json` 与 `assets/map/**/README.md`（占位）
- MapCanvas：道路改为贴图渲染（shape+运行时旋转，bridge 独立 key）；营销按 type 选择 icon 并叠加产品 icon；房屋需求叠加 product icons
- 新增 fixtures：`core/tests/fixtures/modules_v2_visuals_valid/*`
- 新增 headless 测试：`core/tests/visual_catalog_loader_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（36/36）

### 2026-01-02 - M8：生成 base_* 真实贴图（替换占位）

- 新增贴图生成脚本：`tools/generate_module_textures.gd`（headless 生成 PNG）
- 生成并落盘 `modules/base_tiles|base_pieces|base_products|base_marketing/assets/map/**/*.png`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（36/36）

### 2026-01-02 - M2：随机地图生成接入（不放回 + 随机旋转）

- `core/engine/game_engine.gd`：地图生成改为通过模块 rules 注册的 primary map generator（Strict Mode：缺失直接 init fail）
- `modules/base_maps/content/maps/map_2p.json`：改为 MapOption（主题/选项），不再写死 grid/pool；`random_rotation` 由主题控制
- `modules/base_rules/rules/entry.gd`：按 `docs/rules.md` 的玩家数规则生成网格尺寸（2P=3x3/3P=3x4/4P=4x4/5P=5x4），tile_pool 直接来自本局 `ContentCatalog.tiles`（按文件夹枚举的全部 tiles，不放回）
- `core/random/random_manager.gd`：修正 `shuffle/pick/...` 内部调用，避免误用全局 `randi_range` 导致非确定性
- 新增测试：`core/tests/random_map_generation_test.gd`（同 seed 初始化 tile_placements 必须一致）
- 调整测试：`core/tests/fail_fast_parsing_test.gd`（不再依赖固定 map_def.tiles）
- 补齐 pieces：`apartment/park`（用于 `tile_x/tile_y/tile_z` 的 printed_structures），避免“pool=全部 tiles”时随机抽到导致 bake 失败
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（37/37）

### 2026-01-01 - M7：补充“剩余硬编码迁移”清单与计划（待确认）

- 整理剩余硬编码点并落盘到 `docs/refactor_plan.md`（M7 / D0.4–D0.7 / E1–E4）
- `docs/development_status.md` 的“已知问题/下一步计划”已同步该 backlog

### 2026-01-01 - M5：模块系统 V2 最终方案落盘（严格模式 + 结算全模块化 + 路线B）

- 你已确认：缺少必需主结算器（primary settlement）时，新游戏初始化直接失败（Fail Fast）
- 新增架构设计：`docs/architecture/60-modules-v2.md`
- 新增决策记录：`docs/decisions/0002-modules-v2-strict-mode.md`
- 更新设计文档模块章节：`docs/design.md`（补充 V2 总览，并标记 V1 待迁移）
- 实现 V2 M1：新增 `core/modules/v2/*`（`ModuleManifest/ModulePackageLoader`）、新增 `modules/README.md` 与 fixtures，新增 headless 测试 `core/tests/module_package_loader_v2_test.gd`（`all_tests` 31/31 通过）
- 启动 V2 M2：新增 `core/modules/v2/ContentCatalog*`（按启用模块加载 employees/milestones），新增 headless 测试 `core/tests/content_catalog_v2_test.gd`（`all_tests` 32/32 通过）
- 新增 V2 ModulePlanBuilder：依赖闭包/冲突检测/确定性拓扑排序（`core/modules/v2/module_plan_builder.gd` + `core/tests/module_plan_builder_v2_test.gd`），并修复 `NightShiftManagersModuleTest` 对“当前回合玩家=0”的假设（`all_tests` 33/33 通过）
- 接入 V2 到 `GameEngine.initialize()`：新增可选参数用于装配 V2 plan + catalog，并新增集成测试 `core/tests/module_system_v2_bootstrap_test.gd`（`all_tests` 34/34 通过）
- 启动 V2 M5：新增 `core/rules/effect_registry.gd`，并在 `RulesetRegistrarV2` 提供 `register_effect(effect_id, handler)`（`all_tests` 37/37 通过）
- V2 M5：`EmployeeDef/MilestoneDef` 新增 `effect_ids`（`module_id:...`）字段解析（`all_tests` 37/37 通过）
- V2 M5：V2 初始化阶段新增校验 “所有 content 引用的 effect_id 必须有 handler”（缺失直接初始化失败，`all_tests` 37/37 通过）
- V2 M5：`DinnertimeSettlement` 的 waitress/CFO 硬编码逻辑迁移到 EffectRegistry（base_rules 注册 handlers；`waitress/cfo/first_have_100` 添加 `effect_ids`），`all_tests` 37/37 通过
- V2 M5：新增 `core/tests/effect_registry_v2_test.gd` + fixtures（缺 handler init fail、effect_id 命名校验、每出现一次调用一次），并接入 `ui/scenes/tests/all_tests.gd`（`all_tests` 37/37 通过）
- V2 M5：`PaydaySettlement` 的 recruiting_manager/hr_director 折扣额度改为 EffectRegistry 驱动（base_rules 注册 handlers；员工添加 `effect_ids`），`all_tests` 37/37 通过
- V2 M5：`PaydaySettlement` 的 `salary_total_delta` 改为从里程碑 JSON `effects.value` 读取（`first_train=-15`），并在 `PaydaySalaryTest` 增加覆盖（`all_tests` 37/37 通过）
- V2 M5：`CleanupSettlement` 的冰箱容量改为从里程碑 JSON `effects.value` 读取（`first_throw_away/gain_fridge=10`），`CleanupInventoryTest` 覆盖保持通过（`all_tests` 37/37 通过）
- V2 M5：女服务员里程碑小费提升改为从里程碑 JSON `effects.value` 读取（`first_waitress/waitress_tips=5`），`DinnertimeSettlementTest` 覆盖保持通过（`all_tests` 37/37 通过）
- V2 M5：饮料采购里程碑效果从里程碑 JSON `effects.value` 读取：`first_cart_operator/distance_plus_one`（范围+1）与 `first_errand_boy/procure_plus_one=1`（每源+1）；扩展 `ProcureDrinksRouteRulesTest` 覆盖并回归（`all_tests` 37/37 通过）
- V2 M5：`MarketingSettlement` 的 first_radio radio 需求量改为 EffectRegistry 驱动（base_rules 注册 handler；`modules/base_milestones/content/milestones/first_radio.json` 添加 `effect_ids`）；`MarketingCampaignsTest` 增加“注入 EffectRegistry”覆盖（`all_tests` 37/37 通过）
- Working：Train 次数按员工 JSON `train_capacity` 统计（trainer/coach/guru），PlaceHouses 判定改用员工 `usage_tags`（`use:place_house`/`use:add_garden`）；对应测试更新并回归（`all_tests` 35/35 通过）
- Working/Payday：Recruit 次数与薪资折扣次数改为员工数据驱动（新增 `recruit_capacity`；CEO 不再由代码写死）；Payday 折扣仅由在岗员工提供（待命不计入）；测试回归通过（`all_tests` 35/35 通过）

### 2026-01-01 - 模块系统：清理旧 V1 实现

- 移除旧模块系统 V1（`data/modules/*` + `core/modules/*` 旧实现）与对应测试；`ui/scenes/tests/all_tests.gd` 聚合回归通过（`all_tests` 34/34）
- `GameEngine.initialize()` 移除 V1 modules 参数与启用逻辑，仅保留 V2 modules 参数
- UI：`Globals.enabled_modules` 改为 `Globals.enabled_modules_v2`，并更新 `ui/scenes/game/game.gd` 调用

### 2026-01-03 - M4：模块10 大众营销员（Mass Marketeers）模块化落盘（V2）

- 更新 `core/rules/phase/marketing_settlement.gd`：支持 `rounds` 多轮结算（持续时间在轮次结束后统一 -1），并在 `round_state.marketing` 写入 `rounds`
- 更新 `core/engine/phase_manager.gd`：Marketing 结算移动到 Marketing 的 `BEFORE_ENTER` hooks 之后执行，并读取 `round_state.marketing_rounds`
- 新增模块包 `modules/mass_marketeers/`：通过 `SettlementRegistry` extension（priority < 100）在 `Marketing enter` 写入 `state.round_state.marketing_rounds = 1 + N`
- 将 `mass_marketeer` 员工定义迁移到 `modules/mass_marketeers/content/employees/mass_marketeer.json`（Strict Mode：禁用模块时该员工运行期不存在）
- 更新 `gameplay/actions/recruit_action.gd`：入门级员工招聘要求该员工存在于本局 `employee_pool`（避免把“不在本局池中”的员工当作“缺货预支”）
- 新增 `core/tests/mass_marketeers_v2_test.gd` 并加入 `ui/scenes/tests/all_tests.gd` 聚合；回归通过（`all_tests` 38/38，60s 超时脚本）

### 2026-01-03 - M4：模块8 番茄酱机制（The Ketchup Mechanism）模块化落盘（V2）

- 新增模块包 `modules/ketchup_mechanism/`：晚餐结算后（Dinnertime enter extension，priority >=100）根据 `round_state.dinnertime.sold_marketed_demand_events` 触发一次里程碑 `ketchup_sold_your_demand`
- 新增晚餐距离修正扩展点：`DinnertimeSettlement` 支持 `:dinnertime:distance_delta:` effect segment，并强制 distance 非负（clamp 由模块 handler 实现）
- 里程碑池支持拷贝数：`MilestoneDef.pool.count` + `PoolBuilder.build_milestone_pool()`（用于“每人一张”类供给；获得后 Cleanup 移除剩余拷贝）
- 新增测试 `core/tests/ketchup_mechanism_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；回归通过（`all_tests` 39/39，60s 超时脚本）

### 2026-01-03 - M4：模块15 电影明星（Movie Stars）模块化落盘（V2）

- 新增受控员工 patch：`RulesetRegistrarV2.register_employee_patch(target_employee_id, patch)`，并在 V2 初始化阶段应用（用于跨模块培训链；目标缺失则 init fail）
- 新增模块包 `modules/movie_stars/`：通过 employee patch 将 `waitress.train_to` 追加 `movie_star_b/c/d`（每位玩家最多 1 张；salary=true；unique=true；pool fixed=1/张）
- OrderOfBusiness：移除 `WorkingFlow` 中对电影明星的硬编码；改为模块在 `OrderOfBusiness AFTER_ENTER` hook 按 B > C > D 重排选择顺序（其余玩家再按空槽数排序；同级明星出现直接失败）
- Dinnertime：通过 `movie_stars:dinnertime:tiebreaker:movie_star_{b|c|d}` 作为更高优先级平局裁决（B > C > D），并自动赢得“女服务员数量”平局链路
- 新增/更新测试 `core/tests/movie_stars_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；回归通过（`all_tests` 45/45，60s 超时脚本）

### 2026-01-03 - M4：模块11 夜班经理（Night Shift Managers）模块化落盘（V2）

- 新增 V2 phase/sub_phase hooks：模块可通过 `RulesetRegistrarV2.register_phase_hook/register_sub_phase_hook` 注册钩子，并在初始化阶段装配到 `PhaseManager`（同优先级按 source 稳定排序）
- strict：员工 `train_to` 引用必须存在，否则初始化失败（依赖关系确保目标一定存在）
- 新增模块包 `modules/night_shift_managers/`：提供员工 `night_shift_manager`（pool fixed=6）并在 `Working BEFORE_ENTER` 写入 `round_state.working_employee_multipliers`（无薪员工×2，CEO 排除，不叠加）
- 新增测试 `core/tests/night_shift_managers_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；回归通过（`all_tests` 41/41，60s 超时脚本）

### 2026-01-03 - 模块1：新区域（New Districts）严格落盘（V2）

- 新增模块包 `modules/new_districts/`：提供 `apartment` piece + `tile_u/v/w/x/y`（从 `base_tiles/base_pieces` 迁移以满足 Strict Mode：禁用模块则运行期完全不存在）
- `tile_x/tile_y` 的公寓行为数据驱动：通过 `printed_structures[].house_props` 写入 `no_demand_cap=true` 与 `marketing_demand_multiplier=2`
- `core/map/map_baker.gd`：支持透传 `house_props` 到 `state.map.houses[house_id]`
- `core/rules/phase/marketing_settlement.gd`：支持 `houses[*].marketing_demand_multiplier`（公寓营销需求 *2）
- 新增测试 `core/tests/new_districts_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`
- 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（47/47），`tools/check_compile.gd`（188 files）

### 2026-01-03 - M4：模块9 薯条厨师（Fry Chefs）模块化落盘（V2）

- 新增晚餐“按房屋额外奖金”扩展点：`DinnertimeSettlement` 支持 `:dinnertime:sale_house_bonus:` effect segment，并在 `round_state.dinnertime.income_sale_house_bonus` 写入每位玩家本回合该类奖金总额
- 新增占位依赖模块（仅提供员工定义，规则细节后续补齐）：
  - `modules/noodles/`：新增产品 `noodles`（不可营销）与员工 `noodles_cook/noodles_chef`，并在晚餐阶段提供“需求无法满足时用面条完全替代”的规则（不替代 coffee）
  - `modules/sushi/`：新增产品 `sushi`（不可营销）与员工 `sushi_cook/sushi_chef`，并在晚餐阶段对“带花园房屋”提供“优先用寿司完全替代”的规则（不替代 coffee）
  - 启用任一模块会让供应池额外 +1 张 `luxury_manager`（多模块同时使用仍只加一次）
  - 修正：`noodles_cook/sushi_cook` 并非入门员工（应由 `kitchen_trainee` 培训而来），已移除错误的 `entry_level` tag；回归 `all_tests` 49/49

### 2026-01-03 - M4：模块5 泡菜（Kimchi）模块化落盘（V2）

- 新增模块包 `modules/kimchi/`：产品 `kimchi`（不可营销），员工 `kimchi_master`（one_x，Cleanup 丢弃后生产 1 个 kimchi 并自动保存）
- 晚餐偏好：通过 `DinnertimeDemandRegistry` 优先尝试 `kimchi_plus_base`（以及与面条/寿司的组合 variants），从而实现“房屋优先选择能额外提供 1 个 kimchi 的餐厅”
- 储存规则：当前为确定性版本（存 kimchi ⇒ 其他产品清空；kimchi clamp 到 10），后续如需玩家选择将改为显式动作
- 复用 employee_pool patch：启用该模块也会触发 `extra_luxury_manager`（只加一次）
- 新增测试 `core/tests/kimchi_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；回归通过（`all_tests` 50/50，60s 超时脚本）
- 新增模块包 `modules/fry_chefs/`：
  - 新增员工 `fry_chef`（pool fixed=8，salary=true）
  - 通过 employee patch 将 `burger_cook/burger_chef/pizza_cook/pizza_chef/noodles_cook/sushi_cook.train_to += fry_chef`
  - 注册 `fry_chefs:dinnertime:sale_house_bonus:fry_chef`：当售卖的房屋需求包含“非饮品 food”时，每个在岗 `fry_chef` +$10（按房屋算）
- 新增测试 `core/tests/fry_chefs_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；回归通过（`all_tests` 42/42，60s 超时脚本）

### 2025-12-31 - M5：Night Shift Managers（参考模块）+ Working 有效行动额度

- 新增 `core/modules/night_shift_managers_module.gd` + `data/modules/night_shift_managers.json`：注入员工池 `night_shift_manager`，并在 Working `after_enter` 写入 `round_state.working_employee_multipliers`
- 新增 `modules/base_employees/content/employees/night_shift_manager.json`
- 更新 `core/rules/employee_rules.gd`：新增 Working 阶段“有效员工数量”扩展点与 helper API（`*_for_working`）
- 更新 `gameplay/actions/*`：Recruit/Train/ProduceFood/ProcureDrinks/PlaceHouse/AddGarden/PlaceRestaurant/MoveRestaurant 读取 Working 有效行动额度
- 新增 `core/tests/night_shift_managers_module_test.gd` 并加入 `ui/scenes/tests/all_tests.gd` 聚合

### 2025-12-31 - M4：营销里程碑效果补齐

- 更新 `gameplay/actions/initiate_marketing_action.gd`：`first_billboard` 后发起的营销永久（`remaining_duration=-1`）
- 更新 `core/rules/phase/marketing_settlement.gd`：支持永久营销；实现 `first_radio`（radio 每房屋放置 2 个需求）
- 更新 `core/rules/employee_rules.gd`：`first_billboard` 使营销员免薪（按 usage_tags 判定营销员）
- 更新 `core/tests/marketing_campaigns_test.gd`：覆盖 `first_billboard`/`first_radio` 并回归

### 2025-12-31 - M5：模块系统（最小实现）

- 新增 `core/modules/*`：ModuleDef/ModuleRegistry/ModuleContext + 示例模块（阶段钩子注入）
- 更新 `core/engine/game_engine.gd`：初始化与回放加载时启用模块并写入 `state.modules`
- 更新 `core/state/game_state.gd` / `core/state/game_state_serialization.gd`：新增 `modules` 字段并升级 schema_version
- 新增纯逻辑测试 `core/tests/module_system_test.gd` 并加入 `ui/scenes/tests/all_tests.tscn` 聚合

### 2025-12-30 - M5：里程碑系统（起步）

- 新增 `core/data/milestone_def.gd` / `core/data/milestone_registry.gd`：加载 `modules/*/content/milestones/*.json`
- 新增 `core/rules/milestone_system.gd`：基于“事件名 + 上下文”触发里程碑（drink 类目兼容）
- 更新 `core/state/state_updater.gd`：`claim_milestone()` 支持同回合多名获得，Cleanup 统一从供给移除
- 更新 `core/engine/phase_manager.gd`：Marketing/Dinnertime 触发里程碑；Cleanup 处理“已获得/已过期”的供给移除
- 更新动作：`train` / `initiate_marketing` / `set_price` / `set_discount` / `produce_food` 接入里程碑触发
- 新增纯逻辑测试 `core/tests/milestone_system_test.gd` 并加入 `ui/scenes/tests/all_tests.tscn`

### 2025-12-30 - M4：银行破产（Breaking the Bank）+ 终局（GameOver）

- 更新 `core/state/game_state.gd`：新增玩家 `reserve_cards/reserve_card_selected`；新增 `bank.reserve_added_total`
- 更新 `core/state/state_updater.gd`：第二次破产（`broke_count>=2`）允许银行透支以完成应付款项
- 更新 `core/engine/game_engine.gd`：现金守恒不变量纳入 `reserve_added_total`；第二次破产后允许银行余额为负
- 更新 `core/engine/phase_manager.gd`：实现第一次/第二次破产；晚餐结算支付流程接入破产处理；第二次破产后从 Dinnertime 推进进入 `GameOver`（跳过 Payday）
- 新增纯逻辑测试 `core/tests/bankruptcy_test.gd` 并加入 `ui/scenes/tests/all_tests.tscn` 聚合

### 2025-12-30 - M4：晚餐结算 + 定价管道（含规则回归测试）

- 新增 `core/rules/pricing_pipeline.gd`：基础定价管道（强制动作/里程碑修正；花园倍增；营销奖励；收入下限 0）
- 更新 `core/engine/phase_manager.gd`：进入 Dinnertime 自动结算晚餐（候选筛选/平局链路/收入/库存变化/女服务员/CFO），结果写入 `round_state.dinnertime`
- 新增纯逻辑测试 `core/tests/dinnertime_settlement_test.gd`：覆盖距离/库存过滤/平局链路/花园仅影响收入/女服务员/CFO，并加入 `all_tests` 聚合

### 2025-12-29 - M3：不变量扩展（员工供应池守恒）

- 更新 `core/engine/game_engine.gd`：新增员工供应池守恒不变量（员工池 + 玩家 employees/reserve/busy 总和恒定），失败时返回可解释原因
- 更新测试：修正若干测试用例中“直接添加员工但未同步 employee_pool”的行为（确保从 pool 取用/归还）
- M3 进度从 90% 提升至 100%

### 2025-12-29 - M3：清理阶段库存结算（Cleanup）

- 更新 `core/engine/phase_manager.gd`：进入 Cleanup 阶段时自动清理库存
  - 无冰箱（未拥有 `first_throw_away`）：清空所有库存
  - 有冰箱：每种产品各自限幅到 10（按 `docs/design.md` 的简化策略）
  - 写入 `round_state.cleanup.inventory_discarded` 便于调试
- 新增纯逻辑测试：`core/tests/cleanup_inventory_test.gd`（已加入 `ui/scenes/tests/all_tests.tscn` 聚合）
- M3 进度从 65% 提升至 70%

### 2025-12-29 - M3：采购饮料 road range 修复（使用餐厅入口 + RoadGraph）

- 修复 `gameplay/actions/procure_drinks_action.gd`：
  - 不再依赖 `player.restaurants` 的临时结构，改为使用 `state.map.restaurants` 的餐厅数据
  - road range：按“餐厅入口邻接道路格 → 饮品源邻接道路格”的 `RoadGraph.get_distance()` 判断可达
- 更新测试 `core/tests/procure_drinks_test.gd`：使用 Setup 放置餐厅搭建真实场景，并补齐卡车司机（road）采购断言
- M3 进度从 70% 提升至 72%

### 2025-12-29 - M3：解雇动作补齐（Payday 可用 + 禁止解雇 CEO）

- 更新 `gameplay/actions/fire_action.gd`：允许在 `Payday` 阶段执行解雇；禁止解雇 `ceo`
- 新增纯逻辑测试：`core/tests/fire_action_test.gd`（已加入 `ui/scenes/tests/all_tests.tscn` 聚合）
- M3 进度从 72% 提升至 74%

### 2025-12-29 - M3：采购饮料路径细则（路线拾取 + 禁 U 型 + 同来源一次）

- 更新 `gameplay/actions/procure_drinks_action.gd`：
  - 支持 `route` 参数：按路线经过的饮品来源拾取（不再“范围内全收集”）
  - 路线校验：起点为餐厅入口（air）/入口邻接道路（road）；禁止 U 型转弯；超范围拒绝
  - 同一采购员对同一来源每回合仅一次（同一路线重复经过不重复计数）
  - 未提供 `route` 时：确定性默认选路（最近可达来源的最短路）
- 新增纯逻辑测试：`core/tests/procure_drinks_route_rules_test.gd`（已加入 `ui/scenes/tests/all_tests.tscn` 聚合）
- M3 进度从 74% 提升至 78%

### 2025-12-29 - M3：解雇动作完善（Payday 限定 + 忙碌营销员限制）

- 更新 `gameplay/actions/fire_action.gd`：
  - 解雇仅允许在 `Payday` 阶段执行
  - 忙碌营销员：默认禁止解雇；满足“已解雇所有其他带薪员工且仍无力支付忙碌营销员薪水”时允许解雇（营销活动保留由后续 M4 实现承接）
- 更新纯逻辑测试 `core/tests/fire_action_test.gd`：补齐 Restructuring 禁止解雇与忙碌营销员规则覆盖
- M3 进度从 78% 提升至 82%

### 2025-12-29 - M3：发薪日细节（折扣/里程碑/结算时机）

- 更新 `core/engine/phase_manager.gd`：
  - 薪资结算从“进入 Payday”调整为“离开 Payday”触发（先解雇、后结算）
  - `round_state.payday` 写入更可解释的结算明细：基础应付/折扣/里程碑修正/应付/实付/未付
  - 支持薪资折扣（recruiting_manager/hr_director 未使用招聘次数）与 `first_train` 里程碑总薪资修正
- 更新 `core/rules/employee_rules.gd`：Recruit 子阶段招聘次数包含 recruiting_manager/hr_director
- 更新 `gameplay/actions/recruit_action.gd`：记录 `round_state.recruit_used`，用于 Payday 折扣推导
- 更新 `core/tests/payday_salary_test.gd`：发薪结算改为离开 Payday 时触发
- M3 进度从 82% 提升至 90%

### 2025-12-29 - M3：采购饮料动作（GetDrinks 子阶段）+ 公司结构校验器

- 新增 `GET_DRINKS` 子阶段到 `core/engine/phase_manager.gd`
- 新增 `gameplay/actions/procure_drinks_action.gd`：卡车司机/飞艇驾驶员采购饮料
  - 支持道路距离 (road range) 和曼哈顿距离 (air range) 两种计算方式
  - 每个饮料源提供 2 瓶对应类型饮料
  - 同一员工每子阶段只能采购一次
- 新增 `core/events/event_bus.gd` 中的 `DRINKS_PROCURED` 事件类型
- 更新 `core/data/employee_def.gd`：新增 `can_procure()` 方法
- 新增校验器框架：
  - `gameplay/validators/base_validator.gd`：校验器基类
  - `gameplay/validators/company_structure_validator.gd`：公司结构校验器
    - CEO 卡槽容量检查
    - 唯一员工约束检查
- 集成校验器到 `recruit_action.gd` 和 `train_action.gd`
- 新增 headless 测试：
  - `ui/scenes/tests/procure_drinks_test.tscn` + `core/tests/procure_drinks_test.gd`
  - `ui/scenes/tests/company_structure_test.tscn` + `core/tests/company_structure_test.gd`
- 更新 `mandatory_actions_test.gd` 以适应新增的 GetDrinks 子阶段
- M3 进度从 45% 提升至 65%

### 2025-12-29 - M3：生产食物动作（GetFood 子阶段）

- 新增 `gameplay/actions/produce_food_action.gd`：厨师/主厨在 GetFood 子阶段生产食物
  - 生产信息从 `modules/*/content/employees/*.json` 的 `produces` 字段读取（数据驱动）
  - 每个厨师每子阶段只能生产一次
- 更新 `modules/base_employees/content/employees/` 中的厨师 JSON 定义，添加 `produces` 字段：
  - `burger_cook.json`: `{"food_type": "burger", "amount": 3}`
  - `burger_chef.json`: `{"food_type": "burger", "amount": 8}`
  - `pizza_cook.json`: `{"food_type": "pizza", "amount": 3}`
  - `pizza_chef.json`: `{"food_type": "pizza", "amount": 8}`
- 更新 `core/data/employee_def.gd`：
  - 新增 `produces_food_type` 和 `produces_amount` 字段
  - 新增 `can_produce()` 和 `get_production_info()` 方法
- 更新 `core/data/employee_registry.gd`：为 `get_def()` 添加返回类型
- 修改 `core/engine/game_engine.gd`：注册生产食物动作执行器
- 新增生产食物 headless 测试：`ui/scenes/tests/produce_food_test.tscn` + `core/tests/produce_food_test.gd`
- M3 进度从 40% 提升至 45%

### 2025-12-29 - M3：强制动作框架 + 阻塞机制

- 新增 `gameplay/actions/set_price_action.gd`：定价经理强制动作（-$1）
- 新增 `gameplay/actions/set_discount_action.gd`：折扣经理强制动作（-$3）
- 新增 `gameplay/actions/set_luxury_price_action.gd`：奢侈品经理强制动作（+$10）
- 修改 `core/engine/phase_manager.gd`：
  - 新增 `check_mandatory_actions_completed()` 检查未完成的强制动作
  - 新增 `get_required_mandatory_actions()` 获取玩家需要执行的强制动作列表
  - 新增 `get_mandatory_actions_status()` 用于 UI 显示
  - 离开 Working 阶段前检查强制动作是否完成
- 修改 `core/engine/game_engine.gd`：注册新的强制动作执行器
- 新增强制动作 headless 测试：`ui/scenes/tests/mandatory_actions_test.tscn` + `core/tests/mandatory_actions_test.gd`
- M3 进度从 30% 提升至 40%

### 2025-12-28 - M3：初始公司结构 + EmployeeDef/Registry 数据驱动

- 新增 `core/data/employee_def.gd`：员工定义类，解析 `modules/*/content/employees/*.json`
- 新增 `core/data/employee_registry.gd`：员工注册表，懒加载 33 个员工定义
- 修改 `core/state/game_state.gd`：玩家初始化时自动添加 CEO (`employees: ["ceo"]`)
- 修改 `core/rules/employee_rules.gd`：`requires_salary()` 从 EmployeeRegistry 读取 JSON 定义
- 新增初始公司结构 headless 测试：`ui/scenes/tests/initial_company_test.tscn` + `core/tests/initial_company_test.gd`
- M3 进度从 15% 提升至 30%

### 2025-12-28 - 开始 M3：发薪/解雇/容量裁剪 + headless 测试

- 新增解雇动作：`gameplay/actions/fire_action.gd`（Restructuring 阶段）
- 进入 Payday 时自动结算薪水（最小实现）并写入 `round_state.payday`：`core/engine/phase_manager.gd`
- 重组阶段激活待命员工后按 CEO 卡槽裁剪：`core/engine/phase_manager.gd`
- 新增发薪日 headless 测试：`ui/scenes/tests/payday_salary_test.tscn` + `core/tests/payday_salary_test.gd`

### 2025-12-28 - 补齐 M1/M2 交付物与可验证用例

- 新增板块编辑器：`ui/scenes/tools/tile_editor.tscn`
- 新增回放确定性测试：`ui/scenes/tests/replay_test.tscn` + `core/tests/replay_determinism_test.gd`
- 更新文档：M1/M2 状态调整为“✅ 完成”

### 2025-12-27 - 修正文档：M0–M2 状态与实现对齐

- 修正里程碑定义与 `docs/development_plan.md` 对齐
- 将 M1/M2 从“✅ 完成”改为“🟡 进行中”，补充未接入/缺失交付物说明

### 2024-12-27 - M2 代码主体落地（未接入）

- 实现地图工具类 (`core/map/map_utils.gd`)
- 实现板块定义 (`core/map/tile_def.gd`)
- 实现地图定义 (`core/map/map_def.gd`)
- 实现建筑件定义 (`core/map/piece_def.gd`)
- 实现地图烘焙器 (`core/map/map_baker.gd`)
- 实现道路图与路径计算 (`core/map/road_graph.gd`)
- 实现放置验证器 (`core/map/placement_validator.gd`)
- 实现房屋编号管理 (`core/map/house_number_manager.gd`)
- 增强游戏状态地图支持 (`core/state/game_state.gd`)
- 实现放置餐厅动作 (`gameplay/actions/place_restaurant_action.gd`)
- 实现放置房屋动作 (`gameplay/actions/place_house_action.gd`)
- 创建示例板块数据（模块内容：`modules/base_tiles/content/tiles/`）
- 创建示例地图配置（模块内容：`modules/base_maps/content/maps/`）
- 创建建筑件定义（模块内容：`modules/base_pieces/content/pieces/`）

### 2024-01-XX - M1 代码主体落地（未接入）

- 实现事件总线 (`core/events/event_bus.gd`)
- 实现受控随机管理器 (`core/random/random_manager.gd`)
- 实现状态更新辅助类 (`core/state/state_updater.gd`)
- 实现阶段管理器 (`core/engine/phase_manager.gd`)
- 实现动作执行器基类 (`core/actions/action_executor.gd`)
- 实现动作注册表 (`core/actions/action_registry.gd`)
- 完善游戏引擎 (`core/engine/game_engine.gd`)
- 实现示例动作：advance_phase, skip, recruit

### 2024-01-XX - M0 完成

- 创建项目基础结构
- 实现日志系统 (`tools/logger.gd`)
- 实现调试开关 (`autoload/debug_flags.gd`)
- 实现全局配置 (`autoload/globals.gd`)
- 实现场景管理 (`autoload/scene_manager.gd`)
- 实现 Result 类型 (`core/types/result.gd`)
- 实现 Command 结构 (`core/types/command.gd`)
- 实现 GameState 结构 (`core/state/game_state.gd`)
- 创建 UI 场景骨架（主菜单、游戏设置、游戏）
