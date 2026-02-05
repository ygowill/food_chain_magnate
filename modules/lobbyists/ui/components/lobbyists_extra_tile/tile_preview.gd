class_name TilePreview
extends "res://ui/scenes/game/map_canvas.gd"

const CellsClass = preload("res://core/map/map_baker/cells.gd")
const TileBakingClass = preload("res://core/map/map_baker/tile_baking.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PieceRegistryClass = preload("res://core/map/piece_registry.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")

var tile_id: String = ""
var tile_rotation: int = 0 # 0/90/180/270
var _base_minimum_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Preview-only: disable hover/selection and keep rendering clipped inside the node rect.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_base_minimum_size = custom_minimum_size
	# NOTE: clip_contents only clips children; MapCanvas draws in _draw().
	# Use CanvasItem clip mode so tile preview won't bleed into neighboring UI cells.
	if has_method("set_clip_children_mode"):
		set_clip_children_mode(CanvasItem.CLIP_CHILDREN_AND_DRAW)

	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)

	_refresh_preview()
	# Ensure we also fit after layout has settled (some parents size after children enter the tree).
	call_deferred("_update_zoom_to_fit")

func set_tile(id_str: String, rot: int) -> void:
	tile_id = str(id_str).strip_edges()
	tile_rotation = _normalize_rotation(rot)
	_refresh_preview()

func set_zoom(zoom: float) -> void:
	super.set_zoom(zoom)
	# TilePreview is embedded in UI controls; MapCanvas.set_zoom() updates custom_minimum_size based
	# on map bounds, which can force the preview to expand beyond its parent and overlap neighbors.
	# Restore the node's original minimum size defined by the UI layout (or 0 for code-created previews).
	if custom_minimum_size != _base_minimum_size:
		custom_minimum_size = _base_minimum_size
		minimum_size_changed()

func _on_resized() -> void:
	_update_zoom_to_fit()

func _normalize_rotation(rot: int) -> int:
	var r := int(rot) % 360
	if r < 0:
		r += 360
	if r != 0 and r != 90 and r != 180 and r != 270:
		r = 0
	return r

func _refresh_preview() -> void:
	if tile_id.is_empty():
		clear()
		return
	if not TileRegistryClass.is_loaded() or not PieceRegistryClass.is_loaded():
		clear()
		return

	var def_val = TileRegistryClass.get_def(tile_id)
	if def_val == null or not (def_val is TileDef):
		clear()
		return
	var tile_def: TileDef = def_val
	if tile_def.has_method("ensure_road_grid"):
		tile_def.ensure_road_grid()

	var mods: Array[String] = []
	if Globals != null and Globals.enabled_modules_v2 is Array:
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)

	_ensure_skin(mods)

	var tile_size := int(MapUtilsClass.TILE_SIZE)
	var grid_size := Vector2i(tile_size, tile_size)
	var cells := CellsClass.create_empty_cells(grid_size)

	var houses: Dictionary = {}
	var drink_sources: Array = []
	var piece_registry: Dictionary = PieceRegistryClass.get_all_defs()

	# Apply zoom before set_map_data() so MapCanvas doesn't temporarily expand to 5*BASE_CELL_SIZE.
	_update_zoom_to_fit()

	var baked: Result = TileBakingClass.bake_tile_into_cells(
		cells,
		grid_size,
		Vector2i.ZERO,
		tile_def,
		Vector2i.ZERO,
		tile_rotation,
		piece_registry,
		houses,
		drink_sources
	)
	if not baked.ok:
		push_error("TilePreview: bake_tile_into_cells failed: %s" % str(baked.error))
		clear()
		return

	var map_data := {
		"grid_size": grid_size,
		"cells": cells,
		"map_origin": Vector2i.ZERO,
		"external_cells": {},
		"tile_placements": [{
			"tile_id": tile_id,
			"board_pos": Vector2i.ZERO,
			"rotation": tile_rotation,
		}],
		"external_tile_placements": [],
		"houses": houses,
		"restaurants": {},
		"marketing_placements": {},
		"drink_sources": drink_sources,
	}
	set_map_data(map_data)

	_update_zoom_to_fit()

func _update_zoom_to_fit() -> void:
	var avail := size
	if avail.x <= 4.0 or avail.y <= 4.0:
		avail = custom_minimum_size
	if avail.x <= 4.0 or avail.y <= 4.0:
		return
	var tile_size := float(int(MapUtilsClass.TILE_SIZE))
	if tile_size <= 0.0:
		return
	var cell_px: float = floor(minf(avail.x, avail.y) / tile_size)
	cell_px = maxf(2.0, cell_px)
	var z := float(cell_px) / float(BASE_CELL_SIZE)
	set_zoom(z)
