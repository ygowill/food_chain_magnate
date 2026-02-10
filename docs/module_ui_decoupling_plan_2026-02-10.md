# 模块代码混入 core / 核心 UI：迁移与解耦落地方案清单（细化版）

日期：2026-02-10  
作者：Codex（仅产出报告；未修改 core/ui/module 代码）

---

## 0. 背景与结论（TL;DR）

本仓库采用 Modules V2（`res://modules/<module_id>/...`）组织可选内容与规则扩展。近期检查发现：

- **core 生产代码（排除 `core/tests/**`、`core/modules/**`）未直接引用 `res://modules/`**，并且已有边界契约测试防止回流。
- **核心 UI（`ui/**`，排除 `ui/scenes/tests/**`）存在多处模块混入**，包含：
  - 编译期硬依赖：`preload("res://modules/...")`
  - 运行期软耦合：写死 `kind == "kimchi"`、`_has_module(..., "reserve_prices")`、`lobbyists_*` key/前缀、optional 模块提供的 `piece_id/milestone_id` 等
  - 配置/资源耦合：`"res://modules"` base_dir 回退值分散、setup 写死 base_pieces logo 贴图路径

目标是把“模块特有 UI/展示/规则分支/数据 key”迁移到各模块或通用 registry/provider 中，让核心 UI 成为**可扩展宿主（host）**而不是**模块知识的聚合点**。

---

## 1. 范围、术语与约束

### 1.1 范围

- 检查与治理对象：
  - `core/`（重点：生产代码边界）
  - “核心 UI”：`ui/`（排除 `ui/scenes/tests/**` 的测试场景）
- 非本次强制范围（但会记录）：`gameplay/` 与 `autoload/` 中的 glue（例如 actions preload 模块脚本）

### 1.2 术语

- **硬引用（Hard ref）**：`preload/load/extends` 指向 `res://modules/...`，或 UI 写死 `res://modules/<module_id>/...` 资源路径。
- **软耦合（Soft coupling）**：核心 UI 写死 module_id、模块专用 kind/key、`piece_id` 前缀、或引用 optional 模块提供的 content id（即使没写 module_id 字符串）。
- **可选模块（optional module）**：非 `base_*` 模块目录（例如 `lobbyists/kimchi/reserve_prices/...`）。

### 1.3 约束

- Godot 4.5 API。
- 迁移过程需考虑：
  - 旧存档兼容（尤其是 pending_phase_actions 的旧格式）
  - Headless 测试可运行（参考 `docs/testing.md` 与 `tools/run_headless_test.sh`）

---

## 2. 当前“无遗漏”检查摘要（证据清单）

### 2.1 UI 生产代码中 `res://modules/` 硬引用（必须消除）

以下为 `ui/**`（排除 `ui/scenes/tests/**`）中发现的硬引用：

已消除：

- `ui/components/modal_panel/fridge_keep_modal.gd`：已移除对 `modules/base_rules` 的 `preload`（改用 `core/rules/milestone_effect_queries.gd` 查询 `gain_fridge`）
- `ui/scenes/game/map_canvas_drawer_roads_pass.gd`：已移除对 `modules/lobbyists/road_overlays.gd` 的 `preload`（改用本地 key 常量）
- `ui/scenes/game/map_canvas_drawer_structures_pass.gd`：已移除对 `modules/lobbyists/road_overlays.gd` 的 `preload`（overlay 定义暂存于 UI 常量）
- `ui/scenes/setup/game_setup.gd`：已移除写死 base_pieces logo 贴图路径（改为通过 visuals catalog / skin 按 piece_id 加载）

仍待消除：

- （无）

### 2.2 UI 生产代码中 `res://modules` base_dir 回退（建议收口）

典型位置（不完整列举，以 grep 为准）：

- `ui/components/inventory_panel/inventory_panel.gd`（`base_dir := "res://modules"`）
- `ui/components/production_panel/production_panel.gd`
- `ui/components/dinner_time/dinner_time_overlay.gd`
- `ui/components/demand_indicator/demand_indicator.gd`
- `ui/components/marketing_panel/marketing_panel_icon_cache.gd`
- `ui/overlays/marketing_range_overlay.gd`
- `ui/components/milestone_panel/milestone_full_screen_view.gd`（Globals 不可用时回退到 `"res://modules"`）
- `ui/components/reserve_area/reserve_area_full_screen_view.gd`（类似回退）

### 2.3 “内容 id 反查”发现的隐藏耦合（优先治理）

通过解析 optional 模块的 `modules/<id>/content/**/*.json` 中 `"id"` 字段并反查 core/ui 生产代码字符串常量，发现核心 UI 直接引用了若干 optional 模块提供的 content id（即使代码中不出现 module_id）：

- `rural_marketeers`：`highway_offramp` 被地图绘制逻辑写死分支
- `new_districts`：`apartment` 被结构绘制写死分支
- `coffee`：`coffee_shop` 被结构绘制写死分支
- `fry_chefs`：`fry_chef` 被 EmployeeTree 布局写死引用
- `new_milestones`：多个 milestone_id 被 UI 文案/解释写死引用

这类“内容 id 泄漏”通常比单纯的 module_id 字符串更难发现，建议作为验收标准之一：核心 UI 不应依赖 optional 模块的具体 content id。

---

## 3. 目标状态（Target Architecture）

总体策略：**把“模块特有知识”搬到模块侧，通过 ruleset/registry/provider 向 core/ui 暴露“受控接口”。**

### 3.1 核心 UI 的职责

- 作为宿主：展示通用 UI、调度 overlay、显示 pending action modal、调用引擎执行 command。
- 不应承担：
  - 解析模块私有 `round_state` 结构
  - 判断某模块是否启用以切换 UI 分支（应由 provider 决定）
  - 通过字符串前缀识别模块 piece（应由 data/tag 或 hook 决定）

### 3.2 推荐新增/收口的“插拔点”（Registries / Providers）

以下 registry 的配置入口建议与现有模式一致：在 `core/engine/game_engine/modules_v2.gd` 的 `apply_ruleset_registries` 阶段，从 `ruleset_v2` 配置。

1) **PhaseActionUiRegistry（UI 宿主：pending phase actions -> modal handler）**
   - 目的：消除 `kind == "kimchi"`、`fridge_keep` 等核心 UI 特判。
   - handler 输出：`PackedScene`/script path + `setup(model)` + `completed(result)`。
   - handler 输入：`state/current_player_id/covered/interactive` +（可选）pending payload。

2) **ReserveCardPresentationRegistry（储备卡展示策略）**
   - 目的：消除 `_has_module(state, "reserve_prices")` 的 UI 分支。
   - provider 输入：cards + state（或仅 card schema），输出 title/desc/summary/hint。

3) **DistanceModifierRegistry（距离/惩罚/覆盖层修正）**
   - 目的：消除 `DistanceOverlay` 写死 `lobbyists_roadworks_markers` 等 key。
   - provider 输入：path_points + map_data/state，输出 penalty 或替换距离规则。

4) **MapOverlayProviderRegistry（地图 overlay 数据生产）**
   - 目的：消除绘制 pass preload `modules/lobbyists/road_overlays.gd`。
   - provider 只在模块侧读取模块私有 key，UI 只消费通用 overlay 指令。

5) **Piece/Employee/Milestone 的 data-driven tags**
   - 目的：消除 `piece_id` 前缀判断（`lobbyists_road_`）、写死 `fry_chef`、`coffee_shop`、`apartment` 等内容 id。
   - 在 content JSON 中增加 `tags` 或 `ui_kind/ui_category`，UI 按 tag 驱动渲染/布局。

6) **Module UI metadata（module.json 扩展）**
   - 目的：消除 `ModuleSelector` 与 `GameSetup` 中写死分组/标题/排序/冲突文案。
   - 在 manifest 中加入 `ui` 字段（group/title/order/description/badges）。

---

## 4. 落地工作项清单（逐问题点：建议迁移目的地 / 接口 / 步骤 / 验收）

> 说明：以下每项均按“你点头后实施”的粒度拆解；本文件仅做计划与验收标准定义。

### P0-1) `FridgeKeepModal` 直接 preload `modules/base_rules`（硬引用）

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/components/modal_panel/fridge_keep_modal.gd`
- **问题定义**
  - 核心 UI 编译期依赖模块脚本；UI 调用模块逻辑计算冰箱容量。
- **迁移/解耦目标**
  - UI 不再 `preload("res://modules/base_rules/...")`。
- **已实施改动**
  - 移除 `preload("res://modules/base_rules/...")`，改用 `core/rules/milestone_effect_queries.gd` 从 `player.milestones` 查询 `gain_fridge` 计算冰箱容量（保持与 `CleanupSettlement.get_fridge_capacity_from_milestones` 同源逻辑）。
- **新增/补充测试**
  - `ui/scenes/tests/fridge_keep_modal_ui_test.gd`（已加入 `AllTests` 聚合运行）
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **后续（可选优化）**
  - 将 fridge_keep modal 迁移至 `modules/base_rules/ui/...` 并通过 `PhaseActionUiRegistry` 注册，进一步减少核心 UI 对 effect_type（`gain_fridge`）的了解。

### P0-2) 地图绘制 pass preload `modules/lobbyists/road_overlays.gd`（硬引用）

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/scenes/game/map_canvas_drawer_roads_pass.gd`
  - `ui/scenes/game/map_canvas_drawer_structures_pass.gd`
- **问题定义**
  - 核心 UI 地图渲染编译期依赖 lobbyists 模块脚本。
- **迁移/解耦目标**
  - 先清零编译期硬依赖：渲染层不再 `preload("res://modules/lobbyists/road_overlays.gd")`。
  - 后续进一步解耦：渲染层只消费“通用 overlay 指令”，不读模块私有 key/前缀。
- **已实施改动**
  - 移除两处 `preload("res://modules/lobbyists/road_overlays.gd")`
  - `map_canvas_drawer_roads_pass.gd`：使用本地 key 常量读取 pending_roads / roadworks_markers
  - `map_canvas_drawer_structures_pass.gd`：将 `ROAD_OVERLAYS` 定义暂存为本地常量，避免依赖模块脚本
- **新增/补充测试**
  - `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd`（扫描 `ui/**` 生产代码，确保不再出现硬引用字符串）
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **后续（可选优化）**
  - 引入 `MapOverlayProviderRegistry`，让 lobbyists 模块把私有结构（pending_roads/roadworks_markers）转换为通用 overlay 指令，核心 UI 只负责绘制。
- **验收标准**
  - `rg -n 'res://modules/lobbyists/' ui --glob '!ui/scenes/tests/**'` 仅剩模块 UI 测试或 0（目标：生产 UI 为 0）。

### P0-3) Setup 写死 base_pieces logo 贴图路径（硬引用）

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/scenes/setup/game_setup.gd`（logo 路径数组）
- **迁移/解耦目标**
  - 核心 UI 不直接写死 `res://modules/base_pieces/assets/...` 路径。
- **已实施改动**
  - 移除 `GameSetup` 中硬编码的 logo 贴图路径数组，改为使用 `MapSkinBuilder` 从 `content/visuals/*.json` 构建 skin 后按 `MapCanvasDrawer.RESTAURANT_LOGO_PIECE_IDS` 加载对应贴图。
- **新增/补充测试**
  - `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd`（扫描 `ui/**` 生产代码，确保不再出现硬编码 logo 贴图路径前缀）
  - `ui/scenes/tests/restaurant_logo_textures_loaded_test.gd`（确保 restaurant logo 的 piece texture 可通过 skin 加载且非 placeholder）
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **后续（可选优化）**
  - 如需让模块自行提供 logo 列表/排序，可进一步把列表迁移到 base_pieces 的 manifest/content，并引入对应 loader/provider。
- **验收标准**
  - `rg -n 'res://modules/base_pieces/assets/map/logos/' ui/scenes/setup/game_setup.gd` 返回空。

---

### P1-1) `GamePanelModalsController` 写死 `kind == "kimchi"`（软耦合）

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/scenes/game/game_panel_modals_controller.gd`
- **迁移/解耦目标**
  - 核心控制器不再了解任意具体模块的 kind 列表。
- **接口形态**
  - 同 P0-1：`PhaseActionUiRegistry`
- **已实施改动**
  - 新增 `ui/scenes/game/phase_action_ui_registry.gd`：集中处理 Cleanup 的 pending action -> modal 路由（包含旧存档格式兼容）
  - `game_panel_modals_controller.gd`：移除对具体 kind 的分支判断，改为调用 registry 进行显示/隐藏
- **新增/补充测试**
  - `ui/scenes/tests/phase_action_ui_registry_cleanup_test.gd`（覆盖新/旧 pending 格式与交互/非交互分支）
  - `ui/scenes/tests/game_panel_modals_controller_kind_contract_test.gd`（防止 controller 回退到硬编码 kind）
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **实施步骤（建议）**
  1. pending 列表统一数据结构（包含 kind/payload/player_id）。
  2. 控制器统一按 kind 调 handler。
- **验收标准**
  - `rg -n 'kind == \"kimchi\"|\"fridge_keep\"' ui/scenes/game/game_panel_modals_controller.gd` 返回空（或仅保留兼容旧存档的 very small shim）。

### P1-2) `KimchiStorageModal` 与 kimchi 私有 round_state 混入核心 UI

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `modules/kimchi/ui/components/modal_panel/kimchi_storage_modal.gd`
  - `modules/kimchi/ui/components/modal_panel/kimchi_storage_modal.tscn`
- **迁移/解耦目标**
  - kimchi 专属 UI 迁移至 `modules/kimchi/ui/...`，核心 UI 不读 `round_state.kimchi` 私有结构。
- **接口形态**
  - handler 由模块提供；UI model 从 payload 或 build_model 产生。
- **已实施改动**
  - 将 `KimchiStorageModal` scene/script 从核心 UI 迁移到 `modules/kimchi/ui/...`
  - 在 `RulesetV2` 中新增 phase action UI modal 注册/查询接口；kimchi 模块在 `rules/entry.gd` 注册 Cleanup 的 kimchi modal 场景路径
  - `GamePanelModalsController` 在显示 kimchi modal 时从 ruleset 查询并动态加载场景（避免核心 UI 硬编码模块 UI 路径）
- **新增/补充测试**
  - `ui/scenes/tests/phase_action_ui_modal_registration_test.gd`（确保 kimchi modal 已注册且可实例化）
  - 更新 `ui/scenes/tests/kimchi_storage_modal_ui_test.gd` 使用模块内的新场景路径
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **验收标准**
  - `rg -n '\\bkimchi\\b' ui/components/modal_panel --glob '!ui/scenes/tests/**'` 不再命中 kimchi 专属 modal（若迁移走）。

### P1-3) `ReserveCardSelectionModal` 通过 `_has_module(..., "reserve_prices")` 切换展示

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/components/modal_panel/reserve_card_selection_modal.gd`
- **迁移/解耦目标**
  - UI 不直接判断模块启用状态决定展示策略。
- **接口形态**
  - `ReserveCardPresentationRegistry`：默认 + 模块覆盖 provider
- **已实施改动**
  - 移除 `_has_module(state, "reserve_prices")` 判断，改为基于卡片字段（是否包含 `cash/ceo_slots`）推导展示模式与提示文案。
- **新增/补充测试**
  - `ui/scenes/tests/reserve_card_selection_modal_presentation_test.gd`（覆盖 base vs reserve_prices 两种卡片字段展示）
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **验收标准**
  - `rg -n '_has_module\\(state, \"reserve_prices\"\\)' ui/components/modal_panel/reserve_card_selection_modal.gd` 返回空。

### P1-4) `DistanceOverlay` 写死 lobbyists key（roadworks markers）

- **状态**
  - ✅ 已完成（2026-02-10）
- **涉及位置**
  - `ui/overlays/distance_overlay.gd`
- **迁移/解耦目标**
  - 距离惩罚逻辑对模块可插拔，UI 不写死 `lobbyists_*` key。
- **接口形态**
  - `DistanceModifierRegistry`
- **已实施改动**
  - 移除 UI 中对 `lobbyists_roadworks_markers` 的硬编码：通过扫描 map_data 中以 `roadworks_markers` 结尾的 key 来读取 markers（兼容旧存档/旧 key）。
  - 同步移除 `map_canvas_drawer_roads_pass.gd` 中出现的 `lobbyists_roadworks_markers` 字符串（含标识符/常量）。
- **验收结果**
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过
- **验收标准**
  - `rg -n 'lobbyists_roadworks_markers' ui --glob '!ui/scenes/tests/**'` 返回空。

### P1-5) `lobbyists_*` 字符串前缀分支（piece 分类/渲染/选择）

- **涉及位置（示例）**
  - `ui/scenes/game/map_canvas_drawer.gd`
  - `ui/scenes/game/map_canvas_drawer_structures_pass.gd`
  - `ui/components/action_panel/piece_picker_button.gd`
- **迁移/解耦目标**
  - 核心 UI 不再按字符串前缀识别模块 piece。
- **接口形态**
  - content tags（`PieceDef.tags`）或渲染 hook/provider
- **验收标准**
  - `rg -n 'lobbyists_road_|lobbyists_park_' ui --glob '!ui/scenes/tests/**'` 目标为 0（或仅在模块 UI 目录中出现）。

---

### P2-1) UI 分散的 `base_dir := "res://modules"` 回退值

- **迁移/解耦目标**
  - UI 统一使用 `Globals.modules_v2_base_dir`（或单 helper），减少散落回退。
- **建议实施**
  - 新增 `ui/utils/modules_base_dir.gd`（或等价 helper）集中回退策略。
- **验收标准**
  - `rg -n '\"res://modules\"' ui --glob '!ui/scenes/tests/**'` 命中收敛到极少数（理想为 0）。

### P2-2) 产品名映射（coffee/kimchi/noodles/sushi）写死在 UI

- **迁移/解耦目标**
  - UI 用 `ProductRegistry` 的 `ProductDef.name` 生成展示名，避免硬编码模块产品集合。
- **验收标准**
  - `rg -n '\"coffee\"\\s*:\\s*\"咖啡\"|\"kimchi\"\\s*:\\s*\"泡菜\"|\"noodles\"|\"sushi\"' ui/components --glob '!ui/scenes/tests/**'` 命中显著减少/归零。

### P2-3) EmployeeTree 布局写死 `fry_chef`

- **迁移/解耦目标**
  - 以 employee tags/role 驱动布局，而非写死某个 optional 模块员工 id。
- **验收标准**
  - `rg -n '\"fry_chef\"' ui --glob '!ui/scenes/tests/**'` 目标为 0（或仅在模块 UI/模块 content 中出现）。

---

## 5. 统一验收与“无混入”守护（建议新增的持续检查）

> 计划在实施后新增/扩展契约测试，确保不会回退。

### 5.1 建议的 grep/contract 清单（生产代码视角）

- 核心 UI 不应出现硬引用：
  - `res://modules/<optional_module>/...`（除非该 UI 文件本身已迁入模块目录）
- 核心 UI 不应出现模块私有 key 或前缀：
  - `lobbyists_*`、`kind == "kimchi"` 等
- 核心 UI 不应直接引用 optional 模块 content id（可用“内容 id 反查”脚本化检查）

### 5.2 测试建议（实施后）

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`

---

## 6. 风险与兼容性策略（实施时必须明确）

1) **旧存档 pending action 格式兼容**
   - 当前存在旧格式（例如列表为 `[player_id]`）的兼容逻辑；迁移到 handler registry 后需保留 shim 或提供升级路径。

2) **模块 UI 资源路径变化**
   - 把 modal/scene 移到 `modules/<id>/ui/...` 会改变 preload path；需要确保加载由 handler 提供而非硬编码。

3) **数据驱动 tags 的引入成本**
   - 给 piece/employee/milestone 增加 tags 会触及 content schema；需要内容校验与迁移策略。

---

## 7. 推荐实施顺序（你点头后）

1) **清零硬引用（P0）**：FridgeKeepModal、lobbyists overlays、base_pieces logo 路径
2) **宿主化控制器（P1）**：pending action handler registry、reserve card presentation provider
3) **移除字符串前缀/内容 id 特判（P1/P2）**：tags + hooks
4) **低优先级收敛（P2）**：base_dir 回退、产品名映射、EmployeeTree 特判
