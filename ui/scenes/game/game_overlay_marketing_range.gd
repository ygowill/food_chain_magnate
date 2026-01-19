# Game scene：营销范围覆盖层
extends RefCounted

const MarketingRangeOverlayScene = preload("res://ui/overlays/marketing_range_overlay.tscn")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const OverlayUtils = preload("res://ui/scenes/game/game_overlay_utils.gd")

var _scene = null
var _map_canvas = null

var marketing_range_overlay = null
var _calculator = null

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_calculator = MarketingRangeCalculatorClass.new()

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
		_ensure_marketing_range_overlay()
		if not is_instance_valid(marketing_range_overlay):
			return

		if marketing_range_overlay.has_method("set_visual_modules"):
			var state2: GameState = null
			if _scene != null and (_scene.has_method("get") and _scene.get("game_engine") != null):
				var engine2 = _scene.get("game_engine")
				if engine2 != null and (engine2 is GameEngine):
					state2 = engine2.get_state()
			if state2 != null and (state2.modules is Array):
				marketing_range_overlay.set_visual_modules(Array(state2.modules, TYPE_STRING, "", null))

		var normalized: Array[Dictionary] = []
		for c_val in campaigns:
			if not (c_val is Dictionary):
				continue
			var c: Dictionary = (c_val as Dictionary).duplicate(true)

			# 兼容输入字段：position / world_pos
			if not c.has("position") or not (c["position"] is Vector2i):
				var wp = c.get("world_pos", null)
				if wp is Vector2i:
					c["position"] = wp
			if not c.has("position") or not (c["position"] is Vector2i):
				continue

			# 兼容输入字段：type / marketing_type
			if not c.has("type") or not (c["type"] is String):
				var mt = c.get("marketing_type", null)
				if mt is String:
					c["type"] = mt
			var type_id := str(c.get("type", ""))
			if type_id.is_empty():
				continue

			# 若未提供 tiles，则用核心算法推导（与预览保持一致）
			var tiles_val = c.get("tiles", null)
			if not (tiles_val is Array) or (tiles_val as Array).is_empty():
				var extra := {}
				if type_id == "airplane":
					var axis := str(c.get("axis", ""))
					if axis == "row" or axis == "col":
						extra["axis"] = axis
				var tiles: Array[Vector2i] = _compute_preview_tiles(Vector2i(c["position"]), type_id, extra)
				if not tiles.is_empty():
					c["tiles"] = tiles
					if not c.has("range"):
						c["range"] = 0

			normalized.append(c)

		if marketing_range_overlay.has_method("set_campaigns"):
			marketing_range_overlay.set_campaigns(normalized)

		marketing_range_overlay.visible = true

func hide_marketing_range_overlay() -> void:
	if is_instance_valid(marketing_range_overlay):
		marketing_range_overlay.visible = false
		if marketing_range_overlay.has_method("clear_all"):
			marketing_range_overlay.clear_all()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String, extra: Dictionary = {}) -> void:
	if marketing_type.is_empty():
		hide_marketing_range_overlay()
		return

	_ensure_marketing_range_overlay()
	if not is_instance_valid(marketing_range_overlay):
		return

	if marketing_range_overlay.has_method("set_visual_modules"):
		var state3: GameState = null
		if _scene != null and (_scene.has_method("get") and _scene.get("game_engine") != null):
			var engine3 = _scene.get("game_engine")
			if engine3 != null and (engine3 is GameEngine):
				state3 = engine3.get_state()
		if state3 != null and (state3.modules is Array):
			marketing_range_overlay.set_visual_modules(Array(state3.modules, TYPE_STRING, "", null))

	var tiles: Array[Vector2i] = _compute_preview_tiles(position, marketing_type, extra)

	if marketing_range_overlay.has_method("show_preview"):
		marketing_range_overlay.show_preview(position, range_val, marketing_type, tiles)

	marketing_range_overlay.visible = true

func _compute_preview_tiles(position: Vector2i, marketing_type: String, extra: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _scene == null:
		return out
	if not (_scene.has_method("get") and _scene.get("game_engine") != null):
		return out
	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return out
	var state: GameState = engine.get_state()
	if state == null:
		return out

	var inst := {
		"type": marketing_type,
		"world_pos": position,
	}

	if marketing_type == "airplane":
		var axis := ""
		if extra != null:
			var axis_val = extra.get("axis", null)
			if axis_val is String:
				axis = str(axis_val)
		if axis.is_empty():
			axis = _infer_airplane_axis(state, position)
		if axis != "row" and axis != "col":
			return out

		var tile_pos: Vector2i = MapUtils.world_to_tile(position).board_pos
		var tile_index := tile_pos.y if axis == "row" else tile_pos.x
		inst["axis"] = axis
		inst["tile_index"] = tile_index

	if _calculator == null:
		_calculator = MarketingRangeCalculatorClass.new()

	var r: Result = _calculator.get_affected_house_ids(state, inst)
	if not r.ok:
		return out
	var house_ids: Array = r.value

	var set := {}
	for hid_val in house_ids:
		if not (hid_val is String):
			continue
		var house_id: String = str(hid_val)
		if house_id.is_empty():
			continue
		var pos := OverlayUtils.get_house_anchor_world_pos(state, house_id)
		if pos == Vector2i(-1, -1):
			continue
		set[pos] = true

	for k in set.keys():
		if k is Vector2i:
			out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	return out

func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""

func _ensure_marketing_range_overlay() -> void:
	if _scene == null:
		return

	if marketing_range_overlay == null or not is_instance_valid(marketing_range_overlay):
		marketing_range_overlay = MarketingRangeOverlayScene.instantiate()

	var parent: Node = _map_canvas if is_instance_valid(_map_canvas) else _scene
	if is_instance_valid(marketing_range_overlay) and marketing_range_overlay.get_parent() != parent:
		var old_parent = marketing_range_overlay.get_parent()
		if old_parent != null:
			old_parent.remove_child(marketing_range_overlay)
		parent.add_child(marketing_range_overlay)

	_sync_marketing_range_overlay_transform()

func _sync_marketing_range_overlay_transform() -> void:
	if not is_instance_valid(marketing_range_overlay):
		return
	if not is_instance_valid(_map_canvas):
		return

	var cell_size := 40
	if _map_canvas.has_method("get_cell_size"):
		cell_size = int(_map_canvas.call("get_cell_size"))

	var world_origin := Vector2i.ZERO
	if _map_canvas.has_method("get_world_origin"):
		var wo = _map_canvas.call("get_world_origin")
		if wo is Vector2i:
			world_origin = wo

	if marketing_range_overlay.has_method("set_tile_size"):
		marketing_range_overlay.call("set_tile_size", Vector2(float(cell_size), float(cell_size)))
	if marketing_range_overlay.has_method("set_map_offset"):
		marketing_range_overlay.call("set_map_offset", Vector2(float(-world_origin.x * cell_size), float(-world_origin.y * cell_size)))
