# 地图定义
# 定义整张地图的板块布局和配置
class_name MapDef
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")

# === 基础信息 ===
var id: String = ""
var display_name: String = ""

# === 地图尺寸 (以板块为单位) ===
# 例如 3x3 表示 3x3 个板块，世界格子数为 15x15
var grid_size: Vector2i = Vector2i(3, 3)

# === 板块布局 ===
# 每个板块: { "tile_id": "a1", "board_pos": Vector2i(0, 0), "rotation": 0 }
var tiles: Array[Dictionary] = []

# === 玩家数量限制 ===
var min_players: int = 2
var max_players: int = 5

# === 随机生成配置 (可选) ===
var random_tile_pool: Array[String] = []
var random_rotation: bool = true
var random_seed: int = 0

# === 工厂方法 ===

static func create_empty(map_id: String, size: Vector2i) -> MapDef:
	var map_def := MapDef.new()
	map_def.id = map_id
	map_def.display_name = map_id
	map_def.grid_size = size
	return map_def

# 创建固定布局的地图
static func create_fixed(map_id: String, tile_placements: Array[Dictionary]) -> MapDef:
	var map_def := MapDef.new()
	map_def.id = map_id
	map_def.display_name = map_id

	# 计算网格大小
	var max_x := 0
	var max_y := 0
	for placement in tile_placements:
		var board_pos = placement.get("board_pos")
		if board_pos is Vector2i:
			max_x = max(max_x, board_pos.x)
			max_y = max(max_y, board_pos.y)
		elif board_pos is Array and board_pos.size() >= 2:
			max_x = max(max_x, board_pos[0])
			max_y = max(max_y, board_pos[1])

	map_def.grid_size = Vector2i(max_x + 1, max_y + 1)
	map_def.tiles = tile_placements

	return map_def

# === 序列化 ===

func to_dict() -> Dictionary:
	var tiles_arr := []
	for tile in tiles:
		var tile_dict := tile.duplicate()
		if tile.has("board_pos") and tile.board_pos is Vector2i:
			tile_dict["board_pos"] = [tile.board_pos.x, tile.board_pos.y]
		tiles_arr.append(tile_dict)

	return {
		"id": id,
		"display_name": display_name,
		"grid_size": [grid_size.x, grid_size.y],
		"tiles": tiles_arr,
		"min_players": min_players,
		"max_players": max_players,
		"random_tile_pool": random_tile_pool,
		"random_rotation": random_rotation,
		"random_seed": random_seed
	}

static func from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("MapDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"grid_size",
		"tiles",
		"min_players",
		"max_players",
		"random_tile_pool",
		"random_rotation",
		"random_seed",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("MapDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).is_empty():
		return Result.failure("MapDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).is_empty():
		return Result.failure("MapDef.display_name 类型错误或为空（期望非空 String）")

	var grid_size_read := _parse_vec2i(data.get("grid_size", null), "MapDef.grid_size")
	if not grid_size_read.ok:
		return grid_size_read
	var gs: Vector2i = grid_size_read.value
	if gs.x <= 0 or gs.y <= 0:
		return Result.failure("MapDef.grid_size 无效: %s" % str(gs))

	var min_players_read := _parse_non_negative_int(data.get("min_players", null), "MapDef.min_players")
	if not min_players_read.ok:
		return min_players_read
	var max_players_read := _parse_non_negative_int(data.get("max_players", null), "MapDef.max_players")
	if not max_players_read.ok:
		return max_players_read

	var random_tile_pool_read := _parse_string_array(data.get("random_tile_pool", null), "MapDef.random_tile_pool", false)
	if not random_tile_pool_read.ok:
		return random_tile_pool_read

	var random_rotation_val = data.get("random_rotation", null)
	if not (random_rotation_val is bool):
		return Result.failure("MapDef.random_rotation 类型错误（期望 bool）")

	var random_seed_read := _parse_non_negative_int(data.get("random_seed", null), "MapDef.random_seed")
	if not random_seed_read.ok:
		return random_seed_read

	var tiles_val = data.get("tiles", null)
	var tiles_read := _parse_tiles(tiles_val, "MapDef.tiles")
	if not tiles_read.ok:
		return tiles_read

	var map_def := MapDef.new()
	map_def.id = str(id_val)
	map_def.display_name = str(display_name_val)
	map_def.grid_size = gs
	map_def.min_players = int(min_players_read.value)
	map_def.max_players = int(max_players_read.value)
	map_def.random_tile_pool = random_tile_pool_read.value
	map_def.random_rotation = bool(random_rotation_val)
	map_def.random_seed = int(random_seed_read.value)
	map_def.tiles = tiles_read.value

	return Result.success(map_def)

static func from_json(json_string: String) -> Result:
	var data = JSON.parse_string(json_string)
	if data == null or not (data is Dictionary):
		return Result.failure("MapDef JSON 解析失败")
	return from_dict(data)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 MapDef: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

# === 严格解析辅助 ===

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_non_negative_int(value, path: String) -> Result:
	var r := _parse_int(value, path)
	if not r.ok:
		return r
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func _parse_vec2i(value, path: String) -> Result:
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_read := _parse_int(value[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := _parse_int(value[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

static func _parse_string_array(value, path: String, require_non_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		var s := str(item)
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空字符串" % [path, i])
		out.append(s)
	if require_non_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func _parse_tiles(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[Dictionary]）" % path)
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var tile: Dictionary = item
		for k in ["tile_id", "board_pos", "rotation"]:
			if not tile.has(k):
				return Result.failure("%s[%d] 缺少字段: %s" % [path, i, k])
		var tile_id_val = tile.get("tile_id", null)
		if not (tile_id_val is String) or str(tile_id_val).is_empty():
			return Result.failure("%s[%d].tile_id 类型错误或为空（期望非空 String）" % [path, i])
		var board_pos_read := _parse_vec2i(tile.get("board_pos", null), "%s[%d].board_pos" % [path, i])
		if not board_pos_read.ok:
			return board_pos_read
		var rotation_read := _parse_int(tile.get("rotation", null), "%s[%d].rotation" % [path, i])
		if not rotation_read.ok:
			return rotation_read
		out.append({
			"tile_id": str(tile_id_val),
			"board_pos": board_pos_read.value,
			"rotation": int(rotation_read.value),
		})
	return Result.success(out)

# === 编辑方法 ===

# 添加板块
func add_tile(tile_id: String, board_pos: Vector2i, rotation: int = 0) -> void:
	tiles.append({
		"tile_id": tile_id,
		"board_pos": board_pos,
		"rotation": rotation
	})
	# 更新网格大小
	grid_size.x = max(grid_size.x, board_pos.x + 1)
	grid_size.y = max(grid_size.y, board_pos.y + 1)

# 移除指定位置的板块
func remove_tile_at(board_pos: Vector2i) -> bool:
	for i in range(tiles.size() - 1, -1, -1):
		var tile := tiles[i]
		if tile.board_pos == board_pos:
			tiles.remove_at(i)
			return true
	return false

# 获取指定位置的板块配置
func get_tile_at(board_pos: Vector2i) -> Dictionary:
	for tile in tiles:
		if tile.board_pos == board_pos:
			return tile
	return {}

# === 查询方法 ===

# 获取世界坐标的格子大小
func get_world_size() -> Vector2i:
	return grid_size * TileDef.TILE_SIZE

# 检查板块位置是否有效
func is_valid_board_pos(board_pos: Vector2i) -> bool:
	return board_pos.x >= 0 and board_pos.x < grid_size.x and \
		   board_pos.y >= 0 and board_pos.y < grid_size.y

# 检查是否所有板块位置都已填充
func is_fully_populated() -> bool:
	var expected := grid_size.x * grid_size.y
	return tiles.size() >= expected

# 获取未填充的板块位置
func get_empty_positions() -> Array[Vector2i]:
	var filled := {}
	for tile in tiles:
		filled[tile.board_pos] = true

	var empty: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			var pos := Vector2i(x, y)
			if not filled.has(pos):
				empty.append(pos)
	return empty

# === 随机生成 ===

# 使用随机池填充空位
func randomize_tiles(rng: RandomNumberGenerator) -> void:
	if random_tile_pool.is_empty():
		return

	var empty_positions := get_empty_positions()
	for pos in empty_positions:
		var tile_idx := rng.randi() % random_tile_pool.size()
		var tile_id := random_tile_pool[tile_idx]
		var rotation := 0
		if random_rotation:
			rotation = MapUtilsClass.VALID_ROTATIONS[rng.randi() % MapUtilsClass.VALID_ROTATIONS.size()]
		add_tile(tile_id, pos, rotation)

# === 验证 ===

func validate() -> Result:
	if id.is_empty():
		return Result.failure("地图缺少 ID")

	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("地图尺寸无效: %s" % str(grid_size))

	# 检查板块位置有效性
	for tile in tiles:
		var board_pos = tile.get("board_pos")
		if board_pos == null:
			return Result.failure("板块缺少位置")
		if not is_valid_board_pos(board_pos):
			return Result.failure("板块位置超出范围: %s" % str(board_pos))

		var tile_id: String = tile.get("tile_id", "")
		if tile_id.is_empty():
			return Result.failure("板块缺少 tile_id")

		var rotation: int = tile.get("rotation", 0)
		if rotation not in MapUtilsClass.VALID_ROTATIONS:
			return Result.failure("无效的旋转角度: %d" % rotation)

	# 检查是否有重叠
	var positions := {}
	for tile in tiles:
		var pos = tile.board_pos
		if positions.has(pos):
			return Result.failure("板块位置重叠: %s" % str(pos))
		positions[pos] = true

	return Result.success()

# === 调试 ===

func dump() -> String:
	var output := "=== MapDef: %s ===\n" % id
	output += "Grid size: %dx%d tiles (%dx%d cells)\n" % [
		grid_size.x, grid_size.y,
		grid_size.x * TileDef.TILE_SIZE,
		grid_size.y * TileDef.TILE_SIZE
	]
	output += "Tiles: %d\n" % tiles.size()

	# 绘制板块网格
	output += "Layout:\n"
	for y in grid_size.y:
		var row_str := "  "
		for x in grid_size.x:
			var tile := get_tile_at(Vector2i(x, y))
			if tile.is_empty():
				row_str += "[    ] "
			else:
				var tile_id: String = tile.get("tile_id", "?")
				var rotation: int = tile.get("rotation", 0)
				var rot_char := ""
				match rotation:
					0: rot_char = "↑"
					90: rot_char = "→"
					180: rot_char = "↓"
					270: rot_char = "←"
				row_str += "[%s%s] " % [tile_id.left(3), rot_char]
		output += row_str + "\n"

	output += "Players: %d-%d\n" % [min_players, max_players]

	return output
