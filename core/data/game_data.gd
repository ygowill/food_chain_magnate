# Game data container
# V2：tiles/maps/pieces 由模块系统 ContentCatalog 装配；GameData 仅作为便捷聚合结构。
class_name GameData
extends RefCounted

const TileDefClass = preload("res://core/map/tile_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")

var tiles: Dictionary = {}   # tile_id -> TileDef
var maps: Dictionary = {}    # map_id  -> MapOptionDef
var pieces: Dictionary = {}  # piece_id -> PieceDef

static func load_default() -> Result:
	return Result.failure("GameData.load_default 已弃用：请通过模块系统 V2 的 ContentCatalog 装配 tiles/maps/pieces")

static func from_catalog(catalog) -> Result:
	if catalog == null:
		return Result.failure("GameData.from_catalog: catalog 为空")

	if not (catalog.tiles is Dictionary):
		return Result.failure("GameData.from_catalog: catalog.tiles 类型错误（期望 Dictionary）")
	if not (catalog.maps is Dictionary):
		return Result.failure("GameData.from_catalog: catalog.maps 类型错误（期望 Dictionary）")
	if not (catalog.pieces is Dictionary):
		return Result.failure("GameData.from_catalog: catalog.pieces 类型错误（期望 Dictionary）")

	var data := GameData.new()

	var tiles_out: Dictionary = {}
	for tile_id_val in catalog.tiles.keys():
		if not (tile_id_val is String):
			return Result.failure("GameData.from_catalog: tiles key 类型错误（期望 String）")
		var tile_id: String = str(tile_id_val)
		if tile_id.is_empty():
			return Result.failure("GameData.from_catalog: tiles key 不能为空")
		var def_val = catalog.tiles.get(tile_id, null)
		if def_val == null:
			return Result.failure("GameData.from_catalog: tiles[%s] 为空" % tile_id)
		if not (def_val is TileDefClass):
			return Result.failure("GameData.from_catalog: tiles[%s] 类型错误（期望 TileDef）" % tile_id)
		var def: TileDef = def_val
		if def.id != tile_id:
			return Result.failure("GameData.from_catalog: tiles[%s].id 不一致: %s" % [tile_id, def.id])
		tiles_out[tile_id] = def
	data.tiles = tiles_out

	var maps_out: Dictionary = {}
	for map_id_val in catalog.maps.keys():
		if not (map_id_val is String):
			return Result.failure("GameData.from_catalog: maps key 类型错误（期望 String）")
		var map_id: String = str(map_id_val)
		if map_id.is_empty():
			return Result.failure("GameData.from_catalog: maps key 不能为空")
		var def_val = catalog.maps.get(map_id, null)
		if def_val == null:
			return Result.failure("GameData.from_catalog: maps[%s] 为空" % map_id)
		if not (def_val is MapOptionDefClass):
			return Result.failure("GameData.from_catalog: maps[%s] 类型错误（期望 MapOptionDef）" % map_id)
		var def = def_val
		if def.id != map_id:
			return Result.failure("GameData.from_catalog: maps[%s].id 不一致: %s" % [map_id, def.id])
		maps_out[map_id] = def
	data.maps = maps_out

	var pieces_out: Dictionary = {}
	for piece_id_val in catalog.pieces.keys():
		if not (piece_id_val is String):
			return Result.failure("GameData.from_catalog: pieces key 类型错误（期望 String）")
		var piece_id: String = str(piece_id_val)
		if piece_id.is_empty():
			return Result.failure("GameData.from_catalog: pieces key 不能为空")
		var def_val = catalog.pieces.get(piece_id, null)
		if def_val == null:
			return Result.failure("GameData.from_catalog: pieces[%s] 为空" % piece_id)
		if not (def_val is PieceDefClass):
			return Result.failure("GameData.from_catalog: pieces[%s] 类型错误（期望 PieceDef）" % piece_id)
		var def: PieceDef = def_val
		if def.id != piece_id:
			return Result.failure("GameData.from_catalog: pieces[%s].id 不一致: %s" % [piece_id, def.id])
		pieces_out[piece_id] = def
	data.pieces = pieces_out

	return Result.success(data)

func get_map_for_player_count(player_count: int) -> Result:
	if maps.is_empty():
		return Result.failure("没有加载任何地图定义")
	var candidates: Array = []
	var all_ranges: Array[String] = []
	for map_id in maps.keys():
		var opt = maps[map_id]
		if opt == null:
			continue
		all_ranges.append("%s(%d-%d)" % [opt.id, opt.min_players, opt.max_players])
		if player_count >= opt.min_players and player_count <= opt.max_players:
			candidates.append(opt)

	if not candidates.is_empty():
		candidates.sort_custom(func(a, b) -> bool:
			return a.id < b.id
		)
		return Result.success(candidates[0])

	all_ranges.sort()
	return Result.failure("没有匹配玩家数量的地图: player_count=%d (available: %s)" % [
		player_count, ", ".join(all_ranges)
	])
