# 游戏设置页面重构方案（设计稿 + 开发计划）

状态：设计审查中（未实施）

## 背景与现状问题

1. “游戏设置”页的“返回”在开始游戏前无效  
	- 现状：`ui/scenes/setup/game_setup.gd` 调用 `SceneManager.go_back()`；但从主菜单首次进入时场景栈没有记录主菜单，导致 `scene_stack` 为空，返回失败。
2. 页面结构需要重构  
	- 现状：运行时创建 `TabContainer`（模块/玩家/储备卡）；交互散落，维护成本较高。
3. 产品需求变更  
	- 删除“储备卡”Tab（该页不再需要展示储备卡）。
	- “玩家Tab”与“模块Tab”合并为单页分区。
	- 玩家设置需与“玩家数量”联动，放在页面上半部分。
	- 玩家“颜色选择”替换为“店铺 icon（餐厅 Logo）选择”；默认随机；如果不选则在开始游戏时按随机种子确定性分配；且所有玩家必须唯一。
	- 模块列表需要分组（相似模块归类），并支持：全选/全不选、分组全选/分组全不选。
	- 模块依赖与冲突处理规则已确认：依赖自动勾选并锁定；冲突自动取消（以 `new_milestones` 优先）。

## 目标与非目标

### 目标（本次必须实现）

- 返回键可用：从主菜单进入设置页时，点击“返回”回到上一个场景（主菜单）。
- 单页分区布局：无 Tab；上半玩家设置（联动玩家数量）；中下模块分组；底部按钮。
- 玩家设置：玩家名称 + 店铺 icon（默认随机、唯一、确定性）。
- 模块设置：分组展示；全选/全不选；分组全选/分组全不选；依赖/冲突按规则自动处理。
- 开始游戏：基于最终配置启动，且把玩家店铺 icon 写入初始 `GameState.players[*].restaurant_logo_id`（保证回放/存档确定性）。

### 非目标（本次不做/不承诺）

- 不改变游戏内现有“玩家颜色”的使用方式（仅移除设置页的颜色选择 UI）。  
	- 若后续要用 icon 替代颜色识别，可另开需求。
- 不新增搜索/过滤模块、也不做复杂折叠动画（先保证功能正确与可维护）。
- 不调整模块本身的 `module.json`（如依赖声明是否合理）——仅在 UI/配置层处理选择逻辑。

## 关键约束（已确认）

- 返回：回到上一个场景（使用场景栈 `go_back`）。
- 返回不保存：点击返回不写入 `settings.cfg`。
- 无 Tab：单页分区。
- 玩家设置字段：暂仅“名称 + 店铺 icon”。
- 店铺 icon：
	- 使用现有 5 个餐厅 Logo（`modules/base_pieces/assets/map/logos/*.png`）。
	- 必须每位玩家唯一。
	- 默认状态为随机（“随机”不是预览值；实际分配在点“开始游戏”时决定）。
	- 随机分配必须与随机种子绑定（确定性）。
- 模组依赖/冲突/全选规则：
	- 依赖：勾选模块时自动勾选依赖，并在依赖仍被需要时禁止取消。
	- 冲突：勾选 `new_milestones` 时自动取消 `hard_choices`，并自动移除 `base_milestones`。
	- 全选冲突：以 `new_milestones` 为准（全选时若涉及冲突按该优先级自动消解）。

## 页面布局设计（单页分区）

### 结构草图（Wireframe）

```
┌────────────────────────────── 游戏设置 ──────────────────────────────┐
│ 基础设置                                                             │
│  玩家数量 [2..5]  随机种子 [___________]（空=自动生成）               │
│                                                                      │
│ 玩家设置（与玩家数量联动）                                           │
│  玩家1  名称 [________]  店铺icon [随机 v]  (小预览)                  │
│  玩家2  名称 [________]  店铺icon [随机 v]  (小预览)                  │
│  ...                                                                 │
│                                                                      │
│ 模块（分组）                                    [全选] [全不选]     │
│  ┌─ 地图扩展（新城区/说客/咖啡） ─────────────── [组选] [组不选] ┐    │
│  │ [ ] New Districts ...                                           │
│  │ [ ] Lobbyists ...                                               │
│  │ [ ] Coffee ...                                                  │
│  └──────────────────────────────────────────────────────────────────┘
│  ┌─ 新菜系/厨师 ──────────────────────────────── [组选] [组不选] ┐    │
│  │ [ ] Kimchi ...                                                  │
│  │ [ ] Sushi ...                                                   │
│  │ [ ] Noodles ...                                                  │
│  │ [ ] Fry Chefs (依赖 Sushi/Noodles)                               │
│  └──────────────────────────────────────────────────────────────────┘
│  ┌─ 营销扩展 ─────────────────────────────────── [组选] [组不选] ┐    │
│  │ [ ] Mass Marketeers ...                                          │
│  │ [ ] Rural Marketeers ...                                         │
│  │ [ ] Gourmet Food Critics ...                                     │
│  └──────────────────────────────────────────────────────────────────┘
│  ┌─ 规则/里程碑变体 ───────────────────────────── [组选] [组不选] ┐    │
│  │ [ ] New Milestones（与 Hard Choices、Base Milestones 不兼容）     │
│  │ [ ] Hard Choices（可能被 New Milestones 自动取消）               │
│  │ [ ] Ketchup Mechanism ...                                        │
│  │ [ ] Reserve Prices ...                                           │
│  └──────────────────────────────────────────────────────────────────┘
│  ┌─ 员工变体 ───────────────────────────────────── [组选] [组不选] ┐    │
│  │ [ ] Movie Stars ...                                              │
│  │ [ ] Night Shift Managers ...                                     │
│  └──────────────────────────────────────────────────────────────────┘
│                                                                      │
│ 提示：储备卡将在进入游戏后由每位玩家秘密选择。                       │
│                                                                      │
│                          [返回]           [开始游戏]                 │
└──────────────────────────────────────────────────────────────────────┘
```

### UI 组件与信息层级

- “基础设置”区：保持现有玩家数量/种子输入。
- “玩家设置”区（上半部分）：固定显示 `player_count` 行；每行包含：
	- 玩家序号 Label（玩家 1..N）
	- 名称 LineEdit
	- 店铺 icon OptionButton（默认 “随机”）
	- icon 预览 TextureRect（仅在手动选择具体 icon 时显示；“随机”不做分配预览）
- “模块”区（中下）：一个 `ScrollContainer` 包住全部分组，避免分辨率较小时溢出。
	- 顶部提供全局按钮：全选 / 全不选
	- 每个分组 header 提供：组选 / 组不选
	- 模块项使用 CheckBox（或 CheckButton）：
		- 显示：模块名 + module_id
		- Tooltip：依赖、冲突、以及模块大致内容（根据 `content/*` 文件/`module.json.provides` 汇总）
		- 若被依赖锁定：置灰且 tooltip 说明“被 XXX 依赖，需先取消 XXX”
- 信息提示 Label（轻量）：展示自动处理结果，例如：
	- “已自动勾选依赖：Sushi, Noodles（因 Fry Chefs）”
	- “已自动取消：Hard Choices（与 New Milestones 冲突）”

## 交互与行为细节

### 返回

- 点击“返回”：调用 `SceneManager.go_back()`。
- 不保存任何设置（不调用 `Globals.save_settings()`）。
- 技术修复点：需要保证从主菜单进入设置页时 `scene_stack` 正确记录主菜单（详见开发计划）。

### 开始游戏

点击“开始游戏”时按顺序执行：

1. 读取玩家数量、随机种子  
	- 种子为空：生成并写回 `Globals.random_seed`
2. 应用模块选择（含依赖/冲突处理后的最终结果）
3. 应用玩家名称
4. 计算玩家店铺 icon 最终分配（确定性、唯一）
5. `Globals.save_settings()`（仅在开始游戏时保存）
6. 进入游戏场景

### 玩家设置与玩家数量联动

- 变更玩家数量后：
	- 重建玩家行（或增删行），只展示 1..N。
	- 保留已输入的玩家 1..min(old,new) 的名称与 icon 选择。
	- 新增的玩家行默认：名称 “玩家 X”、icon “随机”。
- icon 唯一性：
	- 玩家选择某个具体 icon 后，其他玩家的下拉菜单中该 icon 置灰/不可选。
	- 若某玩家此前已选的 icon 因人数变化/其他选择导致冲突（理论上通过禁用可避免），则自动回退到“随机”，并在信息提示区说明。

### 店铺 icon 分配算法（确定性、唯一、默认随机）

定义：

- icon_id 取值 `[0..logo_count-1]`，顺序与 base_pieces visuals `restaurant_logo_piece_ids` 一致（UI 通过 `MapSkin.get_restaurant_logo_piece_ids()` 读取，保持与绘制系统一致）。
- 玩家在设置页保存的是 `choice`：
	- `choice = -1` 表示“随机”
	- `choice = 0..logo_count-1` 表示指定 icon

开始游戏时计算最终 `assigned_logo_id[player_id]`：

1. 收集已指定的 icon（必须互不重复；若重复视为 UI bug，启动前强制纠正/报错）
2. `remaining = [0..logo_count-1] - fixed_set`
3. 用独立 RNG（seed = `Globals.random_seed ^ 0x4C4F474F`，与当前代码一致）对 `remaining` 洗牌
4. 对所有 `choice=-1` 的玩家，按 player_id 从小到大依次分配 `remaining.pop_front()`

性质：

- 同一 seed + 同一显式选择 => 分配结果稳定
- 每位玩家唯一
- “默认随机”下等价于当前 GameStateFactory 的随机分配逻辑（保持一致性）

### 模块选择：分组/全选/依赖/冲突

#### 全选 / 全不选

- 全选：勾选所有“可选模块”（非基础模块）后，执行一次“冲突消解 + 依赖闭包”，得到最终可用集合。
	- 若因冲突/依赖导致无法同时启用所有模块（例如 `new_milestones` 会导致依赖 `base_milestones` 的模块不可用），则按规则自动取消不兼容模块，并在提示区列出。
- 全不选：取消所有可选模块；同时解除由依赖造成的锁定状态。

#### 分组全选 / 分组全不选

- 组选：仅对该分组内模块做全选，然后执行一次全局的依赖/冲突处理（因为跨组也可能存在依赖/冲突）。
- 组不选：仅取消该分组内模块；若该组的某模块是其他已选模块的依赖，则保持勾选但置灰锁定，并提示“被依赖，无法取消”。

#### 依赖处理（规则 A）

以当前项目真实依赖为例：

- `fry_chefs` 依赖 `noodles`、`sushi`
	- 勾选 `fry_chefs` => 自动勾选 `noodles`、`sushi`
	- 在 `fry_chefs` 仍勾选时，`noodles`、`sushi` 不允许被取消（checkbox disabled）
	- 取消 `fry_chefs` 后，`noodles`、`sushi` 恢复可取消

#### 冲突处理（规则 A，且全选冲突 A）

- `new_milestones` conflicts：`hard_choices`、`base_milestones`
	- 勾选 `new_milestones` => 自动取消 `hard_choices`，并从最终启用计划中移除 `base_milestones`
	- 全选时同理：保留 `new_milestones`，取消 `hard_choices`

重要补充（实现时必须处理）：

- 项目中有多个模块直接依赖 `base_milestones`（目前扫描到：`coffee`、`hard_choices`、`kimchi`、`lobbyists`、`rural_marketeers`）。  
	当 `new_milestones` 被勾选并移除 `base_milestones` 时，这些模块将因依赖闭包把 `base_milestones` 拉回计划，从而触发冲突并导致引擎初始化失败。  
	因此 UI 必须在选择 `new_milestones` 时额外处理：
	- 自动取消所有（直接或间接）依赖 `base_milestones` 的已选模块，或阻止勾选并提示原因。  
	本方案建议：自动取消并提示（与“冲突 A”的自动行为一致）。

## 模块分组提议（可调整）

说明：以下为基于 `modules/*/content` 文件与 `module.json.provides` 的“第一版提议”。你可在审查时按你习惯的命名/归类调整。

### 组 1：地图扩展（新城区/说客/咖啡）

- `new_districts`（New Districts）：新增多个地图 tile（U-V-W-X-Y）与 `apartment` piece
- `lobbyists`（说客）：新增 tile Z、道路/公园相关 piece、lobbyist 员工与里程碑；包含额外放置动作（road/park/extra tile）
- `coffee`（Coffee）：新增 coffee 产品、barista 系员工、`coffee_shop` piece 与相关放置/路线购买规则

### 组 2：新菜系/厨师

- `kimchi`（Kimchi）：新增 kimchi 产品与 `kimchi_master` 员工（注意：依赖 `base_milestones`）
- `sushi`（Sushi）：新增 sushi 产品与 sushi chef/cook
- `noodles`（Noodles）：新增 noodles 产品与 noodle chef/cook
- `fry_chefs`（Fry Chefs）：新增 `fry_chef` 员工（依赖 `sushi`、`noodles`）

### 组 3：营销扩展

- `mass_marketeers`（Mass Marketeers）：新增 mass_marketeer 员工（营销阶段扩展）
- `rural_marketeers`（Rural Marketeers）：新增 rural_marketeer、里程碑与 `highway_offramp` piece；包含放置 billboard/offramp 行为（注意：依赖 `base_milestones`）
- `gourmet_food_critics`（Gourmet Food Critics）：新增美食评论家员工与多张 Gourmet Guide 营销牌

### 组 4：规则/里程碑变体

- `new_milestones`（全新里程碑）：替换里程碑体系并新增部分营销内容（冲突：`base_milestones`、`hard_choices`）
- `hard_choices`（Hard Choices）：规则变体（依赖 `base_milestones`；可能被 `new_milestones` 自动取消）
- `ketchup_mechanism`（The Ketchup Mechanism）：新增 ketchup 相关里程碑与晚餐结算机制
- `reserve_prices`（Reserve Prices）：重组阶段/破产相关规则扩展（无 content 文件，靠 hook 生效）

### 组 5：员工变体

- `movie_stars`（Movie Stars）：新增 movie_star 员工与晚餐 tie-breaker 扩展
- `night_shift_managers`（Night Shift Managers）：新增 night_shift_manager 员工与工作阶段前置 hook

## 需要修改/新增的数据与接口（实施时）

### Globals（持久化设置）

新增字段建议：

- `player_restaurant_logo_choices: Array[int]`（长度 MAX_PLAYERS）
	- `-1` = 随机
	- `0..4` = 指定 icon_id
	- 保存到 `user://settings.cfg`，例如：
		- section: `players`
		- key: `restaurant_logo_choices`

说明：返回不保存，但“开始游戏”保存；因此该字段与玩家名称类似，会在下次进入设置页时回填。

### GameEngine / GameStateFactory（把 icon 写入初始状态）

当前初始状态由 `core/state/game_state_factory.gd` 负责写 `restaurant_logo_id`（完全随机、确定性）。  
为支持“默认随机 + 可指定”的需求，建议做法：

- 扩展初始化调用链，显式注入 `player_restaurant_logo_choices` 或最终 `assigned_logo_ids`：
	- `GameEngine.initialize(...)` 增加可选参数（例如 `restaurant_logo_choices_by_player` 或 `restaurant_logo_ids_by_player`）
	- `core/engine/game_engine/initializer.gd` 透传到 `GameState.create_initial_state_with_rng(...)`
	- `core/state/game_state_factory.gd` 在分配 `restaurant_logo_id` 时使用“固定优先 + 剩余洗牌”算法

这样可保证：

- 回放/存档确定性（logo_id 进入 state）
- core 不依赖 UI/Globals

## 开发计划（分阶段）

> 仅计划，不实施；待你点头后才开始改代码。

### Phase 1：修复返回键（场景栈初始化）

- 修改 `autoload/scene_manager.gd`
	- 在 `_ready()` 时初始化 `current_scene_path`（使用 `current_scene.scene_file_path`）
	- 确保从主菜单首次跳转到设置页时，主菜单路径会被压入 `scene_stack`
- 验收：
	- 从主菜单进入“新游戏/设置页”，点击“返回”能回到主菜单

### Phase 2：设置页 UI 重构为单页分区

- 修改 `ui/scenes/setup/game_setup.tscn`
	- 移除 TabContainer 的运行时插入依赖（或保留脚本创建但不再有 Tab）
	- 增加：玩家设置容器、模块设置容器、全选按钮区、分组容器等节点
- 修改 `ui/scenes/setup/game_setup.gd`
	- 删除 `_ensure_extra_tabs()` / `_rebuild_reserve_rows()` 等 Tab 相关代码
	- 重构 `_refresh_extra_ui()` 为：`_refresh_players_ui()` + `_refresh_modules_ui()`
- 验收：
	- 页面结构符合“上半玩家、中下模块、底部按钮”
	- “储备卡”不再以 Tab 形式出现

### Phase 3：玩家店铺 icon 选择（默认随机、唯一、确定性）

- 修改 `ui/scenes/setup/game_setup.gd`
	- 玩家行：颜色选择改为 icon 选择（OptionButton + 预览 TextureRect）
	- 实现唯一性约束（禁用已被其他玩家选定的 icon）
	- start 时根据 seed 计算最终 logo_id 分配
- 修改 `autoload/globals.gd`
	- 新增并持久化 `player_restaurant_logo_choices`
	- 保留现有 `player_color_indices`（但设置页不再编辑）
- 修改 core 初始化链（见“数据与接口”）
- 验收：
	- 默认全随机时，进入游戏后每位玩家 logo 唯一且与 seed 绑定
	- 指定某玩家 logo 后，其他玩家不能重复选择
	- 返回不保存；开始游戏保存并下次回填

### Phase 4：模块分组 + 全选/分组选 + 依赖/冲突自动处理

- 修改 `ui/scenes/setup/game_setup.gd`
	- 模块列表按分组生成 UI
	- 增加按钮：全选/全不选；每组：组选/组不选
	- 依赖自动勾选并锁定（特别是 `fry_chefs -> sushi/noodles`）
	- 冲突自动取消：
		- `new_milestones` 勾选时取消 `hard_choices`
		- 同时处理 `base_milestones` 替换，以及由此导致的“依赖 base_milestones 的模块”自动取消
	- 保证最终 `enabled_modules_v2` 能通过 `ModulePlanBuilder.build_plan`（可在 start 前做一次校验，失败则弹窗/提示并阻止开始）
- 验收：
	- 分组展示正确
	- 全选/全不选/分组选择按规则工作
	- 任意组合下点“开始游戏”不会因为模块计划错误而初始化失败（或能在设置页被阻止并明确提示）

### Phase 5：测试（建议新增）

- core 逻辑测试（推荐放 `core/tests/`）：
	- 店铺 icon 分配算法：确定性、唯一、尊重显式选择
	- 模块选择消解：依赖锁定与冲突优先级（至少覆盖 `new_milestones` 与 `fry_chefs`）
- UI 测试（可选）：如有现成 test scene，可加 smoke test（打开设置页、触发全选、开始前校验）
- 验收：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过

## 验收清单（最终交付标准）

- 返回键：从主菜单进入设置页，返回能回到主菜单（场景栈工作正常）
- 页面结构：无 Tab；上半玩家设置与玩家数量联动；中下模块分组；底部按钮
- 玩家 icon：
	- 默认随机；不预览；开始游戏时分配
	- 唯一；可手动指定；随机分配确定性（与 seed 绑定）
	- 分配结果写入 `GameState.players[*].restaurant_logo_id`
- 模块：
	- 分组清晰；支持全选/全不选、分组全选/分组全不选
	- 依赖自动勾选并锁定
	- 冲突自动消解（`new_milestones` 优先），且不会导致引擎初始化失败
