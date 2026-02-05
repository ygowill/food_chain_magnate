# MapCanvasIndexer structures scan must treat _cells indices as idx(world + map_origin).
# Otherwise, when map_origin shifts after expanding to the left/top, structure pieces will render offset.
class_name MapIndexerStructuresRespectsMapOriginTest
extends RefCounted

const MapCanvasIndexerClass = preload("res://ui/scenes/game/map_canvas_indexer.gd")

class FakeCanvas extends RefCounted:
	var _map_data: Dictionary = {}
	var _base_grid_size: Vector2i = Vector2i.ZERO
	var _cells: Array = []
	var _external_cells_by_pos: Dictionary = {}
	var _world_origin: Vector2i = Vector2i.ZERO

	var _marketing_by_pos: Dictionary = {}
	var _structures_by_anchor: Dictionary = {}

	func _init(map_data: Dictionary, base_grid_size: Vector2i, cells: Array) -> void:
		_map_data = map_data.duplicate(true)
		_base_grid_size = base_grid_size
		_cells = cells
		_external_cells_by_pos = {}
		_marketing_by_pos = {}
		_structures_by_anchor = {}

		var bounds := MapCanvasIndexerClass.compute_bounds(_base_grid_size, Vector2i(_map_data.get("map_origin", Vector2i.ZERO)), _external_cells_by_pos)
		_world_origin = bounds.get("min", Vector2i.ZERO)

	func _world_to_view(world_pos: Vector2i) -> Vector2i:
		return world_pos - _world_origin

static func run() -> Result:
	var base_grid_size := Vector2i(10, 10)
	var map_origin := Vector2i(5, 0) # simulate an extra tile added on the left (TILE_SIZE=5)
	var map_data := {"map_origin": map_origin, "grid_size": base_grid_size}

	var cells: Array = []
	for y in range(base_grid_size.y):
		var row: Array = []
		for x in range(base_grid_size.x):
			row.append({"structure": {}})
		cells.append(row)

	var anchor := Vector2i(0, 0)
	var world_pos := Vector2i(0, 0)
	var idx := world_pos + map_origin
	cells[idx.y][idx.x] = {
		"structure": {
			"piece_id": "restaurant",
			"owner": 0,
			"rotation": 0,
			"house_id": "",
			"parent_anchor": anchor,
		}
	}

	var canvas := FakeCanvas.new(map_data, base_grid_size, cells)
	MapCanvasIndexerClass.rebuild_overlay_indexes(canvas)

	if not canvas._structures_by_anchor.has(anchor):
		return Result.failure("expected anchor %s in _structures_by_anchor, got keys=%s" % [str(anchor), str(canvas._structures_by_anchor.keys())])

	var info_val = canvas._structures_by_anchor.get(anchor, null)
	if not (info_val is Dictionary):
		return Result.failure("expected info dictionary for anchor %s, got %s" % [str(anchor), typeof(info_val)])
	var info: Dictionary = info_val

	var expected_view := canvas._world_to_view(world_pos)
	var min_pos_val = info.get("min", null)
	if not (min_pos_val is Vector2i):
		return Result.failure("expected info.min Vector2i, got %s" % str(min_pos_val))
	var min_pos: Vector2i = min_pos_val
	if min_pos != expected_view:
		return Result.failure("expected structure cell view pos %s, got %s (map_origin=%s world_origin=%s)" % [str(expected_view), str(min_pos), str(map_origin), str(canvas._world_origin)])

	var cells_val = info.get("cells", null)
	if not (cells_val is Array):
		return Result.failure("expected info.cells Array, got %s" % str(cells_val))
	var view_cells: Array = cells_val
	if view_cells.is_empty() or not view_cells.has(expected_view):
		return Result.failure("expected info.cells to include %s, got %s" % [str(expected_view), str(view_cells)])

	return Result.success({})
