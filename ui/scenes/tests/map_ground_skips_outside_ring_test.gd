# Map ground fill should not paint the UI-only outside ring nor real external_cells.
# Covers issue_tracker #40 ("外圈无背景" including external_cells like offramp).
class_name MapGroundSkipsOutsideRingTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const MapCanvasIndexerClass = preload("res://ui/scenes/game/map_canvas_indexer.gd")

class FakeSkin extends RefCounted:
	func get_blocked_overlay_texture() -> Texture2D:
		return null

class FakeCanvas extends RefCounted:
	var _grid_size: Vector2i = Vector2i.ZERO
	var _world_origin: Vector2i = Vector2i.ZERO
	var _base_grid_size: Vector2i = Vector2i.ZERO
	var _map_data: Dictionary = {}
	var _cells: Array = []
	var _external_cells_by_pos: Dictionary = {}
	var _skin = null

	var ground_world_cells: Array[Vector2i] = []

	func _init(map_data: Dictionary, base_grid_size: Vector2i, cells: Array, external_cells: Dictionary) -> void:
		_map_data = map_data.duplicate(true)
		_base_grid_size = base_grid_size
		_cells = cells
		_external_cells_by_pos = external_cells.duplicate(true)
		_skin = FakeSkin.new()

		var bounds := MapCanvasIndexerClass.compute_bounds(_base_grid_size, Vector2i(_map_data.get("map_origin", Vector2i.ZERO)), _external_cells_by_pos)
		_world_origin = bounds.get("min", Vector2i.ZERO)
		_grid_size = bounds.get("size", _base_grid_size)

	func _get_cell_world(world_pos: Vector2i) -> Dictionary:
		var map_origin: Vector2i = _map_data.get("map_origin", Vector2i.ZERO)
		var idx := world_pos + map_origin
		if _base_grid_size != Vector2i.ZERO and idx.x >= 0 and idx.x < _base_grid_size.x and idx.y >= 0 and idx.y < _base_grid_size.y:
			var row_val = _cells[idx.y]
			if not (row_val is Array):
				return {}
			var row: Array = row_val
			var cell_val = row[idx.x]
			return cell_val if cell_val is Dictionary else {}
		if _external_cells_by_pos.has(world_pos):
			var c = _external_cells_by_pos[world_pos]
			return c if c is Dictionary else {}
		return {}

	func draw_rect(rect: Rect2, color: Color, filled: bool = true, _width: float = -1.0) -> void:
		if not filled:
			return
		# Ground fill uses solid color; only record those.
		if not color.is_equal_approx(Color("#faf4da")):
			return
		var cell_size := rect.size.x
		var vx := int(round(rect.position.x / cell_size))
		var vy := int(round(rect.position.y / cell_size))
		ground_world_cells.append(_world_origin + Vector2i(vx, vy))

	func draw_texture_rect(_texture: Texture2D, _rect: Rect2, _tile: bool, _modulate: Color = Color(1, 1, 1, 1)) -> void:
		pass

static func run() -> Result:
	var base_grid_size := Vector2i(4, 4)
	var map_origin := Vector2i(1, 1) # ensure world coords are not 0-based
	var map_data := {"map_origin": map_origin, "grid_size": base_grid_size}

	var cells: Array = []
	for y in range(base_grid_size.y):
		var row: Array = []
		for x in range(base_grid_size.x):
			row.append({"blocked": false})
		cells.append(row)

	# One real external cell outside base grid (should be visible but must not be ground-filled).
	var base_min := -map_origin
	var external_cells := {
		base_min + Vector2i(-3, 0): {"blocked": false},
	}

	var canvas := FakeCanvas.new(map_data, base_grid_size, cells, external_cells)
	MapCanvasDrawerClass._draw_ground_and_blocked(canvas, 10)

	var expected_count := base_grid_size.x * base_grid_size.y
	if canvas.ground_world_cells.size() != expected_count:
		return Result.failure("expected %d ground cells, got %d" % [expected_count, canvas.ground_world_cells.size()])

	var base_max := Vector2i(base_grid_size.x - map_origin.x - 1, base_grid_size.y - map_origin.y - 1)
	for wp in canvas.ground_world_cells:
		if not (wp is Vector2i):
			continue
		var p: Vector2i = wp
		if p.x < base_min.x or p.x > base_max.x or p.y < base_min.y or p.y > base_max.y:
			return Result.failure("ground should not be painted outside base map; got painted at %s" % str(p))

	return Result.success({})
