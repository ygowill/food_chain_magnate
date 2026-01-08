extends RefCounted

const TileDefClass = preload("res://core/map/tile_def.gd")
const PieceDefClass = preload("res://core/map/piece_def.gd")

static func load_piece_ids(modules_base_dir: String) -> Result:
	var dir_path := modules_base_dir.path_join("base_pieces/content/pieces")
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success([])

	var piece_ids: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if not dir.current_is_dir() and f.to_lower().ends_with(".json"):
			var path := dir_path.path_join(f)
			var piece_result := PieceDefClass.load_from_file(path)
			if not piece_result.ok:
				dir.list_dir_end()
				return Result.failure("加载建筑件失败: %s (%s)" % [path, piece_result.error])
			var piece: PieceDef = piece_result.value
			if not piece.id.is_empty():
				piece_ids.append(piece.id)
		f = dir.get_next()
	dir.list_dir_end()

	piece_ids.sort()
	return Result.success(piece_ids)

static func load_tile_paths(modules_base_dir: String, user_tiles_dir: String) -> Result:
	var tile_paths: Dictionary = {}

	# 先加载 res:// 模块内板块，再加载 user:// 覆盖（如导出环境的编辑结果）
	var base_dir := modules_base_dir.path_join("base_tiles/content/tiles")
	var merge_base := merge_tile_index_from_dir(tile_paths, base_dir)
	if not merge_base.ok:
		return merge_base
	var merge_user := merge_tile_index_from_dir(tile_paths, user_tiles_dir)
	if not merge_user.ok:
		return merge_user

	return Result.success(tile_paths)

static func merge_tile_index_from_dir(tile_paths: Dictionary, dir_path: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.success()

	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if not dir.current_is_dir() and f.to_lower().ends_with(".json"):
			files.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for file_name in files:
		var path := dir_path.path_join(file_name)
		var tile_result := TileDefClass.load_from_file(path)
		if not tile_result.ok:
			return Result.failure("加载板块失败: %s (%s)" % [path, tile_result.error])
		var tile: TileDef = tile_result.value
		if not tile.id.is_empty():
			tile_paths[tile.id] = path

	return Result.success()

static func write_tile_json(tile: TileDef, tile_id: String, current_path: String, modules_base_dir: String, user_tiles_dir: String) -> Result:
	var path := current_path
	if path.is_empty():
		path = modules_base_dir.path_join("base_tiles/content/tiles").path_join("%s.json" % tile_id)

	var json := JSON.stringify(tile.to_dict(), "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var user_path := user_tiles_dir.path_join("%s.json" % tile_id)
		var abs_user_path := ProjectSettings.globalize_path(user_path)
		var abs_user_dir := abs_user_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(abs_user_dir):
			DirAccess.make_dir_recursive_absolute(abs_user_dir)

		file = FileAccess.open(user_path, FileAccess.WRITE)
		if file == null:
			return Result.failure("无法写入文件: %s (fallback: %s)" % [path, user_path])
		path = user_path

	file.store_string(json)
	file.close()

	return Result.success({
		"path": path,
		"used_user_dir": path.begins_with("user://"),
	})

