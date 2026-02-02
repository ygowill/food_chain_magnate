# Game scene：地图交互控制器 - Placement 模式逻辑下沉
# 负责：餐厅/房屋/piece 的高亮扫描与 footprint 预览校验。
class_name GameMapInteractionPlacementMode
extends RefCounted

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _controller = null

func _init(controller) -> void:
	_controller = controller

func on_restaurant_preview_cleared() -> void:
	if _controller == null:
		return
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
		_controller._map_canvas.call("clear_structure_preview")
	if is_instance_valid(_controller.restaurant_placement_overlay) and _controller.restaurant_placement_overlay.has_method("set_validation"):
		_controller.restaurant_placement_overlay.set_validation(true, "")

func on_restaurant_highlight_requested(mode: String, rotation: int, restaurant_id: String) -> void:
	if _controller == null:
		return
	if _controller._mode != "restaurant_placement":
		return
	if not (is_instance_valid(_controller.restaurant_placement_overlay) and _controller.restaurant_placement_overlay.visible):
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var action_id := "place_restaurant" if mode != "move_restaurant" else "move_restaurant"

	# move_restaurant：未选择餐厅前不高亮
	if action_id == "move_restaurant" and restaurant_id.is_empty():
		_controller._restaurant_valid_anchors.clear()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
			_controller._map_canvas.call("clear_move_restaurant_selected_restaurant")
		return

	# 非 move_restaurant：确保清理“被移动餐厅”的高亮
	if action_id != "move_restaurant":
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_move_restaurant_selected_restaurant"):
			_controller._map_canvas.call("clear_move_restaurant_selected_restaurant")
	else:
		# move_restaurant：高亮当前选中餐厅（入口 anchor）
		var anchor_world := Vector2i(-1, -1)
		if not restaurant_id.is_empty() and (state.map is Dictionary) and state.map.has("restaurants") and (state.map["restaurants"] is Dictionary):
			var rests: Dictionary = state.map["restaurants"]
			if rests.has(restaurant_id):
				var rest_val = rests[restaurant_id]
				if rest_val is Dictionary:
					var rest: Dictionary = rest_val
					var ep_val = rest.get("entrance_pos", null)
					if ep_val is Vector2i:
						anchor_world = Vector2i(ep_val)
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_move_restaurant_selected_restaurant"):
			_controller._map_canvas.call("set_move_restaurant_selected_restaurant", anchor_world)

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
			var r: Result = RestaurantPlacementClass.validate_restaurant_placement(
				ctx,
				world_anchor,
				rotation,
				piece_registry,
				actor,
				state.phase == DefsClass.PHASE_SETUP,
				extra
			)
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_controller._restaurant_valid_anchors = anchor_set
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", anchors)

func on_house_highlight_requested(action_id: String, rotation: int) -> void:
	if _controller == null:
		return
	if _controller._mode != "house_placement":
		return
	if not (is_instance_valid(_controller.house_placement_overlay) and _controller.house_placement_overlay.visible):
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return
	if action_id != "place_house":
		_controller._house_valid_anchors.clear()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
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
	if not piece_registry.has("house_with_garden") or not (piece_registry["house_with_garden"] is PieceDef):
		piece_registry["house_with_garden"] = PieceDefClass.create_house_with_garden()

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": map_origin,
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var r: Result = PlacementClass.validate_placement(ctx, "house_with_garden", world_anchor, rotation, piece_registry, {})
			if not r.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_controller._house_valid_anchors = anchor_set
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", anchors)

func on_house_preview_cleared() -> void:
	if _controller == null:
		return
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
		_controller._map_canvas.call("clear_structure_preview")

func on_restaurant_preview_requested(mode: String, position: Vector2i, rotation: int, restaurant_id: String) -> void:
	if _controller == null:
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
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
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var extra := {}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		if state.map.restaurants.has(restaurant_id):
			var rest: Dictionary = state.map.restaurants[restaurant_id]
			if rest.has("cells") and (rest["cells"] is Array):
				extra["ignore_structure_cells"] = rest["cells"]

	var validate_r: Result = RestaurantPlacementClass.validate_restaurant_placement(
		ctx,
		position,
		rotation,
		piece_registry,
		actor,
		state.phase == DefsClass.PHASE_SETUP,
		extra
	)

	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	# 额外约束：与动作执行器一致的“回合/次数/数量”检查（避免只靠放置校验导致误导）
	# 这里用执行器 validate（包含员工/回合等规则），确保提示与真实执行一致
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation}
	if action_id == "move_restaurant" and not restaurant_id.is_empty():
		cmd_params["restaurant_id"] = restaurant_id
	if is_instance_valid(_controller.restaurant_placement_overlay) and _controller.restaurant_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(_controller.restaurant_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			cmd_params["employee_type"] = employee_type
	var cmd := Command.create(action_id, actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor(action_id)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_structure_preview"):
		_controller._map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": "restaurant",
			"anchor": position,
			"rotation": rotation,
			"owner": actor,
		})
	if is_instance_valid(_controller.restaurant_placement_overlay) and _controller.restaurant_placement_overlay.has_method("set_validation"):
		_controller.restaurant_placement_overlay.set_validation(valid, message)

func on_house_preview_requested(action_id: String, position: Vector2i, rotation: int) -> void:
	if _controller == null:
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()

	var piece_registry: Dictionary = engine.game_data.pieces if engine.game_data != null else {}
	if not piece_registry.has("house_with_garden") or not (piece_registry["house_with_garden"] is PieceDef):
		piece_registry["house_with_garden"] = PieceDefClass.create_house_with_garden()
	var piece_def_val = piece_registry.get("house_with_garden", null)
	var piece_def: PieceDef = piece_def_val if piece_def_val is PieceDef else PieceDefClass.create_house_with_garden()
	var footprint_cells: Array[Vector2i] = piece_def.get_world_cells(position, rotation)

	var ctx := {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": state.map.get("map_origin", Vector2i.ZERO),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
		"marketing_placements": state.map.get("marketing_placements", {}),
	}

	var validate_r: Result = PlacementClass.validate_placement(ctx, "house_with_garden", position, rotation, piece_registry, {})
	var valid := validate_r.ok
	var message := "" if valid else validate_r.error

	var house_number := -1
	if is_instance_valid(_controller.house_placement_overlay) and _controller.house_placement_overlay.has_method("get_selected_house_number"):
		house_number = int(_controller.house_placement_overlay.get_selected_house_number())
	var cmd_params := {"position": [position.x, position.y], "rotation": rotation, "house_number": house_number}
	if is_instance_valid(_controller.house_placement_overlay) and _controller.house_placement_overlay.has_method("get_selected_employee"):
		var employee_type := str(_controller.house_placement_overlay.get_selected_employee()).strip_edges()
		if not employee_type.is_empty():
			cmd_params["employee_type"] = employee_type
	var cmd := Command.create("place_house", actor, cmd_params)
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor("place_house")
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error

	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_structure_preview"):
		_controller._map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": "house_with_garden",
			"anchor": position,
			"rotation": rotation,
		})

	# HousePlacementOverlay 目前没有 validation UI（只做预览与确认）

func on_piece_highlight_requested(action_id: String, rotation: int, piece_id: String) -> void:
	if _controller == null:
		return
	if _controller._mode != "piece_placement":
		return
	if not (is_instance_valid(_controller.piece_placement_overlay) and _controller.piece_placement_overlay.visible):
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var aid := str(action_id).strip_edges()
	var pid := str(piece_id).strip_edges()
	if aid.is_empty() or pid.is_empty():
		_controller._piece_valid_anchors.clear()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
		return

	if not (state.map is Dictionary):
		return
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return
	var grid_size: Vector2i = state.map["grid_size"]
	var map_origin: Vector2i = state.map.get("map_origin", Vector2i.ZERO)

	var actor: int = state.get_current_player_id()
	var executor = engine.get_action_registry().get_executor(aid)
	if executor == null:
		_controller._piece_valid_anchors.clear()
		if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_cell_highlights"):
			_controller._map_canvas.call("clear_cell_highlights")
		return

	var anchors: Array[Vector2i] = []
	var anchor_set := {}
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var world_anchor: Vector2i = Vector2i(x, y) - map_origin
			var cmd := Command.create(aid, actor, {
				"piece_id": pid,
				"anchor_pos": [world_anchor.x, world_anchor.y],
				"rotation": int(rotation),
			})
			cmd.phase = state.phase
			cmd.sub_phase = state.sub_phase
			var vr: Result = executor.validate(state, cmd)
			if not vr.ok:
				continue
			if anchor_set.has(world_anchor):
				continue
			anchor_set[world_anchor] = true
			anchors.append(world_anchor)

	_controller._piece_valid_anchors = anchor_set
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_cell_highlights"):
		_controller._map_canvas.call("set_cell_highlights", anchors)

func on_piece_preview_cleared() -> void:
	if _controller == null:
		return
	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("clear_structure_preview"):
		_controller._map_canvas.call("clear_structure_preview")
	if is_instance_valid(_controller.piece_placement_overlay) and _controller.piece_placement_overlay.has_method("set_validation"):
		_controller.piece_placement_overlay.set_validation(true, "")

func on_piece_preview_requested(action_id: String, position: Vector2i, rotation: int, piece_id: String) -> void:
	if _controller == null:
		return
	if _controller._scene == null:
		return
	var engine = _controller._scene.game_engine
	if engine == null:
		return
	var state = engine.get_state()
	if state == null:
		return

	var actor: int = state.get_current_player_id()
	var aid := str(action_id).strip_edges()
	var pid := str(piece_id).strip_edges()

	var footprint_cells: Array[Vector2i] = []
	var valid := true
	var message := ""

	if pid.is_empty():
		valid = false
		message = "piece_id 为空"
	elif not PieceRegistryClass.is_loaded():
		valid = false
		message = "PieceRegistry 未初始化"
	else:
		var piece_def_val = PieceRegistryClass.get_def(pid)
		if piece_def_val == null or not (piece_def_val is PieceDef):
			valid = false
			message = "未加载的 piece: %s" % pid
		else:
			var piece_def: PieceDef = piece_def_val
			footprint_cells = piece_def.get_world_cells(position, rotation)

	var cmd := Command.create(aid, actor, {
		"piece_id": pid,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	})
	cmd.phase = state.phase
	cmd.sub_phase = state.sub_phase
	var executor = engine.get_action_registry().get_executor(aid)
	if executor != null:
		var ex_r: Result = executor.validate(state, cmd)
		if not ex_r.ok:
			valid = false
			message = ex_r.error
	else:
		valid = false
		if message.is_empty():
			message = "无法找到执行器: %s" % aid

	if is_instance_valid(_controller._map_canvas) and _controller._map_canvas.has_method("set_structure_preview"):
		_controller._map_canvas.call("set_structure_preview", footprint_cells, valid, {
			"piece_id": pid,
			"anchor": position,
			"rotation": int(rotation),
			"owner": actor,
		})
	if is_instance_valid(_controller.piece_placement_overlay) and _controller.piece_placement_overlay.has_method("set_validation"):
		_controller.piece_placement_overlay.set_validation(valid, message)
