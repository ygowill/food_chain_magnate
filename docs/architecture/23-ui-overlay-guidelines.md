# UI 遮罩与覆盖层清单（`ui/` / `modules/*/ui/`）

本文档用于回答三个问题：

1. 哪些节点属于“标准弹窗遮罩”，应该统一风格？
2. 哪些节点虽然也是全屏覆盖，但属于故意例外，不应强行统一？
3. 后续新增弹窗时，应该接入哪条维护路径？

当前统一标准色定义在：

- `ui/utils/ui_styles.gd`
	- `UiStyles.COLOR_OVERLAY_DIM = Color(0.05, 0.04, 0.03, 0.75)`
	- `UiStyles.apply_overlay_dim()`

## 1. 标准弹窗遮罩

这类节点语义上都属于“模态弹窗遮罩”：用于压暗底层界面、阻断背后交互，并把注意力集中到当前弹窗。

维护要求：

- 新增此类弹窗时，优先复用基类，不要手写一套新的遮罩颜色
- 视觉标准统一为 `UiStyles.apply_overlay_dim()`
- 若必须偏离统一值，应先说明原因，并补文档

### 1.1 `ModalDialogBase` 体系

入口：

- `ui/components/modal_dialog/modal_dialog_base.gd`

这类适合常规对话框、欢迎弹窗、信息提示、设置弹窗、全屏教学卡片等。

#### 场景型

- `ui/dialogs/confirm_dialog.tscn`
- `ui/dialogs/choice_dialog.tscn`
- `ui/dialogs/game_config_dialog.tscn`
- `ui/dialogs/rules_viewer_dialog.tscn`
- `ui/dialogs/settings_dialog.tscn`
- `ui/components/tutorial/tutorial_spotlight_overlay.tscn`

#### 动态构建型

- `ui/dialogs/auth_dialog.gd`
- `ui/dialogs/password_dialog.gd`
- `ui/dialogs/create_room_dialog.gd`
- `ui/dialogs/account_settings_dialog.gd`
- `ui/dialogs/info_dialog.gd`
- `ui/dialogs/save_load_dialog.gd`
- `ui/scenes/game/dialogs/online_game_details_dialog.gd`

这些脚本会在运行时创建 `Overlay` 节点，但仍然通过 `ModalDialogBase.overlay_color` 继承统一遮罩风格。

### 1.2 `ModalPanelBase` 体系

入口：

- `ui/components/modal_panel/modal_panel_base.gd`

这类适合“游戏内覆盖式操作面板”，例如储备卡选择、重组、清理阶段的强制选择。

当前归属此体系的面板：

- `ui/components/modal_panel/reserve_card_selection_modal.tscn`
- `ui/components/modal_panel/turn_order_selection_modal.tscn`
- `ui/components/modal_panel/restructuring_modal.tscn`
- `modules/base_rules/ui/components/modal_panel/fridge_keep_modal.tscn`
- `modules/kimchi/ui/components/modal_panel/kimchi_storage_modal.tscn`

### 1.3 其他已纳入标准遮罩的模态层

这些节点没有直接继承上述两个基类，但语义上仍然属于“标准模态遮罩”，因此也应保持一致。

- `ui/scenes/game/game.tscn`
	- `MenuDialog/Overlay`
- `ui/components/bank_break/bank_break_panel.tscn`
	- `Background`

## 2. 故意例外的覆盖层

这类节点虽然也是全屏覆盖，但语义不是“普通弹窗遮罩”。它们可以保留与标准遮罩不同的透明度或表现方式。

### 2.1 全屏浏览或终局展示

这类界面更接近“独立页面”或“强聚焦浏览页”，通常会使用更重的遮挡或不同底色。

- `ui/components/reserve_cards/reserve_cards_full_screen_view.tscn`
	- `Background = Color(0.05, 0.04, 0.03, 0.85)`
- `ui/components/reserve_area/reserve_area_full_screen_view.tscn`
	- `Background = Color(0.05, 0.04, 0.03, 0.85)`
- `ui/components/game_over/game_over_panel.tscn`
	- `Background = Color(0.05, 0.04, 0.03, 0.85)`
- `ui/components/milestone_panel/milestone_full_screen_view.tscn`
	- `Background = Color(0.97, 0.94, 0.86, 0.98)`

其中 `milestone_full_screen_view` 不是 dim 蒙层，而是偏“说明页 / 展示页”的浅色底板。

### 2.2 强阻断模式

这类覆盖层的目标是强制阻断交互，不适合使用普通弹窗的半透明遮罩标准。

- `ui/components/loading/loading_overlay.tscn`
	- `Blocker = Color(0.05, 0.04, 0.03, 1.0)`
- `modules/lobbyists/ui/components/lobbyists_extra_tile/lobbyists_extra_tile_overlay.tscn`
	- `Background = Color(0.08, 0.09, 0.1, 0.92)`

### 2.3 场景氛围层（Vignette）

这些节点不是弹窗蒙层，而是场景背景氛围层，统一走 `UiStyles.apply_vignette()`。

- `ui/scenes/main_menu.tscn`
	- `VignetteOverlay`
- `ui/scenes/online/online_lobby.tscn`
	- `VignetteOverlay`
- `ui/scenes/setup/game_setup.tscn`
	- `VignetteOverlay`
- `ui/scenes/game/game.tscn`
	- `VignetteOverlay`

### 2.4 游戏过程中的功能型视觉覆盖

这些覆盖层是玩法反馈，不应混入弹窗遮罩规则。

- `ui/overlays/marketing_range_overlay.gd`
	- 营销范围与标记可视化
- `ui/scenes/game/dinnertime/map_helpers.gd`
	- 晚餐阶段阴影 / 辅助表现

## 3. 名字叫 `Background`，但不是遮罩

仓库里很多组件都有一个名为 `Background` 的 `ColorRect`，但它们只是面板底板，不是模态蒙层。

这些不属于“遮罩统一”范围：

- `ui/components/action_panel/action_panel.tscn`
- `ui/components/player_panel/player_panel.tscn`
- `ui/components/inventory_panel/inventory_panel.tscn`
- `ui/components/hand_area/hand_area.tscn`
- `ui/components/company_structure/company_structure.tscn`
- `ui/components/employee_tree/employee_tree.tscn`
- `ui/components/left_panel/left_panel.tscn`
- `ui/components/marketing_panel/marketing_panel.tscn`
- `ui/components/production_panel/production_panel.tscn`
- `ui/components/recruit_panel/recruit_panel.tscn`
- `ui/components/payday_panel/payday_panel.tscn`
- `ui/components/price_panel/price_setting_panel.tscn`
- `ui/components/milestone_panel/milestone_panel.tscn`
- `ui/components/game_log/game_log_panel.tscn`
- `ui/components/turn_order/turn_order_track.tscn`
- `ui/components/turn_order/turn_order_display.tscn`

判断原则不是看节点名，而是看它是否同时满足：

- 全屏铺满或覆盖主要交互区域
- 语义上用于压暗底层界面
- 需要阻断底层交互

不满足这三点的，一般只是组件底板。

## 4. 维护规则

### 4.1 新增普通弹窗

优先选以下两条路径：

- 常规对话框：继承 `ModalDialogBase`
- 游戏内覆盖式操作面板：继承 `ModalPanelBase`

这样可以自动获得统一遮罩风格。

### 4.2 新增例外覆盖层

如果新增的覆盖层属于以下情况，可以不走标准 `0.75` 遮罩：

- 全屏浏览页
- 终局页
- 加载阻断页
- 特殊玩法模式（例如强制地图放置模式）
- 氛围层 / 玩法辅助层

但需要满足两个条件：

- 在代码中能看出其语义确实不同
- 在本文件或相邻文档中说明原因

### 4.3 不要把局部装饰层误判成遮罩

例如：

- `ui/components/modal_panel/reserve_card_selection_modal.tscn` 内部卡片的浅色块
- `ui/components/modal_panel/restructuring_modal.tscn` 中局部背景条

这些只是弹窗内部装饰，不是外层蒙版，不应纳入遮罩统一规则。

## 5. 测试契约

标准弹窗遮罩的回归测试位于：

- `ui/scenes/tests/modal_overlay_opacity_contract_test.gd`

当前测试重点检查：

- 标准遮罩主色是否统一
- 标准遮罩透明度是否统一

后续如果新增“标准弹窗遮罩”类型，应把对应场景或脚本加入这个测试，避免出现新的风格漂移。

## 6. 当前建议

当前仓库的维护建议如下：

1. 标准模态弹窗继续统一走 `UiStyles.apply_overlay_dim()`
2. 例外覆盖层保留差异，但不要无说明地新增新的色值体系
3. 后续如要继续收敛，可把“标准遮罩”和“例外遮罩”进一步提炼为独立 token，例如：
	- `COLOR_OVERLAY_DIM_STANDARD`
	- `COLOR_OVERLAY_DIM_HEAVY`
	- `COLOR_OVERLAY_BLOCKING`

当前阶段先保持“标准弹窗统一，例外显式保留”的策略即可。
