# Game scene：营销范围覆盖层
extends RefCounted

const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const OverlayUtils = preload("res://ui/scenes/game/overlay/utils.gd")

var _scene = null
var _map_canvas = null

# Compatibility alias (older code may still read this directly).
var marketing_range_overlay = null
var _calculator = null

# Placeholder colors for unified highlight mechanism (issue_tracker #27).
# If you want to tweak visuals later, start here.
const OVERLAY_ID := "marketing_range"
const RANGE_FILL_COLOR := Color(0.29, 0.58, 0.98, 0.18)
const RANGE_BORDER_COLOR := Color(0.29, 0.58, 0.98, 0.55)
const RANGE_BORDER_WIDTH := 2.0

func _init(scene, map_canvas) -> void:
	_scene = scene
	_map_canvas = map_canvas
	_calculator = MarketingRangeCalculatorClass.new()

func show_marketing_range_overlay(campaigns: Array[Dictionary]) -> void:
	var cells_set := {}
	var cells: Array[Vector2i] = []

	for c_val in campaigns:
		if not (c_val is Dictionary):
			continue
		var c: Dictionary = c_val

		# 兼容输入字段：position / world_pos
		var pos := Vector2i(-1, -1)
		var pos_val = c.get("position", null)
		if pos_val is Vector2i:
			pos = pos_val
		else:
			var wp = c.get("world_pos", null)
			if wp is Vector2i:
				pos = wp
		if pos == Vector2i(-1, -1):
			continue

		# 兼容输入字段：type / marketing_type
		var type_id := ""
		var type_val = c.get("type", null)
		if type_val is String:
			type_id = str(type_val)
		else:
			var mt = c.get("marketing_type", null)
			if mt is String:
				type_id = str(mt)
		type_id = type_id.strip_edges()
		if type_id.is_empty():
			continue

		# 若提供了 tiles（视为“需要覆盖的 world cells”），直接使用；否则按核心算法推导。
		var tiles_val = c.get("tiles", null)
		if tiles_val is Array and not (tiles_val as Array).is_empty():
			for t in (tiles_val as Array):
				if t is Vector2i:
					cells_set[t] = true
			continue

		var extra := {}
		if type_id == "airplane":
			var axis := str(c.get("axis", ""))
			if axis == "row" or axis == "col":
				extra["axis"] = axis

		var computed: Array[Vector2i] = _compute_preview_cells(pos, type_id, extra)
		for p in computed:
			cells_set[p] = true

	for k in cells_set.keys():
		if k is Vector2i:
			cells.append(k)

	_set_overlay_cells(cells)

func hide_marketing_range_overlay() -> void:
	_clear_overlay()

func preview_marketing_range(position: Vector2i, range_val: int, marketing_type: String, extra: Dictionary = {}) -> void:
	if marketing_type.is_empty():
		hide_marketing_range_overlay()
		return

	var cells: Array[Vector2i] = _compute_preview_cells(position, marketing_type, extra)
	_set_overlay_cells(cells)

func _compute_preview_cells(position: Vector2i, marketing_type: String, extra: Dictionary) -> Array[Vector2i]:
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

		inst["axis"] = axis
		# airplane range depends on its board footprint size (length 1/3/5, thickness=2).
		if extra != null:
			var fs_val = extra.get("footprint_size", null)
			if fs_val is Vector2i:
				inst["footprint_size"] = Vector2i(fs_val)
			elif fs_val is Array:
				var arr: Array = fs_val
				if arr.size() == 2:
					inst["footprint_size"] = [int(arr[0]), int(arr[1])]

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
		var cells: Array[Vector2i] = OverlayUtils.get_house_footprint_cells(state, house_id)
		for p2 in cells:
			if p2 is Vector2i:
				set[p2] = true

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

func _set_overlay_cells(cells: Array[Vector2i]) -> void:
	if not is_instance_valid(_map_canvas):
		return
	if not _map_canvas.has_method("set_piece_overlay"):
		return
	_map_canvas.call("set_piece_overlay", OVERLAY_ID, cells, {
		"fill": RANGE_FILL_COLOR,
		"border": RANGE_BORDER_COLOR,
		"border_width": RANGE_BORDER_WIDTH,
	})

func _clear_overlay() -> void:
	if not is_instance_valid(_map_canvas):
		return
	if _map_canvas.has_method("clear_piece_overlay"):
		_map_canvas.call("clear_piece_overlay", OVERLAY_ID)
