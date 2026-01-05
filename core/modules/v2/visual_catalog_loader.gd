# 模块系统 V2：从模块包 content/visuals/ 加载每局 VisualCatalog（UI 可选）
# 约定：
# - visuals 目录不存在：允许（该模块不提供视觉资源）
# - 任意单个 visuals JSON 解析失败：Fail Fast（开发期应尽早发现）
# - 同一 key 在多个模块中重复：允许覆盖（按 module_plan 顺序，后者覆盖前者），并产生 warning
class_name VisualCatalogLoader
extends RefCounted

const VisualCatalogClass = preload("res://core/modules/v2/visual_catalog.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")

static func load_for_modules(base_dir: String, module_ids: Array[String]) -> Result:
	if base_dir.is_empty():
		return Result.failure("VisualCatalogLoader: base_dir 不能为空")

	var read := ModuleDirSpecClass.parse_base_dirs(base_dir)
	if not read.ok:
		return Result.failure("VisualCatalogLoader: base_dir 解析失败: %s" % read.error)

	var base_dirs: Array = read.value
	return load_for_modules_from_dirs(base_dirs, module_ids)

static func load_for_modules_from_dirs(base_dirs: Array, module_ids: Array[String]) -> Result:
	if base_dirs == null or not (base_dirs is Array):
		return Result.failure("VisualCatalogLoader: base_dirs 类型错误（期望 Array[String]）")
	if base_dirs.is_empty():
		return Result.failure("VisualCatalogLoader: base_dirs 不能为空")

	var catalog := VisualCatalogClass.new()
	var warnings: Array[String] = []

	for i in range(module_ids.size()):
		var mid_val = module_ids[i]
		if not (mid_val is String):
			return Result.failure("module_ids[%d] 类型错误（期望 String）" % i)
		var module_id: String = str(mid_val)
		if module_id.is_empty():
			return Result.failure("module_ids[%d] 不能为空" % i)

		var root_read := ModulePackageLoaderClass.resolve_module_root(base_dirs, module_id)
		if not root_read.ok:
			return root_read
		var module_root: String = root_read.value

		var visuals_root := module_root.path_join("content").path_join("visuals")
		var dir := DirAccess.open(visuals_root)
		if dir == null:
			continue

		var files_read := _list_json_files(visuals_root)
		if not files_read.ok:
			return files_read

		for file_name in files_read.value:
			var path := visuals_root.path_join(file_name)
			var file_read := _read_json_file(path)
			if not file_read.ok:
				return Result.failure("加载 visuals 失败: %s (%s)" % [path, file_read.error])
			var data: Dictionary = file_read.value
			var apply := _apply_visuals_dict(catalog, data, module_id, warnings, path)
			if not apply.ok:
				return apply

	return Result.success(catalog).with_warnings(warnings)

static func _apply_visuals_dict(catalog, data: Dictionary, module_id: String,
		warnings: Array[String], source_path: String) -> Result:
	if catalog == null:
		return Result.failure("VisualCatalog 为空")

	var schema_val = data.get("schema_version", null)
	var schema_read := _parse_int_required(schema_val, "%s.schema_version" % source_path)
	if not schema_read.ok:
		return schema_read
	var schema_version: int = int(schema_read.value)
	if schema_version != 1:
		return Result.failure("%s.schema_version 不支持: %d (期望 1)" % [source_path, schema_version])

	var cell_val = data.get("cell_visuals", {})
	var cell_read := _parse_visual_map_simple(cell_val, "%s.cell_visuals" % source_path)
	if not cell_read.ok:
		return cell_read
	var cell_map: Dictionary = cell_read.value
	for k in cell_map.keys():
		var key: String = str(k)
		var entry: Dictionary = cell_map[k]
		_merge_entry(catalog.cell_visuals, catalog.cell_visual_sources, key, entry, module_id, warnings)

	var road_val = data.get("road_visuals", {})
	var road_read := _parse_visual_map_simple(road_val, "%s.road_visuals" % source_path)
	if not road_read.ok:
		return road_read
	var road_map: Dictionary = road_read.value
	for k in road_map.keys():
		var key2: String = str(k)
		var entry2: Dictionary = road_map[k]
		_merge_entry(catalog.road_visuals, catalog.road_visual_sources, key2, entry2, module_id, warnings)

	var piece_val = data.get("piece_visuals", {})
	var piece_read := _parse_piece_visuals(piece_val, "%s.piece_visuals" % source_path)
	if not piece_read.ok:
		return piece_read
	var piece_map: Dictionary = piece_read.value
	for k in piece_map.keys():
		var piece_id: String = str(k)
		var entry3: Dictionary = piece_map[k]
		_merge_entry(catalog.piece_visuals, catalog.piece_visual_sources, piece_id, entry3, module_id, warnings)

	var prod_val = data.get("product_icons", {})
	var prod_read := _parse_visual_map_simple(prod_val, "%s.product_icons" % source_path)
	if not prod_read.ok:
		return prod_read
	var prod_map: Dictionary = prod_read.value
	for k in prod_map.keys():
		var product_id: String = str(k)
		var entry4: Dictionary = prod_map[k]
		_merge_entry(catalog.product_icons, catalog.product_icon_sources, product_id, entry4, module_id, warnings)

	var mk_val = data.get("marketing_visuals", {})
	var mk_read := _parse_visual_map_simple(mk_val, "%s.marketing_visuals" % source_path)
	if not mk_read.ok:
		return mk_read
	var mk_map: Dictionary = mk_read.value
	for k in mk_map.keys():
		var key3: String = str(k)
		var entry5: Dictionary = mk_map[k]
		_merge_entry(catalog.marketing_visuals, catalog.marketing_visual_sources, key3, entry5, module_id, warnings)

	return Result.success()

static func _merge_entry(store: Dictionary, sources: Dictionary, key: String, entry: Dictionary,
		module_id: String, warnings: Array[String]) -> void:
	if store.has(key):
		var prev_src: String = str(sources.get(key, ""))
		warnings.append("visual 覆盖: %s (modules: %s -> %s)" % [key, prev_src, module_id])
	store[key] = entry
	sources[key] = module_id

static func _read_json_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开文件: %s" % path)
	var json := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json)
	if parsed == null or not (parsed is Dictionary):
		return Result.failure("JSON 解析失败（期望 Dictionary）")
	return Result.success(parsed)

static func _list_json_files(dir_path: String) -> Result:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return Result.failure("无法读取目录: %s" % dir_path)

	var json_files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			json_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	json_files.sort()
	return Result.success(json_files)

static func _parse_int_required(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_visual_map_simple(value, path: String) -> Result:
	if value == null:
		return Result.success({})
	if not (value is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)

	var out: Dictionary = {}
	var dict: Dictionary = value
	for k in dict.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String）" % path)
		var key: String = str(k)
		if key.is_empty():
			return Result.failure("%s key 不能为空" % path)
		var entry_val = dict.get(k, null)
		if not (entry_val is Dictionary):
			return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [path, key])
		var entry: Dictionary = entry_val

		var texture_val = entry.get("texture", "")
		if not (texture_val is String):
			return Result.failure("%s[%s].texture 类型错误（期望 String）" % [path, key])
		out[key] = {
			"texture": str(texture_val),
		}

	return Result.success(out)

static func _parse_vec2i(value, path: String) -> Result:
	if value == null:
		return Result.success(Vector2i.ZERO)
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_read := _parse_int_required(value[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := _parse_int_required(value[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

static func _parse_vec2(value, path: String) -> Result:
	if value == null:
		return Result.success(Vector2.ONE)
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_val = value[0]
	var y_val = value[1]
	if not ((x_val is int) or (x_val is float)):
		return Result.failure("%s[0] 类型错误（期望数字）" % path)
	if not ((y_val is int) or (y_val is float)):
		return Result.failure("%s[1] 类型错误（期望数字）" % path)
	return Result.success(Vector2(float(x_val), float(y_val)))

static func _parse_piece_visuals(value, path: String) -> Result:
	if value == null:
		return Result.success({})
	if not (value is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)

	var out: Dictionary = {}
	var dict: Dictionary = value
	for k in dict.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String）" % path)
		var piece_id: String = str(k)
		if piece_id.is_empty():
			return Result.failure("%s key 不能为空" % path)
		var entry_val = dict.get(k, null)
		if not (entry_val is Dictionary):
			return Result.failure("%s[%s] 类型错误（期望 Dictionary）" % [path, piece_id])
		var entry: Dictionary = entry_val

		var texture_val = entry.get("texture", "")
		if not (texture_val is String):
			return Result.failure("%s[%s].texture 类型错误（期望 String）" % [path, piece_id])
		var offset_read := _parse_vec2i(entry.get("offset_px", null), "%s[%s].offset_px" % [path, piece_id])
		if not offset_read.ok:
			return offset_read
		var scale_read := _parse_vec2(entry.get("scale", null), "%s[%s].scale" % [path, piece_id])
		if not scale_read.ok:
			return scale_read

		out[piece_id] = {
			"texture": str(texture_val),
			"offset_px": offset_read.value,
			"scale": scale_read.value,
		}

	return Result.success(out)
