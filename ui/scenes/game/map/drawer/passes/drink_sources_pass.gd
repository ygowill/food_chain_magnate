# MapCanvasDrawer：饮料来源绘制下沉
extends RefCounted

const TextureUtilsClass = preload("res://ui/scenes/game/map/drawer/texture_utils.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")

static var _drink_source_textures: Dictionary = {} # product_id -> Texture2D
static var _drink_source_textures_base_dir: String = ""

static func clear_drink_source_texture_cache() -> void:
	_drink_source_textures.clear()
	_drink_source_textures_base_dir = ""

static func draw_drink_sources(canvas, cell_size: int) -> void:
	for y in range(canvas._grid_size.y):
		for x in range(canvas._grid_size.x):
			var world_pos = canvas._world_origin + Vector2i(x, y)
			var cell: Dictionary = canvas._get_cell_world(world_pos)
			var drink_val = cell.get("drink_source", null)
			if not (drink_val is Dictionary):
				continue
			var drink: Dictionary = drink_val
			if drink.is_empty():
				continue
			var product_id: String = str(drink.get("type", ""))
			if product_id.is_empty():
				continue
			var override_tex: Texture2D = _get_drink_source_texture(product_id)
			var tex: Texture2D = override_tex if (override_tex is Texture2D) else canvas._skin.get_product_icon_texture(product_id)

			var rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			TextureUtilsClass.draw_texture_aspect_fill(canvas, tex, rect, Color(1, 1, 1, 0.95))

static func _get_drink_source_texture(product_id: String) -> Texture2D:
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"
	if pid.is_empty():
		return null

	var base_dir := str(ModulesBaseDirClass.get_base_dir()).strip_edges()
	if base_dir != _drink_source_textures_base_dir:
		_drink_source_textures_base_dir = base_dir
		_drink_source_textures.clear()

	var cached_val = _drink_source_textures.get(pid, null)
	if cached_val is Texture2D:
		return cached_val
	if _drink_source_textures.has(pid):
		return null

	var path := base_dir.path_join("base_products").path_join("assets").path_join("map").path_join("drink_sources").path_join("%s.png" % pid)
	var tex := _load_texture_from_path(path)
	_drink_source_textures[pid] = tex
	return tex

static func _load_texture_from_path(path: String) -> Texture2D:
	var p := str(path).strip_edges()
	if p.is_empty():
		return null

	# Enforce packaged resources only.
	if not p.begins_with("res://"):
		return null
	var res = load(p)
	if res is Texture2D:
		return res
	return null

