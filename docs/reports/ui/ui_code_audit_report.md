# ui/ 代码评估报告 (2026-02-17)

## 范围
- 项目路径：`/Users/qinkai/Documents/FCM_new`
- 扫描目录：`ui/`
- 文件总数：619
- 类型统计：`.uid`=264, `.gd`=262, `.tscn`=78, `.tres`=13, `.gdshader`=2

## 方法与限制
- 本报告基于**静态扫描**：解析 `res://ui/...` 路径引用、`uid://...` 引用，并对 `class_name` 做启发式使用点检索。
- 已**排除**隐藏/生成目录（如 `.godot/`）的引用结果，避免把缓存文件当作“使用证据”。
- 限制：动态拼接路径 `load("res://ui/%s" % x)`、运行时反射、Editor-only 预览等可能导致“静态未引用但运行时仍会用到”。因此本报告用词为“疑似未使用”，需要人工确认。

## 总览结论
- 引用/使用分类统计：`runtime`=413, `test`=185, `unused?(no static refs)`=10, `test_only`=5, `test?(no static refs)`=5, `entrypoint(runtime)`=1
- 重复实现：未发现**完全一致**的脚本重复（按去注释/去空行规范化哈希）。
- 高相似脚本（>=0.96）：6 个脚本存在近重复（主要集中在测试契约用例）。

## 疑似未使用（需要人工确认）
- `ui/components/employee_card/employee_card.tscn` (.tscn, 8 行)
- `ui/components/employee_icon/employee_icon.tscn` (.tscn, 30 行)
- `ui/components/game_log/full_log_window.tscn` (.tscn, 46 行)
- `ui/components/modal_dialog/modal_dialog_base.gd.uid` (.uid, 1 行)
- `ui/components/modal_panel/modal_panel_base.tscn` (.tscn, 76 行)
- `ui/overlays/base_tile_overlay.gd.uid` (.uid, 1 行)
- `ui/overlays/marketing_range_overlay.tscn` (.tscn, 14 行)
- `ui/scenes/game/game_overlay_dinnertime.gd` (.gd, 146 行)
- `ui/scenes/game/game_overlay_dinnertime.gd.uid` (.uid, 2 行)
- `ui/scenes/replay_test.tscn` (.tscn, 41 行)

## 逐文件清单（不遗漏）
说明：`notes` 为空（显示为 `—`）表示静态扫描未发现显著设计/冗余/未使用问题；并不等同于代码绝对没有问题。

| 路径 | 类型 | 行数 | 使用 | 关键信息 | 发现/建议 |
|---|---:|---:|---|---|---|
| `ui/audio/audio_system_initializer.gd` | .gd | 64 | runtime | class `AudioSystemInitializer`, extends `Node` | — |
| `ui/audio/audio_system_initializer.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/audio/audio_system_initializer.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/audio/audio_system_initializer.tscn` | .tscn | 7 | runtime | root `Node` | — |
| `ui/audio/music_manager.gd` | .gd | 282 | runtime | class `MusicManager`, extends `Node` | — |
| `ui/audio/music_manager.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/audio/music_manager.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/audio/music_manager.tscn` | .tscn | 7 | runtime | root `Node` | — |
| `ui/audio/sound_manager.gd` | .gd | 327 | runtime | class `SoundManager`, extends `Node` | — |
| `ui/audio/sound_manager.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/audio/sound_manager.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/audio/sound_manager.tscn` | .tscn | 7 | runtime | root `Node` | — |
| `ui/components/action_flow_controls/action_flow_controls.gd` | .gd | 102 | runtime | class `ActionFlowControls`, extends `VBoxContainer` | — |
| `ui/components/action_flow_controls/action_flow_controls.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/action_flow_controls/action_flow_controls.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/action_flow_controls/action_flow_controls.tscn` | .tscn | 32 | runtime | root `VBoxContainer` | — |
| `ui/components/action_panel/action_panel.gd` | .gd | 973 | runtime | class `ActionPanel`, extends `Control` | 大型脚本(>=800行): 可能职责过多 |
| `ui/components/action_panel/action_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/action_panel/action_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/action_panel/action_panel.tscn` | .tscn | 264 | runtime | root `Control` | — |
| `ui/components/action_panel/action_panel_context_controller.gd` | .gd | 683 | runtime | extends `RefCounted` | — |
| `ui/components/action_panel/action_panel_context_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/action_panel/action_panel_context_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/action_panel/piece_picker_button.gd` | .gd | 212 | runtime | extends `Button` | — |
| `ui/components/action_panel/piece_picker_button.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/action_panel/piece_picker_button.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/bank_break/bank_break_panel.gd` | .gd | 139 | runtime | class `BankBreakPanel`, extends `Control` | — |
| `ui/components/bank_break/bank_break_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/bank_break/bank_break_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/bank_break/bank_break_panel.tscn` | .tscn | 70 | runtime | root `Control` | — |
| `ui/components/common/panel_zoom_bar.gd` | .gd | 93 | runtime | class `PanelZoomBar`, extends `HBoxContainer` | — |
| `ui/components/common/panel_zoom_bar.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/common/panel_zoom_bar.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/common/panel_zoom_bar.tscn` | .tscn | 34 | runtime | root `HBoxContainer` | — |
| `ui/components/common/right_panel_embeddable_panel.gd` | .gd | 126 | runtime | class `RightPanelEmbeddablePanel`, extends `Control` | 特征: await |
| `ui/components/common/right_panel_embeddable_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/common/right_panel_embeddable_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/company_structure/company_structure.gd` | .gd | 812 | runtime | class `CompanyStructure`, extends `Control` | 大型脚本(>=800行): 可能职责过多 |
| `ui/components/company_structure/company_structure.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/company_structure/company_structure.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/company_structure/company_structure.tscn` | .tscn | 95 | runtime | root `Control` | — |
| `ui/components/company_structure/company_structure_card_slot.gd` | .gd | 87 | runtime | class `CompanyStructureCardSlot`, extends `PanelContainer` | — |
| `ui/components/company_structure/company_structure_card_slot.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/company_structure/company_structure_card_slot.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/demand_indicator/demand_indicator.gd` | .gd | 273 | runtime | class `DemandIndicator`, extends `Control` | 特征: await |
| `ui/components/demand_indicator/demand_indicator.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/demand_indicator/demand_indicator.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/demand_indicator/demand_indicator.tscn` | .tscn | 14 | runtime | root `Control` | — |
| `ui/components/dinner_time/dinner_time_overlay.gd` | .gd | 363 | runtime | class `DinnerTimeOverlay`, extends `Control` | 特征: await |
| `ui/components/dinner_time/dinner_time_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/dinner_time/dinner_time_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/dinner_time/dinner_time_overlay.tscn` | .tscn | 119 | runtime | root `Control` | — |
| `ui/components/employee_card/employee_card.gd` | .gd | 689 | runtime | class `EmployeeCard`, extends `PanelContainer` | — |
| `ui/components/employee_card/employee_card.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_card/employee_card.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_card/employee_card.tscn` | .tscn | 8 | unused?(no static refs) | root `PanelContainer` | — |
| `ui/components/employee_card_preview/employee_card_preview_manager.gd` | .gd | 280 | runtime | class `EmployeeCardPreviewManager`, extends `CanvasLayer` | — |
| `ui/components/employee_card_preview/employee_card_preview_manager.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_card_preview/employee_card_preview_manager.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_card_preview/employee_card_preview_manager.tscn` | .tscn | 27 | runtime | root `CanvasLayer` | — |
| `ui/components/employee_icon/employee_icon.gd` | .gd | 159 | runtime | class `EmployeeIcon`, extends `PanelContainer` | — |
| `ui/components/employee_icon/employee_icon.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_icon/employee_icon.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_icon/employee_icon.tscn` | .tscn | 30 | unused?(no static refs) | root `PanelContainer` | — |
| `ui/components/employee_picker/employee_picker.gd` | .gd | 347 | runtime | class `EmployeePicker`, extends `HFlowContainer` | — |
| `ui/components/employee_picker/employee_picker.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_picker/employee_picker.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_tree/employee_tree.gd` | .gd | 394 | runtime | class `EmployeeTree`, extends `Control` | 特征: await |
| `ui/components/employee_tree/employee_tree.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_tree/employee_tree.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_tree/employee_tree.tscn` | .tscn | 94 | runtime | root `Control` | — |
| `ui/components/employee_tree/employee_tree_graph.gd` | .gd | 344 | runtime | class `EmployeeTreeGraph`, extends `Control` | — |
| `ui/components/employee_tree/employee_tree_graph.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_tree/employee_tree_graph.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/employee_tree/employee_tree_layout.gd` | .gd | 588 | runtime | class `EmployeeTreeLayout`, extends `RefCounted` | — |
| `ui/components/employee_tree/employee_tree_layout.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/employee_tree/employee_tree_layout.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/full_log_window.gd` | .gd | 52 | runtime | class `FullLogWindow`, extends `Window` | — |
| `ui/components/game_log/full_log_window.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/full_log_window.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/full_log_window.tscn` | .tscn | 46 | unused?(no static refs) | root `Window` | — |
| `ui/components/game_log/game_log_action_group_header_item.gd` | .gd | 234 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/game_log_action_group_header_item.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_action_group_header_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_details_window_controller.gd` | .gd | 76 | runtime | extends `RefCounted` | — |
| `ui/components/game_log/game_log_details_window_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_details_window_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_employee_preview_links.gd` | .gd | 192 | runtime | class `GameLogEmployeePreviewLinks`, extends `RefCounted` | — |
| `ui/components/game_log/game_log_employee_preview_links.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_employee_preview_links.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_entry_utils.gd` | .gd | 79 | runtime | extends `RefCounted` | — |
| `ui/components/game_log/game_log_entry_utils.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_entry_utils.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_event_item.gd` | .gd | 211 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/game_log_event_item.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_event_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_item.gd` | .gd | 270 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/game_log_item.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_panel.gd` | .gd | 758 | runtime | class `GameLogPanel`, extends `Control` | — |
| `ui/components/game_log/game_log_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_panel.tscn` | .tscn | 105 | runtime | root `Control` | — |
| `ui/components/game_log/game_log_phase_header_item.gd` | .gd | 91 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/game_log_phase_header_item.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_phase_header_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_round_header_item.gd` | .gd | 72 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/game_log_round_header_item.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_round_header_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/game_log_unified_timeline_builder.gd` | .gd | 456 | runtime | extends `RefCounted` | — |
| `ui/components/game_log/game_log_unified_timeline_builder.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/game_log_unified_timeline_builder.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/replay_bar.gd` | .gd | 145 | runtime | extends `PanelContainer` | — |
| `ui/components/game_log/replay_bar.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_log/replay_bar.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_log/replay_bar.tscn` | .tscn | 70 | runtime | root `PanelContainer` | — |
| `ui/components/game_over/game_over_panel.gd` | .gd | 396 | runtime | class `GameOverPanel`, extends `Control` | — |
| `ui/components/game_over/game_over_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/game_over/game_over_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/game_over/game_over_panel.tscn` | .tscn | 82 | runtime | root `Control` | — |
| `ui/components/hand_area/hand_area.gd` | .gd | 377 | runtime | class `HandArea`, extends `Control` | — |
| `ui/components/hand_area/hand_area.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/hand_area/hand_area.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/hand_area/hand_area.tscn` | .tscn | 104 | runtime | root `Control` | — |
| `ui/components/help_tooltip/help_tooltip_manager.gd` | .gd | 250 | runtime | class `HelpTooltipManager`, extends `CanvasLayer` | — |
| `ui/components/help_tooltip/help_tooltip_manager.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/help_tooltip/help_tooltip_manager.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/help_tooltip/help_tooltip_manager.tscn` | .tscn | 39 | runtime | root `CanvasLayer` | — |
| `ui/components/house_placement/house_placement_overlay.gd` | .gd | 273 | runtime | class `HousePlacementOverlay`, extends `Control` | — |
| `ui/components/house_placement/house_placement_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/house_placement/house_placement_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/house_placement/house_placement_overlay.tscn` | .tscn | 39 | runtime | root `VBoxContainer` | — |
| `ui/components/inventory_panel/inventory_panel.gd` | .gd | 220 | runtime | class `InventoryPanel`, extends `Control` | — |
| `ui/components/inventory_panel/inventory_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/inventory_panel/inventory_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/inventory_panel/inventory_panel.tscn` | .tscn | 46 | runtime | root `Control` | — |
| `ui/components/left_panel/left_panel.gd` | .gd | 1394 | runtime | class `LeftPanel`, extends `Control` | 大型脚本(>=800行): 可能职责过多 |
| `ui/components/left_panel/left_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/left_panel/left_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/left_panel/left_panel.tscn` | .tscn | 272 | runtime | root `Control` | — |
| `ui/components/left_panel/left_panel_employee_icons_controller.gd` | .gd | 270 | runtime | extends `RefCounted` | — |
| `ui/components/left_panel/left_panel_employee_icons_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/left_panel/left_panel_employee_icons_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/left_panel/left_panel_turn_log_controller.gd` | .gd | 172 | runtime | extends `RefCounted` | — |
| `ui/components/left_panel/left_panel_turn_log_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/left_panel/left_panel_turn_log_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/loading/loading_overlay.gd` | .gd | 45 | runtime | class `LoadingOverlay`, extends `CanvasLayer` | — |
| `ui/components/loading/loading_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/loading/loading_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/loading/loading_overlay.tscn` | .tscn | 71 | runtime | root `CanvasLayer` | — |
| `ui/components/map_mode_bar/map_mode_bar.gd` | .gd | 27 | runtime | class `MapModeBar`, extends `Control` | — |
| `ui/components/map_mode_bar/map_mode_bar.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/map_mode_bar/map_mode_bar.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/map_mode_bar/map_mode_bar.tscn` | .tscn | 69 | runtime | root `VBoxContainer` | — |
| `ui/components/marketing_panel/marketing_board_button.gd` | .gd | 154 | runtime | extends `Button` | — |
| `ui/components/marketing_panel/marketing_board_button.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/marketing_panel/marketing_board_button.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/marketing_panel/marketing_panel.gd` | .gd | 786 | runtime | class `MarketingPanel`, extends `"res://ui/components/common/right_panel_embeddable_panel.gd"` | — |
| `ui/components/marketing_panel/marketing_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/marketing_panel/marketing_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/marketing_panel/marketing_panel.tscn` | .tscn | 207 | runtime | root `Control` | — |
| `ui/components/marketing_panel/marketing_panel_icon_cache.gd` | .gd | 158 | runtime | extends `RefCounted` | — |
| `ui/components/marketing_panel/marketing_panel_icon_cache.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/marketing_panel/marketing_panel_icon_cache.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/marketing_panel/marketing_type_button.gd` | .gd | 125 | runtime | extends `PanelContainer` | — |
| `ui/components/marketing_panel/marketing_type_button.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/components/marketing_panel/marketing_type_button.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/milestone_panel/milestone_full_screen_view.gd` | .gd | 765 | runtime | class `MilestoneFullScreenView`, extends `Control` | 特征: await |
| `ui/components/milestone_panel/milestone_full_screen_view.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/milestone_panel/milestone_full_screen_view.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/milestone_panel/milestone_full_screen_view.tscn` | .tscn | 82 | runtime | root `Control` | — |
| `ui/components/milestone_panel/milestone_panel.gd` | .gd | 650 | runtime | class `MilestonePanel`, extends `Control` | — |
| `ui/components/milestone_panel/milestone_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/milestone_panel/milestone_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/milestone_panel/milestone_panel.tscn` | .tscn | 62 | runtime | root `Control` | — |
| `ui/components/milestone_panel/milestone_preview_card.gd` | .gd | 100 | runtime | class `MilestonePreviewCard`, extends `PanelContainer` | — |
| `ui/components/milestone_panel/milestone_preview_card.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/milestone_panel/milestone_preview_card.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_dialog/modal_dialog_base.gd` | .gd | 50 | runtime | class `ModalDialogBase`, extends `Control` | — |
| `ui/components/modal_dialog/modal_dialog_base.gd.uid` | .uid | 1 | unused?(no static refs) | sidecar -> `ui/components/modal_dialog/modal_dialog_base.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_panel/modal_panel_base.gd` | .gd | 213 | runtime | class `ModalPanelBase`, extends `Control` | — |
| `ui/components/modal_panel/modal_panel_base.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/modal_panel/modal_panel_base.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_panel/modal_panel_base.tscn` | .tscn | 76 | unused?(no static refs) | root `Control` | — |
| `ui/components/modal_panel/reserve_card_selection_modal.gd` | .gd | 330 | runtime | class `ReserveCardSelectionModal`, extends `"res://ui/components/modal_panel/modal_panel_base.gd"` | — |
| `ui/components/modal_panel/reserve_card_selection_modal.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/modal_panel/reserve_card_selection_modal.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_panel/reserve_card_selection_modal.tscn` | .tscn | 240 | runtime | root `Control` | — |
| `ui/components/modal_panel/restructuring_modal.gd` | .gd | 240 | runtime | class `RestructuringModal`, extends `"res://ui/components/modal_panel/modal_panel_base.gd"` | — |
| `ui/components/modal_panel/restructuring_modal.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/modal_panel/restructuring_modal.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_panel/restructuring_modal.tscn` | .tscn | 129 | runtime | root `Control` | — |
| `ui/components/modal_panel/turn_order_selection_modal.gd` | .gd | 81 | runtime | class `TurnOrderSelectionModal`, extends `"res://ui/components/modal_panel/modal_panel_base.gd"` | — |
| `ui/components/modal_panel/turn_order_selection_modal.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/modal_panel/turn_order_selection_modal.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/modal_panel/turn_order_selection_modal.tscn` | .tscn | 92 | runtime | root `Control` | — |
| `ui/components/module_selector/module_selector.gd` | .gd | 919 | runtime | extends `VBoxContainer` | 大型脚本(>=800行): 可能职责过多 |
| `ui/components/module_selector/module_selector.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/module_selector/module_selector.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/payday_panel/payday_panel.gd` | .gd | 767 | runtime | class `PaydayPanel`, extends `Control` | — |
| `ui/components/payday_panel/payday_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/payday_panel/payday_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/payday_panel/payday_panel.tscn` | .tscn | 112 | runtime | root `Control` | — |
| `ui/components/phase_track/phase_track_strip.gd` | .gd | 259 | runtime | class `PhaseTrackStrip`, extends `Control` | — |
| `ui/components/phase_track/phase_track_strip.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/phase_track/phase_track_strip.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/piece_placement/piece_placement_overlay.gd` | .gd | 203 | runtime | class `PiecePlacementOverlay`, extends `Control` | — |
| `ui/components/piece_placement/piece_placement_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/piece_placement/piece_placement_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/piece_placement/piece_placement_overlay.tscn` | .tscn | 40 | runtime | root `VBoxContainer` | — |
| `ui/components/player_panel/player_info_item.gd` | .gd | 172 | test_only | class `PlayerInfoItem`, extends `PanelContainer` | — |
| `ui/components/player_panel/player_info_item.gd.uid` | .uid | 1 | test_only | sidecar -> `ui/components/player_panel/player_info_item.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/player_panel/player_panel.gd` | .gd | 327 | runtime | class `PlayerPanel`, extends `Control` | — |
| `ui/components/player_panel/player_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/player_panel/player_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/player_panel/player_panel.tscn` | .tscn | 93 | runtime | root `Control` | — |
| `ui/components/price_panel/price_setting_panel.gd` | .gd | 112 | runtime | class `PriceSettingPanel`, extends `Control` | — |
| `ui/components/price_panel/price_setting_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/price_panel/price_setting_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/price_panel/price_setting_panel.tscn` | .tscn | 68 | runtime | root `Control` | — |
| `ui/components/production_panel/production_panel.gd` | .gd | 958 | runtime | class `ProductionPanel`, extends `"res://ui/components/common/right_panel_embeddable_panel.gd"` | 大型脚本(>=800行): 可能职责过多 |
| `ui/components/production_panel/production_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/production_panel/production_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/production_panel/production_panel.tscn` | .tscn | 82 | runtime | root `Control` | — |
| `ui/components/recruit_panel/recruit_panel.gd` | .gd | 196 | runtime | class `RecruitPanel`, extends `"res://ui/components/common/right_panel_embeddable_panel.gd"` | — |
| `ui/components/recruit_panel/recruit_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/recruit_panel/recruit_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/recruit_panel/recruit_panel.tscn` | .tscn | 87 | runtime | root `Control` | — |
| `ui/components/replay_player/replay_player.gd` | .gd | 657 | runtime | class `ReplayPlayer`, extends `PanelContainer` | 特征: FileAccess/DirAccess |
| `ui/components/replay_player/replay_player.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/replay_player/replay_player.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/replay_player/replay_player.tscn` | .tscn | 10 | test_only | root `PanelContainer` | — |
| `ui/components/reserve_area/reserve_area_full_screen_view.gd` | .gd | 772 | runtime | class `ReserveAreaFullScreenView`, extends `Control` | 特征: await |
| `ui/components/reserve_area/reserve_area_full_screen_view.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/reserve_area/reserve_area_full_screen_view.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/reserve_area/reserve_area_full_screen_view.tscn` | .tscn | 81 | runtime | root `Control` | — |
| `ui/components/reserve_area/reserve_area_full_screen_view_tokens.gd` | .gd | 423 | runtime | extends `RefCounted` | — |
| `ui/components/reserve_area/reserve_area_full_screen_view_tokens.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/reserve_area/reserve_area_full_screen_view_tokens.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/reserve_area/tile_preview_factory.gd` | .gd | 55 | runtime | extends `RefCounted` | — |
| `ui/components/reserve_area/tile_preview_factory.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/reserve_area/tile_preview_factory.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/restaurant_placement/restaurant_placement_overlay.gd` | .gd | 290 | runtime | class `RestaurantPlacementOverlay`, extends `Control` | — |
| `ui/components/restaurant_placement/restaurant_placement_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/restaurant_placement/restaurant_placement_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/restaurant_placement/restaurant_placement_overlay.tscn` | .tscn | 39 | runtime | root `VBoxContainer` | — |
| `ui/components/room_config_editor/room_config_editor.gd` | .gd | 333 | runtime | extends `VBoxContainer` | — |
| `ui/components/room_config_editor/room_config_editor.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/room_config_editor/room_config_editor.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/train_panel/train_panel.gd` | .gd | 350 | runtime | class `TrainPanel`, extends `"res://ui/components/common/right_panel_embeddable_panel.gd"` | — |
| `ui/components/train_panel/train_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/train_panel/train_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/train_panel/train_panel.tscn` | .tscn | 100 | runtime | root `Control` | — |
| `ui/components/turn_order/turn_order_display.gd` | .gd | 541 | runtime | class `TurnOrderDisplay`, extends `Control` | — |
| `ui/components/turn_order/turn_order_display.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/turn_order/turn_order_display.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/turn_order/turn_order_display.tscn` | .tscn | 63 | runtime | root `Control` | — |
| `ui/components/turn_order/turn_order_track.gd` | .gd | 187 | runtime | class `TurnOrderTrack`, extends `Control` | — |
| `ui/components/turn_order/turn_order_track.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/turn_order/turn_order_track.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/turn_order/turn_order_track.tscn` | .tscn | 47 | runtime | root `Control` | — |
| `ui/components/zoom_control/zoom_control.gd` | .gd | 95 | runtime | class `ZoomControl`, extends `VBoxContainer` | — |
| `ui/components/zoom_control/zoom_control.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/components/zoom_control/zoom_control.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/components/zoom_control/zoom_control.tscn` | .tscn | 38 | runtime | root `VBoxContainer` | — |
| `ui/debug/debug_command_registry.gd` | .gd | 164 | runtime | extends `RefCounted` | — |
| `ui/debug/debug_command_registry.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/debug/debug_command_registry.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/debug/debug_commands/action_commands.gd` | .gd | 599 | runtime | extends `RefCounted` | — |
| `ui/debug/debug_commands/action_commands.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/debug/debug_commands/action_commands.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/debug/debug_commands/game_commands.gd` | .gd | 226 | runtime | extends `RefCounted` | — |
| `ui/debug/debug_commands/game_commands.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/debug/debug_commands/game_commands.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/debug/debug_commands/state_commands.gd` | .gd | 272 | runtime | extends `RefCounted` | — |
| `ui/debug/debug_commands/state_commands.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/debug/debug_commands/state_commands.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/debug/debug_commands/util_commands.gd` | .gd | 269 | runtime | extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/debug/debug_commands/util_commands.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/debug/debug_commands/util_commands.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/choice_dialog.gd` | .gd | 169 | runtime | class `ChoiceDialog`, extends `ModalDialogBase` | — |
| `ui/dialogs/choice_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/choice_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/choice_dialog.tscn` | .tscn | 91 | runtime | root `Control` | — |
| `ui/dialogs/confirm_dialog.gd` | .gd | 93 | runtime | class `ConfirmDialog`, extends `ModalDialogBase` | — |
| `ui/dialogs/confirm_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/confirm_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/confirm_dialog.tscn` | .tscn | 98 | runtime | root `Control` | — |
| `ui/dialogs/game_config_dialog.gd` | .gd | 368 | runtime | extends `ModalDialogBase` | — |
| `ui/dialogs/game_config_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/game_config_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/game_config_dialog.tscn` | .tscn | 169 | runtime | root `Control` | — |
| `ui/dialogs/info_dialog.gd` | .gd | 116 | runtime | class `InfoDialog`, extends `ModalDialogBase` | — |
| `ui/dialogs/info_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/info_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/password_dialog.gd` | .gd | 131 | runtime | class `PasswordDialog`, extends `ModalDialogBase` | — |
| `ui/dialogs/password_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/password_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/rules_viewer_dialog.gd` | .gd | 465 | runtime | class `RulesViewerDialog`, extends `ModalDialogBase` | 特征: FileAccess/DirAccess |
| `ui/dialogs/rules_viewer_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/rules_viewer_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/rules_viewer_dialog.tscn` | .tscn | 173 | runtime | root `Control` | — |
| `ui/dialogs/save_load_dialog.gd` | .gd | 649 | runtime | class `SaveLoadDialog`, extends `ModalDialogBase` | 特征: FileAccess/DirAccess |
| `ui/dialogs/save_load_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/save_load_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/settings_dialog.gd` | .gd | 544 | runtime | class `SettingsDialog`, extends `ModalDialogBase` | — |
| `ui/dialogs/settings_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/dialogs/settings_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/dialogs/settings_dialog.tscn` | .tscn | 433 | runtime | root `Control` | — |
| `ui/overlays/base_tile_overlay.gd` | .gd | 57 | runtime | class `BaseTileOverlay`, extends `Control` | — |
| `ui/overlays/base_tile_overlay.gd.uid` | .uid | 1 | unused?(no static refs) | sidecar -> `ui/overlays/base_tile_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/overlays/distance_overlay.gd` | .gd | 424 | runtime | class `DistanceOverlay`, extends `BaseTileOverlay` | — |
| `ui/overlays/distance_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/overlays/distance_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/overlays/distance_overlay.tscn` | .tscn | 14 | runtime | root `Control` | — |
| `ui/overlays/marketing_range_overlay.gd` | .gd | 219 | runtime | class `MarketingRangeOverlay`, extends `BaseTileOverlay` | — |
| `ui/overlays/marketing_range_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/overlays/marketing_range_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/overlays/marketing_range_overlay.tscn` | .tscn | 14 | unused?(no static refs) | root `Control` | — |
| `ui/overlays/procurement_route_overlay.gd` | .gd | 114 | runtime | class `ProcurementRouteOverlay`, extends `BaseTileOverlay` | — |
| `ui/overlays/procurement_route_overlay.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/overlays/procurement_route_overlay.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/overlays/procurement_route_overlay.tscn` | .tscn | 15 | runtime | root `Control` | — |
| `ui/scenes/debug/components/param_dialog.gd` | .gd | 193 | runtime | class `DebugParamDialog`, extends `Window` | — |
| `ui/scenes/debug/components/param_dialog.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/components/param_dialog.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/components/param_dialog.tscn` | .tscn | 46 | runtime | root `Window` | — |
| `ui/scenes/debug/debug_panel.gd` | .gd | 369 | runtime | class `DebugPanel`, extends `Window` | — |
| `ui/scenes/debug/debug_panel.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/debug_panel.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/debug_panel.tscn` | .tscn | 182 | runtime | root `Window` | — |
| `ui/scenes/debug/tabs/command_tab.gd` | .gd | 387 | runtime | extends `MarginContainer` | — |
| `ui/scenes/debug/tabs/command_tab.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/tabs/command_tab.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/tabs/entity_tab.gd` | .gd | 298 | runtime | extends `MarginContainer` | — |
| `ui/scenes/debug/tabs/entity_tab.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/tabs/entity_tab.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/tabs/history_tab.gd` | .gd | 138 | runtime | extends `MarginContainer` | 特征: FileAccess/DirAccess |
| `ui/scenes/debug/tabs/history_tab.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/tabs/history_tab.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/tabs/settings_tab.gd` | .gd | 167 | runtime | extends `MarginContainer` | — |
| `ui/scenes/debug/tabs/settings_tab.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/tabs/settings_tab.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/debug/tabs/state_tab.gd` | .gd | 225 | runtime | extends `MarginContainer` | — |
| `ui/scenes/debug/tabs/state_tab.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/debug/tabs/state_tab.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game.gd` | .gd | 1145 | runtime | extends `Control` | 大型脚本(>=800行): 可能职责过多；特征: await |
| `ui/scenes/game/game.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game.tscn` | .tscn | 409 | runtime | root `Control` | — |
| `ui/scenes/game/game_background_warmup_controller.gd` | .gd | 91 | runtime | class `GameBackgroundWarmupController`, extends `RefCounted` | 特征: await |
| `ui/scenes/game/game_background_warmup_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_background_warmup_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_command_controller.gd` | .gd | 299 | runtime | class `GameCommandController`, extends `RefCounted` | — |
| `ui/scenes/game/game_command_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_command_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_debug_panel_controller.gd` | .gd | 83 | runtime | class `GameDebugPanelController`, extends `RefCounted` | — |
| `ui/scenes/game/game_debug_panel_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_debug_panel_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_event_log_controller.gd` | .gd | 185 | test_only | class `GameEventLogController`, extends `RefCounted` | — |
| `ui/scenes/game/game_event_log_controller.gd.uid` | .uid | 1 | test_only | sidecar -> `ui/scenes/game/game_event_log_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_event_log_formatter.gd` | .gd | 889 | runtime | class `GameEventLogFormatter`, extends `RefCounted` | 大型脚本(>=800行): 可能职责过多 |
| `ui/scenes/game/game_event_log_formatter.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_event_log_formatter.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_event_log_reports_formatter.gd` | .gd | 198 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_event_log_reports_formatter.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_event_log_reports_formatter.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_input_controller.gd` | .gd | 193 | runtime | class `GameInputController`, extends `RefCounted` | — |
| `ui/scenes/game/game_input_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_input_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_layout_controller.gd` | .gd | 316 | runtime | class `GameLayoutController`, extends `RefCounted` | — |
| `ui/scenes/game/game_layout_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_layout_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_log_dock_controller.gd` | .gd | 134 | runtime | class `GameLogDockController`, extends `RefCounted` | — |
| `ui/scenes/game/game_log_dock_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_log_dock_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_map_interaction_controller.gd` | .gd | 1116 | runtime | class `GameMapInteractionController`, extends `RefCounted` | 大型脚本(>=800行): 可能职责过多 |
| `ui/scenes/game/game_map_interaction_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_map_interaction_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_map_interaction_marketing_mode.gd` | .gd | 754 | runtime | class `GameMapInteractionMarketingMode`, extends `RefCounted` | — |
| `ui/scenes/game/game_map_interaction_marketing_mode.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_map_interaction_marketing_mode.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_map_interaction_placement_mode.gd` | .gd | 477 | runtime | class `GameMapInteractionPlacementMode`, extends `RefCounted` | — |
| `ui/scenes/game/game_map_interaction_placement_mode.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_map_interaction_placement_mode.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_map_mode_bar_controller.gd` | .gd | 50 | runtime | class `GameMapModeBarController`, extends `RefCounted` | — |
| `ui/scenes/game/game_map_mode_bar_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_map_mode_bar_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_menu_controller.gd` | .gd | 216 | runtime | class `GameMenuController`, extends `RefCounted` | — |
| `ui/scenes/game/game_menu_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_menu_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_menu_debug_controller.gd` | .gd | 48 | runtime | class `GameMenuDebugController`, extends `RefCounted` | — |
| `ui/scenes/game/game_menu_debug_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_menu_debug_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_online_resync_controller.gd` | .gd | 458 | runtime | class `GameOnlineResyncController`, extends `RefCounted` | 特征: await |
| `ui/scenes/game/game_online_resync_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_online_resync_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_controller.gd` | .gd | 607 | runtime | class `GameOverlayController`, extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_overlay_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_demand_indicator.gd` | .gd | 136 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_demand_indicator.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/scenes/game/game_overlay_demand_indicator.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_dinnertime.gd` | .gd | 146 | unused?(no static refs) | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_dinnertime.gd.uid` | .uid | 2 | unused?(no static refs) | sidecar -> `ui/scenes/game/game_overlay_dinnertime.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_distance.gd` | .gd | 100 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_distance.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/scenes/game/game_overlay_distance.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_marketing_range.gd` | .gd | 191 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_marketing_range.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/scenes/game/game_overlay_marketing_range.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_procurement_route.gd` | .gd | 75 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_procurement_route.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_overlay_procurement_route.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_utils.gd` | .gd | 108 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_utils.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/scenes/game/game_overlay_utils.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_overlay_zoom.gd` | .gd | 65 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_overlay_zoom.gd.uid` | .uid | 2 | runtime | sidecar -> `ui/scenes/game/game_overlay_zoom.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_controller.gd` | .gd | 1179 | runtime | class `GamePanelController`, extends `RefCounted` | 大型脚本(>=800行): 可能职责过多；特征: await |
| `ui/scenes/game/game_panel_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_end_panels.gd` | .gd | 365 | runtime | extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/game/game_panel_end_panels.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_end_panels.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_marketing_panels.gd` | .gd | 320 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_panel_marketing_panels.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_marketing_panels.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_modals_controller.gd` | .gd | 569 | runtime | class `GamePanelModalsController`, extends `RefCounted` | 特征: await |
| `ui/scenes/game/game_panel_modals_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_modals_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_placement_overlays.gd` | .gd | 609 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_panel_placement_overlays.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_placement_overlays.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_restructuring_controller.gd` | .gd | 542 | runtime | class `GamePanelRestructuringController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_restructuring_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_restructuring_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_views_controller.gd` | .gd | 205 | runtime | class `GamePanelViewsController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_views_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_views_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_drinks_procurement_controller.gd` | .gd | 1351 | runtime | class `GamePanelWorkingDrinksProcurementController`, extends `RefCounted` | 大型脚本(>=800行): 可能职责过多 |
| `ui/scenes/game/game_panel_working_drinks_procurement_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_drinks_procurement_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_milestone_controller.gd` | .gd | 73 | runtime | class `GamePanelWorkingMilestoneController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_milestone_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_milestone_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_panels.gd` | .gd | 109 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_panels.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_panels.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_price_controller.gd` | .gd | 97 | runtime | class `GamePanelWorkingPriceController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_price_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_price_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_production_controller.gd` | .gd | 386 | runtime | class `GamePanelWorkingProductionController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_production_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_production_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_recruit_controller.gd` | .gd | 110 | runtime | class `GamePanelWorkingRecruitController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_recruit_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_recruit_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_panel_working_train_controller.gd` | .gd | 196 | runtime | class `GamePanelWorkingTrainController`, extends `RefCounted` | — |
| `ui/scenes/game/game_panel_working_train_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_panel_working_train_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_right_panel_dock_controller.gd` | .gd | 295 | runtime | class `GameRightPanelDockController`, extends `RefCounted` | — |
| `ui/scenes/game/game_right_panel_dock_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_right_panel_dock_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_save_load_controller.gd` | .gd | 67 | runtime | class `GameSaveLoadController`, extends `RefCounted` | — |
| `ui/scenes/game/game_save_load_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_save_load_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_timeline_controller.gd` | .gd | 798 | runtime | class `GameTimelineController`, extends `RefCounted` | — |
| `ui/scenes/game/game_timeline_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_timeline_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_timeline_log_entries_builder.gd` | .gd | 83 | runtime | class `GameTimelineLogEntriesBuilder`, extends `RefCounted` | — |
| `ui/scenes/game/game_timeline_log_entries_builder.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_timeline_log_entries_builder.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/game_ui_sync_controller.gd` | .gd | 262 | runtime | class `GameUiSyncController`, extends `RefCounted` | — |
| `ui/scenes/game/game_ui_sync_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/game_ui_sync_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas.gd` | .gd | 680 | runtime | extends `Control` | — |
| `ui/scenes/game/map_canvas.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer.gd` | .gd | 480 | runtime | class `MapCanvasDrawer`, extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_ground_pass.gd` | .gd | 32 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_ground_pass.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_ground_pass.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_marketing_pass.gd` | .gd | 280 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_marketing_pass.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_marketing_pass.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_overlay_utils.gd` | .gd | 88 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_overlay_utils.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_overlay_utils.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_roads_pass.gd` | .gd | 223 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_roads_pass.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_roads_pass.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_structures_pass.gd` | .gd | 771 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_structures_pass.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_structures_pass.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_texture_utils.gd` | .gd | 127 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_texture_utils.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_texture_utils.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_drawer_tiles_pass.gd` | .gd | 124 | runtime | extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_drawer_tiles_pass.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_drawer_tiles_pass.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_indexer.gd` | .gd | 217 | runtime | class `MapCanvasIndexer`, extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_indexer.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_indexer.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_canvas_tooltip.gd` | .gd | 62 | runtime | class `MapCanvasTooltip`, extends `RefCounted` | — |
| `ui/scenes/game/map_canvas_tooltip.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_canvas_tooltip.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/map_view.gd` | .gd | 227 | runtime | extends `ScrollContainer` | 特征: await |
| `ui/scenes/game/map_view.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/map_view.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/game/phase_action_ui_registry.gd` | .gd | 76 | runtime | class `PhaseActionUiRegistry`, extends `RefCounted` | — |
| `ui/scenes/game/phase_action_ui_registry.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/game/phase_action_ui_registry.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/main_menu.tscn` | .tscn | 167 | entrypoint(runtime) | root `Control` | — |
| `ui/scenes/menus/main_menu.gd` | .gd | 170 | runtime | extends `Control` | 特征: await |
| `ui/scenes/menus/main_menu.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/menus/main_menu.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/online/online_lobby.gd` | .gd | 813 | runtime | extends `Control` | 大型脚本(>=800行): 可能职责过多；特征: await |
| `ui/scenes/online/online_lobby.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/online/online_lobby.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/online/online_lobby.tscn` | .tscn | 410 | runtime | root `Control` | — |
| `ui/scenes/online/online_lobby_room_list_controller.gd` | .gd | 114 | runtime | extends `RefCounted` | — |
| `ui/scenes/online/online_lobby_room_list_controller.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/online/online_lobby_room_list_controller.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/online/online_lobby_room_state_renderer.gd` | .gd | 198 | runtime | extends `RefCounted` | — |
| `ui/scenes/online/online_lobby_room_state_renderer.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/online/online_lobby_room_state_renderer.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/replay_test.tscn` | .tscn | 41 | unused?(no static refs) | root `Control` | — |
| `ui/scenes/setup/game_setup.gd` | .gd | 670 | runtime | extends `Control` | 特征: FileAccess/DirAccess, await |
| `ui/scenes/setup/game_setup.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/setup/game_setup.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/setup/game_setup.tscn` | .tscn | 119 | runtime | root `Control` | — |
| `ui/scenes/tests/action_panel_end_buttons_order_test.gd` | .gd | 57 | test | class `ActionPanelEndButtonsOrderTest`, extends `RefCounted` | — |
| `ui/scenes/tests/action_panel_end_buttons_order_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/action_panel_end_buttons_order_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/action_panel_executor_metadata_test.gd` | .gd | 44 | test | class `ActionPanelExecutorMetadataTest`, extends `RefCounted` | — |
| `ui/scenes/tests/action_panel_executor_metadata_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/action_panel_executor_metadata_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/action_panel_global_disabled_restore_test.gd` | .gd | 58 | test | class `ActionPanelGlobalDisabledRestoreTest`, extends `RefCounted` | — |
| `ui/scenes/tests/action_panel_global_disabled_restore_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/action_panel_global_disabled_restore_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/action_panel_guided_action_placeholder_test.gd` | .gd | 83 | test | class `ActionPanelGuidedActionPlaceholderTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/action_panel_guided_action_placeholder_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/action_panel_guided_action_placeholder_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/action_panel_online_local_player_test.gd` | .gd | 47 | test | extends `RefCounted` | — |
| `ui/scenes/tests/action_panel_online_local_player_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/action_panel_online_local_player_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/air_procure_start_tile_choice_test.gd` | .gd | 96 | test | class `AirProcureStartTileChoiceTest`, extends `RefCounted` | — |
| `ui/scenes/tests/air_procure_start_tile_choice_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/air_procure_start_tile_choice_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/airplane_marketing_icon_rotation_test.gd` | .gd | 85 | test | class `AirplaneMarketingIconRotationTest`, extends `RefCounted` | — |
| `ui/scenes/tests/airplane_marketing_icon_rotation_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/airplane_marketing_icon_rotation_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/airplane_marketing_outside_render_test.gd` | .gd | 154 | test | class `AirplaneMarketingOutsideRenderTest`, extends `RefCounted` | — |
| `ui/scenes/tests/airplane_marketing_outside_render_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/airplane_marketing_outside_render_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/airplane_marketing_outside_selection_test.gd` | .gd | 130 | test | class `AirplaneMarketingOutsideSelectionTest`, extends `RefCounted` | — |
| `ui/scenes/tests/airplane_marketing_outside_selection_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/airplane_marketing_outside_selection_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/all_tests.gd` | .gd | 929 | test | extends `Control` | 大型脚本(>=800行): 可能职责过多；特征: await |
| `ui/scenes/tests/all_tests.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/all_tests.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/all_tests.tscn` | .tscn | 47 | test | root `Control` | — |
| `ui/scenes/tests/all_tests_refs.gd` | .gd | 189 | test | extends `RefCounted` | — |
| `ui/scenes/tests/all_tests_refs.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/all_tests_refs.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/company_structure_deferred_rebuild_test.gd` | .gd | 47 | test | class `CompanyStructureDeferredRebuildTest`, extends `RefCounted` | — |
| `ui/scenes/tests/company_structure_deferred_rebuild_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/company_structure_deferred_rebuild_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/distance_overlay_roadworks_penalty_test.gd` | .gd | 137 | test | class `DistanceOverlayRoadworksPenaltyTest`, extends `RefCounted` | — |
| `ui/scenes/tests/distance_overlay_roadworks_penalty_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/distance_overlay_roadworks_penalty_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/drag_preview_visual_test.gd` | .gd | 63 | test | class `DragPreviewVisualTest`, extends `RefCounted` | — |
| `ui/scenes/tests/drag_preview_visual_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/drag_preview_visual_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/employee_card_description_wrap_test.gd` | .gd | 73 | test | class `EmployeeCardDescriptionWrapTest`, extends `RefCounted` | — |
| `ui/scenes/tests/employee_card_description_wrap_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/employee_card_description_wrap_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/employee_picker_min_size_test.gd` | .gd | 36 | test | class `EmployeePickerMinSizeTest`, extends `RefCounted` | — |
| `ui/scenes/tests/employee_picker_min_size_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/employee_picker_min_size_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/employee_tree_layout_bottom_tag_test.gd` | .gd | 49 | test | class `EmployeeTreeLayoutBottomTagTest`, extends `RefCounted` | — |
| `ui/scenes/tests/employee_tree_layout_bottom_tag_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/employee_tree_layout_bottom_tag_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/entity_tab_reserve_card_privacy_test.gd` | .gd | 78 | test | extends `RefCounted` | — |
| `ui/scenes/tests/entity_tab_reserve_card_privacy_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/entity_tab_reserve_card_privacy_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/external_tile_internal_grid_lines_test.gd` | .gd | 75 | test | class `ExternalTileInternalGridLinesTest`, extends `RefCounted` | 疑似重复实现: ui/scenes/tests/tile_internal_grid_lines_test.gd (0.99) |
| `ui/scenes/tests/external_tile_internal_grid_lines_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/external_tile_internal_grid_lines_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/fridge_keep_modal_ui_test.gd` | .gd | 114 | test | class `FridgeKeepModalUiTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/fridge_keep_modal_ui_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/fridge_keep_modal_ui_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/game_over_freeze_full_game_test.gd` | .gd | 144 | test | class `GameOverFreezeFullGameTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/game_over_freeze_full_game_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/game_over_freeze_full_game_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/game_over_panel_read_only_test.gd` | .gd | 97 | test | class `GameOverPanelReadOnlyTest`, extends `RefCounted` | — |
| `ui/scenes/tests/game_over_panel_read_only_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/game_over_panel_read_only_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/game_panel_modals_controller_kind_contract_test.gd` | .gd | 30 | test | class `GamePanelModalsControllerKindContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/game_panel_modals_controller_kind_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/game_panel_modals_controller_kind_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/game_smoke_test.gd` | .gd | 333 | test | extends `Control` | 特征: await |
| `ui/scenes/tests/game_smoke_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/game_smoke_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/game_smoke_test.tscn` | .tscn | 44 | test | root `Control` | — |
| `ui/scenes/tests/hand_area_view_switch_test.gd` | .gd | 67 | test | class `HandAreaViewSwitchTest`, extends `RefCounted` | — |
| `ui/scenes/tests/hand_area_view_switch_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/hand_area_view_switch_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/kimchi_storage_modal_ui_test.gd` | .gd | 117 | test | class `KimchiStorageModalUiTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/kimchi_storage_modal_ui_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/kimchi_storage_modal_ui_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/left_panel_selection_isolation_test.gd` | .gd | 40 | test | extends `RefCounted` | — |
| `ui/scenes/tests/left_panel_selection_isolation_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/left_panel_selection_isolation_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/company_structure_test.gd` | .gd | 51 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/company_structure_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/company_structure_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/company_structure_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/employee_test.gd` | .gd | 45 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/employee_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/employee_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/employee_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/game_map_view_test.gd` | .gd | 128 | test | extends `Control` | 特征: await |
| `ui/scenes/tests/legacy/game_map_view_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/game_map_view_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/game_map_view_test.tscn` | .tscn | 43 | test?(no static refs) | root `Control` | — |
| `ui/scenes/tests/legacy/initial_company_test.gd` | .gd | 50 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/initial_company_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/initial_company_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/initial_company_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/mandatory_actions_test.gd` | .gd | 52 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/mandatory_actions_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/mandatory_actions_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/mandatory_actions_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/order_of_business_test.gd` | .gd | 45 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/order_of_business_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/order_of_business_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/order_of_business_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/payday_salary_test.gd` | .gd | 45 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/payday_salary_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/payday_salary_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/payday_salary_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/procure_drinks_test.gd` | .gd | 53 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/procure_drinks_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/procure_drinks_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/procure_drinks_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/legacy/produce_food_test.gd` | .gd | 53 | test | extends `Control` | — |
| `ui/scenes/tests/legacy/produce_food_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/legacy/produce_food_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/legacy/produce_food_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/lobbyists_extra_tile_multi_player_same_round_ui_test.gd` | .gd | 378 | test | class `LobbyistsExtraTileMultiPlayerSameRoundUiTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/lobbyists_extra_tile_multi_player_same_round_ui_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/lobbyists_extra_tile_multi_player_same_round_ui_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/lobbyists_extra_tile_picker_layout_ui_test.gd` | .gd | 78 | test | class `LobbyistsExtraTilePickerLayoutUiTest`, extends `RefCounted` | 特征: await |
| `ui/scenes/tests/lobbyists_extra_tile_picker_layout_ui_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/lobbyists_extra_tile_picker_layout_ui_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/log_restore_after_load_test.gd` | .gd | 78 | test | class `LogRestoreAfterLoadTest`, extends `RefCounted` | — |
| `ui/scenes/tests/log_restore_after_load_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/log_restore_after_load_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/manual_test_saves_smoke_test.gd` | .gd | 96 | test | extends `Control` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/manual_test_saves_smoke_test.gd.uid` | .uid | 2 | test | sidecar -> `ui/scenes/tests/manual_test_saves_smoke_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/manual_test_saves_smoke_test.tscn` | .tscn | 44 | test?(no static refs) | root `Control` | — |
| `ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd` | .gd | 82 | test | class `MapBlockedOverlaySkipsVoidCellsTest`, extends `RefCounted` | — |
| `ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/map_ground_skips_outside_ring_test.gd` | .gd | 98 | test | class `MapGroundSkipsOutsideRingTest`, extends `RefCounted` | — |
| `ui/scenes/tests/map_ground_skips_outside_ring_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/map_ground_skips_outside_ring_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/map_indexer_structures_respects_map_origin_test.gd` | .gd | 84 | test | class `MapIndexerStructuresRespectsMapOriginTest`, extends `RefCounted` | — |
| `ui/scenes/tests/map_indexer_structures_respects_map_origin_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/map_indexer_structures_respects_map_origin_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/map_zoom_property_test.gd` | .gd | 96 | test | class `MapZoomPropertyTest`, extends `RefCounted` | — |
| `ui/scenes/tests/map_zoom_property_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/map_zoom_property_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_board_number_badge_test.gd` | .gd | 89 | test | class `MarketingBoardNumberBadgeTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_board_number_badge_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_board_number_badge_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_highlights_no_drink_source_test.gd` | .gd | 106 | test | class `MarketingHighlightsNoDrinkSourceTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_highlights_no_drink_source_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_highlights_no_drink_source_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_panel_module_types_ui_test.gd` | .gd | 48 | test | class `MarketingPanelModuleTypesUiTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_panel_module_types_ui_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_panel_module_types_ui_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_range_full_footprint_test.gd` | .gd | 82 | test | class `MarketingRangeFullFootprintTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_range_full_footprint_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_range_full_footprint_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_remaining_duration_label_test.gd` | .gd | 66 | test | class `MarketingRemainingDurationLabelTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_remaining_duration_label_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_remaining_duration_label_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/marketing_selection_freeze_test.gd` | .gd | 85 | test | class `MarketingSelectionFreezeTest`, extends `RefCounted` | — |
| `ui/scenes/tests/marketing_selection_freeze_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/marketing_selection_freeze_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/milestone_panel_effect_text_contract_test.gd` | .gd | 42 | test | class `MilestonePanelEffectTextContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/milestone_panel_effect_text_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/milestone_panel_effect_text_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/module_product_icons_loaded_test.gd` | .gd | 47 | test | class `ModuleProductIconsLoadedTest`, extends `RefCounted` | — |
| `ui/scenes/tests/module_product_icons_loaded_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/module_product_icons_loaded_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/module_selector_setup_constraints_test.gd` | .gd | 106 | test | class `ModuleSelectorSetupConstraintsTest`, extends `RefCounted` | — |
| `ui/scenes/tests/module_selector_setup_constraints_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/module_selector_setup_constraints_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/move_restaurant_display_label_test.gd` | .gd | 34 | test | class `MoveRestaurantDisplayLabelTest`, extends `RefCounted` | — |
| `ui/scenes/tests/move_restaurant_display_label_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/move_restaurant_display_label_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/online_connect_smoke_test.gd` | .gd | 71 | test | extends `Control` | 特征: await |
| `ui/scenes/tests/online_connect_smoke_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/online_connect_smoke_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/online_connect_smoke_test.tscn` | .tscn | 14 | test?(no static refs) | root `Control` | — |
| `ui/scenes/tests/phase_action_ui_modal_registration_test.gd` | .gd | 67 | test | class `PhaseActionUiModalRegistrationTest`, extends `RefCounted` | — |
| `ui/scenes/tests/phase_action_ui_modal_registration_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/phase_action_ui_modal_registration_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/phase_action_ui_registry_cleanup_test.gd` | .gd | 106 | test | class `PhaseActionUiRegistryCleanupTest`, extends `RefCounted` | — |
| `ui/scenes/tests/phase_action_ui_registry_cleanup_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/phase_action_ui_registry_cleanup_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/piece_ui_hints_registry_lobbyists_test.gd` | .gd | 45 | test | class `PieceUiHintsRegistryLobbyistsTest`, extends `RefCounted` | — |
| `ui/scenes/tests/piece_ui_hints_registry_lobbyists_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/piece_ui_hints_registry_lobbyists_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/procure_drinks_map_click_test.gd` | .gd | 113 | test | extends `Node` | — |
| `ui/scenes/tests/procure_drinks_map_click_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/procure_drinks_map_click_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/procure_drinks_map_click_test.tscn` | .tscn | 8 | test?(no static refs) | root `Node` | — |
| `ui/scenes/tests/procure_drinks_start_restaurant_select_test.gd` | .gd | 112 | test | class `ProcureDrinksStartRestaurantSelectTest`, extends `RefCounted` | — |
| `ui/scenes/tests/procure_drinks_start_restaurant_select_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/procure_drinks_start_restaurant_select_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/production_panel_used_counts_sync_test.gd` | .gd | 73 | test | class `ProductionPanelUsedCountsSyncTest`, extends `RefCounted` | — |
| `ui/scenes/tests/production_panel_used_counts_sync_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/production_panel_used_counts_sync_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/recruit_quota_turn_sync_test.gd` | .gd | 169 | test | extends `Control` | 特征: await |
| `ui/scenes/tests/recruit_quota_turn_sync_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/recruit_quota_turn_sync_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/recruit_quota_turn_sync_test.tscn` | .tscn | 44 | test?(no static refs) | root `Control` | — |
| `ui/scenes/tests/replay_log_future_visibility_test.gd` | .gd | 127 | test | class `ReplayLogFutureVisibilityTest`, extends `RefCounted` | — |
| `ui/scenes/tests/replay_log_future_visibility_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/replay_log_future_visibility_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/replay_player_smoke_test.gd` | .gd | 60 | test | class `ReplayPlayerSmokeTest`, extends `RefCounted` | — |
| `ui/scenes/tests/replay_player_smoke_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/replay_player_smoke_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/replay_test.gd` | .gd | 52 | test | extends `Control` | — |
| `ui/scenes/tests/replay_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/replay_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/replay_test.tscn` | .tscn | 43 | test | root `Control` | — |
| `ui/scenes/tests/reserve_area_supply_visuals_test.gd` | .gd | 181 | test | class `ReserveAreaSupplyVisualsTest`, extends `RefCounted` | — |
| `ui/scenes/tests/reserve_area_supply_visuals_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/reserve_area_supply_visuals_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/reserve_card_selection_modal_presentation_test.gd` | .gd | 112 | test | class `ReserveCardSelectionModalPresentationTest`, extends `RefCounted` | — |
| `ui/scenes/tests/reserve_card_selection_modal_presentation_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/reserve_card_selection_modal_presentation_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd` | .gd | 91 | test | extends `RefCounted` | — |
| `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/restaurant_logo_textures_loaded_test.gd` | .gd | 59 | test | class `RestaurantLogoTexturesLoadedTest`, extends `RefCounted` | — |
| `ui/scenes/tests/restaurant_logo_textures_loaded_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/restaurant_logo_textures_loaded_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/restructuring_layout_test.gd` | .gd | 232 | test | class `RestructuringLayoutTest`, extends `RefCounted` | — |
| `ui/scenes/tests/restructuring_layout_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/restructuring_layout_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/restructuring_privacy_test.gd` | .gd | 104 | test | extends `RefCounted` | — |
| `ui/scenes/tests/restructuring_privacy_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/restructuring_privacy_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/restructuring_reserve_drop_target_test.gd` | .gd | 48 | test | class `RestructuringReserveDropTargetTest`, extends `RefCounted` | — |
| `ui/scenes/tests/restructuring_reserve_drop_target_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/restructuring_reserve_drop_target_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/road_procure_start_restaurant_choice_test.gd` | .gd | 88 | test | class `RoadProcureStartRestaurantChoiceTest`, extends `RefCounted` | — |
| `ui/scenes/tests/road_procure_start_restaurant_choice_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/road_procure_start_restaurant_choice_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/room_config_editor_editable_signal_test.gd` | .gd | 31 | test | extends `RefCounted` | — |
| `ui/scenes/tests/room_config_editor_editable_signal_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/room_config_editor_editable_signal_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/rural_area_map_panel_bounds_test.gd` | .gd | 91 | test | class `RuralAreaMapPanelBoundsTest`, extends `RefCounted` | — |
| `ui/scenes/tests/rural_area_map_panel_bounds_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/rural_area_map_panel_bounds_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/tile_internal_grid_lines_test.gd` | .gd | 74 | test | class `TileInternalGridLinesTest`, extends `RefCounted` | 疑似重复实现: ui/scenes/tests/external_tile_internal_grid_lines_test.gd (0.99) |
| `ui/scenes/tests/tile_internal_grid_lines_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/tile_internal_grid_lines_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/turn_order_selection_modal_online_visibility_test.gd` | .gd | 130 | test | extends `RefCounted` | — |
| `ui/scenes/tests/turn_order_selection_modal_online_visibility_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/turn_order_selection_modal_online_visibility_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd` | .gd | 76 | test | class `UiBasePiecesLogoHardRefContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess；疑似重复实现: ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd (0.97) |
| `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd` | .gd | 80 | test | class `UiFryChefEmployeeIdContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess；疑似重复实现: ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd (0.97) |
| `ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd` | .gd | 81 | test | class `UiLobbyistsPiecePrefixContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess；疑似重复实现: ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd (0.97) |
| `ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd` | .gd | 76 | test | class `UiLobbyistsRoadOverlaysHardRefContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess；疑似重复实现: ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd (0.97) |
| `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_map_optional_piece_ids_contract_test.gd` | .gd | 80 | test | class `UiMapOptionalPieceIdsContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/ui_map_optional_piece_ids_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_map_optional_piece_ids_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_map_overlay_private_state_contract_test.gd` | .gd | 48 | test | class `UiMapOverlayPrivateStateContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/ui_map_overlay_private_state_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_map_overlay_private_state_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_module_selector_hardcoded_module_ids_contract_test.gd` | .gd | 67 | test | class `UiModuleSelectorHardcodedModuleIdsContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/ui_module_selector_hardcoded_module_ids_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_module_selector_hardcoded_module_ids_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_modules_base_dir_contract_test.gd` | .gd | 76 | test | class `UiModulesBaseDirContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/ui_modules_base_dir_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_modules_base_dir_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_product_name_mapping_contract_test.gd` | .gd | 86 | test | class `UiProductNameMappingContractTest`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tests/ui_product_name_mapping_contract_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_product_name_mapping_contract_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tests/ui_regression_property_test.gd` | .gd | 98 | test | class `UiRegressionPropertyTest`, extends `RefCounted` | — |
| `ui/scenes/tests/ui_regression_property_test.gd.uid` | .uid | 1 | test | sidecar -> `ui/scenes/tests/ui_regression_property_test.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tools/tile_editor.gd` | .gd | 401 | runtime | extends `Control` | — |
| `ui/scenes/tools/tile_editor.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/tools/tile_editor.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tools/tile_editor.tscn` | .tscn | 225 | runtime | root `Control` | — |
| `ui/scenes/tools/tile_editor/cell_model.gd` | .gd | 27 | runtime | extends `RefCounted` | — |
| `ui/scenes/tools/tile_editor/cell_model.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/tools/tile_editor/cell_model.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tools/tile_editor/storage.gd` | .gd | 98 | runtime | extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/scenes/tools/tile_editor/storage.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/tools/tile_editor/storage.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/scenes/tools/tile_editor/tile_def_edit.gd` | .gd | 63 | runtime | extends `RefCounted` | — |
| `ui/scenes/tools/tile_editor/tile_def_edit.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/scenes/tools/tile_editor/tile_def_edit.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/shaders/tiled_texture.gdshader` | .gdshader | 12 | runtime |  | — |
| `ui/shaders/tiled_texture.gdshader.uid` | .uid | 1 | runtime | sidecar -> `ui/shaders/tiled_texture.gdshader` | Godot 自动生成 UID 侧车文件 |
| `ui/shaders/vignette.gdshader` | .gdshader | 12 | runtime |  | — |
| `ui/shaders/vignette.gdshader.uid` | .uid | 1 | runtime | sidecar -> `ui/shaders/vignette.gdshader` | Godot 自动生成 UID 侧车文件 |
| `ui/themes/button_primary_disabled.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_primary_hover.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_primary_normal.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_primary_pressed.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_secondary_disabled.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_secondary_hover.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_secondary_normal.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/button_secondary_pressed.tres` | .tres | 18 | runtime |  | — |
| `ui/themes/dialog_surface.tres` | .tres | 17 | runtime |  | — |
| `ui/themes/overlay_dim.tres` | .tres | 5 | runtime |  | — |
| `ui/themes/panel_poster.tres` | .tres | 14 | runtime |  | — |
| `ui/themes/panel_poster_alt.tres` | .tres | 14 | runtime |  | — |
| `ui/themes/poster_inner_border.tres` | .tres | 14 | runtime |  | — |
| `ui/utils/modules_base_dir.gd` | .gd | 15 | runtime | class `ModulesBaseDir`, extends `RefCounted` | — |
| `ui/utils/modules_base_dir.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/modules_base_dir.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/utils/node_access.gd` | .gd | 23 | runtime | class `UiNodeAccess`, extends `RefCounted` | — |
| `ui/utils/node_access.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/node_access.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/utils/rebuild_helpers.gd` | .gd | 18 | runtime | class `UiRebuildHelpers`, extends `RefCounted` | — |
| `ui/utils/rebuild_helpers.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/rebuild_helpers.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/utils/rules_docs.gd` | .gd | 63 | runtime | class `RulesDocs`, extends `RefCounted` | — |
| `ui/utils/rules_docs.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/rules_docs.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/utils/signal_helpers.gd` | .gd | 15 | runtime | class `UiSignalHelpers`, extends `RefCounted` | — |
| `ui/utils/signal_helpers.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/signal_helpers.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/utils/ui_styles.gd` | .gd | 349 | runtime | class `UiStyles`, extends `RefCounted` | — |
| `ui/utils/ui_styles.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/utils/ui_styles.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/visual/employee_role_colors.gd` | .gd | 45 | runtime | class `EmployeeRoleColors`, extends `RefCounted` | — |
| `ui/visual/employee_role_colors.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/visual/employee_role_colors.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/visual/map_skin.gd` | .gd | 328 | runtime | class `MapSkin`, extends `RefCounted` | 特征: FileAccess/DirAccess |
| `ui/visual/map_skin.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/visual/map_skin.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/visual/map_skin_builder.gd` | .gd | 35 | runtime | class `MapSkinBuilder`, extends `RefCounted` | — |
| `ui/visual/map_skin_builder.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/visual/map_skin_builder.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/visual/ui_animation_manager.gd` | .gd | 322 | runtime | class `UIAnimationManager`, extends `Node` | — |
| `ui/visual/ui_animation_manager.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/visual/ui_animation_manager.gd` | Godot 自动生成 UID 侧车文件 |
| `ui/visual/ui_animation_manager.tscn` | .tscn | 7 | runtime | root `Node` | — |
| `ui/visual/ui_skin_cache.gd` | .gd | 47 | runtime | class `UiSkinCache`, extends `RefCounted` | — |
| `ui/visual/ui_skin_cache.gd.uid` | .uid | 1 | runtime | sidecar -> `ui/visual/ui_skin_cache.gd` | Godot 自动生成 UID 侧车文件 |

## 附录：高相似脚本（疑似重复实现/可参数化）
- `ui/scenes/tests/external_tile_internal_grid_lines_test.gd`
  - 0.990 `ui/scenes/tests/tile_internal_grid_lines_test.gd`
- `ui/scenes/tests/tile_internal_grid_lines_test.gd`
  - 0.990 `ui/scenes/tests/external_tile_internal_grid_lines_test.gd`
- `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd`
  - 0.966 `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd`
- `ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd`
  - 0.968 `ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd`
- `ui/scenes/tests/ui_lobbyists_piece_prefix_contract_test.gd`
  - 0.968 `ui/scenes/tests/ui_fry_chef_employee_id_contract_test.gd`
- `ui/scenes/tests/ui_lobbyists_road_overlays_hard_ref_contract_test.gd`
  - 0.966 `ui/scenes/tests/ui_base_pieces_logo_hard_ref_contract_test.gd`

## 附录：扫描完整性校验
- records 覆盖 ui/ 文件：619/619
