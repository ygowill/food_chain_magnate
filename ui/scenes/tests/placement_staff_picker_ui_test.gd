class_name PlacementStaffPickerUiTest
extends RefCounted

const ActionPanelScene = preload("res://ui/components/action_panel/action_panel.tscn")
const HouseOverlayClass = preload("res://ui/components/house_placement/house_placement_overlay.gd")
const PlacementOverlaysClass = preload("res://ui/scenes/game/panel/placement_overlays.gd")
const RestaurantOverlayClass = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.gd")
const StaffPickerStateClass = preload("res://ui/components/employee_picker/staff_picker_state.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

class _FakeGameScene:
	extends Control

	var game_engine: GameEngine = null

class _MapControllerSpy:
	extends RefCounted

	var house_overlay = null
	var clear_selection_count: int = 0

	func begin_selection(_mode: String, _params: Dictionary = {}) -> void:
		pass

	func clear_selection() -> void:
		clear_selection_count += 1

	func set_house_placement_overlay(overlay) -> void:
		house_overlay = overlay

	func on_house_preview_requested(_action_id: String, _position: Vector2i, _rotation: int) -> void:
		pass

	func on_house_preview_cleared() -> void:
		pass

	func on_house_highlight_requested(_action_id: String, _rotation: int) -> void:
		pass

	func on_house_garden_preview_requested(_house_id: String, _direction: String) -> void:
		pass

	func on_house_garden_preview_cleared() -> void:
		pass

class _OverlayControllerSpy:
	extends RefCounted

	var hide_all_count: int = 0

	func hide_all_overlays() -> void:
		hide_all_count += 1

class _CommandExecutor:
	extends RefCounted

	var _engine: GameEngine = null

	func _init(engine: GameEngine) -> void:
		_engine = engine

	func execute(command: Command) -> Result:
		if _engine == null:
			return Result.failure("engine 为空")
		return _engine.execute_command(command)

static func run() -> Result:
	var r := _case_staff_picker_state_defaults_to_enabled_staff()
	if not r.ok:
		return r
	r = _case_staff_picker_state_reselects_by_employee_type()
	if not r.ok:
		return r
	r = _case_house_overlay_keeps_selected_staff_id()
	if not r.ok:
		return r
	r = _case_house_overlay_falls_back_when_selected_staff_disappears()
	if not r.ok:
		return r
	r = _case_restaurant_overlay_defaults_to_enabled_staff()
	if not r.ok:
		return r
	r = await _case_restaurant_context_uses_custom_layout()
	if not r.ok:
		return r
	r = await _case_house_confirm_keeps_context_and_marks_used_staff()
	if not r.ok:
		return r
	return Result.success({})

static func _case_staff_picker_state_defaults_to_enabled_staff() -> Result:
	var state := StaffPickerStateClass.new(["can_place_house", "can_add_garden"])
	state.set_items([
		{"staff_id": 101, "employee_type": "new_business_developer", "capacity": 1, "used": 1, "remaining": 0, "can_place_house": true, "can_add_garden": true},
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	if int(state.get_selected_staff_id()) != 102:
		return Result.failure("StaffPickerState 应默认选中 remaining>0 的 staff_id=102，实际: %s" % str(state.get_selected_staff_id()))
	var items := state.get_items()
	if items.size() != 2:
		return Result.failure("StaffPickerState 应保留 2 个 picker item，实际: %d" % items.size())
	if not bool(Dictionary(items[0]).get("can_place_house", false)):
		return Result.failure("StaffPickerState 应复制 capability 字段 can_place_house")
	return Result.success()

static func _case_staff_picker_state_reselects_by_employee_type() -> Result:
	var state := StaffPickerStateClass.new(["can_place_restaurant", "can_move_restaurant"])
	state.set_items([
		{"staff_id": 201, "employee_type": "regional_manager", "capacity": 1, "used": 1, "remaining": 0, "can_place_restaurant": true, "can_move_restaurant": true},
		{"staff_id": 202, "employee_type": "regional_manager", "capacity": 1, "used": 0, "remaining": 1, "can_place_restaurant": true, "can_move_restaurant": true},
	])
	state.apply_selected_key("staff:201")
	if int(state.get_selected_staff_id()) != 201:
		return Result.failure("StaffPickerState 按 key 切换后应保留 staff_id=201，实际: %s" % str(state.get_selected_staff_id()))
	state.apply_selected_employee_type("regional_manager")
	if int(state.get_selected_staff_id()) != 202:
		return Result.failure("StaffPickerState 按 employee_type 回退时应优先选择可用 staff_id=202，实际: %s" % str(state.get_selected_staff_id()))
	state.refresh_selected()
	if int(state.get_selected_staff_id()) != 202:
		return Result.failure("StaffPickerState refresh_selected 后应保留 staff_id=202，实际: %s" % str(state.get_selected_staff_id()))
	return Result.success()

static func _case_house_overlay_keeps_selected_staff_id() -> Result:
	var overlay := HouseOverlayClass.new()
	overlay.set_available_employee_items([
		{"staff_id": 101, "employee_type": "new_business_developer", "capacity": 1, "used": 1, "remaining": 0, "can_place_house": true, "can_add_garden": true},
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	if int(overlay.get_selected_staff_id()) != 102:
		overlay.free()
		return Result.failure("house overlay 应默认选中 remaining>0 的 staff_id=102，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_selected_employee_key("staff:101")
	if int(overlay.get_selected_staff_id()) != 101:
		overlay.free()
		return Result.failure("house overlay 切换后应保留 staff_id=101，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.free()
	return Result.success()

static func _case_house_overlay_falls_back_when_selected_staff_disappears() -> Result:
	var overlay := HouseOverlayClass.new()
	overlay.set_available_employee_items([
		{"staff_id": 101, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	overlay.set_selected_employee_key("staff:101")
	if int(overlay.get_selected_staff_id()) != 101:
		overlay.free()
		return Result.failure("house overlay 初始应选中 staff_id=101，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_available_employee_items([
		{"staff_id": 102, "employee_type": "new_business_developer", "capacity": 1, "used": 0, "remaining": 1, "can_place_house": true, "can_add_garden": true},
	])
	if int(overlay.get_selected_staff_id()) != 102:
		overlay.free()
		return Result.failure("house overlay 旧 staff_id 消失后应回退到剩余 staff_id=102，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_selected_employee_key("staff:101")
	if int(overlay.get_selected_staff_id()) != 102:
		overlay.free()
		return Result.failure("house overlay 收到失效 key 时不应清空，实际应保持/回退到 staff_id=102，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.free()
	return Result.success()

static func _case_restaurant_overlay_defaults_to_enabled_staff() -> Result:
	var overlay := RestaurantOverlayClass.new()
	overlay.set_available_employee_items([
		{"staff_id": 201, "employee_type": "regional_manager", "capacity": 1, "used": 1, "remaining": 0, "can_place_restaurant": true, "can_move_restaurant": true},
		{"staff_id": 202, "employee_type": "regional_manager", "capacity": 1, "used": 0, "remaining": 1, "can_place_restaurant": true, "can_move_restaurant": true},
	])
	if int(overlay.get_selected_staff_id()) != 202:
		overlay.free()
		return Result.failure("restaurant overlay 应默认选中 remaining>0 的 staff_id=202，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.set_selected_employee_key("staff:201")
	if int(overlay.get_selected_staff_id()) != 201:
		overlay.free()
		return Result.failure("restaurant overlay 切换后应保留 staff_id=201，实际: %s" % str(overlay.get_selected_staff_id()))
	overlay.free()
	return Result.success()

static func _case_restaurant_context_uses_custom_layout() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行餐厅 Context UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载餐厅 Context UI 测试节点）")
	if ActionPanelScene == null:
		return Result.failure("预加载 action_panel.tscn 失败（PackedScene 为空）")

	var overlay := RestaurantOverlayClass.new()
	host.add_child(overlay)
	overlay.visible = true
	overlay.set_mode("place_restaurant")
	overlay.set_map_data({
		"restaurants": {
			"rest_0": {"entrance_pos": Vector2i(2, 3)},
		}
	})
	overlay.set_available_restaurants(["rest_0"])
	overlay.set_available_employee_items([
		{"staff_id": 201, "employee_type": "regional_manager", "capacity": 1, "used": 0, "remaining": 1, "can_place_restaurant": true, "can_move_restaurant": true},
	])

	var action_panel = ActionPanelScene.instantiate()
	if action_panel == null or not is_instance_valid(action_panel):
		return await _finish_restaurant_context_case(Result.failure("实例化 ActionPanel 失败"), overlay, action_panel, st)
	host.add_child(action_panel)
	(action_panel as Control).visible = true
	await st.process_frame

	if not (action_panel is ActionPanel):
		return await _finish_restaurant_context_case(Result.failure("实例不是 ActionPanel"), overlay, action_panel, st)
	var panel: ActionPanel = action_panel
	panel.bind_context_overlay(overlay)
	await st.process_frame

	if not panel.context_panel.visible:
		return await _finish_restaurant_context_case(Result.failure("绑定餐厅 overlay 后 ContextPanel 应可见"), overlay, action_panel, st)
	if panel.custom_context_container.get_child_count() <= 0:
		return await _finish_restaurant_context_case(Result.failure("餐厅 ContextPanel 应挂载自定义 UI"), overlay, action_panel, st)
	if panel.restaurant_row.visible or panel.employee_row.visible or panel.confirm_context_button.visible:
		return await _finish_restaurant_context_case(Result.failure("餐厅自定义 Context 不应显示旧的行式餐厅/员工/确认控件"), overlay, action_panel, st)

	var context_node = panel.custom_context_container.get_child(0)
	var employee_row = context_node.get("_employee_row")
	var mode_row = context_node.get("_mode_row")
	if employee_row == null or not is_instance_valid(employee_row):
		return await _finish_restaurant_context_case(Result.failure("餐厅 Context 缺少顶部员工选择区"), overlay, action_panel, st)
	if mode_row == null or not is_instance_valid(mode_row):
		return await _finish_restaurant_context_case(Result.failure("餐厅 Context 缺少下方模式切换区"), overlay, action_panel, st)
	if context_node.get_child(0) != employee_row or context_node.get_child(1) != mode_row:
		return await _finish_restaurant_context_case(Result.failure("餐厅 Context 应先显示员工选择，再显示放置/移动面板"), overlay, action_panel, st)

	var move_button = context_node.get("_move_restaurant_button")
	if not (move_button is Button):
		return await _finish_restaurant_context_case(Result.failure("餐厅 Context 缺少移动餐厅按钮"), overlay, action_panel, st)
	if (move_button as Button).disabled:
		return await _finish_restaurant_context_case(Result.failure("区域经理和已有餐厅可用时，移动餐厅按钮不应禁用"), overlay, action_panel, st)

	(move_button as Button).emit_signal("pressed")
	await st.process_frame

	if overlay.get_mode() != "move_restaurant":
		return await _finish_restaurant_context_case(Result.failure("点击移动餐厅后 overlay 模式应切换为 move_restaurant，实际: %s" % overlay.get_mode()), overlay, action_panel, st)
	if overlay.get_selected_restaurant() != "rest_0":
		return await _finish_restaurant_context_case(Result.failure("切换移动餐厅后应默认选中可移动餐厅 rest_0，实际: %s" % overlay.get_selected_restaurant()), overlay, action_panel, st)

	return await _finish_restaurant_context_case(Result.success({}), overlay, action_panel, st)

static func _case_house_confirm_keeps_context_and_marks_used_staff() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 PlacementStaffPicker UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 Placement UI 测试节点）")
	if ActionPanelScene == null:
		return Result.failure("预加载 action_panel.tscn 失败（PackedScene 为空）")

	var scene := _FakeGameScene.new()
	var action_panel = null
	var overlays = null
	var engine := GameEngine.new()

	var init := engine.initialize(2, 24680)
	if not init.ok:
		return await _finish_overlay_case(Result.failure("初始化失败: %s" % init.error), overlays, scene, action_panel, engine, st)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 40)
	if not to_working.ok:
		return await _finish_overlay_case(to_working, overlays, scene, action_panel, engine, st)

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	var take := StateUpdaterClass.take_from_pool(state, "new_business_developer", 2)
	if not take.ok:
		return await _finish_overlay_case(Result.failure("取出 new_business_developer 失败: %s" % take.error), overlays, scene, action_panel, engine, st)
	for _i in range(2):
		var add := StateUpdaterClass.add_employee(state, actor, "new_business_developer", false)
		if not add.ok:
			return await _finish_overlay_case(Result.failure("添加 new_business_developer 失败: %s" % add.error), overlays, scene, action_panel, engine, st)

	var ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, actor, "new_business_developer", ["employees"])
	if not ids_read.ok:
		return await _finish_overlay_case(Result.failure("读取 new_business_developer staff_id 失败: %s" % ids_read.error), overlays, scene, action_panel, engine, st)
	var ids: Array = ids_read.value
	if ids.size() < 2:
		return await _finish_overlay_case(Result.failure("需要 2 个 new_business_developer staff_id，实际: %s" % str(ids)), overlays, scene, action_panel, engine, st)
	var first_staff_id := int(ids[0])
	var second_staff_id := int(ids[1])

	var to_place_houses := TestPhaseUtilsClass.advance_until_working_sub_phase(engine, DefsClass.SUB_PHASE_PLACE_HOUSES, 20)
	if not to_place_houses.ok:
		return await _finish_overlay_case(to_place_houses, overlays, scene, action_panel, engine, st)

	scene.game_engine = engine
	host.add_child(scene)
	scene.visible = true
	await st.process_frame

	var map_controller := _MapControllerSpy.new()
	var overlay_controller := _OverlayControllerSpy.new()
	var command_executor := _CommandExecutor.new(engine)
	overlays = PlacementOverlaysClass.new(
		scene,
		map_controller,
		overlay_controller,
		Callable(command_executor, "execute"),
		Callable()
	)

	overlays.show_house_placement("place_house", {"staff_id": first_staff_id})
	await st.process_frame

	if not is_instance_valid(overlays.house_placement_overlay) or not overlays.house_placement_overlay.visible:
		return await _finish_overlay_case(Result.failure("show_house_placement 后 overlay 应可见"), overlays, scene, action_panel, engine, st)
	if int(overlays.house_placement_overlay.get_selected_staff_id()) != first_staff_id:
		return await _finish_overlay_case(
			Result.failure("overlay 初始应选中第一个拓展经理，实际: %s" % str(overlays.house_placement_overlay.get_selected_staff_id())),
			overlays,
			scene,
			action_panel,
			engine,
			st
		)

	action_panel = ActionPanelScene.instantiate()
	if action_panel == null or not is_instance_valid(action_panel):
		return await _finish_overlay_case(Result.failure("实例化 ActionPanel 失败"), overlays, scene, action_panel, engine, st)
	host.add_child(action_panel)
	(action_panel as Control).visible = true
	await st.process_frame

	if not (action_panel is ActionPanel):
		return await _finish_overlay_case(Result.failure("实例不是 ActionPanel"), overlays, scene, action_panel, engine, st)
	var panel: ActionPanel = action_panel
	panel.bind_context_overlay(overlays.get_active_context_overlay())
	await st.process_frame

	if not panel.context_panel.visible:
		return await _finish_overlay_case(Result.failure("绑定房屋 overlay 后 ContextPanel 应可见"), overlays, scene, action_panel, engine, st)
	if panel.custom_context_container.get_child_count() <= 0:
		return await _finish_overlay_case(Result.failure("ContextPanel 应挂载房屋自定义 UI"), overlays, scene, action_panel, engine, st)

	var plan := _find_valid_house_plan(engine, actor, first_staff_id)
	if plan.is_empty():
		return await _finish_overlay_case(Result.failure("找不到合法的 place_house 测试落点"), overlays, scene, action_panel, engine, st)

	overlays._on_house_placement_confirmed(
		Vector2i(plan.get("position", Vector2i(-1, -1))),
		int(plan.get("rotation", 0)),
		int(plan.get("house_number", -1))
	)
	await st.process_frame

	if not is_instance_valid(overlays.house_placement_overlay) or not overlays.house_placement_overlay.visible:
		return await _finish_overlay_case(Result.failure("放置房屋成功后，若仍有可用员工则房屋 overlay 应保持打开"), overlays, scene, action_panel, engine, st)
	if overlay_controller.hide_all_count != 0:
		return await _finish_overlay_case(Result.failure("仍在 PlaceHouses 子阶段时不应关闭全部 overlay，实际调用次数=%d" % overlay_controller.hide_all_count), overlays, scene, action_panel, engine, st)

	var items: Array[Dictionary] = overlays.house_placement_overlay.get_available_employee_items()
	if items.size() != 2:
		return await _finish_overlay_case(Result.failure("放置后应仍显示 2 张拓展经理卡（含已用灰显），实际: %d" % items.size()), overlays, scene, action_panel, engine, st)

	var first_item := _find_staff_picker_item(items, first_staff_id)
	var second_item := _find_staff_picker_item(items, second_staff_id)
	if first_item.is_empty() or second_item.is_empty():
		return await _finish_overlay_case(Result.failure("放置后 staff picker 缺少预期的两个 staff_id"), overlays, scene, action_panel, engine, st)
	if bool(first_item.get("enabled", true)):
		return await _finish_overlay_case(Result.failure("已使用的第一个拓展经理应变为灰显不可用"), overlays, scene, action_panel, engine, st)
	if not bool(second_item.get("enabled", false)):
		return await _finish_overlay_case(Result.failure("未使用的第二个拓展经理应仍可用"), overlays, scene, action_panel, engine, st)

	var context_node = panel.custom_context_container.get_child(0)
	var picker = context_node.get("_employee_picker")
	if picker == null or not is_instance_valid(picker):
		return await _finish_overlay_case(Result.failure("房屋 Context 缺少员工 picker"), overlays, scene, action_panel, engine, st)
	if not picker.has_method("set_selected"):
		return await _finish_overlay_case(Result.failure("员工 picker 缺少 set_selected"), overlays, scene, action_panel, engine, st)

	picker.set_selected("staff:%d" % second_staff_id)
	context_node.call("_on_employee_picker_selected", "new_business_developer")
	await st.process_frame

	if not panel.context_panel.visible:
		return await _finish_overlay_case(Result.failure("点击第二个拓展经理后 ContextPanel 不应变空白"), overlays, scene, action_panel, engine, st)
	if panel.custom_context_container.get_child_count() <= 0:
		return await _finish_overlay_case(Result.failure("点击第二个拓展经理后自定义 Context 不应被清空"), overlays, scene, action_panel, engine, st)
	if int(overlays.house_placement_overlay.get_selected_staff_id()) != second_staff_id:
		return await _finish_overlay_case(
			Result.failure("点击第二个拓展经理后应切换到 staff_id=%d，实际: %s" % [second_staff_id, str(overlays.house_placement_overlay.get_selected_staff_id())]),
			overlays,
			scene,
			action_panel,
			engine,
			st
		)

	state = engine.get_state()
	var first_used := StaffStateClass.get_staff_track_used(state, first_staff_id, "place_house_or_garden")
	var second_used := StaffStateClass.get_staff_track_used(state, second_staff_id, "place_house_or_garden")
	if not first_used.ok or not second_used.ok:
		return await _finish_overlay_case(Result.failure("读取拓展经理 usage 失败: %s / %s" % [str(first_used), str(second_used)]), overlays, scene, action_panel, engine, st)
	if int(first_used.value) != 1 or int(second_used.value) != 0:
		return await _finish_overlay_case(Result.failure("放置后应只消耗第一个拓展经理，实际 first=%s second=%s" % [str(first_used.value), str(second_used.value)]), overlays, scene, action_panel, engine, st)

	return await _finish_overlay_case(Result.success({}), overlays, scene, action_panel, engine, st)

static func _find_valid_house_plan(engine: GameEngine, actor: int, staff_id: int) -> Dictionary:
	if engine == null:
		return {}
	var state := engine.get_state()
	if state == null:
		return {}
	var executor = engine.action_registry.get_executor("place_house")
	if executor == null:
		return {}

	var house_number := 1
	var supply_val = state.map.get("house_number_supply_remaining", null)
	if supply_val is Array and not Array(supply_val).is_empty():
		house_number = int(Array(supply_val)[0])

	var grid: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	for y in range(grid.y):
		for x in range(grid.x):
			for rotation in [0, 90, 180, 270]:
				var cmd := Command.create("place_house", actor, {
					"position": [x, y],
					"rotation": rotation,
					"house_number": house_number,
					"employee_type": "new_business_developer",
					"staff_id": staff_id,
				})
				if executor.validate(state, cmd).ok:
					return {
						"position": Vector2i(x, y),
						"rotation": rotation,
						"house_number": house_number,
					}
	return {}

static func _find_staff_picker_item(items: Array[Dictionary], staff_id: int) -> Dictionary:
	for item_val in items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if int(item.get("staff_id", -1)) == staff_id:
			return item
	return {}

static func _finish_restaurant_context_case(result: Result, overlay: Node, action_panel: Node, st: SceneTree) -> Result:
	if action_panel != null and is_instance_valid(action_panel):
		action_panel.queue_free()
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	await st.process_frame
	return result

static func _finish_overlay_case(result: Result, overlays, scene: Node, action_panel: Node, engine: GameEngine, st: SceneTree) -> Result:
	if overlays != null and overlays.has_method("dispose"):
		overlays.dispose()
	if action_panel != null and is_instance_valid(action_panel):
		action_panel.queue_free()
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await st.process_frame
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
