# 采购日志：地图路径预览（hover / pin）
extends RefCounted

const DrinksProcurementInputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const TileRouteUtilsClass = preload("res://core/rules/drinks_procurement/tile_route_utils.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

var _get_game_engine: Callable
var _overlay_controller = null
var _game_log_panel = null
var _timeline_controller = null

var _pinned_entry_id: int = -1
var _hover_entry_id: int = -1

func _init(get_game_engine: Callable, overlay_controller, game_log_panel, timeline_controller) -> void:
	_get_game_engine = get_game_engine
	_overlay_controller = overlay_controller
	_game_log_panel = game_log_panel
	_timeline_controller = timeline_controller

func dispose() -> void:
	_clear_preview()
	_get_game_engine = Callable()
	_overlay_controller = null
	_game_log_panel = null
	_timeline_controller = null

func on_replay_toggle_changed(active: bool) -> void:
	if _timeline_controller != null and is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("set_manual_replay_enabled"):
			_timeline_controller.call("set_manual_replay_enabled", bool(active))
	_clear_preview()

func on_log_entry_hovered(entry_id: int, hovering: bool) -> void:
	if not _is_preview_enabled():
		return

	if bool(hovering):
		if not _is_drinks_procurement_log_entry(entry_id):
			return
		_hover_entry_id = int(entry_id)
	else:
		if _hover_entry_id != int(entry_id):
			return
		_hover_entry_id = -1

	_refresh_preview_overlay()

func on_log_entry_clicked(entry_id: int) -> void:
	if not _is_preview_enabled():
		return

	var eid := int(entry_id)
	if not _is_drinks_procurement_log_entry(eid):
		_pinned_entry_id = -1
		_refresh_preview_overlay()
		return

	if _pinned_entry_id == eid:
		_pinned_entry_id = -1
	else:
		_pinned_entry_id = eid
	_refresh_preview_overlay()

func _is_preview_enabled() -> bool:
	# 仅在“正常模式”下启用：回放/复盘/时间线手动回放打开时不干预日志点击行为。
	if _timeline_controller != null and is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("is_manual_replay_enabled") and bool(_timeline_controller.call("is_manual_replay_enabled")):
			return false
		if _timeline_controller.has_method("is_replay_mode_active") and bool(_timeline_controller.call("is_replay_mode_active")):
			return false
		if _timeline_controller.has_method("is_timeline_read_only_active"):
			var engine = _get_game_engine.call() if _get_game_engine.is_valid() else null
			if engine is GameEngine:
				if bool(_timeline_controller.call("is_timeline_read_only_active", engine)):
					return false
	return true

func _is_drinks_procurement_log_entry(entry_id: int) -> bool:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return false
	if not _game_log_panel.has_method("get_entry_by_id"):
		return false
	var entry: Dictionary = _game_log_panel.call("get_entry_by_id", int(entry_id))
	if entry.is_empty():
		return false
	var details_val = entry.get("details", null)
	var details: Dictionary = details_val if (details_val is Dictionary) else {}
	var event_type := str(details.get("event_type", entry.get("event_type", ""))).strip_edges()
	return event_type == EventBus.EventType.DRINKS_PROCURED

func _clear_preview() -> void:
	_pinned_entry_id = -1
	_hover_entry_id = -1
	_hide_preview_overlay()

func _refresh_preview_overlay() -> void:
	var show_id := -1
	if _hover_entry_id >= 0:
		show_id = _hover_entry_id
	elif _pinned_entry_id >= 0:
		show_id = _pinned_entry_id

	if show_id < 0:
		_hide_preview_overlay()
		return
	if not _try_show_preview_overlay(show_id):
		_hide_preview_overlay()

func _hide_preview_overlay() -> void:
	if _overlay_controller != null and _overlay_controller.has_method("hide_procurement_route_overlay"):
		_overlay_controller.call("hide_procurement_route_overlay")

func _try_show_preview_overlay(entry_id: int) -> bool:
	if _overlay_controller == null or not _overlay_controller.has_method("show_procurement_route_overlay"):
		return false
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return false
	if not _game_log_panel.has_method("get_entry_by_id"):
		return false

	var entry: Dictionary = _game_log_panel.call("get_entry_by_id", int(entry_id))
	if entry.is_empty():
		return false
	var details_val = entry.get("details", null)
	var details: Dictionary = details_val if (details_val is Dictionary) else {}
	var event_type := str(details.get("event_type", entry.get("event_type", ""))).strip_edges()
	if event_type != EventBus.EventType.DRINKS_PROCURED:
		return false

	var engine_val = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine_val == null or not (engine_val is GameEngine):
		return false
	var engine: GameEngine = engine_val

	var cmd_index := -999
	var ci_val = details.get("command_index", entry.get("command_index", null))
	if ci_val is int:
		cmd_index = int(ci_val)
	elif ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			cmd_index = int(f)
	if cmd_index < 0 or cmd_index >= engine.command_history.size():
		return false

	var cmd_val = engine.command_history[cmd_index]
	if not (cmd_val is Command):
		return false
	var cmd: Command = cmd_val
	if str(cmd.action_id).strip_edges() != "procure_drinks":
		return false

	var route_parse: Result = DrinksProcurementInputsClass.parse_route_positions(cmd.params.get("route", null))
	if not route_parse.ok:
		return false
	var route: Array[Vector2i] = route_parse.value
	if route.is_empty():
		return false

	# picked_sources 优先来自事件 data（更贴近实际“本次采购确认的来源”）；缺失则回退 selected_sources。
	var picked_sources: Array[Vector2i] = []
	var ps_val = details.get("picked_sources", null)
	if ps_val is Array:
		for src_val in Array(ps_val):
			if not (src_val is Dictionary):
				continue
			var src: Dictionary = src_val
			var wp_val = src.get("world_pos", null)
			if wp_val is Vector2i:
				picked_sources.append(Vector2i(wp_val))
			elif wp_val is Array:
				var a: Array = wp_val
				if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
					picked_sources.append(Vector2i(int(a[0]), int(a[1])))
	if picked_sources.is_empty():
		var selected_parse: Result = DrinksProcurementInputsClass.parse_route_positions(details.get("selected_sources", cmd.params.get("selected_sources", null)))
		if selected_parse.ok:
			picked_sources = selected_parse.value

	var restaurant_id := str(details.get("restaurant_id", cmd.params.get("restaurant_id", ""))).strip_edges()
	var entrance_pos := Vector2i(-1, -1)
	var start_restaurant_cells: Array[Vector2i] = []
	if not restaurant_id.is_empty():
		var s: GameState = engine.get_state()
		if s != null and s.map is Dictionary:
			var restaurants_val = s.map.get("restaurants", null)
			if restaurants_val is Dictionary:
				var rest_val = (restaurants_val as Dictionary).get(restaurant_id, null)
				if rest_val is Dictionary:
					var rest: Dictionary = rest_val
					var ep_val = rest.get("entrance_pos", null)
					if ep_val is Vector2i:
						entrance_pos = Vector2i(ep_val)
					var cells_val = rest.get("cells", null)
					if cells_val is Array:
						for p in (cells_val as Array):
							if p is Vector2i:
								start_restaurant_cells.append(Vector2i(p))
							elif p is Array:
								var a: Array = p
								if a.size() == 2 and (a[0] is int or a[0] is float) and (a[1] is int or a[1] is float):
									start_restaurant_cells.append(Vector2i(int(a[0]), int(a[1])))

	var employee_type := str(details.get("employee_type", cmd.params.get("employee_type", ""))).strip_edges()
	var is_air := false
	if not employee_type.is_empty() and EmployeeRegistryClass.is_loaded():
		var emp_def: EmployeeDef = EmployeeRegistryClass.get_def(employee_type)
		if emp_def != null and str(emp_def.range_type).strip_edges() == "air":
			is_air = true

	if is_air:
		var tile_size_cells := int(MapUtils.TILE_SIZE)
		var state: GameState = engine.get_state()
		if state != null:
			var tile_size_r := TileRouteUtilsClass.get_tile_size(state)
			if tile_size_r.ok:
				tile_size_cells = int(tile_size_r.value)

		var opts := {
			"tile_mode": true,
			"tile_size_cells": tile_size_cells,
			"selected_tiles": route.duplicate(),
			"start_restaurant_cells": start_restaurant_cells,
		}
		var empty_route: Array[Vector2i] = []
		_overlay_controller.call("show_procurement_route_overlay", Vector2i(-1, -1), empty_route, picked_sources, opts)
		return true

	var opts2 := {
		"start_restaurant_cells": start_restaurant_cells,
	}
	_overlay_controller.call("show_procurement_route_overlay", entrance_pos, route, picked_sources, opts2)
	return true

