# Blocked overlay (red-X) should not be painted for "void" cells created by map expansion.
# Those cells have tile_origin == (-1,-1) and are meant to be empty/available for future placement.
class_name MapBlockedOverlaySkipsVoidCellsTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")
const MapCanvasIndexerClass = preload("res://ui/scenes/game/map/indexer.gd")

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

	var blocked_world_cells: Array[Vector2i] = []

	func _init(map_data: Dictionary, base_grid_size: Vector2i, cells: Array) -> void:
		_map_data = map_data.duplicate(true)
		_base_grid_size = base_grid_size
		_cells = cells
		_external_cells_by_pos = {}
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
		return {}

	func draw_rect(_rect: Rect2, _color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		pass

	func draw_texture_rect(_texture: Texture2D, rect: Rect2, _tile: bool, _modulate: Color = Color(1, 1, 1, 1)) -> void:
		var cell_size := rect.size.x
		var vx := int(round(rect.position.x / cell_size))
		var vy := int(round(rect.position.y / cell_size))
		blocked_world_cells.append(_world_origin + Vector2i(vx, vy))

static func run() -> Result:
	var base_grid_size := Vector2i(3, 3)
	var map_origin := Vector2i(0, 0)
	var map_data := {"map_origin": map_origin, "grid_size": base_grid_size}

	var cells: Array = []
	for y in range(base_grid_size.y):
		var row: Array = []
		for x in range(base_grid_size.x):
			row.append({"blocked": false, "tile_origin": Vector2i(0, 0)})
		cells.append(row)

	# One real blocked cell and one "void" blocked cell.
	cells[0][0] = {"blocked": true, "tile_origin": Vector2i(0, 0)}
	cells[0][1] = {"blocked": true, "tile_origin": Vector2i(-1, -1)}

	var canvas := FakeCanvas.new(map_data, base_grid_size, cells)
	MapCanvasDrawerClass._draw_ground_and_blocked(canvas, 10)

	if canvas.blocked_world_cells.size() != 1:
		return Result.failure("expected 1 blocked overlay draw, got %d (%s)" % [canvas.blocked_world_cells.size(), str(canvas.blocked_world_cells)])
	if canvas.blocked_world_cells[0] != Vector2i(0, 0):
		return Result.failure("expected blocked overlay at (0,0), got %s" % str(canvas.blocked_world_cells[0]))

	return Result.success({})

