# MapCanvasDrawer：地面/阻塞格绘制下沉
extends RefCounted

static func draw_ground_and_blocked(canvas, cell_size: int) -> void:
	var blocked_tex: Texture2D = canvas._skin.get_blocked_overlay_texture()
	var ground_col := Color("#faf4da")
	# Only paint ground for the base map cells that are already part of a placed tile.
	# external_cells and the UI-only outside ring (used by airplane marketing) must stay transparent (issue_tracker #40).
	# Also skip "void" cells created by ensure_world_rect; these are empty expansion space that may become valid later.
	var map_origin: Vector2i = canvas._map_data.get("map_origin", Vector2i.ZERO)
	var base_grid_size: Vector2i = canvas._base_grid_size
	if base_grid_size == Vector2i.ZERO:
		var gs_val = canvas._map_data.get("grid_size", null)
		if gs_val is Vector2i:
			base_grid_size = gs_val
	var base_min := -map_origin
	var base_max := Vector2i(base_grid_size.x - map_origin.x - 1, base_grid_size.y - map_origin.y - 1)

	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			var world_pos: Vector2i = canvas._world_origin + Vector2i(x, y)
			var cell: Dictionary = canvas._get_cell_world(world_pos)
			var tile_origin_val = cell.get("tile_origin", null)
			var is_void := tile_origin_val is Vector2i and (tile_origin_val as Vector2i) == Vector2i(-1, -1)

			if (not is_void) and world_pos.x >= base_min.x and world_pos.x <= base_max.x and world_pos.y >= base_min.y and world_pos.y <= base_max.y:
				canvas.draw_rect(rect, ground_col, true)

			if bool(cell.get("blocked", false)) and not is_void:
				canvas.draw_texture_rect(blocked_tex, rect, false, Color(1, 1, 1, 0.85))
