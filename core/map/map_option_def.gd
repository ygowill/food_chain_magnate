# 地图选项定义（模块内容）
# 说明：
# - MapOptionDef 仅描述“可选地图/主题/约束”，不描述运行期板块布局。
# - 运行期板块布局由 Ruleset 的 MapGenerator 生成 MapDef（包含 grid_size 与 tiles placements）。
class_name MapOptionDef
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")

const _VALID_LAYOUT_MODES: Array[String] = ["random_all_tiles", "fixed"]
const _VALID_ROTATIONS = MapUtilsClass.VALID_ROTATIONS
const _SELF_SCRIPT = preload("res://core/map/map_option_def.gd")

var id: String = ""
var display_name: String = ""
var min_players: int = 2
var max_players: int = 6

var layout_mode: String = "random_all_tiles"
var random_rotation: bool = true
var required_modules: Array[String] = []

# fixed 模式下使用：每个板块 { "tile_id": "...", "board_pos": Vector2i, "rotation": 0 }
var tiles: Array[Dictionary] = []

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
		"min_players": min_players,
		"max_players": max_players,
		"layout_mode": layout_mode,
		"random_rotation": random_rotation,
		"required_modules": required_modules,
		"tiles": tiles_arr,
	}

static func from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("MapOptionDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"min_players",
		"max_players",
		"layout_mode",
		"random_rotation",
		"required_modules",
		"tiles",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("MapOptionDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).is_empty():
		return Result.failure("MapOptionDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).is_empty():
		return Result.failure("MapOptionDef.display_name 类型错误或为空（期望非空 String）")

	var min_players_read := _parse_non_negative_int(data.get("min_players", null), "MapOptionDef.min_players")
	if not min_players_read.ok:
		return min_players_read
	var max_players_read := _parse_non_negative_int(data.get("max_players", null), "MapOptionDef.max_players")
	if not max_players_read.ok:
		return max_players_read
	var min_players: int = int(min_players_read.value)
	var max_players: int = int(max_players_read.value)
	if min_players <= 0 or max_players <= 0 or min_players > max_players:
		return Result.failure("MapOptionDef 玩家数范围无效: min=%d max=%d" % [min_players, max_players])

	var layout_mode_val = data.get("layout_mode", null)
	if not (layout_mode_val is String) or str(layout_mode_val).is_empty():
		return Result.failure("MapOptionDef.layout_mode 类型错误或为空（期望非空 String）")
	var layout_mode: String = str(layout_mode_val)
	if not _VALID_LAYOUT_MODES.has(layout_mode):
		return Result.failure("MapOptionDef.layout_mode 非法: %s" % layout_mode)

	var random_rotation_val = data.get("random_rotation", null)
	if not (random_rotation_val is bool):
		return Result.failure("MapOptionDef.random_rotation 类型错误（期望 bool）")

	var required_modules_read := _parse_string_array(data.get("required_modules", null), "MapOptionDef.required_modules", false)
	if not required_modules_read.ok:
		return required_modules_read

	var tiles_read := _parse_tiles(data.get("tiles", null), "MapOptionDef.tiles")
	if not tiles_read.ok:
		return tiles_read

	if layout_mode == "random_all_tiles":
		if not tiles_read.value.is_empty():
			return Result.failure("MapOptionDef.tiles 必须为空（layout_mode=random_all_tiles）")
	elif layout_mode == "fixed":
		if tiles_read.value.is_empty():
			return Result.failure("MapOptionDef.tiles 不能为空（layout_mode=fixed）")

	var opt := _SELF_SCRIPT.new()
	opt.id = str(id_val)
	opt.display_name = str(display_name_val)
	opt.min_players = min_players
	opt.max_players = max_players
	opt.layout_mode = layout_mode
	opt.random_rotation = bool(random_rotation_val)
	opt.required_modules = required_modules_read.value
	opt.tiles = tiles_read.value
	return Result.success(opt)

static func from_json(json_string: String) -> Result:
	var data = JSON.parse_string(json_string)
	if data == null or not (data is Dictionary):
		return Result.failure("MapOptionDef JSON 解析失败")
	return from_dict(data)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 MapOptionDef: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

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
		var rot: int = int(rotation_read.value)
		if not _VALID_ROTATIONS.has(rot):
			return Result.failure("%s[%d].rotation 非法: %d" % [path, i, rot])

		out.append({
			"tile_id": str(tile_id_val),
			"board_pos": board_pos_read.value,
			"rotation": rot,
		})
	return Result.success(out)
