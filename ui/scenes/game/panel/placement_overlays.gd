# Game scene：放置覆盖层（餐厅/住宅/花园/板块）
extends RefCounted

const RestaurantPlacementScene = preload("res://ui/components/restaurant_placement/restaurant_placement_overlay.tscn")
const HousePlacementScene = preload("res://ui/components/house_placement/house_placement_overlay.tscn")
const PiecePlacementScene = preload("res://ui/components/piece_placement/piece_placement_overlay.tscn")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _map_controller = null
var _overlay_controller = null
var _execute_command: Callable
var _hide_all: Callable

var restaurant_placement_overlay = null
var house_placement_overlay = null
var piece_placement_overlay = null
var _module_overlay_controllers: Array = []
var _module_overlay_controllers_loaded: bool = false
var _module_overlay_load_error: String = ""

func _init(scene, map_controller, overlay_controller, execute_command: Callable, hide_all: Callable) -> void:
	_scene = scene
	_map_controller = map_controller
	_overlay_controller = overlay_controller
	_execute_command = execute_command
	_hide_all = hide_all

func dispose() -> void:
	hide()

	if _map_controller != null:
		if _map_controller.has_method("set_restaurant_placement_overlay"):
			_map_controller.set_restaurant_placement_overlay(null)
		if _map_controller.has_method("set_house_placement_overlay"):
			_map_controller.set_house_placement_overlay(null)
		if _map_controller.has_method("set_piece_placement_overlay"):
			_map_controller.set_piece_placement_overlay(null)

	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.queue_free()
	restaurant_placement_overlay = null

	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.queue_free()
	house_placement_overlay = null

	if is_instance_valid(piece_placement_overlay):
		piece_placement_overlay.queue_free()
	piece_placement_overlay = null

	for c in _module_overlay_controllers:
		if c == null or not is_instance_valid(c):
			continue
		if c.has_method("dispose"):
			c.call("dispose")
	_module_overlay_controllers.clear()
	_module_overlay_controllers_loaded = false

	_scene = null
	_map_controller = null
	_overlay_controller = null
	_execute_command = Callable()
	_hide_all = Callable()

func get_active_context_overlay():
	var module_load_r := _ensure_module_overlay_controllers_loaded()
	if not module_load_r.ok:
		return null
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible:
		return restaurant_placement_overlay
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.visible:
		return house_placement_overlay
	if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.visible:
		return piece_placement_overlay
	for c in _module_overlay_controllers:
		if c == null or not is_instance_valid(c):
			continue
		if c.has_method("get_context_overlay"):
			var ov = c.call("get_context_overlay")
			if ov != null and is_instance_valid(ov):
				return ov
	return null

func hide() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if is_instance_valid(piece_placement_overlay):
		piece_placement_overlay.visible = false
	for c in _module_overlay_controllers:
		if c != null and is_instance_valid(c) and c.has_method("hide"):
			c.call("hide")

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	_sync_restaurant_placement_overlay(state, force_full_refresh)
	_sync_house_placement_overlay(state, force_full_refresh)
	_sync_piece_placement_overlay(state, force_full_refresh)
	_sync_module_overlays(state, force_full_refresh)

func _sync_restaurant_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(restaurant_placement_overlay) or not restaurant_placement_overlay.visible:
		return

	var allowed := false
	if state.phase == DefsClass.PHASE_SETUP:
		allowed = true
	elif state.phase == DefsClass.PHASE_WORKING and state.sub_phase == DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
		allowed = true

	if not allowed:
		restaurant_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	# 时间线变化：保持覆盖层打开，但从 state 强制刷新可用员工/地图数据，避免残留旧 UI/选点缓存。
	if force_full_refresh:
		var current_player_id := state.get_current_player_id()
		var current_player: Dictionary = state.get_current_player()

		var action_id := "place_restaurant"
		if restaurant_placement_overlay.has_method("get_mode"):
			action_id = str(restaurant_placement_overlay.get_mode())

		var prev_employee_key := ""
		if restaurant_placement_overlay.has_method("get_selected_employee_key"):
			prev_employee_key = str(restaurant_placement_overlay.get_selected_employee_key()).strip_edges()
		var prev_restaurant := ""
		if restaurant_placement_overlay.has_method("get_selected_restaurant"):
			prev_restaurant = str(restaurant_placement_overlay.get_selected_restaurant()).strip_edges()

		if _map_controller != null:
			_map_controller.begin_selection("restaurant_placement", {"action_id": action_id})
			if _map_controller.has_method("on_restaurant_preview_cleared"):
				_map_controller.on_restaurant_preview_cleared()

		if restaurant_placement_overlay.has_method("set_map_data"):
			restaurant_placement_overlay.set_map_data(state.map)

		if restaurant_placement_overlay.has_method("set_available_restaurants"):
			var ids: Array[String] = []
			for rid in Array(current_player.get("restaurants", [])):
				ids.append(str(rid))
			restaurant_placement_overlay.set_available_restaurants(ids)
		if action_id == "move_restaurant" and restaurant_placement_overlay.has_method("set_selected_restaurant") and not prev_restaurant.is_empty():
			restaurant_placement_overlay.set_selected_restaurant(prev_restaurant)

		if restaurant_placement_overlay.has_method("set_available_employee_items"):
			restaurant_placement_overlay.set_available_employee_items(
				_build_restaurant_employee_items(state, current_player_id, action_id)
			)
			if restaurant_placement_overlay.has_method("set_selected_employee_key") and not prev_employee_key.is_empty() and _employee_items_contain_key(restaurant_placement_overlay, prev_employee_key):
				restaurant_placement_overlay.set_selected_employee_key(prev_employee_key)

		if restaurant_placement_overlay.has_method("get_selected_rotation") and restaurant_placement_overlay.has_method("set_selected_rotation"):
			var r := int(restaurant_placement_overlay.get_selected_rotation())
			restaurant_placement_overlay.set_selected_rotation(r)

func _sync_house_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(house_placement_overlay) or not house_placement_overlay.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_PLACE_HOUSES:
		house_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	# 时间线变化：保持覆盖层打开，但从 state 强制刷新可用员工/地图数据，避免残留旧 UI/选点缓存。
	if force_full_refresh:
		var current_player_id := state.get_current_player_id()

		var action_id := "place_house"
		if house_placement_overlay.has_method("get_mode"):
			action_id = str(house_placement_overlay.get_mode())

		var prev_employee_key := ""
		if house_placement_overlay.has_method("get_selected_employee_key"):
			prev_employee_key = str(house_placement_overlay.get_selected_employee_key()).strip_edges()

		if _map_controller != null:
			_map_controller.begin_selection("house_placement", {"action_id": action_id})
			if _map_controller.has_method("on_house_preview_cleared"):
				_map_controller.on_house_preview_cleared()

		if house_placement_overlay.has_method("set_map_data"):
			house_placement_overlay.set_map_data(state.map)

		if house_placement_overlay.has_method("set_available_employee_items"):
			house_placement_overlay.set_available_employee_items(
				_build_house_garden_employee_items(state, current_player_id, action_id)
			)
			if house_placement_overlay.has_method("set_selected_employee_key") and not prev_employee_key.is_empty() and _employee_items_contain_key(house_placement_overlay, prev_employee_key):
				house_placement_overlay.set_selected_employee_key(prev_employee_key)

		if house_placement_overlay.has_method("get_selected_rotation") and house_placement_overlay.has_method("set_selected_rotation"):
			var r := int(house_placement_overlay.get_selected_rotation())
			house_placement_overlay.set_selected_rotation(r)

func _sync_piece_placement_overlay(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(piece_placement_overlay) or not piece_placement_overlay.visible:
		return
	if _scene == null or _scene.game_engine == null:
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	var engine: GameEngine = _scene.game_engine
	var action_id := ""
	if piece_placement_overlay.has_method("get_mode"):
		action_id = str(piece_placement_overlay.get_mode()).strip_edges()
	if action_id.is_empty():
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	var executor = engine.get_action_registry().get_executor(action_id)
	var allowed := executor != null
	if allowed and (executor.allowed_phases is Array) and not executor.allowed_phases.is_empty():
		allowed = executor.allowed_phases.has(state.phase)
	if allowed and (executor.allowed_sub_phases is Array) and not executor.allowed_sub_phases.is_empty() and not str(state.sub_phase).is_empty():
		allowed = executor.allowed_sub_phases.has(state.sub_phase)

	if not allowed:
		piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		return

	if not force_full_refresh:
		return

	# 时间线变化：保持覆盖层打开，重新同步选点模式与高亮/预览（避免残留旧 state 缓存）。
	var selected_pos: Vector2i = Vector2i(-1, -1)
	var selected_rot := 0
	var selected_piece := ""
	if piece_placement_overlay.has_method("get_selected_position"):
		selected_pos = piece_placement_overlay.get_selected_position()
	if piece_placement_overlay.has_method("get_selected_rotation"):
		selected_rot = int(piece_placement_overlay.get_selected_rotation())
	if piece_placement_overlay.has_method("get_selected_piece"):
		selected_piece = str(piece_placement_overlay.get_selected_piece()).strip_edges()

	if _map_controller != null:
		_map_controller.begin_selection("piece_placement", {"action_id": action_id})
		if _map_controller.has_method("on_piece_highlight_requested"):
			_map_controller.on_piece_highlight_requested(action_id, selected_rot, selected_piece)
		if selected_pos != Vector2i(-1, -1) and _map_controller.has_method("on_piece_preview_requested"):
			_map_controller.on_piece_preview_requested(action_id, selected_pos, selected_rot, selected_piece)
		elif _map_controller.has_method("on_piece_preview_cleared"):
			_map_controller.on_piece_preview_cleared()

func try_show_piece_placement(action_id: String, params: Dictionary) -> bool:
	if _scene == null or _scene.game_engine == null:
		return false

	var ex = _scene.game_engine.get_action_registry().get_executor(action_id)
	if ex == null:
		return false

	var piece_ids: Array[String] = []
	var ids_val = ex.ui_piece_ids
	if ids_val is Array:
		for v in Array(ids_val):
			var s := str(v).strip_edges()
			if not s.is_empty():
				piece_ids.append(s)
	if piece_ids.is_empty():
		return false

	show_piece_placement(action_id, piece_ids, params)
	return true

func try_show_module_action_overlay(action_id: String, params: Dictionary) -> bool:
	# Allow module-provided overlay controllers to handle action clicks and open custom UI flows.
	var module_load_r := _ensure_module_overlay_controllers_loaded()
	if not module_load_r.ok:
		return false
	for c in _module_overlay_controllers:
		if c == null or not is_instance_valid(c):
			continue
		if not c.has_method("try_handle_action_request"):
			continue
		var handled = c.call("try_handle_action_request", action_id, params)
		if handled is bool and bool(handled):
			return true
	return false

func show_piece_placement(action_id: String, piece_ids: Array[String], params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if piece_placement_overlay == null:
		piece_placement_overlay = PiecePlacementScene.instantiate()
		if piece_placement_overlay.has_signal("placement_confirmed"):
			piece_placement_overlay.placement_confirmed.connect(_on_piece_placement_confirmed)
		if piece_placement_overlay.has_signal("cancelled"):
			piece_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if piece_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			piece_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_piece_preview_requested"))
		if piece_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			piece_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_piece_preview_cleared"))
		if piece_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			piece_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_piece_highlight_requested"))
		_scene.add_child(piece_placement_overlay)
		if _map_controller != null and _map_controller.has_method("set_piece_placement_overlay"):
			_map_controller.set_piece_placement_overlay(piece_placement_overlay)

	if _map_controller != null:
		_map_controller.begin_selection("piece_placement", {"action_id": action_id})
	piece_placement_overlay.visible = true

	if piece_placement_overlay.has_method("set_mode"):
		piece_placement_overlay.set_mode(action_id)
	if piece_placement_overlay.has_method("set_available_pieces"):
		piece_placement_overlay.set_available_pieces(piece_ids)

	if params.has("piece_id") and piece_placement_overlay.has_method("set_selected_piece"):
		piece_placement_overlay.set_selected_piece(str(params.piece_id))
	if params.has("rotation") and piece_placement_overlay.has_method("set_selected_rotation"):
		piece_placement_overlay.set_selected_rotation(int(params.rotation))

	if _map_controller != null and _map_controller.has_method("on_piece_preview_cleared"):
		_map_controller.on_piece_preview_cleared()

func show_restaurant_placement(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if restaurant_placement_overlay == null:
		restaurant_placement_overlay = RestaurantPlacementScene.instantiate()
		if restaurant_placement_overlay.has_signal("placement_confirmed"):
			restaurant_placement_overlay.placement_confirmed.connect(_on_restaurant_placement_confirmed)
		if restaurant_placement_overlay.has_signal("cancelled"):
			restaurant_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if restaurant_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			restaurant_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_restaurant_preview_requested"))
		if restaurant_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			restaurant_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_restaurant_preview_cleared"))
		if restaurant_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			restaurant_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_restaurant_highlight_requested"))
		_scene.add_child(restaurant_placement_overlay)
		if _map_controller != null:
			_map_controller.set_restaurant_placement_overlay(restaurant_placement_overlay)

	var state = _scene.game_engine.get_state()
	var current_player_id = state.get_current_player_id()
	var current_player: Dictionary = state.get_current_player()

	if _map_controller != null:
		_map_controller.begin_selection("restaurant_placement", {"action_id": action_id})
	restaurant_placement_overlay.visible = true

	if restaurant_placement_overlay.has_method("set_mode"):
		restaurant_placement_overlay.set_mode(action_id)
	if restaurant_placement_overlay.has_method("set_map_data"):
		restaurant_placement_overlay.set_map_data(state.map)

	if restaurant_placement_overlay.has_method("set_available_restaurants"):
		var ids: Array[String] = []
		for rid in Array(current_player.get("restaurants", [])):
			ids.append(str(rid))
		restaurant_placement_overlay.set_available_restaurants(ids)

	if action_id == "move_restaurant" and params.has("restaurant_id") and restaurant_placement_overlay.has_method("set_selected_restaurant"):
		restaurant_placement_overlay.set_selected_restaurant(str(params.restaurant_id))

	if restaurant_placement_overlay.has_method("set_available_employee_items"):
		restaurant_placement_overlay.set_available_employee_items(
			_build_restaurant_employee_items(state, current_player_id, action_id)
		)
		if params.has("staff_id") and restaurant_placement_overlay.has_method("set_selected_employee_key"):
			restaurant_placement_overlay.set_selected_employee_key("staff:%d" % int(params.staff_id))
		elif params.has("employee_type") and restaurant_placement_overlay.has_method("set_selected_employee"):
			restaurant_placement_overlay.set_selected_employee(str(params.employee_type))

	if _map_controller != null:
		_map_controller.on_restaurant_preview_cleared()

func show_house_placement(action_id: String, params: Dictionary) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if house_placement_overlay == null:
		house_placement_overlay = HousePlacementScene.instantiate()
		if house_placement_overlay.has_signal("house_placement_confirmed"):
			house_placement_overlay.house_placement_confirmed.connect(_on_house_placement_confirmed)
		if house_placement_overlay.has_signal("garden_confirmed"):
			house_placement_overlay.garden_confirmed.connect(_on_garden_confirmed)
		if house_placement_overlay.has_signal("cancelled"):
			house_placement_overlay.cancelled.connect(_on_overlay_cancelled)
		if house_placement_overlay.has_signal("preview_requested") and _map_controller != null:
			house_placement_overlay.preview_requested.connect(Callable(_map_controller, "on_house_preview_requested"))
		if house_placement_overlay.has_signal("preview_cleared") and _map_controller != null:
			house_placement_overlay.preview_cleared.connect(Callable(_map_controller, "on_house_preview_cleared"))
		if house_placement_overlay.has_signal("garden_preview_requested") and _map_controller != null:
			house_placement_overlay.garden_preview_requested.connect(Callable(_map_controller, "on_house_garden_preview_requested"))
		if house_placement_overlay.has_signal("garden_preview_cleared") and _map_controller != null:
			house_placement_overlay.garden_preview_cleared.connect(Callable(_map_controller, "on_house_garden_preview_cleared"))
		if house_placement_overlay.has_signal("highlight_requested") and _map_controller != null:
			house_placement_overlay.highlight_requested.connect(Callable(_map_controller, "on_house_highlight_requested"))
		_scene.add_child(house_placement_overlay)
		if _map_controller != null:
			_map_controller.set_house_placement_overlay(house_placement_overlay)

	var state = _scene.game_engine.get_state()

	if _map_controller != null:
		_map_controller.begin_selection("house_placement", {"action_id": action_id})

	house_placement_overlay.visible = true

	if house_placement_overlay.has_method("set_mode"):
		house_placement_overlay.set_mode(action_id)
	if house_placement_overlay.has_method("set_map_data"):
		house_placement_overlay.set_map_data(state.map)
	if house_placement_overlay.has_method("set_available_employee_items"):
		house_placement_overlay.set_available_employee_items(
			_build_house_garden_employee_items(state, state.get_current_player_id(), action_id)
		)
		if params.has("staff_id") and house_placement_overlay.has_method("set_selected_employee_key"):
			house_placement_overlay.set_selected_employee_key("staff:%d" % int(params.staff_id))
		elif params.has("employee_type") and house_placement_overlay.has_method("set_selected_employee"):
			house_placement_overlay.set_selected_employee(str(params.employee_type))
	if _map_controller != null:
		_map_controller.on_house_preview_cleared()
		if _map_controller.has_method("on_house_garden_preview_cleared"):
			_map_controller.on_house_garden_preview_cleared()

func _sync_module_overlays(state: GameState, force_full_refresh: bool = false) -> void:
	var module_load_r := _ensure_module_overlay_controllers_loaded()
	if not module_load_r.ok:
		return
	for c in _module_overlay_controllers:
		if c == null or not is_instance_valid(c):
			continue
		if c.has_method("sync"):
			c.call("sync", state, force_full_refresh)

func _ensure_module_overlay_controllers_loaded() -> Result:
	if _module_overlay_controllers_loaded:
		if not _module_overlay_load_error.is_empty():
			return Result.failure(_module_overlay_load_error)
		return Result.success()
	if _scene == null or _scene.game_engine == null:
		return Result.success()

	var engine: GameEngine = _scene.game_engine
	var manifests: Dictionary = engine.module_manifests_v2
	var plan: Array[String] = engine.get_module_plan_v2() if engine.has_method("get_module_plan_v2") else []

	var seen := {}
	for mid in plan:
		var manifest_val = manifests.get(mid, null)
		if not (manifest_val is ModuleManifest):
			return _fail_module_overlay_load("module plan 中缺少有效 manifest: %s" % str(mid))
		var manifest: ModuleManifest = manifest_val
		var provides: Dictionary = manifest.provides
		var ui_val = provides.get("ui", null)
		if not (ui_val is Dictionary):
			continue
		var ui: Dictionary = ui_val
		var controllers_val = ui.get("placement_overlays", null)
		if controllers_val == null:
			continue
		if not (controllers_val is Array):
			return _fail_module_overlay_load("%s.provides.ui.placement_overlays 类型错误（期望 Array）" % manifest.id)

		for p in Array(controllers_val):
			var path := str(p).strip_edges()
			if path.is_empty():
				return _fail_module_overlay_load("%s.provides.ui.placement_overlays 包含空路径" % manifest.id)
			if not path.begins_with("res://"):
				return _fail_module_overlay_load("%s.provides.ui.placement_overlays 路径必须以 res:// 开头: %s" % [manifest.id, path])
			if seen.has(path):
				return _fail_module_overlay_load("重复的模块 placement overlay controller 路径: %s" % path)
			seen[path] = true
			var load_r := _instantiate_module_overlay_controller(path, manifest.id)
			if not load_r.ok:
				return _fail_module_overlay_load(load_r.error)
			_module_overlay_controllers.append(load_r.value)

	_module_overlay_controllers_loaded = true
	return Result.success()

func _instantiate_module_overlay_controller(path: String, module_id: String) -> Result:
	if not ResourceLoader.exists(path):
		return Result.failure("%s.provides.ui.placement_overlays 资源不存在: %s" % [module_id, path])
	var res = ResourceLoader.load(path)
	if not (res is Script):
		return Result.failure("%s.provides.ui.placement_overlays 不是 Script: %s" % [module_id, path])
	var ctrl = (res as Script).new(_scene, _map_controller, _overlay_controller, _execute_command, _hide_all)
	if ctrl == null:
		return Result.failure("%s.provides.ui.placement_overlays 创建 controller 失败: %s" % [module_id, path])
	for method_name in ["sync", "hide", "dispose", "get_context_overlay"]:
		if not ctrl.has_method(str(method_name)):
			return Result.failure("%s.provides.ui.placement_overlays controller 缺少方法 %s: %s" % [module_id, str(method_name), path])
	return Result.success(ctrl)

func _fail_module_overlay_load(message: String) -> Result:
	_module_overlay_load_error = str(message).strip_edges()
	if _module_overlay_load_error.is_empty():
		_module_overlay_load_error = "模块 placement overlay controller 加载失败"
	_module_overlay_controllers_loaded = true
	_report_module_overlay_load_error(_module_overlay_load_error)
	return Result.failure(_module_overlay_load_error)

func _report_module_overlay_load_error(message: String) -> void:
	var msg := "模块放置 UI 加载失败：%s" % str(message)
	push_error("[PlacementOverlays] %s" % msg)
	if _overlay_controller != null and _overlay_controller.has_method("show_toast"):
		_overlay_controller.show_toast(msg)

func _on_restaurant_placement_confirmed(position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var command_params := {
		"position": [position.x, position.y],
		"rotation": rotation
	}
	var action_id := "place_restaurant"
	if not restaurant_id.is_empty():
		action_id = "move_restaurant"
		command_params["restaurant_id"] = restaurant_id
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(restaurant_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("get_selected_staff_id"):
		var staff_id := int(restaurant_placement_overlay.get_selected_staff_id())
		if staff_id > 0:
			command_params["staff_id"] = staff_id

	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, command_params))
	if result.ok:
		_after_restaurant_command_success(current_player_id, action_id)
	else:
		if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
			restaurant_placement_overlay.set_validation(false, result.error)

func _on_house_placement_confirmed(position: Vector2i, rotation: int, house_number: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()

	var command_params := {
		"position": [position.x, position.y],
		"rotation": rotation,
		"house_number": int(house_number)
	}
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_staff_id"):
		var staff_id := int(house_placement_overlay.get_selected_staff_id())
		if staff_id > 0:
			command_params["staff_id"] = staff_id
	var result: Result = _execute_command.call(Command.create("place_house", current_player_id, command_params))
	if result.ok:
		_after_house_garden_command_success(current_player_id)
	else:
		if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("set_validation"):
			house_placement_overlay.set_validation(false, result.error)

func _on_garden_confirmed(house_id: String, direction: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	if house_id.is_empty() or direction.is_empty():
		return

	var command_params := {
		"house_id": house_id,
		"direction": direction
	}
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			command_params["employee_type"] = employee_type
	if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("get_selected_staff_id"):
		var staff_id := int(house_placement_overlay.get_selected_staff_id())
		if staff_id > 0:
			command_params["staff_id"] = staff_id
	var result: Result = _execute_command.call(Command.create("add_garden", current_player_id, command_params))
	if result.ok:
		_after_house_garden_command_success(current_player_id)
	else:
		if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("set_validation"):
			house_placement_overlay.set_validation(false, result.error)

func _on_piece_placement_confirmed(position: Vector2i, rotation: int, piece_id: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	if piece_id.is_empty():
		return

	var action_id := ""
	if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("get_mode"):
		action_id = str(piece_placement_overlay.get_mode()).strip_edges()
	if action_id.is_empty():
		return

	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var command_params := {
		"piece_id": piece_id,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	}
	var result: Result = _execute_command.call(Command.create(action_id, current_player_id, command_params))
	if result.ok:
		if is_instance_valid(piece_placement_overlay):
			piece_placement_overlay.visible = false
		if _map_controller != null:
			_map_controller.clear_selection()
		if _overlay_controller != null:
			_overlay_controller.hide_all_overlays()
	else:
		if is_instance_valid(piece_placement_overlay) and piece_placement_overlay.has_method("set_validation"):
			piece_placement_overlay.set_validation(false, result.error)

func _on_overlay_cancelled() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if is_instance_valid(piece_placement_overlay):
		piece_placement_overlay.visible = false
	if _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()

func _after_house_garden_command_success(actor_id: int) -> void:
	var state_after: GameState = _scene.game_engine.get_state() if (_scene != null and _scene.game_engine != null) else null
	if state_after == null:
		_close_house_garden_overlay_and_refresh()
		return

	var same_place_houses_turn := (
		state_after.phase == DefsClass.PHASE_WORKING
		and state_after.sub_phase == DefsClass.SUB_PHASE_PLACE_HOUSES
		and int(state_after.get_current_player_id()) == int(actor_id)
	)
	if same_place_houses_turn:
		_sync_house_placement_overlay(state_after, true)
		_select_first_enabled_house_garden_staff_if_needed()
		if is_instance_valid(house_placement_overlay) and house_placement_overlay.has_method("clear_selection"):
			house_placement_overlay.clear_selection()
		return

	_close_house_garden_overlay_and_refresh()

func _after_restaurant_command_success(actor_id: int, action_id: String = "") -> void:
	var state_after: GameState = _scene.game_engine.get_state() if (_scene != null and _scene.game_engine != null) else null
	if state_after == null:
		_close_restaurant_overlay_and_refresh()
		return

	var same_place_restaurants_turn := (
		state_after.phase == DefsClass.PHASE_WORKING
		and state_after.sub_phase == DefsClass.SUB_PHASE_PLACE_RESTAURANTS
		and int(state_after.get_current_player_id()) == int(actor_id)
	)
	if same_place_restaurants_turn:
		_sync_restaurant_placement_overlay(state_after, true)
		_select_first_enabled_restaurant_staff_if_needed()
		if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("clear_selection"):
			restaurant_placement_overlay.clear_selection(str(action_id).strip_edges() != "move_restaurant")
		return

	_close_restaurant_overlay_and_refresh()

func _close_restaurant_overlay_and_refresh() -> void:
	if is_instance_valid(restaurant_placement_overlay):
		restaurant_placement_overlay.visible = false
		if restaurant_placement_overlay.has_method("clear_selection"):
			restaurant_placement_overlay.clear_selection(false)
	if _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()
	_request_scene_ui_refresh_deferred()

func _close_house_garden_overlay_and_refresh() -> void:
	if is_instance_valid(house_placement_overlay):
		house_placement_overlay.visible = false
	if _map_controller != null:
		_map_controller.clear_selection()
	if _overlay_controller != null:
		_overlay_controller.hide_all_overlays()
	_request_scene_ui_refresh_deferred()

func _select_first_enabled_house_garden_staff_if_needed() -> void:
	if not is_instance_valid(house_placement_overlay):
		return
	if not house_placement_overlay.has_method("get_selected_employee_key"):
		return
	if not house_placement_overlay.has_method("set_selected_employee_key"):
		return

	var current_key := str(house_placement_overlay.get_selected_employee_key()).strip_edges()
	if current_key.is_empty() or _employee_item_key_enabled(house_placement_overlay, current_key):
		return

	var fallback_key := _find_first_enabled_employee_key(house_placement_overlay)
	if fallback_key.is_empty():
		return
	house_placement_overlay.set_selected_employee_key(fallback_key)

func _select_first_enabled_restaurant_staff_if_needed() -> void:
	if not is_instance_valid(restaurant_placement_overlay):
		return
	if not restaurant_placement_overlay.has_method("get_selected_employee_key"):
		return
	if not restaurant_placement_overlay.has_method("set_selected_employee_key"):
		return

	var current_key := str(restaurant_placement_overlay.get_selected_employee_key()).strip_edges()
	if current_key.is_empty() or _employee_item_key_enabled(restaurant_placement_overlay, current_key):
		return

	var fallback_key := _find_first_enabled_employee_key(restaurant_placement_overlay)
	if fallback_key.is_empty():
		return
	restaurant_placement_overlay.set_selected_employee_key(fallback_key)

func _find_first_enabled_employee_key(overlay) -> String:
	if overlay == null or not is_instance_valid(overlay):
		return ""
	if not overlay.has_method("get_available_employee_items"):
		return ""
	var items_val = overlay.call("get_available_employee_items")
	if not (items_val is Array):
		return ""
	for item_val in Array(items_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if not bool(item.get("enabled", true)):
			continue
		var key := str(item.get("key", "")).strip_edges()
		if key.is_empty():
			continue
		return key
	return ""

func _employee_item_key_enabled(overlay, employee_key: String) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	if not overlay.has_method("get_available_employee_items"):
		return false
	var key := str(employee_key).strip_edges()
	if key.is_empty():
		return false
	var items_val = overlay.call("get_available_employee_items")
	if not (items_val is Array):
		return false
	for item_val in Array(items_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("key", "")).strip_edges() != key:
			continue
		return bool(item.get("enabled", true))
	return false

func _request_scene_ui_refresh_deferred() -> void:
	if _scene == null or not is_instance_valid(_scene):
		return
	if _scene.has_method("_update_ui"):
		_scene.call_deferred("_update_ui")

func _build_house_garden_employee_items(state: GameState, player_id: int, action_id: String) -> Array[Dictionary]:
	var all_items := EmployeeRulesClass.get_house_garden_placers_for_working(state, player_id)
	var out: Array[Dictionary] = []
	var capability := "can_add_garden" if str(action_id).strip_edges() == "add_garden" else "can_place_house"
	for item_val in all_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val).duplicate(true)
		if not bool(item.get(capability, false)):
			continue
		out.append(item)
	return out

func _build_restaurant_employee_items(state: GameState, player_id: int, _action_id: String) -> Array[Dictionary]:
	var all_items := EmployeeRulesClass.get_restaurant_placers_for_working(state, player_id)
	var out: Array[Dictionary] = []
	for item_val in all_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = Dictionary(item_val).duplicate(true)
		if not bool(item.get("can_place_restaurant", false)) and not bool(item.get("can_move_restaurant", false)):
			continue
		out.append(item)
	return out

func _employee_items_contain_key(overlay, employee_key: String) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	if not overlay.has_method("get_available_employee_items"):
		return false
	var key := str(employee_key).strip_edges()
	if key.is_empty():
		return false
	var items_val = overlay.call("get_available_employee_items")
	if not (items_val is Array):
		return false
	for item_val in Array(items_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("key", "")).strip_edges() == key:
			return true
	return false
