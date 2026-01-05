# 营销板件定义
# 解析模块 content/marketing/*.json 中的营销板件数据（board_number/type）。
class_name MarketingDef
extends RefCounted

var id: String = ""
var board_number: int = 0
var type: String = ""  # strict：具体 type 是否可用由模块注册的 MarketingTypeRegistry 决定

var min_players: int = 2
var max_players = null  # int | null

static func from_dict(data: Dictionary) -> Result:
	var def := MarketingDef.new()

	var id_read := _parse_string(data.get("id", null), "MarketingDef.id", false)
	if not id_read.ok:
		return id_read
	def.id = id_read.value

	var board_number_read := _parse_int(data.get("board_number", null), "MarketingDef.board_number")
	if not board_number_read.ok:
		return board_number_read
	def.board_number = int(board_number_read.value)
	if def.board_number <= 0:
		return Result.failure("MarketingDef.board_number 必须 > 0")

	var type_read := _parse_string(data.get("type", null), "MarketingDef.type", false)
	if not type_read.ok:
		return type_read
	def.type = type_read.value

	# 按玩家数可用性（Strict Mode：缺字段直接失败）
	if not data.has("min_players"):
		return Result.failure("MarketingDef 缺少 min_players")
	var min_players_read := _parse_int(data.get("min_players", null), "MarketingDef.min_players")
	if not min_players_read.ok:
		return min_players_read
	def.min_players = int(min_players_read.value)
	if def.min_players < 2:
		return Result.failure("MarketingDef.min_players 必须 >= 2，实际: %d" % def.min_players)

	if not data.has("max_players"):
		return Result.failure("MarketingDef 缺少 max_players")
	var max_val = data.get("max_players", null)
	if max_val == null:
		def.max_players = null
	else:
		var max_read := _parse_int(max_val, "MarketingDef.max_players")
		if not max_read.ok:
			return max_read
		var max_players: int = int(max_read.value)
		if max_players < def.min_players:
			return Result.failure("MarketingDef.max_players 必须 >= min_players（%d），实际: %d" % [def.min_players, max_players])
		def.max_players = max_players

	return Result.success(def)

static func from_json(json_string: String) -> Result:
	var parsed = JSON.parse_string(json_string)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("MarketingDef JSON 解析失败（期望 Dictionary）")
	return from_dict(parsed)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开营销板件定义文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

# === 严格解析辅助 ===

static func _parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = value
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

func to_dict() -> Dictionary:
	return {
		"id": id,
		"board_number": board_number,
		"type": type,
		"min_players": min_players,
		"max_players": max_players,
	}

func is_available_for_player_count(player_count: int) -> bool:
	if player_count < min_players:
		return false
	if max_players != null and player_count > int(max_players):
		return false
	return true
