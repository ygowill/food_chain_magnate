# Game scene：地图交互控制器
# 负责：map_canvas 选点/hover、营销预览、餐厅/房屋放置选点与预览/高亮
class_name GameMapInteractionController
extends RefCounted

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")

var _scene = null
var _map_canvas = null
var _overlay_controller = null

var _mode: String = ""
var _payload: Dictionary = {}
var _restaurant_valid_anchors: Dictionary = {} # Vector2i -> true
var _house_valid_anchors: Dictionary = {} # Vector2i -> true
var _distance_tool_from: Vector2i = Vector2i(-1, -1)

var marketing_panel = null
var restaurant_placement_overlay = null
var house_placement_overlay = null

func _init(scene, map_canvas, overlay_controller) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_overlay_controller = overlay_controller

func connect_signals() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_signal("cell_selected") and not _map_canvas.cell_selected.is_connected(_on_map_cell_selected):
		_map_canvas.cell_selected.connect(_on_map_cell_selected)
	if _map_canvas.has_signal("cell_hovered") and not _map_canvas.cell_hovered.is_connected(_on_map_cell_hovered):
		_map_canvas.cell_hovered.connect(_on_map_cell_hovered)

func set_marketing_panel(panel) -> void:
	marketing_panel = panel

func set_restaurant_placement_overlay(overlay) -> void:
	restaurant_placement_overlay = overlay

func set_house_placement_overlay(overlay) -> void:
	house_placement_overlay = overlay

func begin_selection(mode: String, payload: Dictionary = {}) -> void:
	_mode = mode
	_payload = payload.duplicate(true)
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")

func clear_selection() -> void:
	var old_mode := _mode
	_mode = ""
	_payload.clear()
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
		_map_canvas.call("clear_cell_highlights")
	_restaurant_valid_anchors.clear()
	_house_valid_anchors.clear()
	if old_mode == "distance_tool":
		_distance_tool_from = Vector2i(-1, -1)
		if _overlay_controller != null:
			_overlay_controller.hide_distance_overlay()

func toggle_distance_tool() -> void:
	if _mode == "distance_tool":
		clear_selection()
		GameLog.info("Game", "距离工具已关闭")
		return

	if not _mode.is_empty():
		GameLog.warn("Game", "当前正在 %s 选点模式，无法启用距离工具" % _mode)
		return

	begin_selection("distance_tool")
	_distance_tool_from = Vector2i(-1, -1)
	if _overlay_controller != null:
		_overlay_controller.hide_distance_overlay()
	GameLog.info("Game", "距离工具已启用：点击起点，再点击终点")

func _on_map_cell_selected(world_pos: Vector2i) -> void:
	if world_pos == Vector2i(-1, -1):
		return

	match _mode:
		"marketing":
			if is_instance_valid(marketing_panel) and marketing_panel.visible and marketing_panel.has_method("set_selected_target"):
				marketing_panel.set_selected_target(world_pos)

			var mt := str(_payload.get("marketing_type", ""))
			var range_val := int(_payload.get("range", 0))
			if not mt.is_empty() and _overlay_controller != null:
				_overlay_controller.preview_marketing_range(world_pos, range_val, mt)
		"restaurant_placement":
			# 仅允许点击“高亮的合法格”
			if _restaurant_valid_anchors.is_empty() or not _restaurant_valid_anchors.has(world_pos):
				if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_validation"):
					restaurant_placement_overlay.set_validation(false, "请选择绿色高亮的可放置格")
				return
			if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible and restaurant_placement_overlay.has_method("set_selected_position"):
				restaurant_placement_overlay.set_selected_position(world_pos)
		"house_placement":
			var action_id := str(_payload.get("action_id", ""))
			if action_id == "place_house":
				if _house_valid_anchors.is_empty() or not _house_valid_anchors.has(world_pos):
					return
			if is_instance_valid(house_placement_overlay) and house_placement_overlay.visible and house_placement_overlay.has_method("set_selected_position"):
				house_placement_overlay.set_selected_position(world_pos)
		"distance_tool":
			if _overlay_controller == null:
				return

			if _distance_tool_from == Vector2i(-1, -1):
				_distance_tool_from = world_pos
				_overlay_controller.hide_distance_overlay()
				GameLog.info("Game", "距离工具：起点=%s，请选择终点" % str(world_pos))
				return

			# 再次点击起点视为重置
			if world_pos == _distance_tool_from:
				_distance_tool_from = Vector2i(-1, -1)
				_overlay_controller.hide_distance_overlay()
				GameLog.info("Game", "距离工具：已清除起点，请重新选择起点")
				return

			var to_positions: Array[Vector2i] = []
			to_positions.append(world_pos)
			_overlay_controller.show_distance_overlay(_distance_tool_from, to_positions)
		_:
			pass

func _on_map_cell_hovered(world_pos: Vector2i) -> void:
	if _mode != "marketing":
		return
	if world_pos == Vector2i(-1, -1):
		if _overlay_controller != null:
			_overlay_controller.hide_marketing_range_overlay()
		return

	var mt := str(_payload.get("marketing_type", ""))
	var range_val := int(_payload.get("range", 0))
	if mt.is_empty():
		return

	if _overlay_controller != null:
		_overlay_controller.preview_marketing_range(world_pos, range_val, mt)

func on_marketing_map_selection_requested(marketing_type: String, range_val: int) -> void:
	begin_selection("marketing", {
		"marketing_type": marketing_type,
		"range": range_val,
	})
	if _overlay_controller != null:
		_overlay_controller.hide_marketing_range_overlay()

func on_restaurant_preview_cleared() -> void:
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_structure_preview"):
		_map_canvas.call("clear_structure_preview")
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(true, "")

func on_restaurant_highlight_requested(mode: String, rotation: int, restaurant_id: String) -> void:
	if _mode != "restaurant_placement":
		return
	if not (is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.visible):
		return
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# move_restaurant：未选择餐厅前不高亮
	if action_id == "move_restaurant" and restaurant_id.is_empty():
		_restaurant_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = Vector2i.ZERO
	var map_origin_val = state.map.get("map_origin", Vector2i.ZERO)
	if map_origin_val is Vector2i:
		map_origin = map_origin_val

	# 基于 PlacementValidator 扫描（结构合法性），不依赖 executor.validate 的全图遍历
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("restaurant") or not (piece_registry["restaurant"] is PieceDef):
		piece_registry["restaurant"] = PieceDefClass.create_restaurant()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = PlacementValidatorClass.validate_restaurant_placement(
				ctx,
				world_anchor,
				rotation,
				piece_registry,
				actor,
				state.phase == "Setup",
				extra
			)
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_restaurant_valid_anchors = anchor_set
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", anchors)

func on_house_highlight_requested(action_id: String, rotation: int) -> void:
	if _mode != "house_placement":
		return
	if not (is_instance_valid(house_placement_overlay) and house_placement_overlay.visible):
		return
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return
	if action_id != "place_house":
		_house_valid_anchors.clear()
		if is_instance_valid(_map_canvas) and _map_canvas.has_method("clear_cell_highlights"):
			_map_canvas.call("clear_cell_highlights")
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = Vector2i.ZERO
	var map_origin_val = state.map.get("map_origin", Vector2i.ZERO)
	if map_origin_val is Vector2i:
		map_origin = map_origin_val

	var actor: int = state.get_current_player_id()
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("house") or not (piece_registry["house"] is PieceDef):
		piece_registry["house"] = PieceDefClass.create_house()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = PlacementValidatorClass.validate_house_placement(
				ctx,
				world_anchor,
				rotation,
				piece_registry,
				actor,
				{}
			)
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_house_valid_anchors = anchor_set
	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_cell_highlights"):
		_map_canvas.call("set_cell_highlights", anchors)

func on_restaurant_preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _scene == null:
		return
	var engine = _scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# footprint 预览：尽量不依赖校验成功
	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("restaurant") or not (piece_registry["restaurant"] is PieceDef):
		piece_registry["restaurant"] = PieceDefClass.create_restaurant()
	var piece_def_val = piece_registry.get("restaurant", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_restaurant()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	# UI 校验：用核心 PlacementValidator + 与动作一致的 ignore_cells 语义
	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var validate_r: Result = PlacementValidatorClass.validate_restaurant_placement(
		ctx,
		position,
		rotation,
		piece_registry,
		actor,
		state.phase == "Setup",
		extra
	)

	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	# 额外约束：与动作执行器一致的“回合/次数/数量”检查（避免只靠放置校验导致误导）
	# 这里用执行器 validate（包含员工/回合等规则），确保提示与真实执行一致
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		cmd_params["restaurant_id"] = restaurant_id
	var cmd := Command.create(action_id, actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor(action_id)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(_map_canvas) and _map_canvas.has_method("set_structure_preview"):
		_map_canvas.call("set_structure_preview", footprint_cells, valid)
	if is_instance_valid(restaurant_placement_overlay) and restaurant_placement_overlay.has_method("set_validation"):
		restaurant_placement_overlay.set_validation(valid, message)
