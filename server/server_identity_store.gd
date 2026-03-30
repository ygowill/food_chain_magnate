class_name ServerIdentityStore
extends RefCounted

const DEFAULT_SAVE_PATH := "user://dedicated_server/server_identity.cfg"

var _save_path := DEFAULT_SAVE_PATH

func _init(save_path: String = DEFAULT_SAVE_PATH) -> void:
	var path := str(save_path).strip_edges()
	if not path.is_empty():
		_save_path = path

func load_or_create(port: int) -> Result:
	var existing := load_identity()
	if existing.ok:
		var data: Dictionary = Dictionary(existing.value)
		var game_server_id := str(data.get("game_server_id", "")).strip_edges()
		if not game_server_id.is_empty():
			return Result.success(data)

	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(8)
	var created := {
		"game_server_id": "local_%s_%d" % [bytes.hex_encode(), int(port)],
	}
	var save_r := save_identity(created)
	if not save_r.ok:
		return save_r
	return Result.success(created)

func load_identity() -> Result:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path) != OK:
		return Result.success({})

	var game_server_id := str(cfg.get_value("identity", "game_server_id", "")).strip_edges()
	if game_server_id.is_empty():
		return Result.success({})
	return Result.success({
		"game_server_id": game_server_id,
	})

func save_identity(data: Dictionary) -> Result:
	var abs_path := ProjectSettings.globalize_path(_save_path)
	var abs_dir := abs_path.get_base_dir()
	var mkdir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkdir_err != OK:
		return Result.failure("创建 identity 目录失败: %s err=%s" % [abs_dir, str(mkdir_err)])

	var cfg := ConfigFile.new()
	cfg.set_value("identity", "game_server_id", str(data.get("game_server_id", "")).strip_edges())
	var err := cfg.save(_save_path)
	if err != OK:
		return Result.failure("保存 identity 失败: %s" % str(err))
	return Result.success({
		"path": abs_path,
	})
